import Foundation

/// A task that had time blocks yesterday and is still open, with those blocks.
public struct RollOverItem: Equatable, Identifiable, Sendable {
    public var task: TaskItem
    public var blocks: [EventItem]
    public var id: String { task.id }
}

/// The end-of-day card (PLAN §5.1.7): "3 things from yesterday — Move to today / Leave".
/// Only blocks that start yesterday count. The answer is kept per day in the `settings` table.
public enum RollOver {
    static let handledKey = "rollover.handled"

    /// Open tasks with a block that starts on the day before `today`, in the order of their first block.
    public static func items(_ r: Repos, today: DayKey) throws -> [RollOverItem] {
        let yesterday = today.adding(days: -1)
        let blocks = try r.events.inRange(yesterday, yesterday)
            .filter { $0.kind == .block && $0.taskId != nil && $0.start.day == yesterday }
        var order: [String] = []
        var byTask: [String: [EventItem]] = [:]
        for b in blocks {
            guard let id = b.taskId else { continue }
            if byTask[id] == nil { order.append(id) }
            byTask[id, default: []].append(b)
        }
        return try order.compactMap { id in
            guard let task = try r.tasks.get(id), task.status == .open else { return nil }
            return RollOverItem(task: task, blocks: byTask[id] ?? [])
        }
    }

    /// True once the person answered the card on `today` ("Move" or "Leave").
    public static func isHandled(_ r: Repos, today: DayKey) -> Bool {
        ((try? r.settings.get(handledKey)) ?? nil) == today.string
    }

    public static func markHandled(_ r: Repos, today: DayKey) {
        try? r.settings.set(handledKey, today.string)
    }
}
