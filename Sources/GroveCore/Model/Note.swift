import Foundation

public enum NoteKind: String, Codable, Sendable { case note, daily, weekly }

public struct Note: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var body: String
    public var kind: NoteKind
    public var date: DayKey?            // daily: the day; weekly: the Monday
    public var pinned: Bool
    public var mood: Int?               // daily only, 1…3
    public var createdAt: String
    public var updatedAt: String

    public init(id: String = UUID().uuidString, title: String, body: String = "", kind: NoteKind = .note,
                date: DayKey? = nil, pinned: Bool = false, mood: Int? = nil) {
        let now = Stamp.now()
        self.id = id; self.title = title; self.body = body; self.kind = kind
        self.date = date; self.pinned = pinned; self.mood = mood
        self.createdAt = now; self.updatedAt = now
    }
}
