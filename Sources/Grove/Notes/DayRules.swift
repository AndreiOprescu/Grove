import Foundation
import GroveCore

/// One line in the day panel of a daily note.
struct AgendaRow: Identifiable, Equatable {
    enum Kind { case event, block, task }
    var id: String
    var kind: Kind
    var title: String
    /// Minutes since midnight. Nil for an all-day event and for a task that has no block on the day.
    var start: Int?
    var end: Int?
    var allDay = false
    var done = false
    /// What a click opens.
    var ref: ItemRef
}

/// A busy day in the weekly review.
struct BusyDay: Equatable {
    var day: DayKey
    var minutes: Int
}

/// What the week showed, for the review panel and the summary text.
struct WeekReview: Equatable {
    var monday: DayKey
    /// Tasks finished in the week, in the order they were finished.
    var done: [TaskItem]
    /// Tasks planned for the week that are still open. Tasks with a day come first.
    var open: [TaskItem]
    /// Minutes of task blocks in the week.
    var plannedMinutes: Int
    /// Minutes of those blocks whose task is done.
    var doneMinutes: Int
    /// The day with the most booked time (task blocks and timed events). Nil when no time is booked.
    var busiest: BusyDay?
}

/// The rules behind the day panel and the weekly review. No database and no views here.
enum DayRules {
    // MARK: The day panel

    /// What a day holds, in the order the panel shows it: all-day events, then events and task blocks by start time,
    /// then the day's tasks that have no block (open ones first). A task with a block shows once, as its block.
    static func agenda(day: DayKey, events: [EventItem], dayTasks: [TaskItem], taskFor: (String) -> TaskItem?) -> [AgendaRow] {
        var allDay: [AgendaRow] = []
        var timed: [AgendaRow] = []
        var blocked = Set<String>()
        for e in events where CalendarRules.covers(e, day) {
            if e.kind == .block, let id = e.taskId, let t = taskFor(id) {
                blocked.insert(id)
                timed.append(AgendaRow(id: e.id, kind: .block, title: t.title, start: start(of: e, on: day), end: end(of: e, on: day),
                                       done: t.isDone, ref: ItemRef(.task, id)))
            } else if e.allDay {
                allDay.append(AgendaRow(id: e.id, kind: .event, title: e.title, allDay: true, ref: ItemRef(.event, e.id)))
            } else {
                timed.append(AgendaRow(id: e.id, kind: .event, title: e.title, start: start(of: e, on: day), end: end(of: e, on: day),
                                       ref: ItemRef(.event, e.id)))
            }
        }
        allDay.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        timed.sort { ($0.start ?? 0, $0.end ?? 0, $0.title) < ($1.start ?? 0, $1.end ?? 0, $1.title) }
        let loose = dayTasks.filter { !blocked.contains($0.id) }
        let open = loose.filter { !$0.isDone }, finished = loose.filter(\.isDone)
        let tasks = (open + finished).map {
            AgendaRow(id: $0.id, kind: .task, title: $0.title, done: $0.isDone, ref: ItemRef(.task, $0.id))
        }
        return allDay + timed + tasks
    }

    private static func start(of e: EventItem, on day: DayKey) -> Int { e.start.day == day ? e.start.minute : 0 }
    private static func end(of e: EventItem, on day: DayKey) -> Int { e.end.day == day ? e.end.minute : 1440 }

    /// "09:00" or "09:00–10:30" for a timed row. "All day" for an all-day event. Empty for a task with no block.
    static func timeLabel(_ row: AgendaRow) -> String {
        if row.allDay { return "All day" }
        guard let s = row.start, let e = row.end else { return "" }
        return e > s ? "\(PlannerMath.clock(s))–\(PlannerMath.clock(e == 1440 ? 1439 : e))" : PlannerMath.clock(s)
    }

    /// The clock time a task was finished. `completedAt` is "YYYY-MM-DDTHH:MM:SS".
    static func finishedClock(_ task: TaskItem) -> String {
        guard let at = task.completedAt, at.count >= 16 else { return "" }
        return String(at.dropFirst(11).prefix(5))
    }

