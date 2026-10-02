import Foundation

/// What a piece of a text is. The editor turns each kind into fonts and colours.
public enum SpanKind: Hashable, Sendable {
    /// A whole heading line, marker included.
    case heading(Int)
    /// The `## ` at the start of a heading.
    case headingMark
    /// A whole quote line, marker included.
    case quote
    case quoteMark
    /// Everything before the text of a list line: indent, marker, box and the space after it.
    case listPrefix
    /// The `- ` or `1. ` itself, without the indent.
    case listMark
    case checkbox(checked: Bool)
    /// The text after a ticked box.
    case checkedText
    /// The text between the markers. The markers are `.syntax`.
    case bold, italic, code
    /// Marker characters (`**`, `*`, `` ` ``).
    case syntax
    /// Characters the editor does not show.
    case hidden
    /// A whole `[[Title|ID]]`. `id` is nil until the title is resolved.
    case mention(id: String?, title: String)
    /// A whole `![alt](grove-image:ID)`.
    case image(id: String)
    case tag
    case link(String)
}

public struct TextSpan: Equatable, Sendable {
    public var kind: SpanKind
    /// UTF-16 offsets in the whole text.
    public var range: NSRange

    public init(_ kind: SpanKind, _ range: NSRange) { self.kind = kind; self.range = range }
}

/// Reads the Markdown that Grove uses and says what each part is. No UI, no state.
/// Nothing crosses a line, so a changed line can be read again alone.
public enum MarkdownSpans {
    /// Spans of the lines that touch `range`, or of the whole text. Sorted by position.
    public static func scan(_ text: String, in range: NSRange? = nil) -> [TextSpan] {
        let ns = text as NSString
        guard ns.length > 0 else { return [] }
        var target = NSRange(location: 0, length: ns.length)
        if let range {
            let loc = min(max(0, range.location), ns.length)
            let len = min(max(0, range.length), ns.length - loc)
            target = ns.lineRange(for: NSRange(location: loc, length: len))
        }

        var out: [TextSpan] = []
        ns.enumerateSubstrings(in: target, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            scanLine(ns.substring(with: lineRange) as NSString, at: lineRange.location, into: &out)
        }
        return out.enumerated().sorted { a, b in
            (a.element.range.location, a.offset) < (b.element.range.location, b.offset)
        }.map(\.element)
    }

    // MARK: Chips

    /// Mentions and images. The editor treats each as one character.
    public static func atoms(in spans: [TextSpan]) -> [NSRange] {
        spans.compactMap { span in
            switch span.kind {
            case .mention, .image: span.range
            default: nil
            }
        }
    }

    /// Moves a selection out of the middle of a chip. A caret goes to the edge it moves towards;
    /// a range grows to take whole chips.
    public static func snapped(_ selection: NSRange, in spans: [TextSpan], movingForward: Bool = true) -> NSRange {
        let atoms = atoms(in: spans)
        func inside(_ p: Int) -> NSRange? { atoms.first { $0.location < p && p < NSMaxRange($0) } }
        if selection.length == 0 {
            guard let a = inside(selection.location) else { return selection }
            return NSRange(location: movingForward ? NSMaxRange(a) : a.location, length: 0)
        }
        let start = inside(selection.location)?.location ?? selection.location
        let end = inside(NSMaxRange(selection)).map(NSMaxRange) ?? NSMaxRange(selection)
        return NSRange(location: start, length: end - start)
    }

    /// The range an edit must really replace: a change that touches part of a chip takes all of it.
    /// Typing inside a chip lands after it.
    public static func expanded(_ change: NSRange, in spans: [TextSpan]) -> NSRange {
        let atoms = atoms(in: spans)
        if change.length == 0 {
            guard let a = atoms.first(where: { $0.location < change.location && change.location < NSMaxRange($0) }) else { return change }
            return NSRange(location: NSMaxRange(a), length: 0)
        }
        var start = change.location, end = NSMaxRange(change)
        for a in atoms where a.location < end && start < NSMaxRange(a) {
            start = min(start, a.location)
            end = max(end, NSMaxRange(a))
        }
        return NSRange(location: start, length: end - start)
    }

    // MARK: One line

