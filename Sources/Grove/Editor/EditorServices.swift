import AppKit
import GroveCore

/// One row in the `[[` list.
struct MentionSuggestion: Identifiable, Equatable {
    var ref: ItemRef
    var title: String
    var kind: String
    var id: String { ref.id }
}

/// What the editor needs from the rest of the app. Closures keep the editor free of the store,
/// so it can be shown with any data.
struct EditorServices {
    /// Items that match what was typed after `[[`.
    var suggest: (_ query: String) -> [MentionSuggestion] = { _ in [] }
    /// False when the item a mention points at is gone.
    var isLive: (_ id: String) -> Bool = { _ in true }
    /// The current title of an item.
    var title: (_ id: String) -> String? = { _ in nil }
    /// Called when a mention is clicked.
    var open: (_ id: String?, _ title: String) -> Void = { _, _ in }
    /// Stores an image and returns its id. Nil when the data is not an image.
    var storeImage: (_ data: Data) -> String? = { _ in nil }
    var loadImage: (_ id: String) -> NSImage? = { _ in nil }
    var notify: (_ message: String) -> Void = { _ in }
}
