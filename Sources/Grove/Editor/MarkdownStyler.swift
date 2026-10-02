import AppKit
import GroveCore

/// Fonts and colours of the editor text.
struct EditorStyle: Equatable {
    var size: CGFloat
    var ink: NSColor
    var muted: NSColor
    var accent: NSColor
    var accent2: NSColor
    var surface2: NSColor

    init(theme: Theme, size: CGFloat = 13) {
        self.size = size
        ink = NSColor(theme.ink)
        muted = NSColor(theme.muted)
        accent = NSColor(theme.accent)
        accent2 = NSColor(theme.accent2)
        surface2 = NSColor(theme.surface2)
    }

    var base: NSFont { .systemFont(ofSize: size) }
}

/// Turns the spans of `MarkdownSpans` into text attributes. Text stays plain Markdown;
/// only its look changes.
@MainActor
enum MarkdownStyler {
    static let headingScale: [CGFloat] = [1.55, 1.3, 1.15, 1.05, 1, 1]
    /// Hidden text is given no width and no colour. The characters are still there for editing.
    static let hiddenFont = NSFont.systemFont(ofSize: 0.01)

    static func baseAttributes(_ s: EditorStyle) -> [NSAttributedString.Key: Any] {
        [.font: s.base, .foregroundColor: s.ink, .paragraphStyle: paragraph(s)]
    }

    private static func paragraph(_ s: EditorStyle, indent: CGFloat = 0, before: CGFloat = 0) -> NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = s.size * 0.28
        p.paragraphSpacingBefore = before
        p.firstLineHeadIndent = 0
        p.headIndent = indent
        return p
    }

    /// Styles the paragraphs around `range`, or the whole text. `spans` are the spans of the whole text.
    static func apply(to storage: NSTextStorage, spans: [TextSpan], in range: NSRange?, style s: EditorStyle, isLive: (String) -> Bool) {
        let ns = storage.string as NSString
        guard ns.length > 0 else { return }
        var target = NSRange(location: 0, length: ns.length)
        if let range {
            let loc = min(max(0, range.location), ns.length)
            target = ns.paragraphRange(for: NSRange(location: loc, length: min(range.length, ns.length - loc)))
        }
        let mine = spans.filter { NSIntersectionRange($0.range, target).length > 0 }

        storage.beginEditing()
        storage.setAttributes(baseAttributes(s), range: target)
        for span in mine { style(span, in: storage, s, isLive: isLive) }
        for span in mine { styleParagraph(span, in: storage, ns, s) }
        storage.endEditing()
    }

    // MARK: Characters

    private static func style(_ span: TextSpan, in storage: NSTextStorage, _ s: EditorStyle, isLive: (String) -> Bool) {
        let r = span.range
        func set(_ key: NSAttributedString.Key, _ value: Any) { storage.addAttribute(key, value: value, range: r) }
        func font(_ change: @escaping (NSFont) -> NSFont) {
            var runs: [(NSRange, NSFont)] = []
            storage.enumerateAttribute(.font, in: r) { v, sub, _ in runs.append((sub, (v as? NSFont) ?? s.base)) }
            for (sub, f) in runs { storage.addAttribute(.font, value: change(f), range: sub) }
        }

        switch span.kind {
        case .heading(let level):
            let size = s.size * headingScale[min(max(level, 1), 6) - 1]
            set(.font, NSFont.systemFont(ofSize: size, weight: .bold))
        case .headingMark: set(.foregroundColor, s.muted.withAlphaComponent(0.6))
        case .quote: set(.foregroundColor, s.muted)
        case .quoteMark: set(.foregroundColor, NSColor.clear)
        case .listPrefix: break
        case .listMark:
            let ch = (storage.string as NSString).substring(with: NSRange(location: r.location, length: 1))
            // A bullet is drawn by the view as a dot. A number stays text.
            set(.foregroundColor, "-*+".contains(ch) ? NSColor.clear : s.accent)
        case .checkbox:
            set(.font, NSFont.monospacedSystemFont(ofSize: s.size * 0.7, weight: .regular))
            set(.foregroundColor, NSColor.clear)
        case .checkedText:
            set(.foregroundColor, s.muted)
            set(.strikethroughStyle, NSUnderlineStyle.single.rawValue)
        case .bold: font { traits($0, bold: true) }
        case .italic: font { traits($0, italic: true) }
        case .code:
            font { NSFont.monospacedSystemFont(ofSize: $0.pointSize * 0.92, weight: .regular) }
            set(.backgroundColor, s.surface2)
        case .syntax: set(.foregroundColor, s.muted.withAlphaComponent(0.55))
        case .hidden:
            set(.font, hiddenFont)
            set(.foregroundColor, NSColor.clear)
        case .mention(let id, _):
            font { NSFont.systemFont(ofSize: $0.pointSize, weight: .medium) }
            if let id, !isLive(id) {
                set(.foregroundColor, s.muted)
                set(.strikethroughStyle, NSUnderlineStyle.single.rawValue)
            } else {
                set(.foregroundColor, id == nil ? s.muted : s.accent)
            }
        case .image:
            font { NSFont.systemFont(ofSize: $0.pointSize, weight: .medium) }
            set(.foregroundColor, s.accent2)
        case .tag: set(.foregroundColor, s.accent2)
        case .link:
            set(.foregroundColor, s.accent)
            set(.underlineStyle, NSUnderlineStyle.single.rawValue)
        }
    }

    private static func traits(_ font: NSFont, bold: Bool = false, italic: Bool = false) -> NSFont {
        var t = font.fontDescriptor.symbolicTraits
        if bold { t.insert(.bold) }
        if italic { t.insert(.italic) }
        return NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(t), size: font.pointSize) ?? font
    }

    // MARK: Paragraphs

    /// Wrapped lines of a list item or a quote line up with its text, not with the margin.
    private static func styleParagraph(_ span: TextSpan, in storage: NSTextStorage, _ ns: NSString, _ s: EditorStyle) {
        let line = ns.paragraphRange(for: NSRange(location: span.range.location, length: 0))
        switch span.kind {
        case .listPrefix:
            let width = storage.attributedSubstring(from: span.range).size().width
            storage.addAttribute(.paragraphStyle, value: paragraph(s, indent: ceil(width)), range: line)
        case .quote:
            let width = storage.attributedSubstring(from: NSRange(location: span.range.location, length: min(2, span.range.length))).size().width
            storage.addAttribute(.paragraphStyle, value: paragraph(s, indent: ceil(width)), range: line)
        case .heading:
            let first = line.location == 0
            storage.addAttribute(.paragraphStyle, value: paragraph(s, before: first ? 0 : s.size * 0.6), range: line)
        default: break
        }
    }
}
