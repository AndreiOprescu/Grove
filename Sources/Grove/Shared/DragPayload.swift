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
}
