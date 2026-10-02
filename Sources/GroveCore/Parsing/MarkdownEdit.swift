import Foundation

/// One change to a text: replace `range` with `replacement`, then select `selection`.
/// `range` is in the old text and `selection` in the new text. Positions are UTF-16 offsets, as NSTextView uses.
public struct TextEdit: Equatable, Sendable {
    public var range: NSRange
    public var replacement: String
    public var selection: NSRange

    public init(range: NSRange, replacement: String, selection: NSRange) {
        self.range = range; self.replacement = replacement; self.selection = selection
    }
}

/// What a line can start with.
public enum LineStyle: Equatable, Sendable {
    case bullet, numbered, checklist, heading(Int), quote
}

/// The pure text rules of the editor: what Return, Tab and the format buttons do to a text.
/// No UI. The editor view applies the returned `TextEdit`.
public enum MarkdownEdit {
    // MARK: Line prefixes

    struct Prefix: Equatable {
        enum Kind: Equatable {
            case bullet(String)
            case numbered(Int)
            case checklist(bullet: String, checked: Bool)
            case heading(Int)
            case quote
        }
        var indent: Int
        var kind: Kind
        /// Indent, marker and the space after it, in UTF-16 units. All of these are ASCII.
        var length: Int

        var isList: Bool {
            switch kind {
            case .bullet, .numbered, .checklist: true
            case .heading, .quote: false
            }
        }

        func matches(_ style: LineStyle) -> Bool {
            switch (kind, style) {
            case (.bullet, .bullet), (.numbered, .numbered), (.checklist, .checklist), (.quote, .quote): true
            case (.heading(let a), .heading(let b)): a == b
            default: false
            }
        }
    }

    /// Groups: 1 indent · 2 and 3 checklist bullet and box · 4 bullet · 5 number · 6 hashes · 7 quote.
    static let prefixPattern = #"^( *)(?:([-*+]) \[([ xX])\] |([-*+]) |(\d{1,9})\. |(#{1,6}) |(> ))"#
    private static let prefixRegex = try! Regex(prefixPattern)

    static func prefix(of line: String) -> Prefix? {
        guard let m = line.prefixMatch(of: prefixRegex) else { return nil }
        let indent = m.output[1].substring?.count ?? 0
        let length = line[m.range].count
        let kind: Prefix.Kind
        if let b = m.output[2].substring { kind = .checklist(bullet: String(b), checked: m.output[3].substring != " ") }
        else if let b = m.output[4].substring { kind = .bullet(String(b)) }
        else if let n = m.output[5].substring, let value = Int(n) { kind = .numbered(value) }
        else if let h = m.output[6].substring { kind = .heading(h.count) }
        else { kind = .quote }
        return Prefix(indent: indent, kind: kind, length: length)
    }

    private static func marker(for style: LineStyle, number: Int) -> String {
        switch style {
        case .bullet: "- "
        case .numbered: "\(number). "
        case .checklist: "- [ ] "
        case .heading(let level): String(repeating: "#", count: min(6, max(1, level))) + " "
        case .quote: "> "
        }
    }

    private static func isListStyle(_ style: LineStyle) -> Bool {
        switch style {
        case .bullet, .numbered, .checklist: true
        case .heading, .quote: false
        }
    }

    // MARK: Whole lines

    private struct LineBlock {
        var range: NSRange
        var lines: [String]
        var trailingNewline: Bool
    }

    /// The whole lines a selection touches. A selection that ends right after a newline does not touch the next line.
    private static func block(_ ns: NSString, _ sel: NSRange) -> LineBlock {
        var end = sel.location + sel.length
        if sel.length > 0, end > 0, ns.character(at: end - 1) == 10 { end -= 1 }
        let range = ns.lineRange(for: NSRange(location: sel.location, length: max(0, end - sel.location)))
        var body = ns.substring(with: range)
        let trailing = body.hasSuffix("\n")
        if trailing { body.removeLast() }
        return LineBlock(range: range, lines: body.components(separatedBy: "\n"), trailingNewline: trailing)
    }

