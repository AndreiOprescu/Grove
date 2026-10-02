import Foundation

public enum EventKind: String, Codable, Sendable { case event, block }

/// A calendar event, or a task time-block (an event with `taskId` set).
public struct EventItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var start: WallTime
    public var end: WallTime
    public var allDay: Bool
    public var kind: EventKind
    public var taskId: String?
    public var color: String
    public var location: String
    public var notes: String
    public var recurrence: RecurrenceRule?
    public var seriesId: String?        // set on a detached occurrence of a series
    public var originalDate: DayKey?    // which occurrence it replaces
    public var createdAt: String
    public var updatedAt: String

    public init(id: String = UUID().uuidString, title: String, start: WallTime, end: WallTime,
                allDay: Bool = false, kind: EventKind = .event, taskId: String? = nil,
                color: String = "accent2", location: String = "", notes: String = "",
                recurrence: RecurrenceRule? = nil, seriesId: String? = nil, originalDate: DayKey? = nil) {
        let now = Stamp.now()
        self.id = id; self.title = title; self.start = start; self.end = end
        self.allDay = allDay; self.kind = kind; self.taskId = taskId; self.color = color
        self.location = location; self.notes = notes; self.recurrence = recurrence
        self.seriesId = seriesId; self.originalDate = originalDate
        self.createdAt = now; self.updatedAt = now
    }

    public var durationMinutes: Int {
        start.day == end.day ? end.minute - start.minute : end.minute + 1440 * start.day.days(until: end.day) - start.minute
    }
}
