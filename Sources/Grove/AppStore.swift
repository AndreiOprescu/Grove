import SwiftUI
import GroveCore

/// One undoable change. Holds the before and after state of every task and event it touches.
/// `nil` before means "created". `nil` after means "deleted".
struct Mutation {
    var name: String
    var tasks: [(before: TaskItem?, after: TaskItem?)] = []
    var events: [(before: EventItem?, after: EventItem?)] = []
    var notes: [(before: Note?, after: Note?)] = []
    /// Days taken out of (`add`) or put back into a repeating event. Undo does the opposite, in reverse order.
    var exdates: [(eventId: String, day: DayKey, add: Bool)] = []
    /// Tag names of a task before and after. Tags live in their own table, so they are tracked here.
    var tags: [(taskId: String, before: [String], after: [String])] = []
    var isEmpty: Bool { tasks.isEmpty && events.isEmpty && notes.isEmpty && tags.isEmpty && exdates.isEmpty }
    /// Typing makes many small changes. Changes with the same key, close in time, become one undo step.
    var mergeKey: String?
    var at = Date()

    /// Joins `next` (a later change of the same one task or note) into this one.
    func merged(with next: Mutation) -> Mutation? {
        guard let key = mergeKey, key == next.mergeKey, next.at.timeIntervalSince(at) < 60,
              events.isEmpty, next.events.isEmpty, tags.isEmpty, next.tags.isEmpty,
              exdates.isEmpty, next.exdates.isEmpty else { return nil }
        var m = self
        if tasks.count == 1, next.tasks.count == 1, notes.isEmpty, next.notes.isEmpty,
           tasks[0].after?.id == next.tasks[0].before?.id {
            m.tasks[0] = (tasks[0].before, next.tasks[0].after)
        } else if notes.count == 1, next.notes.count == 1, tasks.isEmpty, next.tasks.isEmpty,
                  notes[0].after?.id == next.notes[0].before?.id {
            m.notes[0] = (notes[0].before, next.notes[0].after)
        } else {
            return nil
        }
        m.at = next.at
        return m
    }

    /// Adds everything in `other` to this change.
    mutating func append(_ other: Mutation) {
        tasks += other.tasks
        events += other.events
        notes += other.notes
        tags += other.tags
        exdates += other.exdates
    }
}

@Observable @MainActor
final class AppStore {
    let repos: Repos
    var selectedDay: DayKey = .today()
    /// Bumped after every write so views reload.
    var revision = 0
    /// Selected planner block ids.
    var selection: Set<String> = []
    var toast: String?
    var errorMessage: String?
    /// The task shown in the inspector (M3d) and highlighted in the task list.
    var selectedTaskId: String?
    /// Bumped by ⌘N. The task list focuses its quick-add field when this changes.
    var quickAddRequest = 0
    /// Set when a change takes a day past the daily limit. The planner shows it as an alert.
    var overloadWarning: String?
    /// Set when a change touches an event that repeats. The window asks "This event only / All events".
    var recurringPrompt: RecurringPrompt?
    /// The event the editor popover shows, or nil.
    var editingEvent: EditingEvent?
    /// Which screen fills the window. M8 replaces this with the layouts.
    var screen: Screen = .planner
    /// The note the notes screen shows.
    var selectedNoteId: String?
    var noteFilter: NoteFilter = .all
    var noteQuery = ""

    private(set) var undoStack: [Mutation] = []
    private(set) var redoStack: [Mutation] = []
    private var toastTask: Task<Void, Never>?
    /// Decoded images for task bodies and notes. Not observed: images never change once stored.
    let imageCache = NSCache<NSString, NSImage>()

    init(repos: Repos? = nil) {
        if let repos {
            self.repos = repos
        } else if let db = try? Database.openDefault() {
            self.repos = Repos(db: db)
            if let dir = try? Database.supportDirectory().appendingPathComponent("Backups") {
                try? Backup.runDaily(db: db, directory: dir, today: .today())
            }
            // After the backup: drop images that no text uses and that are over a day old.
            _ = try? self.repos.attachments.sweepOrphans()
        } else {
            self.repos = Repos(db: try! Database.inMemory())
            self.errorMessage = "Grove could not open its database. Changes will not be saved."
        }
    }

    // MARK: Undo