    /// Changes the start of every touched line. `change` gets the index among the handled lines and the line,
    /// and returns the new line plus how long its changed start was before and after (so the caret can follow).
    /// Returns nil when no line changed.
    private static func transformLines(_ text: String, _ sel: NSRange, skipBlank: Bool,
                                       _ change: (Int, String) -> (line: String, oldHead: Int, newHead: Int)?) -> TextEdit? {
        let ns = text as NSString
        let b = block(ns, sel)
        struct Info { var oldStart: Int; var newStart: Int; var oldHead: Int; var newHead: Int }
        var infos: [Info] = [], out: [String] = []
        var oldPos = 0, newPos = 0, handled = 0
        var changed = false
        for line in b.lines {
            let blank = line.trimmingCharacters(in: .whitespaces).isEmpty
            var result: (line: String, oldHead: Int, newHead: Int)?
            if !(blank && skipBlank) { result = change(handled, line); handled += 1 }
            let newLine = result?.line ?? line
            if newLine != line { changed = true }
            infos.append(Info(oldStart: oldPos, newStart: newPos, oldHead: result?.oldHead ?? 0, newHead: result?.oldHead ?? 0))
            if let r = result { infos[infos.count - 1].newHead = r.newHead }
            out.append(newLine)
            oldPos += (line as NSString).length + 1
            newPos += (newLine as NSString).length + 1
        }
        guard changed else { return nil }

        /// Where a position of the old text lands in the new text.
        func map(_ pos: Int) -> Int {
            let rel = pos - b.range.location
            let info = infos.last { $0.oldStart <= rel } ?? infos[0]
            let col = rel - info.oldStart
            let newCol = col >= info.oldHead ? col + (info.newHead - info.oldHead) : min(col, info.newHead)
            return b.range.location + info.newStart + newCol
        }
        let selection: NSRange
        if sel.length == 0 {
            selection = NSRange(location: map(sel.location), length: 0)
        } else {
            let start = sel.location == b.range.location ? b.range.location : map(sel.location)
            selection = NSRange(location: start, length: map(sel.location + sel.length) - start)
        }
        return TextEdit(range: b.range, replacement: out.joined(separator: "\n") + (b.trailingNewline ? "\n" : ""), selection: selection)
    }

    // MARK: Return

    /// Return on a list or quote line starts the next item. On an empty item it leaves the list
    /// (an indented item first moves one level out). Nil means "do the normal new line".
    public static func enter(in text: String, selection sel: NSRange) -> TextEdit? {
        guard sel.length == 0 else { return nil }
        let ns = text as NSString
        let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        var line = ns.substring(with: lineRange)
        if line.hasSuffix("\n") { line.removeLast() }
        guard let p = prefix(of: line), p.isList || p.kind == .quote else { return nil }
        guard sel.location - lineRange.location >= p.length else { return nil }

        if line.dropFirst(p.length).trimmingCharacters(in: .whitespaces).isEmpty {
            if p.indent >= 2 {
                return TextEdit(range: NSRange(location: lineRange.location, length: 2), replacement: "",
                                selection: NSRange(location: max(lineRange.location, sel.location - 2), length: 0))
            }
            return TextEdit(range: NSRange(location: lineRange.location, length: (line as NSString).length), replacement: "",
                            selection: NSRange(location: lineRange.location, length: 0))
        }
        let next: String
        switch p.kind {
        case .bullet(let b): next = "\(b) "
        case .numbered(let n): next = "\(n + 1). "
        case .checklist(let b, _): next = "\(b) [ ] "
        case .quote: next = "> "
        case .heading: return nil
        }
        let insert = "\n" + String(repeating: " ", count: p.indent) + next
        return TextEdit(range: sel, replacement: insert, selection: NSRange(location: sel.location + insert.utf16.count, length: 0))
    }

    // MARK: Tab

    /// Tab moves the list items in the selection one level in, Shift-Tab one level out (two spaces).
    /// Other lines stay as they are. Nil means "no list line here".
    public static func indent(in text: String, selection sel: NSRange, outdent: Bool) -> TextEdit? {
        transformLines(text, sel, skipBlank: false) { _, line in
            guard let p = prefix(of: line), p.isList else { return nil }
            if outdent {
                let k = min(2, p.indent)
                return k == 0 ? nil : (String(line.dropFirst(k)), k, 0)
            }
            return ("  " + line, 0, 2)
        }
    }

    // MARK: Bold, italic, code

    /// Puts `marker` (`**`, `*` or `` ` ``) around the selection, or takes it off when it is already there.
    /// With no selection it adds a pair and puts the caret between them.
    public static func toggleWrap(_ marker: String, in text: String, selection sel: NSRange) -> TextEdit {
        let ns = text as NSString
        let m = marker.utf16.count
        let mark = marker.utf16.first ?? 42
        let selEnd = sel.location + sel.length

        var left = 0, right = 0
        while sel.location - left - 1 >= 0, ns.character(at: sel.location - left - 1) == mark { left += 1 }
        while selEnd + right < ns.length, ns.character(at: selEnd + right) == mark { right += 1 }
        let n = min(left, right)
        // `*` is italic only when an odd number of stars sit around the text: two stars are bold.
        let wrapped = m == 1 && marker == "*" ? n % 2 == 1 : n >= m
        if wrapped {
            return TextEdit(range: NSRange(location: sel.location - m, length: sel.length + 2 * m),
                            replacement: ns.substring(with: sel),
                            selection: NSRange(location: sel.location - m, length: sel.length))
        }
        if marker != "*", sel.length > 2 * m {
            let chosen = ns.substring(with: sel)
            if chosen.hasPrefix(marker), chosen.hasSuffix(marker) {
                let inner = (chosen as NSString).substring(with: NSRange(location: m, length: sel.length - 2 * m))
                return TextEdit(range: sel, replacement: inner, selection: NSRange(location: sel.location, length: sel.length - 2 * m))
            }
        }
        if sel.length == 0 {
            return TextEdit(range: sel, replacement: marker + marker, selection: NSRange(location: sel.location + m, length: 0))
        }
        return TextEdit(range: sel, replacement: marker + ns.substring(with: sel) + marker,
                        selection: NSRange(location: sel.location + m, length: sel.length))
    }

