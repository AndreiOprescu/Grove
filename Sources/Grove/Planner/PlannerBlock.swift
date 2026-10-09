import Foundation
import GroveCore

/// What the grid draws. Built from an event (and its task, if any).
struct PlannerBlock: Identifiable, Equatable {
    var id: String              // event id
    var title: String
    var summary: String = ""      // the short description of the task, if any
    var day: DayKey
    var startMinute: Int
    var endMinute: Int
    var kind: EventKind
    var taskId: String?
    var isDone: Bool
    var color: String
    var isRecurring: Bool
    var hasNote: Bool = false
    /// The priority of the block's task, 0 to 3. 0 for a block with no task.
    var priority: Int = 0
    /// The goal this block belongs to, or nil. A goal block has no task and is never done: it counts while it is there.
    var goalId: String?

    var span: Span { Span(id: id, start: startMinute, end: endMinute) }
    var length: Int { endMinute - startMinute }
    var isTaskBlock: Bool { taskId != nil }
    var isGoalBlock: Bool { goalId != nil }
}

/// One block's new place, used by moves, resizes and ripple.
struct BlockEdit: Equatable {
    var id: String
    var day: DayKey
    var start: Int
    var end: Int
}