    // MARK: The weekly review

    static func review(monday: DayKey, done: [TaskItem], openCandidates: [TaskItem], events: [EventItem],
                       taskFor: (String) -> TaskItem?) -> WeekReview {
        var seen = Set<String>()
        let stillOpen = openCandidates.filter { $0.status == .open && seen.insert($0.id).inserted }
        let open = stillOpen.filter { $0.planDate != nil } + stillOpen.filter { $0.planDate == nil }   // tasks with a day first

        var planned = 0, finished = 0
        var perDay: [DayKey: Int] = [:]
        for e in events where !e.allDay {
            // A block or event that runs past midnight counts on each day it touches.
            var day = e.start.day
            while day <= e.end.day {
                let from = day == e.start.day ? e.start.minute : 0
                let to = day == e.end.day ? e.end.minute : 1440
                if to > from, day >= monday, day <= monday.adding(days: 6) { perDay[day, default: 0] += to - from }
                day = day.adding(days: 1)
            }
            guard e.kind == .block, let id = e.taskId, let t = taskFor(id) else { continue }
            planned += e.durationMinutes
            if t.isDone { finished += e.durationMinutes }
        }
        let busiest = perDay.filter { $0.value > 0 }.min { ($1.value, $0.key) < ($0.value, $1.key) }
            .map { BusyDay(day: $0.key, minutes: $0.value) }
        return WeekReview(monday: monday, done: done, open: open, plannedMinutes: planned, doneMinutes: finished, busiest: busiest)
    }

    // MARK: The summary text

    /// The first line of the summary. It marks the block, so a second click can replace it.
    static let summaryHeading = "**Week summary**"

    private static func count(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }

    private static func mentions(_ tasks: [TaskItem], limit: Int = 8) -> String {
        let shown = tasks.prefix(limit).map { ReferenceParser.mention(title: $0.title, id: $0.id) }.joined(separator: ", ")
        return tasks.count > limit ? "\(shown) and \(tasks.count - limit) more" : shown
    }

    /// Plain Markdown lines with no blank line, so the block can be found again.
    static func summary(_ r: WeekReview) -> String {
        var lines = [summaryHeading]
        lines.append("- Done: \(count(r.done.count, "task"))")
        lines.append("- Still open: \(count(r.open.count, "task"))")
        lines.append(r.plannedMinutes == 0
                     ? "- Time: no task blocks planned"
                     : "- Time: \(PlannerMath.duration(r.doneMinutes)) finished of \(PlannerMath.duration(r.plannedMinutes)) planned")
        if let b = r.busiest { lines.append("- Busiest day: \(NotesRules.weekdayName(b.day)), \(PlannerMath.duration(b.minutes))") }
        if !r.done.isEmpty { lines.append("- Finished: \(mentions(r.done))") }
        if !r.open.isEmpty { lines.append("- Left open: \(mentions(r.open))") }
        return lines.joined(separator: "\n")
    }

    static func hasSummary(_ body: String) -> Bool {
        body.components(separatedBy: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == summaryHeading }
    }

    /// Puts `block` under the `## Review` heading. A summary that is already there is replaced.
    /// The heading is added at the end when the note has none.
    static func insert(_ block: String, into body: String) -> String {
        var lines = body.components(separatedBy: "\n")
        let blockLines = block.components(separatedBy: "\n")
        func isBlank(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespaces).isEmpty }

        if let at = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == summaryHeading }) {
            var end = at + 1
            while end < lines.count, !isBlank(lines[end]) { end += 1 }
            lines.replaceSubrange(at..<end, with: blockLines)
            return lines.joined(separator: "\n")
        }
        if let at = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "## Review" }) {
            let next = at + 1
            let needsGap = next < lines.count && !isBlank(lines[next])
            lines.insert(contentsOf: needsGap ? blockLines + [""] : blockLines, at: next)
            return lines.joined(separator: "\n")
        }
        var head = body
        while head.hasSuffix("\n") { head.removeLast() }
        return (head.isEmpty ? "" : head + "\n\n") + "## Review\n" + block + "\n"
    }
}
