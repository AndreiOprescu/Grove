import Foundation
import GroveCore

/// Where a task lives. Used by quick add defaults, moves and drops.
enum TaskPlacement: Equatable {
    case inbox
    case someday
    case day(DayKey)
    /// Any day of the week; stored as the Monday.
    case week(DayKey)
}

/// Task writes. Every one is a single undo step.
extension AppStore {
    // MARK: Reading

    /// Open top-level tasks that live in `placement`, in the order they are shown.
    func openTasks(in placement: TaskPlacement) -> [TaskItem] {
        let list: [TaskItem]
        switch placement {
        case .inbox: list = (try? repos.tasks.inbox()) ?? []
        case .someday: list = (try? repos.tasks.someday()) ?? []
        case .day(let d): list = (try? repos.tasks.forDay(d)) ?? []
        case .week(let d): list = (try? repos.tasks.forWeek(d.weekStart())) ?? []
        }
        return list.filter { $0.status == .open }
    }

    func subtasks(of parentId: String) -> [TaskItem] { (try? repos.tasks.subtasks(of: parentId)) ?? [] }

    func tagNames(of taskId: String) -> [String] { (try? repos.tags.tags(forTask: taskId)) ?? [] }

    func blocks(ofTask taskId: String) -> [EventItem] { (try? repos.events.blocks(forTask: taskId)) ?? [] }

    /// Sort value that puts a new task after every existing one.
    private func nextSort() -> Double {
        ((try? repos.db.queryOne("SELECT COALESCE(MAX(sort), 0) FROM tasks") { $0.double(0) }) ?? 0) + 1
    }

    private func placed(_ task: TaskItem, in placement: TaskPlacement) -> TaskItem {
        var t = task
        switch placement {
        case .inbox: t.bucket = .inbox; t.planDate = nil; t.planWeek = nil
        case .someday: t.bucket = .someday; t.planDate = nil; t.planWeek = nil
        case .day(let d): t.bucket = .day; t.planDate = d; t.planWeek = nil
        case .week(let d): t.bucket = .week; t.planDate = nil; t.planWeek = d.weekStart()
        }
        return t
    }

    // MARK: Quick add

    /// Makes a task from one line of text ("Call mum tomorrow 6pm for 20m #home !2").
    /// `placement` is used when the text names no date. A clock time on a day makes a time block too.
    @discardableResult
    func quickAdd(_ text: String, default placement: TaskPlacement = .inbox) -> TaskItem? {
        guard let made = quickAddChange(text, default: placement) else { return nil }
        return commit(made.change) ? made.task : nil
    }

    /// The change that `quickAdd` would commit, and the task in it. Nil when the text has no words for a title.
    /// `notes` is the text of the task's notes field.
    func quickAddChange(_ text: String, default placement: TaskPlacement, notes: String = "") -> (task: TaskItem, change: Mutation)? {
        let lists = (try? repos.lists.all()) ?? []
        let r = QuickAddParser(today: .today(), lists: lists.map(\.name)).parse(text)
        guard !r.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        var t = TaskItem(title: r.title, notes: notes, priority: r.priority, due: r.due, estimateMin: r.blockMinutes,
                         recurrence: r.recurrence, sort: nextSort())
        switch r.bucket {
        case .day: t = placed(t, in: .day(r.planDate ?? .today()))
        case .week: t = placed(t, in: .week(r.planWeek ?? .today()))
        case .someday: t = placed(t, in: .someday)
        case .inbox: t = placed(t, in: placement)
        }
        if let name = r.listName {
            t.listId = lists.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id
        }

        var m = Mutation(name: "New Task")
        m.tasks.append((nil, t))
        if !r.tags.isEmpty { m.tags.append((t.id, [], r.tags)) }
        if t.bucket == .day, let day = t.planDate, let start = r.startMinute, let end = r.blockEnd {
            m.events.append((nil, blockEvent(for: t, day: day, start: start, end: end)))
        }
        return (t, m)
    }

    // MARK: Completing

    /// Checks a task off, or reopens it. Completing a repeating task also makes its next copy.
    func toggleDone(taskId: String) {
        guard let old = task(taskId) else { return }
        var t = old
        if t.isDone { t.status = .open; t.completedAt = nil } else { t.status = .done; t.completedAt = Stamp.now() }
        var m = Mutation(name: t.isDone ? "Complete Task" : "Reopen Task")
        m.tasks.append((old, t))
        if t.isDone, let rule = old.recurrence { appendNextInstance(of: old, rule: rule, to: &m) }
        commit(m)
    }

    /// The next copy of a repeating task: new id, next date, subtasks unchecked, one block copied.
    /// The date never lands in the past, even when the task is finished late.
    private func appendNextInstance(of old: TaskItem, rule: RecurrenceRule, to m: inout Mutation) {
        let today = DayKey.today()
        var placement: TaskPlacement
        switch old.bucket {
        case .week:
            let base = max(old.planWeek ?? today, today.weekStart())
            guard let n = RecurrenceEngine.next(after: base, rule: rule) else { return }
            placement = .week(max(n.weekStart(), base.adding(days: 7)))
        default:
            let base = max(old.planDate ?? today, today)
            guard let n = RecurrenceEngine.next(after: base, rule: rule) else { return }
            placement = .day(n)
        }
        if case .day(let d) = placement,
           openTasks(in: .day(d)).contains(where: { $0.title == old.title && $0.recurrence == old.recurrence }) { return }

        var next = placed(old, in: placement)
        next.id = UUID().uuidString
        next.status = .open
        next.completedAt = nil
        next.createdAt = Stamp.now()
        next.sort = nextSort()
        m.tasks.append((nil, next))
        let names = tagNames(of: old.id)
        if !names.isEmpty { m.tags.append((next.id, [], names)) }

        for (i, sub) in subtasks(of: old.id).enumerated() {
            var copy = sub
            copy.id = UUID().uuidString
            copy.parentId = next.id
            copy.status = .open
            copy.completedAt = nil
            copy.createdAt = Stamp.now()
            copy.sort = next.sort + Double(i + 1) / 1000
            m.tasks.append((nil, copy))
        }
        let blocks = blocks(ofTask: old.id)
        if blocks.count == 1, let b = blocks.first, case .day(let d) = placement {
            m.events.append((nil, blockEvent(for: next, day: d, start: b.start.minute, end: b.end.minute)))
        }
    }

