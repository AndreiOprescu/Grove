import Foundation

/// One `- [ ] text` line of a note.
public struct NoteCheckbox: Equatable, Sendable {
    /// Index of the line in the text, from 0.
    public var line: Int
    public var checked: Bool
    /// The words after the box, without the hidden task marker.
    public var text: String
    /// The task this line made, read from the hidden marker. Nil until a task exists.
    public var taskId: String?
}

/// What the app reads out of a note's text: `#tags` and check box lines.
public enum NoteParser {
    // MARK: Tags

    private static let tagRegex = try! NSRegularExpression(pattern: #"(?<![\w#&/\[\]])#([A-Za-z]\w*(?:-\w+)*)"#)
    /// Spans that never hold a tag: code, `[[mentions]]` and links or images.
    private static let skipRegexes = [#"`[^`\n]*`"#, #"\[\[[^\]\n]*\]\]"#, #"!?\[[^\]\n]*\]\([^)\n]*\)"#]
        .map { try! NSRegularExpression(pattern: $0) }

    /// The `#tags` in a text, each once (letter case ignored), in the order they first appear.
    public static func tags(in text: String) -> [String] {
        var clean = text
        for r in skipRegexes {
            clean = r.stringByReplacingMatches(in: clean, range: NSRange(clean.startIndex..., in: clean), withTemplate: " ")
        }
        var seen = Set<String>(), out: [String] = []
        for m in tagRegex.matches(in: clean, range: NSRange(clean.startIndex..., in: clean)) {
            guard let r = Range(m.range(at: 1), in: clean) else { continue }
            let tag = String(clean[r])
            if seen.insert(tag.lowercased()).inserted { out.append(tag) }
        }
        return out
    }

    // MARK: Check boxes

    private static let boxRegex = try! NSRegularExpression(pattern: #"^(\s*- \[)([ xX])(\]\s+)(.*)$"#)
    private static let markerRegex = try! NSRegularExpression(pattern: #"\s?⟦t:([^⟧\s]+)⟧"#)

    /// The hidden text that ties a line to its task.
    public static func marker(for taskId: String) -> String { "⟦t:\(taskId)⟧" }

    private static func lines(_ body: String) -> [String] {
        body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// Every check box line that has some text. An empty box (a template line) is ignored.
    public static func checkboxes(in body: String) -> [NoteCheckbox] {
        var out: [NoteCheckbox] = []
        for (i, line) in lines(body).enumerated() {
            guard let m = boxRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let flag = Range(m.range(at: 2), in: line), let rest = Range(m.range(at: 4), in: line) else { continue }
            let tail = String(line[rest])
            var id: String?
            if let mk = markerRegex.firstMatch(in: tail, range: NSRange(tail.startIndex..., in: tail)), let r = Range(mk.range(at: 1), in: tail) {
                id = String(tail[r])
            }
            let text = withoutMarkers(tail).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            out.append(NoteCheckbox(line: i, checked: line[flag] != " ", text: text, taskId: id))
        }
        return out
    }

    /// The text with every hidden task marker taken out.
    public static func withoutMarkers(_ text: String) -> String {
        markerRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
    }

    /// Puts the marker for `taskId` at the end of line `line`. A line that already has a marker is left alone.
    public static func addingMarker(_ body: String, line: Int, taskId: String) -> String {
        var all = lines(body)
        guard all.indices.contains(line), !all[line].contains("⟦t:") else { return body }
        while all[line].last?.isWhitespace == true { all[line].removeLast() }
        all[line] += " " + marker(for: taskId)
        return all.joined(separator: "\n")
    }

    /// Ticks or clears the box on line `line`. A line that is not a check box is left alone.
    public static func settingChecked(_ body: String, line: Int, to checked: Bool) -> String {
        var all = lines(body)
        guard all.indices.contains(line) else { return body }
        let l = all[line]
        guard let m = boxRegex.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)), let r = Range(m.range(at: 2), in: l) else { return body }
        all[line] = l.replacingCharacters(in: r, with: checked ? "x" : " ")
        return all.joined(separator: "\n")
    }
}
