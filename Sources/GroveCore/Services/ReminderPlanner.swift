import Foundation

/// One notification to ask the system for (PLAN §5.6).
public struct Reminder: Equatable, Sendable {
    /// `ev-<event id>-<start>` for an event or a block, `due-<task id>-<due>` for a due time.
    /// The same thing at the same time always has the same id.
    public var id: String
    public var title: String
    public var body: String
    /// When it shows, in local time.
    public var fireAt: WallTime
    /// The day to open on a click.
    public var day: DayKey
    /// What to open on a click. A block opens its task.
    public var ref: ItemRef
}

/// Works out which reminders to schedule. No system calls here, so a test can check every rule.
public enum ReminderPlanner {
    /// The system keeps 64 pending notifications. Grove uses at most 60.
    public static let limit = 60
    public static let leadChoices = [0, 5, 10, 15]
    public static let defaultLead = 5

    /// - Parameters:
    ///   - events: events and blocks of the coming days, repeating events already split into days.
    ///   - dueTasks: tasks that have a due date. Only a due date with a time reminds.
    ///   - finishedTaskIds: tasks that are done or cancelled. Their blocks do not remind.
    ///   - now: the time now. A reminder at this time or before it is left out.
    ///   - lead: minutes before the start.
    public static func plan(events: [EventItem], dueTasks: [TaskItem], finishedTaskIds: Set<String>,
                            now: WallTime, lead: Int, limit: Int = ReminderPlanner.limit) -> [Reminder] {
        var all: [Reminder] = []

        for e in events where !e.allDay {
            if let taskId = e.taskId, finishedTaskIds.contains(taskId) { continue }
            let ref = e.taskId.map { ItemRef(.task, $0) } ?? ItemRef(.event, e.id)
            all.append(Reminder(id: "ev-\(e.id)-\(e.start.string)", title: e.title,
                                body: "\(PlannerMath.clock(e.start.minute)) – \(PlannerMath.clock(e.end.minute))",
                                fireAt: shifted(e.start, by: -lead), day: e.start.day, ref: ref))
        }

        for t in dueTasks where t.status == .open {
            guard let text = t.due, let due = WallTime(text) else { continue }
            all.append(Reminder(id: "due-\(t.id)-\(due.string)", title: t.title,
                                body: "Due \(PlannerMath.clock(due.minute))",
                                fireAt: shifted(due, by: -lead), day: due.day, ref: ItemRef(.task, t.id)))
        }

        return all.filter { $0.fireAt > now }
            .sorted { ($0.fireAt, $0.id) < ($1.fireAt, $1.id) }
            .prefix(limit).map { $0 }
    }

    /// `time` moved by some minutes, over midnight too.
    static func shifted(_ time: WallTime, by minutes: Int) -> WallTime {
        let total = time.minute + minutes
        let days = Int((Double(total) / 1440).rounded(.down))
        return WallTime(day: time.day.adding(days: days), minute: total - days * 1440)
    }
}