    var undoName: String? { undoStack.last?.name }
    var redoName: String? { redoStack.last?.name }

    /// Applies a change, saves it, and records it for undo.
    @discardableResult
    func commit(_ m: Mutation) -> Bool {
        guard !m.isEmpty else { return false }
        let days = plannedDays(in: m)
        let before = Dictionary(uniqueKeysWithValues: days.map { ($0, plannedMinutes(on: $0)) })
        guard apply(m, forward: true) else { return false }
        warnIfOverloaded(days, before: before)
        if let last = undoStack.last, let joined = last.merged(with: m) {
            undoStack[undoStack.count - 1] = joined
        } else {
            undoStack.append(m)
        }
        redoStack.removeAll()
        if undoStack.count > 200 { undoStack.removeFirst() }
        return true
    }

    // MARK: Busy-day limit

    /// Planned time per day above this many minutes triggers an alert. Default 9 hours.
    var dailyLimitMinutes: Int {
        let v = UserDefaults.standard.integer(forKey: "planner.dailyLimitMin")
        return v > 0 ? v : 9 * 60
    }

    /// Minutes of the day that have at least one block. Overlaps count once.
    func plannedMinutes(on day: DayKey) -> Int {
        var covered = Set<Int>()
        for b in blocks(for: day...day) { covered.formUnion(b.startMinute..<b.endMinute) }
        return covered.count
    }

    private func plannedDays(in m: Mutation) -> [DayKey] {
        var days = Set<DayKey>()
        for e in m.events {
            for ev in [e.before, e.after] { if let ev, !ev.allDay { days.insert(ev.start.day) } }
        }
        return days.sorted()
    }

    /// Alerts only when a change moves a day from within the limit to over it.
    private func warnIfOverloaded(_ days: [DayKey], before: [DayKey: Int]) {
        let limit = dailyLimitMinutes
        for day in days {
            let after = plannedMinutes(on: day)
            if (before[day] ?? 0) <= limit && after > limit {
                let name = day.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
                overloadWarning = "\(name) has \(PlannerMath.duration(after)) planned. That is more than \(PlannerMath.duration(limit)). Move or shorten something to leave room to rest."
                return
            }
        }
    }

    func undo() {
        guard let m = undoStack.popLast() else { return }
        if apply(m, forward: false) { redoStack.append(m); showToast("Undid \(m.name)") }
    }

    func redo() {
        guard let m = redoStack.popLast() else { return }
        if apply(m, forward: true) { undoStack.append(m); showToast("Redid \(m.name)") }
    }

    private func apply(_ m: Mutation, forward: Bool) -> Bool {
        do {
            try repos.db.transaction {
                func target(_ t: (before: TaskItem?, after: TaskItem?)) -> TaskItem? { forward ? t.after : t.before }
                func source(_ t: (before: TaskItem?, after: TaskItem?)) -> TaskItem? { forward ? t.before : t.after }
                for t in m.tasks { if let x = target(t) { try repos.tasks.save(x) } }
                for e in m.events { if let x = forward ? e.after : e.before { try repos.events.save(x) } }
                for n in m.notes { if let x = forward ? n.after : n.before { try repos.notes.save(x) } }
                for x in forward ? m.exdates : m.exdates.reversed() {
                    if x.add == forward { try repos.events.addExdate(x.eventId, x.day) } else { try repos.events.removeExdate(x.eventId, x.day) }
                }
                let gone = Set(m.tasks.filter { target($0) == nil }.compactMap { source($0)?.id })
                for c in m.tags where !gone.contains(c.taskId) {
                    try repos.tags.setTags(taskId: c.taskId, names: forward ? c.after : c.before)
                }
                for e in m.events where (forward ? e.after : e.before) == nil {
                    if let id = (forward ? e.before : e.after)?.id { try repos.events.delete(id) }
                }
                for n in m.notes where (forward ? n.after : n.before) == nil {
                    if let id = (forward ? n.before : n.after)?.id { try repos.notes.delete(id) }
                }
                for t in m.tasks where target(t) == nil {
                    if let id = source(t)?.id { try repos.tasks.delete(id) }
                }
                try updateReferences(m, forward: forward)
            }
            revision += 1
            return true
        } catch {
            errorMessage = "Could not save: \(error)"
            return false
        }
    }

