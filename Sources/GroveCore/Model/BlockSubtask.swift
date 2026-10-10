import Foundation

/// One subtask of one goal block (an event). It belongs to that block only, not to the goal,
/// so another block of the same goal has its own list. Deleting the block deletes its subtasks.
public struct BlockSubtaskItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var eventId: String
    public var title: String
    /// When it was ticked done, or nil while it is open.
    public var doneAt: String?
    public var sort: Double
    public var createdAt: String
    public var updatedAt: String

    public var isDone: Bool { doneAt != nil }

    public init(id: String = UUID().uuidString, eventId: String, title: String, sort: Double = 0) {
        let now = Stamp.now()
        self.id = id; self.eventId = eventId; self.title = title; self.sort = sort
        self.doneAt = nil
        self.createdAt = now; self.updatedAt = now
    }
}
