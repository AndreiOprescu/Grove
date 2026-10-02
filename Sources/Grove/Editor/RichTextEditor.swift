import SwiftUI
import AppKit
import UniformTypeIdentifiers
import GroveCore

/// Lets the buttons around an editor act on its text.
@Observable @MainActor
final class EditorController {
    @ObservationIgnored fileprivate weak var textView: GroveTextView?
    @ObservationIgnored fileprivate weak var coordinator: RichTextEditor.Coordinator?
    /// The image shown large, if any.
    var previewImageId: String?

    func format(_ f: EditorFormat) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.format(f)
    }

    /// Types `[[` so the list of items opens.
    func startMention() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        let sel = textView.selectedRange()
        textView.apply(TextEdit(range: sel, replacement: "[[", selection: NSRange(location: sel.location + 2, length: 0)))
    }

    func addImage() {
        guard let textView, let window = textView.window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            let items = panel.urls.compactMap { url in
                (try? Data(contentsOf: url)).map { (data: $0, name: url.deletingPathExtension().lastPathComponent) }
            }
            MainActor.assumeIsolated { self?.coordinator?.importImages(items) }
        }
    }

    func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }
}

/// A Markdown editor that shows bold, lists, headings, mention chips and image names as it should look,
/// while the stored text stays plain Markdown. Grows to fit its text.
struct RichTextEditor: NSViewRepresentable {
    @Binding var text: String
    var controller: EditorController
    var services: EditorServices
    var fontSize: CGFloat = 13
    var minHeight: CGFloat = 80
    var placeholder = ""
    /// Change this when something the text points at may have changed, so chips are checked again.
    var refreshToken = 0
    /// Called when the text loses the keyboard.
    var onEnd: () -> Void = {}
    @Environment(\.theme) private var theme

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> GroveTextView {
        let view = GroveTextView.make()
        let c = context.coordinator
        c.attach(view, controller: controller)
        c.style = EditorStyle(theme: theme, size: fontSize)
        c.theme = theme
        view.placeholder = placeholder
        view.string = text
        c.reload()
        return view
    }

    func updateNSView(_ view: GroveTextView, context: Context) {
        let c = context.coordinator
        c.parent = self
        view.placeholder = placeholder
        let style = EditorStyle(theme: theme, size: fontSize)
        var restyle = false
        if style != c.style || c.theme.id != theme.id {
            c.style = style
            c.theme = theme
            restyle = true
        }
        if c.lastToken != refreshToken {
            c.lastToken = refreshToken
            c.liveCache = [:]
            restyle = true
        }
        if view.string != text, !view.hasMarkedText() {
            // The text was changed from outside (another task was opened, or an undo).
            let sel = view.selectedRange()
            view.string = text
            view.setSelectedRange(NSRange(location: min(sel.location, (text as NSString).length), length: 0))
            c.reload()
        } else if restyle, !view.hasMarkedText() {
            c.reload()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: GroveTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        return CGSize(width: width, height: max(minHeight, nsView.height(forWidth: width)))
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        var style: EditorStyle?
        var theme: Theme = .grove
        var liveCache: [String: Bool] = [:]
        var lastToken = 0

        private weak var view: GroveTextView?
        private let popup = MentionPopup()
        private var spans: [TextSpan] = []
        /// True between an edit and the next scan. Spans do not match the text then.
        private var stale = false
        private var pendingEdit: NSRange?
        /// Where the user pressed Esc on a list, so it stays closed until they leave that `[[`.
        private var dismissedAt: Int?
        private var shown: (location: Int, query: String)?

        init(_ parent: RichTextEditor) {
            self.parent = parent
            super.init()
            popup.onPick = { [weak self] in self?.accept($0) }
        }

        func attach(_ view: GroveTextView, controller: EditorController) {
            self.view = view
            view.delegate = self
            controller.textView = view
            controller.coordinator = self
            view.onFormat = { [weak view] in view?.format($0) }
            view.onOpenMention = { [weak self] id, title in self?.parent.services.open(id, title) }
            view.onOpenImage = { [weak controller] in controller?.previewImageId = $0 }
            view.onImages = { [weak self] in self?.importImages($0) }
            view.onTaskDrop = { [weak self] id, index in self?.dropTask(id, at: index) }
            view.onAppearanceChange = { [weak self] in self?.appearanceChanged() }
            view.onEscape = { [weak self] in self?.closeList() ?? false }
        }

        // MARK: Look

        private func live(_ id: String) -> Bool {
            if let known = liveCache[id] { return known }
            let value = parent.services.isLive(id)
            liveCache[id] = value
            return value
        }

        /// Reads and styles the whole text.
        func reload() {
            guard let view else { return }
            spans = MarkdownSpans.scan(view.string)
            stale = false
            restyle(nil)
        }

        private func restyle(_ range: NSRange?) {
            guard let view, let style, let storage = view.textStorage else { return }
            view.spans = spans
            view.style = style
            view.isLive = { [weak self] in self?.live($0) ?? true }
            MarkdownStyler.apply(to: storage, spans: spans, in: range, style: style, isLive: { [weak self] in self?.live($0) ?? true })
            view.typingAttributes = MarkdownStyler.baseAttributes(style)
            view.needsDisplay = true
        }

        private func appearanceChanged() {
            guard let view else { return }
            view.effectiveAppearance.performAsCurrentDrawingAppearance {
                style = EditorStyle(theme: theme, size: parent.fontSize)
            }
            reload()
        }

        // MARK: Text changes

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            guard let replacement = replacementString, let view = textView as? GroveTextView else { return true }
            stale = true
            if !view.hasMarkedText() {
                // A mention or image is one unit. A change that touches part of it takes all of it.
                let whole = MarkdownSpans.expanded(range, in: spans)
                if whole != range {
                    let caret = whole.location + (replacement as NSString).length
                    view.apply(TextEdit(range: whole, replacement: replacement, selection: NSRange(location: caret, length: 0)))
                    return false
                }
            }
            pendingEdit = NSRange(location: range.location, length: (replacement as NSString).length)
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let view else { return }
            let edited = pendingEdit
            pendingEdit = nil
            spans = MarkdownSpans.scan(view.string)
            stale = false
            if !view.hasMarkedText() { restyle(edited) } else { view.spans = spans }
            parent.text = view.string
            view.invalidateIntrinsicContentSize()
            updateMentionList()
        }

        func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRange old: NSRange, toCharacterRange new: NSRange) -> NSRange {
            guard !stale, !textView.hasMarkedText() else { return new }
            return MarkdownSpans.snapped(new, in: spans, movingForward: new.location >= old.location)
        }

