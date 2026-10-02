import Foundation

public enum TaskStatus: String, Codable, Sendable { case open, done, cancelled }
public enum TaskBucket: String, Codable, Sendable { case inbox, day, week, someday }

/// A to-do item. (Named TaskItem to avoid clashing with Swift concurrency's `Task`.)
public struct TaskItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var summary: String          // one short line; shows on the planner block
    public var notes: String            // the long description (Markdown)
    public var listId: String?
    public var parentId: String?
    public var priority: Int            // 0 none … 3 high
    public var status: TaskStatus
    public var bucket: TaskBucket
    public var planDate: DayKey?        // when bucket == .day
    public var planWeek: DayKey?        // Monday, when bucket == .week
    public var due: String?             // "YYYY-MM-DD" or "YYYY-MM-DDTHH:MM"
    public var estimateMin: Int
    public var recurrence: RecurrenceRule?
    public var sourceNoteId: String?
    public var sort: Double
    public var createdAt: String
    public var updatedAt: String
    public var completedAt: String?

    public init(id: String = UUID().uuidString, title: String, summary: String = "", notes: String = "", listId: String? = nil,
                parentId: String? = nil, priority: Int = 0, status: TaskStatus = .open,
                bucket: TaskBucket = .inbox, planDate: DayKey? = nil, planWeek: DayKey? = nil,
                due: String? = nil, estimateMin: Int = 30, recurrence: RecurrenceRule? = nil,
                sourceNoteId: String? = nil, sort: Double = 0) {
        let now = Stamp.now()
        self.id = id; self.title = title; self.summary = summary; self.notes = notes; self.listId = listId
        self.parentId = parentId; self.priority = priority; self.status = status
        self.bucket = bucket; self.planDate = planDate; self.planWeek = planWeek
        self.due = due; self.estimateMin = estimateMin; self.recurrence = recurrence
        self.sourceNoteId = sourceNoteId; self.sort = sort
        self.createdAt = now; self.updatedAt = now; self.completedAt = nil
    }

    public var isDone: Bool { status == .done }
}

public struct ListItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var emoji: String
    public var color: String
    public var sort: Int
    public var archived: Bool

    public init(id: String = UUID().uuidString, name: String, emoji: String = "", color: String = "accent",
                sort: Int = 0, archived: Bool = false) {
        self.id = id; self.name = name; self.emoji = emoji; self.color = color
        self.sort = sort; self.archived = archived
    }
}

public struct Tag: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public init(id: String = UUID().uuidString, name: String) { self.id = id; self.name = name }
}
