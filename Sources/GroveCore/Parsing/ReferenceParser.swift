import Foundation

/// One `[[Title]]` or `[[Title|ID]]` found in a text.
public struct Mention {
    public var title: String
    /// The target's id, when the text carries one (`[[Title|ID]]`).
    public var id: String?
    /// Covers the whole `[[…]]` in the text it was parsed from.
    public var range: Range<String.Index>
}

/// Reads and writes the text forms Grove uses inside task bodies, notes and event notes:
/// mentions (`[[Title|ID]]`), images (`![alt](grove-image:ID)`) and hidden task markers (`⟦t:ID⟧`).
public enum ReferenceParser {
    private static let uuid = "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
    private static let mentionRegex = try! Regex("\\[\\[([^\\[\\]\\n]+)\\]\\]")
    private static let idRegex = try! Regex(uuid)
    private static let imageRegex = try! Regex("!\\[([^\\]\\n]*)\\]\\(grove-image:(\(uuid))\\)")
    private static let markerRegex = try! Regex("\\s?⟦t:[^⟧]*⟧")

    // MARK: Mentions

    public static func mentions(in text: String) -> [Mention] {
        text.matches(of: mentionRegex).compactMap { m in
            guard let inner = m.output[1].substring, let parts = split(inner) else { return nil }
            return Mention(title: parts.title, id: parts.id, range: m.range)
        }
    }

    /// The text for a mention. Characters that would break the syntax become spaces.
    public static func mention(title: String, id: String?) -> String {
        let clean = collapse(title, replacing: "[]|")
        let shown = clean.isEmpty ? "Untitled" : clean
        return id.map { "[[\(shown)|\($0)]]" } ?? "[[\(shown)]]"
    }

    /// Changes the title of every mention that points at `id`. Other text is untouched.
    public static func rewriting(_ text: String, id: String, to newTitle: String) -> String {
        var out = text
        for m in mentions(in: text).reversed() where m.id == id {
            out.replaceSubrange(m.range, with: mention(title: newTitle, id: id))
        }
        return out
    }

    private static func split(_ inner: Substring) -> (title: String, id: String?)? {
        var title = inner
        var id: String?
        if let bar = inner.lastIndex(of: "|") {
            let tail = inner[inner.index(after: bar)...].trimmingCharacters(in: .whitespaces)
            if tail.wholeMatch(of: idRegex) != nil {
                id = tail
                title = inner[..<bar]
            }
        }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : (trimmed, id)
    }

    // MARK: Images

    /// Attachment ids used by a text, in order, without repeats.
    public static func imageIDs(in text: String) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for m in text.matches(of: imageRegex) {
            if let id = m.output[2].substring.map(String.init), seen.insert(id).inserted { out.append(id) }
        }
        return out
    }

    public static func imageMarkup(id: String, alt: String) -> String {
        "![\(collapse(alt, replacing: "[]"))](grove-image:\(id))"
    }

    // MARK: Search

    /// The words of a text without ids and markup, so a search cannot hit a UUID.
    public static func searchText(_ text: String) -> String {
        var out = text.replacing(imageRegex) { $0.output[1].substring.map(String.init) ?? "" }
        for m in mentions(in: out).reversed() { out.replaceSubrange(m.range, with: m.title) }
        return out.replacing(markerRegex, with: "")
    }

    /// Newlines and the given characters become spaces; runs of spaces become one; ends are trimmed.
    private static func collapse(_ s: String, replacing bad: String) -> String {
        let spaced = String(s.map { $0.isNewline || $0.isWhitespace || bad.contains($0) ? " " : $0 })
        return spaced.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }
}
