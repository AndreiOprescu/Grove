import Foundation

/// An `@date time` token in a line of a note, like `@fri 3pm` or `@tomorrow 14:00 for 1h` (PLAN §5.5 item 2).
public struct AtDate: Equatable, Sendable {
    /// The whole token, from the `@` to the last word it uses. UTF-16 offsets in the line.
    public var range: NSRange
    /// The day. Nil when the token has only a time (`@3pm`): the caller picks the day.
    public var day: DayKey?
    /// Minute of the day. Nil for a token with a day and no time.
    public var startMinute: Int?
    public var durationMin: Int?
}

public enum AtDateParser {
    /// The longest phrase that can follow the `@`. "next week" or "in 3 days 3pm for 1h" are the long ones.
    private static let maxWords = 7

    /// The first `@` token in the line that holds a day or a time. The `@` must start the line or follow a space,
    /// so an e-mail address is never a token. The token uses the same words as quick-add.
    public static func find(in line: String, today: DayKey = .today()) -> AtDate? {
        let ns = line as NSString
        var at = 0
        while at < ns.length {
            let found = ns.range(of: "@", options: [], range: NSRange(location: at, length: ns.length - at))
            guard found.location != NSNotFound else { return nil }
            at = NSMaxRange(found)
            if found.location > 0, !isSpace(ns.character(at: found.location - 1)) { continue }
            if let hit = token(in: ns, at: found.location, today: today) { return hit }
        }
        return nil
    }

    private static func isSpace(_ c: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(c) else { return false }
        return CharacterSet.whitespaces.contains(scalar)
    }

    /// The words after the `@`, each with its end offset.
    private static func words(in ns: NSString, after start: Int) -> [(text: String, end: Int)] {
        var out: [(String, Int)] = []
        var i = start
        while i < ns.length, out.count < maxWords {
            while i < ns.length, isSpace(ns.character(at: i)) { i += 1 }
            let from = i
            while i < ns.length, !isSpace(ns.character(at: i)) { i += 1 }
            if i > from { out.append((ns.substring(with: NSRange(location: from, length: i - from)), i)) }
        }
        return out
    }

    private static func token(in ns: NSString, at start: Int, today: DayKey) -> AtDate? {
        let list = words(in: ns, after: start + 1)
        let parser = QuickAddParser(today: today)
        for k in stride(from: list.count, through: 1, by: -1) {
            let phrase = list[0..<k].map(\.text).joined(separator: " ")
            // The phrase counts only when the parser reads every word of it and nothing but a day, a time or a length.
            let r = parser.parse("X " + phrase)
            guard r.title == "X", r.tags.isEmpty, r.priority == 0, r.listName == nil, r.recurrence == nil, r.due == nil,
                  r.planDate != nil || r.startMinute != nil else { continue }
            let end = list[k - 1].end
            // A time with no day word gets today from quick-add, so ask if a day word was there.
            return AtDate(range: NSRange(location: start, length: end - start), day: r.namedADay ? r.planDate : nil,
                          startMinute: r.startMinute, durationMin: r.durationMin)
        }
        return nil
    }
}