    // MARK: Editing

    func addSubtask(to parentId: String, title: String) {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, task(parentId) != nil else { return }
        var m = Mutation(name: "New Subtask")
        m.tasks.append((nil, TaskItem(title: name, parentId: parentId, sort: nextSort())))
        commit(m)
    }

    /// Changes any fields of a task in one undo step. Does nothing when `change` leaves the task as it was.
    func editTask(_ id: String, name: String, _ change: (inout TaskItem) -> Void) {
        guard let old = task(id) else { return }
        var t = old
        change(&t)
        guard t != old else { return }
        var m = Mutation(name: name)
        m.tasks.append((old, t))
        commit(m)
    }

    /// Saves the body of a task. Many saves in a row while typing make one undo step.
    func setNotes(_ id: String, _ text: String, now: Date = Date()) {
        guard let old = task(id), old.notes != text else { return }
        var t = old
        t.notes = text
        var m = Mutation(name: "Edit Notes")
        m.tasks.append((old, t))
        m.mergeKey = "notes:\(id)"
        m.at = now
        commit(m)
    }


    /// Saves the short description of a task. Many saves in a row while typing make one undo step.
    func setSummary(_ id: String, _ text: String, now: Date = Date()) {
        let clean = SummaryText.clean(text)
        guard let old = task(id), old.summary != clean else { return }
        var t = old
        t.summary = clean
        var m = Mutation(name: "Edit Short Description")
        m.tasks.append((old, t))
        m.mergeKey = "summary:\(id)"
        m.at = now
        commit(m)
    }

    func setTags(taskId: String, to names: [String]) {
        var seen = Set<String>()
        let clean = names.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespacesAndNewlines)) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        let old = tagNames(of: taskId)
        guard task(taskId) != nil, clean.sorted(by: { $0.lowercased() < $1.lowercased() }) != old else { return }
        var m = Mutation(name: "Edit Tags")
        m.tags.append((taskId, old, clean))
        commit(m)
    }

    // MARK: Moving and ordering

    /// Moves a task to `placement`, in front of `beforeId` (or last when nil).
    /// Its blocks follow it to a new day, and are removed when it leaves the calendar.
    func moveTask(_ id: String, to placement: TaskPlacement, before beforeId: String? = nil) {
        guard let old = task(id), old.parentId == nil else { return }
        let before = openTasks(in: placement)
        var siblings = before.filter { $0.id != id }
        let index = beforeId.flatMap { b in siblings.firstIndex { $0.id == b } } ?? siblings.endIndex

        var t = placed(old, in: placement)
        var m = Mutation(name: "Move Task")

        var ids = siblings.map(\.id)
        ids.insert(id, at: index)
        if t.bucket == old.bucket, t.planDate == old.planDate, t.planWeek == old.planWeek, ids == before.map(\.id) { return }

        let prev = index > 0 ? siblings[index - 1] : nil
        let next = index < siblings.count ? siblings[index] : nil
        switch (prev, next) {
        case (nil, nil): t.sort = old.sort
        case (let p?, nil): t.sort = p.sort + 1
        case (nil, let n?): t.sort = n.sort - 1
        case (let p?, let n?):
            if n.sort - p.sort > 1e-6 {
                t.sort = (p.sort + n.sort) / 2
            } else {
                // The neighbours have no gap between them (equal values): number the whole list again.
                siblings.insert(t, at: index)
                for (i, s) in siblings.enumerated() {
                    var u = s
                    u.sort = Double(i + 1)
                    if s.id == id { t.sort = u.sort } else if u.sort != s.sort { m.tasks.append((s, u)) }
                }
            }
        }
        m.tasks.append((old, t))

        for b in blocks(ofTask: id) {
            if case .day(let d) = placement {
                guard b.start.day != d else { continue }
                var moved = b
                moved.start = WallTime(day: d, minute: b.start.minute)
                moved.end = WallTime(day: d, minute: b.end.minute)
                m.events.append((b, moved))
            } else {
                m.events.append((b, nil))
            }
        }
        commit(m)
    }

    // MARK: Deleting

    /// Deletes a task with its subtasks and time blocks. Undo brings everything back, tags included.
    func deleteTask(_ id: String) {
        guard let root = task(id) else { return }
        var all = [root]
        var queue = [root.id]
        while let parent = queue.popLast() {
            let kids = subtasks(of: parent)
            all += kids
            queue += kids.map(\.id)
        }
        var m = Mutation(name: "Delete Task")
        for t in all {
            m.tasks.append((t, nil))
            for b in blocks(ofTask: t.id) { m.events.append((b, nil)) }
            let names = tagNames(of: t.id)
            if !names.isEmpty { m.tags.append((t.id, names, [])) }
        }
        commit(m)
    }
}