    private static let prefixRegex = try! NSRegularExpression(pattern: MarkdownEdit.prefixPattern)
    private static let codeRegex = try! NSRegularExpression(pattern: "`([^`\\n]+)`")
    private static let uuid = "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
    private static let imageRegex = try! NSRegularExpression(pattern: "!\\[([^\\]\\n]*)\\]\\(grove-image:(\(uuid))\\)")
    private static let linkRegex = try! NSRegularExpression(pattern: "https?://[^\\s<>\\[\\]]+")
    private static let tagRegex = try! NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}_#&/])#[\\p{L}\\p{N}_][\\p{L}\\p{N}_-]*")
    private static let tripleRegex = try! NSRegularExpression(pattern: "(?<!\\*)\\*\\*\\*(?![\\s*])(.+?)(?<![\\s*])\\*\\*\\*(?!\\*)")
    private static let boldRegex = try! NSRegularExpression(pattern: "(?<!\\*)\\*\\*(?![\\s*])(.+?)(?<![\\s*])\\*\\*(?!\\*)")
    private static let italicRegex = try! NSRegularExpression(pattern: "(?<!\\*)\\*(?![\\s*])(.+?)(?<![\\s*])\\*(?!\\*)")

    private static let placeholder = "\u{E000}"
    private static let linkTail = CharacterSet(charactersIn: ".,;:!?)'\"")

    private static func scanLine(_ line: NSString, at base: Int, into out: inout [TextSpan]) {
        let whole = NSRange(location: 0, length: line.length)
        guard whole.length > 0 else { return }
        var found: [TextSpan] = []
        func add(_ kind: SpanKind, _ loc: Int, _ len: Int) {
            guard len > 0 else { return }
            found.append(TextSpan(kind, NSRange(location: base + loc, length: len)))
        }

        var bodyStart = 0
        if let m = prefixRegex.firstMatch(in: line as String, range: whole) {
            bodyStart = m.range.length
            let indent = m.range(at: 1).length
            if m.range(at: 2).location != NSNotFound {
                let checked = line.substring(with: m.range(at: 3)) != " "
                add(.listPrefix, 0, bodyStart)
                add(.listMark, indent, 2)
                add(.checkbox(checked: checked), indent + 2, 3)
                if checked { add(.checkedText, bodyStart, whole.length - bodyStart) }
            } else if m.range(at: 4).location != NSNotFound || m.range(at: 5).location != NSNotFound {
                add(.listPrefix, 0, bodyStart)
                add(.listMark, indent, bodyStart - indent)
            } else if m.range(at: 6).location != NSNotFound {
                add(.heading(m.range(at: 6).length), 0, whole.length)
                add(.headingMark, 0, bodyStart)
            } else {
                add(.quote, 0, whole.length)
                add(.quoteMark, 0, bodyStart)
            }
        }

        // Markers are read on a copy where finished pieces are blanked, so they cannot be read twice.
        let masked = NSMutableString(string: line as String)
        func mask(_ r: NSRange) { masked.replaceCharacters(in: r, with: String(repeating: placeholder, count: r.length)) }
        func body() -> NSRange { NSRange(location: bodyStart, length: whole.length - bodyStart) }

        for m in codeRegex.matches(in: masked as String, range: body()) {
            add(.code, m.range(at: 1).location, m.range(at: 1).length)
            add(.syntax, m.range.location, 1)
            add(.syntax, NSMaxRange(m.range) - 1, 1)
            mask(m.range)
        }

        for m in imageRegex.matches(in: masked as String, range: body()) {
            let alt = m.range(at: 1), r = m.range
            add(.image(id: line.substring(with: m.range(at: 2))), r.location, r.length)
            if alt.length > 0 {
                add(.hidden, r.location, 2)
                add(.hidden, NSMaxRange(alt), NSMaxRange(r) - NSMaxRange(alt))
            } else {
                add(.hidden, NSMaxRange(alt) + 1, NSMaxRange(r) - NSMaxRange(alt) - 1)
            }
            mask(r)
        }

        let text = masked as String
        if text.contains("[[") {
            for m in ReferenceParser.mentions(in: text) {
                let r = NSRange(m.range, in: text)
                guard r.location >= bodyStart else { continue }
                add(.mention(id: m.id, title: m.title), r.location, r.length)
                add(.hidden, r.location, 2)
                if m.id != nil {
                    let bar = (text as NSString).range(of: "|", options: .backwards, range: r).location
                    add(.hidden, bar, NSMaxRange(r) - bar)
                } else {
                    add(.hidden, NSMaxRange(r) - 2, 2)
                }
                mask(r)
            }
        }

        for m in linkRegex.matches(in: masked as String, range: body()) {
            var r = m.range
            while r.length > 1, let last = (masked as NSString).substring(with: NSRange(location: NSMaxRange(r) - 1, length: 1)).unicodeScalars.first,
                  linkTail.contains(last) {
                r.length -= 1
            }
            add(.link((masked as NSString).substring(with: r)), r.location, r.length)
            mask(r)
        }

        for m in tagRegex.matches(in: masked as String, range: body()) { add(.tag, m.range.location, m.range.length) }

        for m in tripleRegex.matches(in: masked as String, range: body()) {
            let inner = m.range(at: 1)
            add(.bold, inner.location, inner.length)
            add(.italic, inner.location, inner.length)
            add(.syntax, m.range.location, 3)
            add(.syntax, NSMaxRange(m.range) - 3, 3)
        }
        for m in boldRegex.matches(in: masked as String, range: body()) {
            let inner = m.range(at: 1)
            add(.bold, inner.location, inner.length)
            add(.syntax, m.range.location, 2)
            add(.syntax, NSMaxRange(m.range) - 2, 2)
        }
        for m in italicRegex.matches(in: masked as String, range: body()) {
            let inner = m.range(at: 1)
            add(.italic, inner.location, inner.length)
            add(.syntax, m.range.location, 1)
            add(.syntax, NSMaxRange(m.range) - 1, 1)
        }

        out += found
    }
}