        func textViewDidChangeSelection(_ notification: Notification) { updateMentionList() }

        func textDidEndEditing(_ notification: Notification) {
            popup.hide()
            shown = nil
            parent.onEnd()
        }

        // MARK: Keys

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let view = textView as? GroveTextView else { return false }
            let open = popup.isVisible
            switch selector {
            case #selector(NSResponder.moveDown(_:)) where open:
                popup.move(1)
                return true
            case #selector(NSResponder.moveUp(_:)) where open:
                popup.move(-1)
                return true
            case #selector(NSResponder.cancelOperation(_:)) where open:
                return closeList()
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                if open, let item = popup.current {
                    accept(item)
                    return true
                }
                if selector == #selector(NSResponder.insertTab(_:)) { return indent(view, outdent: false) }
                guard let edit = MarkdownEdit.enter(in: view.string, selection: view.selectedRange()) else { return false }
                view.apply(edit)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                return indent(view, outdent: true)
            default:
                return false
            }
        }

        /// Esc closes the `[[` list and keeps it closed until the caret leaves that `[[`. False when no list is open.
        private func closeList() -> Bool {
            guard popup.isVisible, let view else { return false }
            dismissedAt = MarkdownEdit.mentionTrigger(in: view.string, caret: view.selectedRange().location)?.range.location
            popup.hide()
            shown = nil
            return true
        }

        /// Tab moves a list item in. Anywhere else it moves to the next field.
        private func indent(_ view: GroveTextView, outdent: Bool) -> Bool {
            if let edit = MarkdownEdit.indent(in: view.string, selection: view.selectedRange(), outdent: outdent) {
                view.apply(edit)
            } else if outdent {
                view.window?.selectPreviousKeyView(nil)
            } else {
                view.window?.selectNextKeyView(nil)
            }
            return true
        }

        // MARK: Mentions

        private func updateMentionList() {
            guard let view, let window = view.window, window.firstResponder === view, !view.hasMarkedText(), !stale else {
                popup.hide()
                shown = nil
                return
            }
            let sel = view.selectedRange()
            guard sel.length == 0, let trigger = MarkdownEdit.mentionTrigger(in: view.string, caret: sel.location) else {
                popup.hide()
                shown = nil
                dismissedAt = nil
                return
            }
            if dismissedAt == trigger.range.location { return }
            if let shown, shown.location == trigger.range.location, shown.query == trigger.query, popup.isVisible { return }
            shown = (trigger.range.location, trigger.query)
            let caret = view.firstRect(forCharacterRange: NSRange(location: sel.location, length: 0), actualRange: nil)
            popup.show(parent.services.suggest(trigger.query), at: caret, in: window, theme: theme)
        }

        private func accept(_ item: MentionSuggestion) {
            guard let view, let trigger = MarkdownEdit.mentionTrigger(in: view.string, caret: view.selectedRange().location) else { return }
            popup.hide()
            shown = nil
            view.apply(MarkdownEdit.insertMention(title: item.title, id: item.ref.id, replacing: trigger.range))
        }

        private func dropTask(_ id: String, at index: Int) {
            guard let view, let title = parent.services.title(id) else { return }
            view.window?.makeFirstResponder(view)
            view.apply(MarkdownEdit.insertMention(title: title, id: id, replacing: NSRange(location: index, length: 0)))
        }

        // MARK: Images

        func importImages(_ items: [(data: Data, name: String)]) {
            guard let view else { return }
            for item in items {
                guard let id = parent.services.storeImage(item.data) else {
                    parent.services.notify("\(item.name) is not an image Grove can read.")
                    continue
                }
                view.apply(MarkdownEdit.insertImage(id: id, alt: item.name, in: view.string, selection: view.selectedRange()))
            }
        }
    }
}
