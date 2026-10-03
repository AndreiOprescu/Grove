import Foundation

/// The things the ⌘K palette can do besides open an item.
public enum PaletteCommandId: String, CaseIterable, Sendable {
    case newTask, newNote, todayNote, goToday, goToDate, planMyDay, showPlanner, showNotes, toggleTheme, toggleMotion
}

public struct PaletteCommand: Equatable, Identifiable, Sendable {
    public var id: PaletteCommandId
    public var title: String
    /// Extra words that find the command. The title words always count.
    public var keywords: [String] = []
    public var shortcut: String?
    /// An SF Symbol name.
    public var symbol: String
}

/// The text rules of the ⌘K palette (PLAN §5.5 item 11): what the box means, which commands match,
/// and whether the text is a day.
public enum PaletteRules {
    public struct Parsed: Equatable, Sendable {
        /// The text started with `>`. Only commands show.
        public var commandsOnly: Bool
        public var text: String
    }

    public static func parse(_ raw: String) -> Parsed {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(">") else { return Parsed(commandsOnly: false, text: trimmed) }
        return Parsed(commandsOnly: true, text: String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
    }

    // MARK: Commands

    /// In the order the palette lists them.
    public static let commands: [PaletteCommand] = [
        .init(id: .newTask, title: "New task", keywords: ["add", "create"], shortcut: "⌘N", symbol: "plus.circle"),
        .init(id: .newNote, title: "New note", keywords: ["add", "create", "write"], symbol: "square.and.pencil"),
        .init(id: .todayNote, title: "Today's note", keywords: ["daily", "journal", "diary"], symbol: "note.text"),
        .init(id: .goToday, title: "Go to today", keywords: ["now"], symbol: "sun.max"),
        .init(id: .goToDate, title: "Go to date…", keywords: ["day", "jump", "calendar"], symbol: "calendar"),
        .init(id: .planMyDay, title: "Plan my day", keywords: ["fit", "schedule", "auto"], symbol: "wand.and.stars"),
        .init(id: .showPlanner, title: "Open planner", keywords: ["calendar", "schedule", "day"], shortcut: "⌘1", symbol: "calendar.day.timeline.left"),
        .init(id: .showNotes, title: "Open notes", keywords: ["notebook"], shortcut: "⌘2", symbol: "note.text"),
        .init(id: .toggleTheme, title: "Toggle theme", keywords: ["theme", "dark", "light", "colour", "color", "appearance", "look", "switch"], symbol: "paintpalette"),
        .init(id: .toggleMotion, title: "Toggle motion", keywords: ["motion", "animation", "animate", "reduce", "calm"], symbol: "wind"),
    ]

    /// Every word typed must start a word of the title or of a keyword. Empty text matches all.
    public static func commands(matching text: String) -> [PaletteCommand] {
        let typed = words(text)
        guard !typed.isEmpty else { return commands }
        return commands.filter { c in
            let pool = words(c.title) + c.keywords.flatMap(words)
            return typed.allSatisfy { w in pool.contains { $0.hasPrefix(w) } }
        }
    }

    private static func words(_ s: String) -> [String] {
        s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    // MARK: Dates

    private static let goToPrefixes = ["go to ", "goto ", "go "]

    /// "go to fri" gives "fri". Other text stays as it is.
    private static func withoutGoTo(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespaces)
        let lower = t.lowercased()
        for p in goToPrefixes where lower.hasPrefix(p) { return String(t.dropFirst(p.count)).trimmingCharacters(in: .whitespaces) }
        return t
    }

    /// The day the whole text names, like `fri`, `tomorrow` or `go to oct 9`. A time after the day is ignored.
    /// Nil when other words come with it: that text is a search.
    public static func date(in text: String, today: DayKey = .today()) -> DayKey? {
        let rest = withoutGoTo(text)
        guard !rest.isEmpty else { return nil }
        let line = "@" + rest
        guard let hit = AtDateParser.find(in: line, today: today), let day = hit.day,
              NSMaxRange(hit.range) == (line as NSString).length else { return nil }
        return day
    }

    /// The text is "go to" and nothing after it: the palette asks which day.
    public static func asksForDay(_ text: String) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespaces).lowercased()
        return lower == "go to" || lower == "goto"
    }

    private static let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    /// "Go to today", "Go to tomorrow" or "Go to Friday".
    public static func dayTitle(_ day: DayKey, today: DayKey = .today()) -> String {
        if day == today { return "Go to today" }
        if day == today.adding(days: 1) { return "Go to tomorrow" }
        return "Go to " + weekdays[day.weekdayIndex - 1]
    }

    /// "Fri 9 Oct"
    public static func dayDetail(_ day: DayKey) -> String {
        AtDatePlanner.whenLabel(day: day, start: nil, end: nil)
    }
}
