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
    /// The goal this block belongs to, or nil. A goal block has no task; `isDone` comes from the event's `doneAt`.
    var goalId: String?
    /// The subtasks of the block's task, in panel order, without cancelled ones.
    /// For a goal block: that one block's own subtasks (other blocks of the goal do not share them). Empty for events.
    var subtasks: [BlockSubtask] = []

    var span: Span { Span(id: id, start: startMinute, end: endMinute) }
    var length: Int { endMinute - startMinute }
    var isTaskBlock: Bool { taskId != nil }
    var isGoalBlock: Bool { goalId != nil }
}

/// One subtask line inside a task block or a goal block.
struct BlockSubtask: Identifiable, Equatable {
    var id: String
    var title: String
    var isDone: Bool
}

/// One block's new place, used by moves, resizes and ripple.
struct BlockEdit: Equatable {
    var id: String
    var day: DayKey
    var start: Int
    var end: Int
}