    /// Keeps `[[mentions]]` in step with a change: links from a changed body, titles after a rename,
    /// and links that point at an item that was just brought back.
    private func updateReferences(_ m: Mutation, forward: Bool) throws {
        for t in m.tasks {
            guard let now = forward ? t.after : t.before else { continue }
            let was = forward ? t.before : t.after
            let ref = ItemRef(.task, now.id)
            if was == nil || was?.notes != now.notes {
                let canonical = try repos.refs.reindex(ref, text: now.notes)
                if canonical != now.notes { var fixed = now; fixed.notes = canonical; try repos.tasks.save(fixed) }
            }
            if was == nil { try repos.refs.rebuildIncoming(to: ref) }
            if let was, was.title != now.title { try repos.refs.renamed(ref, to: now.title) }
            if was == nil || was?.status != now.status { try syncBoxes(of: now) }
        }
        for e in m.events {
            guard let now = forward ? e.after : e.before, now.kind == .event else { continue }   // task blocks hold no text
            let was = forward ? e.before : e.after
            let ref = ItemRef(.event, now.id)
            if was == nil || was?.notes != now.notes {
                let canonical = try repos.refs.reindex(ref, text: now.notes)
                if canonical != now.notes { var fixed = now; fixed.notes = canonical; try repos.events.save(fixed) }
            }
            if was == nil { try repos.refs.rebuildIncoming(to: ref) }
            if let was, was.title != now.title { try repos.refs.renamed(ref, to: now.title) }
        }
        for n in m.notes {
            guard let now = forward ? n.after : n.before else { continue }
            let was = forward ? n.before : n.after
            let ref = ItemRef(.note, now.id)
            if was == nil || was?.body != now.body {
                let canonical = try repos.refs.reindex(ref, text: now.body)
                if canonical != now.body { var fixed = now; fixed.body = canonical; try repos.notes.save(fixed) }
                try repos.tags.setTags(noteId: now.id, names: NoteParser.tags(in: now.body))
            }
            if was == nil { try repos.refs.rebuildIncoming(to: ref) }
            if let was, was.title != now.title { try repos.refs.renamed(ref, to: now.title) }
        }
    }

    /// Opens the task list and puts the cursor in the quick-add field.
    func requestQuickAdd() {
        UserDefaults.standard.set(true, forKey: "shell.tasksOpen")
        quickAddRequest += 1
    }

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    // MARK: Reading for the planner

    /// A stored event, or one occurrence of a repeating event (its id is `OccurrenceID`). Nil when that day is not part of the series.
    func event(_ id: String) -> EventItem? {
        guard let p = OccurrenceID.parse(id) else { return try? repos.events.get(id) }
        guard let series = try? repos.events.get(p.series), let rule = series.recurrence else { return nil }
        let gone = Set((try? repos.events.exdates(series.id)) ?? [])
        guard RecurrenceEngine.occurrences(rule: rule, seriesStart: series.start.day, in: p.day...p.day, exdates: gone).contains(p.day) else { return nil }
        return RecurrenceEngine.occurrence(of: series, on: p.day)
    }
    func task(_ id: String) -> TaskItem? { try? repos.tasks.get(id) }

    func blocks(for days: ClosedRange<DayKey>) -> [PlannerBlock] {
        let events = eventItems(in: days)
        var tasks: [String: TaskItem] = [:]
        var out: [PlannerBlock] = []
        for e in events where !e.allDay {
            var task: TaskItem?
            if let tid = e.taskId {
                if tasks[tid] == nil { tasks[tid] = try? repos.tasks.get(tid) }
                task = tasks[tid]
            }
            let day = e.start.day
            guard days.contains(day) else { continue }
            let end = e.end.day == day ? e.end.minute : 1440
            out.append(PlannerBlock(
                id: e.id, title: task?.title ?? e.title, summary: task?.summary ?? "", day: day, startMinute: e.start.minute,
                endMinute: max(end, e.start.minute + 1), kind: e.kind, taskId: e.taskId,
                isDone: task?.isDone ?? false, color: e.color, isRecurring: e.seriesId != nil))
        }
        return out
    }


