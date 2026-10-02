import AppKit
import UniformTypeIdentifiers
import GroveCore

/// What a key shortcut or a button asks the editor to do to the text.
enum EditorFormat {
    case bold, italic, code
    case line(LineStyle)
}

/// The text view of `RichTextEditor`. It draws what plain attributes cannot (chips, bullets, boxes, the
/// quote bar), and turns clicks, pastes and drops into editor actions. Text rules live in `GroveCore`.
@MainActor
final class GroveTextView: NSTextView {
    /// Spans of the whole text. The coordinator keeps them current.
    var spans: [TextSpan] = [] {
        didSet { window?.invalidateCursorRects(for: self) }
    }
    var style: EditorStyle?
    var isLive: (String) -> Bool = { _ in true }
    var placeholder = ""

    var onFormat: ((EditorFormat) -> Void)?
    var onOpenMention: ((String?, String) -> Void)?
    var onOpenImage: ((String) -> Void)?
    var onImages: (([(data: Data, name: String)]) -> Void)?
    var onTaskDrop: ((String, Int) -> Void)?
    var onAppearanceChange: (() -> Void)?
    /// Asked before a window-wide Esc shortcut. Return true when the editor used the key (it closed its list).
    var onEscape: (() -> Bool)?

    // MARK: Setup