    // MARK: Line styles

    /// Gives every touched line the style, or takes it off when all of them already have it.
    /// A line with another style gets this one instead. Empty lines are skipped when several lines are touched.
    public static func toggleLine(_ style: LineStyle, in text: String, selection sel: NSRange) -> TextEdit? {
        let lines = block(text as NSString, sel).lines
        let filled = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let allHaveIt = !filled.isEmpty && filled.allSatisfy { prefix(of: $0)?.matches(style) == true }
        let list = isListStyle(style)
        return transformLines(text, sel, skipBlank: lines.count > 1) { i, line in
            let p = prefix(of: line)
            let oldHead = p?.length ?? line.prefix(while: { $0 == " " }).count
            let keep = list ? (p?.indent ?? oldHead) : 0
            let head = String(repeating: " ", count: keep) + (allHaveIt ? "" : marker(for: style, number: i + 1))
            return (head + line.dropFirst(oldHead), oldHead, head.utf16.count)
        }
    }

    // MARK: Checklist

    /// Flips `[ ]` and `[x]` on the checklist line that contains `location`. Nil when it is not a checklist line.
    public static func toggleCheckbox(in text: String, at location: Int) -> TextEdit? {
        let ns = text as NSString
        guard location >= 0, location <= ns.length else { return nil }
        let lineRange = ns.lineRange(for: NSRange(location: location, length: 0))
        guard let p = prefix(of: ns.substring(with: lineRange)), case .checklist(_, let checked) = p.kind else { return nil }
        return TextEdit(range: NSRange(location: lineRange.location + p.indent + 3, length: 1),
                        replacement: checked ? " " : "x",
                        selection: NSRange(location: location, length: 0))
    }

    // MARK: Mentions

    /// An open `[[` before the caret: the range from the brackets to the caret, and the text typed after them.
    public struct MentionTrigger: Equatable, Sendable {
        public var range: NSRange
        public var query: String
    }

    public static func mentionTrigger(in text: String, caret: Int) -> MentionTrigger? {
        let ns = text as NSString
        guard caret >= 0, caret <= ns.length else { return nil }
        let lineStart = ns.lineRange(for: NSRange(location: caret, length: 0)).location
        let before = ns.substring(with: NSRange(location: lineStart, length: caret - lineStart)) as NSString
        let open = before.range(of: "[[", options: .backwards)
        guard open.location != NSNotFound else { return nil }
        let query = before.substring(from: open.location + 2)
        guard query.rangeOfCharacter(from: CharacterSet(charactersIn: "[]|")) == nil else { return nil }
        return MentionTrigger(range: NSRange(location: lineStart + open.location, length: caret - lineStart - open.location), query: query)
    }

    /// Writes `[[Title|ID]]` over what the user typed after `[[`. The caret ends after it.
    public static func insertMention(title: String, id: String, replacing range: NSRange) -> TextEdit {
        let text = ReferenceParser.mention(title: title, id: id)
        return TextEdit(range: range, replacement: text, selection: NSRange(location: range.location + text.utf16.count, length: 0))
    }

    /// Puts an image on a line of its own at the selection. The caret ends on the line after it.
    public static func insertImage(id: String, alt: String, in text: String, selection: NSRange) -> TextEdit {
        let ns = text as NSString
        let newline = unichar(10)
        let lead = selection.location > 0 && ns.character(at: selection.location - 1) != newline ? "\n" : ""
        let end = NSMaxRange(selection)
        let nextIsBreak = end < ns.length && ns.character(at: end) == newline
        let replacement = lead + ReferenceParser.imageMarkup(id: id, alt: alt) + (nextIsBreak ? "" : "\n")
        // When a line break follows, the caret steps over it. It is part of the text that stays.
        let caret = selection.location + replacement.utf16.count + (nextIsBreak ? 1 : 0)
        return TextEdit(range: selection, replacement: replacement, selection: NSRange(location: caret, length: 0))
    }

    /// The text without the image `id`. A line that held only that image goes away with its line break.
    public static func removeImage(id: String, from text: String) -> String {
        let ns = text as NSString
        let pattern = "!\\[[^\\]\\n]*\\]\\(grove-image:\(NSRegularExpression.escapedPattern(for: id))\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        var out = text
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            var cut = m.range
            let line = ns.lineRange(for: m.range)
            let alone = line.location == cut.location && (NSMaxRange(line) == NSMaxRange(cut)
                || (NSMaxRange(line) - 1 == NSMaxRange(cut) && ns.character(at: NSMaxRange(cut)) == 10))
            if alone {
                cut = line
                // the last line has no break of its own: take the one before it
                if NSMaxRange(line) == ns.length, line.location > 0, ns.character(at: line.location - 1) == 10 {
                    cut = NSRange(location: line.location - 1, length: line.length + 1)
                }
            }
            out = (out as NSString).replacingCharacters(in: cut, with: "")
        }
        return out
    }
}