    /// A click on a block. A click on a task block also opens that task in the panel at the right.
    /// Command-click adds or removes a block and leaves the panel alone.
    func selectBlock(_ block: PlannerBlock, extend: Bool) {
        if extend {
            if selection.contains(block.id) { selection.remove(block.id) } else { selection.insert(block.id) }
        } else {
            selection = [block.id]
            if let taskId = block.taskId {
                selectedTaskId = taskId
            } else if block.kind == .event, let e = event(block.id) {
                editEvent(e)
            }
        }
    }

    func allDayEvents(for days: ClosedRange<DayKey>) -> [EventItem] {
        eventItems(in: days).filter(\.allDay)
    }

    /// Open tasks for this day, then this week, then the inbox, that have no block on `day`.
    func unscheduled(for day: DayKey) -> [TaskItem] {
        let next = day.adding(days: 1)
        let scheduledIds = Set((try? repos.db.query(
            "SELECT DISTINCT task_id FROM events WHERE task_id IS NOT NULL AND start >= ? AND start < ?",
            [.text(day.string + "T00:00"), .text(next.string + "T00:00")]) { $0.text(0) }) ?? [])
        func open(_ list: [TaskItem]) -> [TaskItem] {
            list.filter { $0.status == .open && $0.parentId == nil && !scheduledIds.contains($0.id) }
        }
        let byPriority: (TaskItem, TaskItem) -> Bool = { $0.priority != $1.priority ? $0.priority > $1.priority : $0.sort < $1.sort }
        let dayTasks = open((try? repos.tasks.forDay(day)) ?? []).sorted(by: byPriority)
        let weekTasks = open((try? repos.tasks.forWeek(day.weekStart())) ?? []).sorted(by: byPriority)
        let inbox = open((try? repos.tasks.inbox()) ?? []).sorted(by: byPriority)
        return dayTasks + weekTasks + inbox
    }

    /// Open tasks with a title that contains `text`, not yet blocked on `day`. For the "schedule existing" hint.
    func matchingTasks(_ text: String, on day: DayKey) -> [TaskItem] {
        let q = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 2 else { return [] }
        return unscheduled(for: day).filter { $0.title.lowercased().contains(q) }.prefix(3).map { $0 }
    }

    /// Minutes of open time and planned time for a day's header.
    func dayTotals(_ day: DayKey, blocks: [PlannerBlock], workStart: Int, workEnd: Int) -> (planned: Int, free: Int, done: Int, total: Int) {
        let taskBlocks = blocks.filter { $0.day == day }
        let planned = Set(taskBlocks.flatMap { Array($0.startMinute..<$0.endMinute) }).count
        let busyInWork = Set(taskBlocks.flatMap { Array($0.startMinute..<$0.endMinute) }).filter { $0 >= workStart && $0 < workEnd }.count
        let withTask = taskBlocks.filter(\.isTaskBlock)
        return (planned, max(0, workEnd - workStart - busyInWork), withTask.filter(\.isDone).count, withTask.count)
    }

    // MARK: Writing from the planner

    func blockEvent(for task: TaskItem, day: DayKey, start: Int, end: Int) -> EventItem {
        EventItem(title: task.title, start: WallTime(day: day, minute: start), end: WallTime(day: day, minute: end),
                  kind: .block, taskId: task.id, color: "accent")
    }

    /// A task moved onto a day: bucket day, plan date set.
    func planned(_ task: TaskItem, on day: DayKey) -> TaskItem {
        var t = task
        t.bucket = .day
        t.planDate = day
        t.planWeek = nil
        return t
    }

    /// New task and block together, or a plain event.
    func createFromDraft(title: String, day: DayKey, start: Int, end: Int, asEvent: Bool) {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var m = Mutation(name: "New Block")
        if asEvent {
            let e = EventItem(title: name, start: WallTime(day: day, minute: start), end: WallTime(day: day, minute: end))
            m.events.append((nil, e))
        } else {
            let t = TaskItem(title: name, bucket: .day, planDate: day, estimateMin: end - start)
            m.tasks.append((nil, t))
            m.events.append((nil, blockEvent(for: t, day: day, start: start, end: end)))
        }
        if commit(m), let id = m.events.first?.after?.id { selection = [id] }
    }

    /// Puts an existing task on the grid. Length is `length`, or the task estimate.
    func schedule(taskId: String, day: DayKey, start: Int, length: Int? = nil) {
        guard let task = task(taskId) else { return }
        let len = max(5, length ?? task.estimateMin)
        let s = PlannerMath.clampMove(start: start, length: len)
        var m = Mutation(name: "Schedule Task")
        m.tasks.append((task, planned(task, on: day)))
        let e = blockEvent(for: task, day: day, start: s, end: s + len)
        m.events.append((nil, e))
        if commit(m) { selection = [e.id] }
    }