    static func make() -> GroveTextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 300, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)

        let view = GroveTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 40), textContainer: container)
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.textContainerInset = NSSize(width: 0, height: 4)
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.registerForDraggedTypes([NSPasteboard.PasteboardType.string, NSPasteboard.PasteboardType.fileURL, NSPasteboard.PasteboardType.png, NSPasteboard.PasteboardType.tiff])
        return view
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let width = max(20, newSize.width - textContainerInset.width * 2)
        if let c = textContainer, abs(c.containerSize.width - width) > 0.5 {
            c.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }

    /// The height the text needs at `width`.
    func height(forWidth width: CGFloat) -> CGFloat {
        guard let layout = layoutManager, let container = textContainer else { return 0 }
        let inner = max(20, width - textContainerInset.width * 2)
        if abs(container.containerSize.width - inner) > 0.5 {
            container.containerSize = NSSize(width: inner, height: CGFloat.greatestFiniteMagnitude)
        }
        layout.ensureLayout(for: container)
        return ceil(layout.usedRect(for: container).height) + textContainerInset.height * 2
    }

    // MARK: Editing

    /// Applies an edit through the normal undo path.
    func apply(_ edit: TextEdit?, keepSelection: Bool = false) {
        guard let edit else { return }
        let before = selectedRange()
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        setSelectedRange(keepSelection ? before : edit.selection)
    }

    func format(_ f: EditorFormat) {
        let text = string, sel = selectedRange()
        switch f {
        case .bold: apply(MarkdownEdit.toggleWrap("**", in: text, selection: sel))
        case .italic: apply(MarkdownEdit.toggleWrap("*", in: text, selection: sel))
        case .code: apply(MarkdownEdit.toggleWrap("`", in: text, selection: sel))
        case .line(let style): apply(MarkdownEdit.toggleLine(style, in: text, selection: sel))
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased()
        if event.keyCode == 53, mods.isEmpty, onEscape?() == true { return true }
        switch (key, mods) {
        case ("b", [.command]): onFormat?(.bold); return true
        case ("i", [.command]): onFormat?(.italic); return true
        case ("e", [.command]): onFormat?(.code); return true
        // The app's own undo is for tasks and blocks. While there is typing to undo, ⌘Z belongs to the text.
        case ("z", [.command]) where undoManager?.canUndo == true: undoManager?.undo(); return true
        case ("z", [.command, .shift]) where undoManager?.canRedo == true: undoManager?.redo(); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    // MARK: Pasting and dropping

    static func images(from pb: NSPasteboard) -> [(data: Data, name: String)] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty {
            return urls.compactMap { url in
                (try? Data(contentsOf: url)).map { ($0, url.deletingPathExtension().lastPathComponent) }
            }
        }
        if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) { return [(data, "Image")] }
        return []
    }

    static func droppedTask(_ pb: NSPasteboard) -> String? {
        guard let s = pb.string(forType: .string), s.hasPrefix(DragPayload.taskPrefix) else { return nil }
        return String(s.dropFirst(DragPayload.taskPrefix.count))
    }

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        let files = pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true,
                                                                         .urlReadingContentsConformToTypes: [UTType.image.identifier]])
        if files || pb.string(forType: .string) == nil {
            let images = Self.images(from: pb)
            if !images.isEmpty { onImages?(images); return }
        }
        pasteAsPlainText(sender)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        accepts(sender) ? .copy : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        accepts(sender) ? .copy : super.draggingUpdated(sender)
    }

    private func accepts(_ sender: NSDraggingInfo) -> Bool {
        Self.droppedTask(sender.draggingPasteboard) != nil || !Self.images(from: sender.draggingPasteboard).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let index = characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil))
        if let id = Self.droppedTask(sender.draggingPasteboard) {
            onTaskDrop?(id, index)
            return true
        }
        let images = Self.images(from: sender.draggingPasteboard)
        if !images.isEmpty {
            setSelectedRange(NSRange(location: index, length: 0))
            onImages?(images)
            return true
        }
        return super.performDragOperation(sender)
    }

    // MARK: Hit testing

    /// Rectangles (in view coordinates) that the glyphs of `range` take, one per line.
    func rects(for range: NSRange) -> [NSRect] {
        guard let layout = layoutManager, let container = textContainer else { return [] }
        let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let origin = textContainerOrigin
        var out: [NSRect] = []
        layout.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
            out.append(rect.offsetBy(dx: origin.x, dy: origin.y))
        }
        return out
    }

    /// The box that is drawn for a checkbox: a square in the middle of the three characters.
    private func boxRect(for range: NSRange) -> NSRect? {
        guard let r = rects(for: range).first else { return nil }
        let side = min(15, max(12, (style?.size ?? 13) * 1.1))
        return NSRect(x: r.midX - side / 2, y: r.midY - side / 2, width: side, height: side)
    }

    private enum Hit {
        case checkbox(Int)
        case mention(String?, String)
        case image(String)
        case link(URL)
    }

    private func hit(at point: NSPoint, command: Bool) -> Hit? {
        for span in spans {
            switch span.kind {
            case .checkbox:
                if let box = boxRect(for: span.range), box.insetBy(dx: -4, dy: -4).contains(point) { return .checkbox(span.range.location) }
            case .mention(let id, let title):
                if rects(for: span.range).contains(where: { $0.insetBy(dx: -3, dy: 0).contains(point) }) { return .mention(id, title) }
            case .image(let id):
                if rects(for: span.range).contains(where: { $0.insetBy(dx: -3, dy: 0).contains(point) }) { return .image(id) }
            case .link(let s):
                if command, let url = URL(string: s), rects(for: span.range).contains(where: { $0.contains(point) }) { return .link(url) }
            default: break
            }
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch hit(at: point, command: event.modifierFlags.contains(.command)) {
        case .checkbox(let location):
            apply(MarkdownEdit.toggleCheckbox(in: string, at: location), keepSelection: true)
        case .mention(let id, let title): onOpenMention?(id, title)
        case .image(let id): onOpenImage?(id)
        case .link(let url): NSWorkspace.shared.open(url)
        case nil: super.mouseDown(with: event)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for span in spans {
            switch span.kind {
            case .mention, .image:
                for r in rects(for: span.range) { addCursorRect(r.intersection(bounds), cursor: .pointingHand) }
            case .checkbox:
                if let box = boxRect(for: span.range) { addCursorRect(box.intersection(bounds), cursor: .pointingHand) }
            default: break
            }
        }
    }

    // MARK: Drawing

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let style, layoutManager != nil else { return }

        if string.isEmpty, !placeholder.isEmpty {
            let origin = textContainerOrigin
            (placeholder as NSString).draw(at: NSPoint(x: origin.x, y: origin.y),
                                           withAttributes: [.font: style.base, .foregroundColor: style.muted.withAlphaComponent(0.7)])
        }

        for span in spans {
            switch span.kind {
            case .mention(let id, _):
                let tint: NSColor = id == nil ? style.muted : (isLive(id!) ? style.accent : style.muted)
                for r in rects(for: span.range) where r.intersects(rect) { chip(r, tint) }
            case .image:
                for r in rects(for: span.range) where r.intersects(rect) { chip(r, style.accent2) }
            case .checkbox(let checked):
                if let box = boxRect(for: span.range), box.intersects(rect) { drawBox(box, checked: checked, style) }
            case .listMark:
                let ch = (string as NSString).substring(with: NSRange(location: span.range.location, length: 1))
                // A checklist line has its box, so it gets no dot.
                let hasBox = spans.contains { if case .checkbox = $0.kind { $0.range.location == span.range.location + 2 } else { false } }
                guard "-*+".contains(ch), !hasBox, let r = rects(for: NSRange(location: span.range.location, length: 1)).first, r.intersects(rect) else { continue }
                let d: CGFloat = max(4, style.size * 0.34)
                style.accent.setFill()
                NSBezierPath(ovalIn: NSRect(x: r.midX - d / 2, y: r.midY - d / 2, width: d, height: d)).fill()
            case .quote:
                guard let layout = layoutManager else { continue }
                let origin = textContainerOrigin
                let glyphs = layout.glyphRange(forCharacterRange: span.range, actualCharacterRange: nil)
                layout.enumerateLineFragments(forGlyphRange: glyphs) { used, _, _, _, _ in
                    let bar = NSRect(x: origin.x, y: used.minY + origin.y + 1, width: 3, height: used.height - 2)
                    guard bar.intersects(rect) else { return }
                    style.accent.withAlphaComponent(0.55).setFill()
                    NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
                }
            default: break
            }
        }
    }

    private func chip(_ r: NSRect, _ tint: NSColor) {
        tint.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: r.insetBy(dx: -3, dy: 0), xRadius: 5, yRadius: 5).fill()
    }

    private func drawBox(_ box: NSRect, checked: Bool, _ style: EditorStyle) {
        let path = NSBezierPath(roundedRect: box.insetBy(dx: 0.75, dy: 0.75), xRadius: 4, yRadius: 4)
        if checked {
            style.accent.setFill()
            path.fill()
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: box.minX + box.width * 0.27, y: box.midY))
            tick.line(to: NSPoint(x: box.minX + box.width * 0.44, y: box.midY + box.height * 0.2))
            tick.line(to: NSPoint(x: box.minX + box.width * 0.75, y: box.midY - box.height * 0.2))
            tick.lineWidth = 1.8
            tick.lineCapStyle = .round
            tick.lineJoinStyle = .round
            NSColor.white.setStroke()
            tick.stroke()
        } else {
            style.muted.setStroke()
            path.lineWidth = 1.4
            path.stroke()
        }
    }
}
