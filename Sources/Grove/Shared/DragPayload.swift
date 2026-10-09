import Foundation

/// Tasks and notes are dragged as plain strings, so no custom file type is needed.
enum DragPayload {
    static let taskPrefix = "grove-task:"
    static func task(_ id: String) -> String { taskPrefix + id }

    static let notePrefix = "grove-note:"
    static func note(_ id: String) -> String { notePrefix + id }
    /// The id in a dragged note, or nil when the text is something else.
    static func noteId(from raw: String) -> String? {
        raw.hasPrefix(notePrefix) ? String(raw.dropFirst(notePrefix.count)) : nil
    }

    static let goalPrefix = "grove-goal:"
    static func goal(_ id: String) -> String { goalPrefix + id }
    /// The id in a dragged goal, or nil when the text is something else (or has no id).
    static func goalId(from raw: String) -> String? {
        guard raw.hasPrefix(goalPrefix), raw.count > goalPrefix.count else { return nil }
        return String(raw.dropFirst(goalPrefix.count))
    }
}