    /// First free gap for a task: from now (today) or from work start (other days).
    func fit(taskId: String, day: DayKey, workStart: Int, workEnd: Int, step: Int) {
        guard let task = task(taskId) else { return }
        let len = max(5, task.estimateMin)
        let busy = blocks(for: day...day).map(\.span)
        let from = day == .today() ? max(workStart, nowMinute()) : workStart
        if let slot = PlannerMath.firstFreeSlot(length: len, busy: busy, from: from, until: 1440, step: step) {
            schedule(taskId: taskId, day: day, start: slot, length: len)
        } else {
            showToast("No free gap of \(PlannerMath.duration(len)) on this day.")
        }
    }

    /// The plan for "Plan my day": each unscheduled task gets a free working-hours slot, by priority.
    func planMyDayPreview(day: DayKey, workStart: Int, workEnd: Int, step: Int) -> [(task: TaskItem, start: Int)] {
        var busy = blocks(for: day...day).map(\.span)
        var from = day == .today() ? max(workStart, nowMinute()) : workStart
        from = PlannerMath.snap(from, step: step)
        var out: [(TaskItem, Int)] = []
        for t in unscheduled(for: day) {
            let len = max(5, t.estimateMin)
            guard let slot = PlannerMath.firstFreeSlot(length: len, busy: busy, from: from, until: workEnd, step: step) else { continue }
            busy.append(Span(id: t.id, start: slot, end: slot + len))
            out.append((t, slot))
        }
        return out.map { (task: $0.0, start: $0.1) }
    }

    func applyPlan(_ plan: [(task: TaskItem, start: Int)], day: DayKey) {
        var m = Mutation(name: "Plan My Day")
        for p in plan {
            m.tasks.append((p.task, planned(p.task, on: day)))
            m.events.append((nil, blockEvent(for: p.task, day: day, start: p.start, end: p.start + max(5, p.task.estimateMin))))
        }
        commit(m)
    }

    /// Moves and resizes. With `ripple`, later overlapping blocks on the same day are pushed down.
    /// Returns how many other blocks were pushed.
    /// A block of a repeating event does not change until the user says "This event only" or "All events".
    @discardableResult
    func applyEdits(_ edits: [BlockEdit], ripple: Bool, name: String) -> Int {
        var all = edits
        var pushed = 0
        if ripple, let primary = edits.first {
            // Occurrences of a repeating event stay where they are. Only stored blocks are pushed.
            let others = blocks(for: primary.day...primary.day)
                .filter { b in OccurrenceID.parse(b.id) == nil && !edits.contains { $0.id == b.id } }.map(\.span)
            let moved = Span(id: primary.id, start: primary.start, end: primary.end)
            for s in PlannerMath.ripple(moved: moved, others: others) {
                all.append(BlockEdit(id: s.id, day: primary.day, start: s.start, end: s.end))
                pushed += 1
            }
        }
        var m = Mutation(name: name)
        var repeating: [(old: EventItem, new: EventItem)] = []
        for edit in all {
            guard let old = event(edit.id) else { continue }
            var new = draft(for: old)
            new.start = WallTime(day: edit.day, minute: edit.start)
            new.end = WallTime(day: edit.day, minute: edit.end)
            if OccurrenceID.parse(edit.id) != nil {
                if new != draft(for: old) { repeating.append((old, new)) }
                continue
            }
            guard new != old else { continue }
            m.events.append((old, new))
            if let tid = old.taskId, edit.day != old.start.day, let task = task(tid) {
                m.tasks.append((task, planned(task, on: edit.day)))
            }
        }
        if commit(m), pushed > 0 { showToast("Pushed \(pushed) block\(pushed == 1 ? "" : "s")") }
        changeOccurrences(repeating, verb: name.hasPrefix("Resize") ? "Resize" : "Move", name: name)
        return pushed
    }

