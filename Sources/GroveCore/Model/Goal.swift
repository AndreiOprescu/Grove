import Foundation

/// What a goal counts each week: the hours of its blocks, or how many blocks there are.
public enum GoalKind: String, Codable, Hashable, Sendable, CaseIterable {
    case hours
    case sessions
}

/// A recurring piece of work with a weekly target and no date.
/// The user drags it into a day as a time block. Every block of the goal in a week adds to that week:
/// its length for an hours goal, one for a sessions goal.
/// The progress is never stored on the goal. It is worked out from its blocks (see `GoalRepo.minutes` and `GoalRepo.sessions`).
public struct GoalItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var notes: String
    /// One of `TaskColor.names`, or "" for none. A block of the goal takes this colour.
    public var color: String
    /// Minutes per week for an hours goal. 300 = 5 hours.
    public var targetMin: Int
    public var sort: Double
    public var archived: Bool
    public var createdAt: String
    public var updatedAt: String
    public var kind: GoalKind
    /// Sessions per week for a sessions goal.
    public var targetCount: Int

    public init(id: String = UUID().uuidString, title: String, notes: String = "", color: String = "",
                targetMin: Int = 300, sort: Double = 0, archived: Bool = false,
                kind: GoalKind = .hours, targetCount: Int = 3) {
        let now = Stamp.now()
        self.id = id; self.title = title; self.notes = notes; self.color = color
        self.targetMin = targetMin; self.sort = sort; self.archived = archived
        self.kind = kind; self.targetCount = targetCount
        self.createdAt = now; self.updatedAt = now
    }
}
