import Foundation

/// Tasks are dragged as plain strings, so no custom file type is needed.
enum DragPayload {
    static let taskPrefix = "grove-task:"
    static func task(_ id: String) -> String { taskPrefix + id }
}