    func rename(blockId: String, to title: String) {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let old = event(blockId) else { return }
        if OccurrenceID.parse(blockId) != nil {
            var new = draft(for: old)
            new.title = name
            changeOccurrences([(old, new)], verb: "Rename", name: "Rename")
            return
        }
        var m = Mutation(name: "Rename")
        var new = old
        new.title = name
        m.events.append((old, new))
        if let tid = old.taskId, let task = task(tid) {
            var t = task
            t.title = name
            m.tasks.append((task, t))
        }
        commit(m)
    }

    func setDuration(blockIds: [String], minutes: Int) {
        edit(blockIds, verb: "Change", name: "Change Duration") { e in
            e.end = WallTime(day: e.start.day, minute: min(1440, e.start.minute + minutes))
        }
    }

    func setColor(blockIds: [String], name: String) {
        edit(blockIds, verb: "Change", name: "Change Colour") { $0.color = name }
    }

    /// Applies `change` to each block. Stored blocks change at once. Blocks of a repeating event ask first.
    private func edit(_ ids: [String], verb: String, name: String, _ change: (inout EventItem) -> Void) {
        var m = Mutation(name: name)
        var repeating: [(old: EventItem, new: EventItem)] = []
        for id in ids {
            guard let old = event(id) else { continue }
            var new = draft(for: old)
            change(&new)
            if OccurrenceID.parse(id) != nil { repeating.append((old, new)) } else { m.events.append((old, new)) }
        }
        commit(m)
        changeOccurrences(repeating, verb: verb, name: name)
    }

    /// Removes blocks. The task stays and goes back to the unscheduled list.
    /// A block of a repeating event asks first: this day only, or the whole series.
    func deleteBlocks(_ ids: [String], name: String = "Delete Block") {
        var m = Mutation(name: name)
        var repeating: [EventItem] = []
        for id in ids {
            guard let old = event(id) else { continue }
            if OccurrenceID.parse(id) != nil { repeating.append(old) } else { m.events.append((old, nil)) }
        }
        if commit(m) { selection.subtract(ids) }
        guard !repeating.isEmpty else { return }
        askScope("Delete") { [weak self] scope in
            guard let self else { return }
            var all = Mutation(name: name)
            var seenSeries = Set<String>()
            for old in repeating {
                if scope == .all, let p = OccurrenceID.parse(old.id), !seenSeries.insert(p.series).inserted { continue }
                all.append(self.deletion(of: old, scope: scope, name: name))
            }
            if self.commit(all) { self.selection.subtract(ids) }
        }
    }

    func duplicate(blockIds: [String]) {
        var m = Mutation(name: "Duplicate")
        var newIds: Set<String> = []
        for id in blockIds {
            guard let old = event(id) else { continue }
            guard old.seriesId == nil else {
                showToast("A repeating event cannot be copied here yet.")
                continue
            }
            let len = old.end.minute - old.start.minute
            let s = PlannerMath.clampMove(start: old.end.minute, length: len)
            var copy = old
            copy.id = UUID().uuidString
            copy.start = WallTime(day: old.start.day, minute: s)
            copy.end = WallTime(day: old.start.day, minute: s + len)
            m.events.append((nil, copy))
            newIds.insert(copy.id)
        }
        if commit(m) { selection = newIds }
    }

    func split(blockId: String) {
        guard let old = event(blockId) else { return }
        guard old.seriesId == nil else { showToast("A repeating event cannot be split."); return }
        let len = old.end.minute - old.start.minute
        guard len >= 10 else { showToast("Block is too short to split."); return }
        let mid = max(old.start.minute + 5, min(old.end.minute - 5, PlannerMath.snap(old.start.minute + len / 2, step: 5)))
        var first = old
        first.end = WallTime(day: old.start.day, minute: mid)
        var second = old
        second.id = UUID().uuidString
        second.start = WallTime(day: old.start.day, minute: mid)
        var m = Mutation(name: "Split Block")
        m.events.append((old, first))
        m.events.append((nil, second))
        commit(m)
    }

    func nextFreeSlot(day: DayKey, length: Int, workStart: Int, step: Int) -> Int? {
        let busy = blocks(for: day...day).map(\.span)
        let from = day == .today() ? max(nowMinute(), 0) : workStart
        return PlannerMath.firstFreeSlot(length: length, busy: busy, from: from, until: 1440, step: step)
    }

    func nowMinute() -> Int {
        let c = GroveCalendar.cal.dateComponents([.hour, .minute], from: Date())
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
