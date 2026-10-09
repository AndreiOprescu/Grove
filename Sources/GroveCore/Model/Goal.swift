import Foundation

/// A recurring piece of work with a target of minutes per week and no date.
/// The user drags it into a day as a time block. A block that is marked done adds its length to the goal.
/// The hours done are never stored on the goal. They are worked out from its blocks (see `GoalRepo.doneMinutes`).
public struct GoalItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var notes: String
    /// One of `TaskColor.names`, or "" for none. A block of the goal takes this colour.
    public var color: String
    /// Minutes per week. 300 = 5 hours.
    public var targetMin: Int
    public var sort: Double
    public var archived: Bool
    public var createdAt: String
    public var updatedAt: String

    public init(id: String = UUID().uuidString, title: String, notes: String = "", color: String = "",
                targetMin: Int = 300, sort: Double = 0, archived: Bool = false) {
        let now = Stamp.now()
        self.id = id; self.title = title; self.notes = notes; self.color = color
        self.targetMin = targetMin; self.sort = sort; self.archived = archived
        self.createdAt = now; self.updatedAt = now
    }
}
