import Foundation
import GroveCore

/// Which notes the list shows.
enum NoteFilter: Hashable {
    case all, daily, weekly, pinned
    case tag(String)
}

/// The small rules behind the notes screen: titles, templates, the list filter and the preview line.
/// Names are fixed English words so a title never depends on the Mac's language.
enum NotesRules {
    private static let months = ["January", "February", "March", "April", "May", "June", "July", "August",
                                 "September", "October", "November", "December"]
    private static let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    /// "Friday, 2 October 2026"
    static func dailyTitle(_ day: DayKey) -> String {
        "\(weekdays[day.weekdayIndex - 1]), \(day.day) \(months[day.month - 1]) \(day.year)"
    }

    /// "Friday"
    static func weekdayName(_ day: DayKey) -> String { weekdays[day.weekdayIndex - 1] }

    /// "2 Oct"
    static func shortDate(_ d: DayKey) -> String { "\(d.day) \(months[d.month - 1].prefix(3))" }

    /// "Week 40 · 28 Sep – 4 Oct"
    static func weeklyTitle(_ monday: DayKey) -> String {
        "Week \(weekNumber(monday)) · \(shortDate(monday)) – \(shortDate(monday.adding(days: 6)))"
    }

    /// The calendar week of the year (week 1 holds the first Thursday).
    static func weekNumber(_ day: DayKey) -> Int {
        Calendar(identifier: .iso8601).component(.weekOfYear, from: day.date)
    }

    static func template(_ kind: NoteKind) -> String {
        switch kind {
        case .daily: "## Plan\n\n## Notes\n\n## Reflection\n"
        case .weekly: "## Goals\n\n## Notes\n\n## Review\n"
        case .note: ""
        }
    }

    /// Keeps the notes the filter allows. The order stays as given.
    static func filter(_ notes: [Note], _ f: NoteFilter, tagsOf: (String) -> [String]) -> [Note] {
        switch f {
        case .all: notes
        case .daily: notes.filter { $0.kind == .daily }
        case .weekly: notes.filter { $0.kind == .weekly }
        case .pinned: notes.filter(\.pinned)
        case .tag(let name): notes.filter { n in tagsOf(n.id).contains { $0.caseInsensitiveCompare(name) == .orderedSame } }
        }
    }

    private static let imageRegex = try! NSRegularExpression(pattern: #"!\[[^\]\n]*\]\([^)\n]*\)"#)
    private static let prefixRegex = try! NSRegularExpression(pattern: #"^\s*(?:- \[[ xX]\]\s*|[-*]\s+|>\s*|\d+\.\s+)"#)

    /// One short line for the list: the first line that has words, without marks.
    static func preview(_ body: String, limit: Int = 90) -> String {
        for raw in body.split(separator: "\n", omittingEmptySubsequences: true) {
            var line = String(raw)
            if line.hasPrefix("#") { continue }
            line = imageRegex.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..., in: line), withTemplate: "")
            line = prefixRegex.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..., in: line), withTemplate: "")
            line = ReferenceParser.searchText(NoteParser.withoutMarkers(line))
            line = line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            return line.count > limit ? String(line.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…" : line
        }
        return ""
    }

    /// "Ideas copy", then "Ideas copy 2", …
    static func copyTitle(_ title: String, existing: Set<String>) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        var candidate = "\(title) copy", n = 2
        while taken.contains(candidate.lowercased()) { candidate = "\(title) copy \(n)"; n += 1 }
        return candidate
    }

    /// "Untitled", then "Untitled 2", …
    static func untitled(existing: Set<String>) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        var candidate = "Untitled", n = 2
        while taken.contains(candidate.lowercased()) { candidate = "Untitled \(n)"; n += 1 }
        return candidate
    }
}
