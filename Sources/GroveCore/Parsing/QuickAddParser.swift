import Foundation

/// One small label shown under the quick-add field for each thing the parser understood.
public struct QuickAddChip: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case date, time, duration, repeats, due, list, tag, priority }
    public var kind: Kind
    public var text: String
}

public struct QuickAddResult: Equatable, Sendable {
    public var title: String
    public var bucket: TaskBucket = .inbox
    public var planDate: DayKey?
    public var planWeek: DayKey?
    public var due: String?
    /// Minute of the day when the task should get a time block.
    public var startMinute: Int?
    public var durationMin: Int?
    public var tags: [String] = []
    public var priority = 0
    /// Name of an existing list (fuzzy matched from `/name`).
    public var listName: String?
    public var recurrence: RecurrenceRule?
    public var chips: [QuickAddChip] = []

    /// Length of the time block: the stated length, or 30 minutes.
    public var blockMinutes: Int { durationMin ?? 30 }
    public var blockEnd: Int? { startMinute.map { min(1440, $0 + blockMinutes) } }
}

/// Turns one line of text ("Call mum tomorrow 6pm for 20m #home !2") into a task.
/// Matched words are removed from the title. Words it does not know stay in the title.
public struct QuickAddParser {
    public let today: DayKey
    public let lists: [String]

    public init(today: DayKey = .today(), lists: [String] = []) {
        self.today = today
        self.lists = lists
    }

    public func parse(_ input: String) -> QuickAddResult {
        let trimmed = input.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var run = Run(tokens: trimmed.split(separator: " ").map(String.init), parser: self)
        run.scan()
        let result = run.finish()
        // Nothing left to be a title: keep exactly what was typed and apply nothing.
        return result.title.isEmpty ? QuickAddResult(title: trimmed) : result
    }

    // MARK: Word lists

    static let weekdayNames: [String: Int] = [
        "mon": 1, "monday": 1, "tue": 2, "tues": 2, "tuesday": 2, "wed": 3, "weds": 3, "wednesday": 3,
        "thu": 4, "thur": 4, "thurs": 4, "thursday": 4, "fri": 5, "friday": 5,
        "sat": 6, "saturday": 6, "sun": 7, "sunday": 7,
    ]
    static let monthNames: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3, "apr": 4, "april": 4,
        "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7, "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9, "oct": 10, "october": 10, "nov": 11, "november": 11,
        "dec": 12, "december": 12,
    ]
    static let weekdayShort = ["", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    static let monthShort = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    static let clock12 = try! Regex(#"^(\d{1,2})(?::(\d{2}))?(am|pm)$"#)
    static let clock24 = try! Regex(#"^(\d{1,2}):(\d{2})$"#)
    static let clockAfterAt = try! Regex(#"^(\d{1,2})(?::(\d{2}))?(am|pm)?$"#)
    static let slashDate = try! Regex(#"^(\d{1,2})/(\d{1,2})$"#)
    static let hoursMinutes = try! Regex(#"^(\d+(?:\.\d+)?)(?:h|hr|hrs)(?:(\d+)(?:m|min|mins)?)?$"#)
    static let minutesOnly = try! Regex(#"^(\d+)(?:m|min|mins)$"#)
    static let plainNumber = try! Regex(#"^\d+(?:\.\d+)?$"#)
    static let tagWord = try! Regex(#"^#([A-Za-z][A-Za-z0-9_-]*)$"#)

    // MARK: One pass over the words

    private enum DateKind { case day(DayKey), week(DayKey), someday }

    private struct Run {
        var tokens: [String]
        let parser: QuickAddParser
        var clean: [String] = []
        var used: [Bool]

        var dateKind: DateKind?
        var startMinute: Int?
        var timeRange: Range<Int>?
        var duration: Int?
        var recurrence: RecurrenceRule?
        var recurrenceText: String?
        var due: String?
        var tags: [String] = []
        var priority: Int?
        var listName: String?

        init(tokens: [String], parser: QuickAddParser) {
            self.tokens = tokens
            self.parser = parser
            self.used = Array(repeating: false, count: tokens.count)
            self.clean = tokens.map { Run.cleaned($0) }
        }

        /// Lowercase, and without a trailing comma or full stop.
        static func cleaned(_ token: String) -> String {
            var t = token.lowercased()
            while t.count > 1, let last = t.last, ",.;:".contains(last) { t.removeLast() }
            return t
        }

        func word(_ i: Int) -> String? { i < clean.count && !used[i] ? clean[i] : nil }

        mutating func take(_ start: Int, _ count: Int) {
            for k in start..<(start + count) { used[k] = true }
        }

        mutating func scan() {
            var i = 0
            while i < tokens.count {
                if used[i] { i += 1; continue }
                let consumed = tryEvery(i) ?? tryDue(i) ?? tryDate(i) ?? tryTime(i) ?? tryDuration(i)
                    ?? tryTag(i) ?? tryPriority(i) ?? tryList(i) ?? 0
                i += max(consumed, 1)
            }
        }

        // MARK: every …

        mutating func tryEvery(_ i: Int) -> Int? {
            guard recurrence == nil, word(i) == "every", let a = word(i + 1) else { return nil }
            let rule: RecurrenceRule, text: String
            var count = 2
            switch a {
            case "day", "days": rule = RecurrenceRule(freq: .daily); text = "Every day"
            case "weekday", "weekdays": rule = RecurrenceRule(freq: .weekly, interval: 1, weekdays: [1, 2, 3, 4, 5]); text = "Every weekday"
            case "week", "weeks": rule = RecurrenceRule(freq: .weekly); text = "Every week"
            case "month", "months": rule = RecurrenceRule(freq: .monthly); text = "Every month"
            case "year", "years": rule = RecurrenceRule(freq: .yearly); text = "Every year"
            default:
                if let d = QuickAddParser.weekdayNames[a] {
                    rule = RecurrenceRule(freq: .weekly, interval: 1, weekdays: [d]); text = "Every \(QuickAddParser.weekdayShort[d])"
                } else if let n = Int(a), n >= 1, let unit = word(i + 2) {
                    count = 3
                    switch unit {
                    case "day", "days": rule = RecurrenceRule(freq: .daily, interval: n)
                    case "week", "weeks": rule = RecurrenceRule(freq: .weekly, interval: n)
                    case "month", "months": rule = RecurrenceRule(freq: .monthly, interval: n)
                    case "year", "years": rule = RecurrenceRule(freq: .yearly, interval: n)
                    default: return nil
                    }
                    text = "Every \(n) \(unit.hasSuffix("s") ? unit : unit + "s")"
                } else { return nil }
            }
            recurrence = rule
            recurrenceText = text
            take(i, count)
            return count
        }

        // MARK: due …

        mutating func tryDue(_ i: Int) -> Int? {
            guard due == nil, word(i) == "due", let hit = dateAt(i + 1), case .day(let day) = hit.kind else { return nil }
            var count = 1 + hit.used
            var text = day.string
            if let t = timeAt(i + count) {
                text += "T" + PlannerMath.clock(t.minute)
                count += t.used
            }
            due = text
            take(i, count)
            return count
        }

        // MARK: dates

        struct DateHit { var kind: DateKind; var used: Int }

        func dateAt(_ i: Int) -> DateHit? {
            guard let t = word(i) else { return nil }
            let today = parser.today
            switch t {
            case "today", "tod": return DateHit(kind: .day(today), used: 1)
            case "tomorrow", "tmr", "tmrw": return DateHit(kind: .day(today.adding(days: 1)), used: 1)
            case "someday": return DateHit(kind: .someday, used: 1)
            case "next" where word(i + 1) == "week":
                return DateHit(kind: .week(today.weekStart().adding(days: 7)), used: 2)
            case "this" where word(i + 1) == "week":
                return DateHit(kind: .week(today.weekStart()), used: 2)
            case "in":
                guard let n = word(i + 1).flatMap({ Int($0) }), n >= 0, let unit = word(i + 2) else { return nil }
                switch unit {
                case "day", "days": return DateHit(kind: .day(today.adding(days: n)), used: 3)
                case "week", "weeks": return DateHit(kind: .day(today.adding(days: n * 7)), used: 3)
                default: return nil
                }
            default: break
            }
            if let wd = QuickAddParser.weekdayNames[t] {
                let delta = (wd - today.weekdayIndex + 7) % 7
                return DateHit(kind: .day(today.adding(days: delta)), used: 1)
            }
            if let g = Run.groups(QuickAddParser.slashDate, t), let d = Int(g[1] ?? ""), let m = Int(g[2] ?? "") {
                return resolve(day: d, month: m).map { DateHit(kind: .day($0), used: 1) }
            }
            if let d = Int(t), let m = word(i + 1).flatMap({ QuickAddParser.monthNames[$0] }) {
                return resolve(day: d, month: m).map { DateHit(kind: .day($0), used: 2) }
            }
            if let m = QuickAddParser.monthNames[t], let d = word(i + 1).flatMap({ Int($0) }) {
                return resolve(day: d, month: m).map { DateHit(kind: .day($0), used: 2) }
            }
            return nil
        }

        /// This year, or next year when the day has already passed. Nil for a day that does not exist.
        func resolve(day: Int, month: Int) -> DayKey? {
            guard (1...12).contains(month), day >= 1 else { return nil }
            let year = parser.today.year
            guard day <= DayKey(year: year, month: month, day: 1).daysInMonth else { return nil }
            let candidate = DayKey(year: year, month: month, day: day)
            if candidate >= parser.today { return candidate }
            guard day <= DayKey(year: year + 1, month: month, day: 1).daysInMonth else { return nil }
            return DayKey(year: year + 1, month: month, day: day)
        }

        mutating func tryDate(_ i: Int) -> Int? {
            guard dateKind == nil, let hit = dateAt(i) else { return nil }
            dateKind = hit.kind
            take(i, hit.used)
            return hit.used
        }

        // MARK: times

        func timeAt(_ i: Int) -> (minute: Int, used: Int)? {
            guard let t = word(i) else { return nil }
            if let g = Run.groups(QuickAddParser.clock12, t), let h = Int(g[1] ?? ""), (1...12).contains(h) {
                let m = Int(g[2] ?? "0") ?? 0
                guard m < 60 else { return nil }
                return (Run.minute(hour: h, minute: m, suffix: g[3]), 1)
            }
            if let g = Run.groups(QuickAddParser.clock24, t), let h = Int(g[1] ?? ""), let m = Int(g[2] ?? ""), h < 24, m < 60 {
                return (h * 60 + m, 1)
            }
            if t == "at", let next = word(i + 1), let g = Run.groups(QuickAddParser.clockAfterAt, next), let h = Int(g[1] ?? "") {
                let m = Int(g[2] ?? "0") ?? 0
                guard m < 60 else { return nil }
                if g[3] != nil { guard (1...12).contains(h) else { return nil } } else { guard h < 24 else { return nil } }
                return (Run.minute(hour: h, minute: m, suffix: g[3]), 2)
            }
            return nil
        }

        static func minute(hour: Int, minute: Int, suffix: String?) -> Int {
            var h = hour
            switch suffix {
            case "am": if h == 12 { h = 0 }
            case "pm": if h < 12 { h += 12 }
            default: break
            }
            return h * 60 + minute
        }

        mutating func tryTime(_ i: Int) -> Int? {
            guard startMinute == nil, let hit = timeAt(i) else { return nil }
            startMinute = hit.minute
            timeRange = i..<(i + hit.used)
            take(i, hit.used)
            return hit.used
        }

        // MARK: lengths

        func lengthToken(_ t: String) -> Int? {
            if let g = Run.groups(QuickAddParser.minutesOnly, t), let m = Int(g[1] ?? "") { return m }
            if let g = Run.groups(QuickAddParser.hoursMinutes, t), let h = Double(g[1] ?? "") {
                return Int((h * 60).rounded()) + (Int(g[2] ?? "") ?? 0)
            }
            return nil
        }

        mutating func tryDuration(_ i: Int) -> Int? {
            guard duration == nil, let t = word(i) else { return nil }
            var minutes: Int?, count = 1
            if t == "for", let next = word(i + 1) {
                if let m = lengthToken(next) {
                    minutes = m; count = 2
                } else if Run.groups(QuickAddParser.plainNumber, next) != nil, let n = Double(next), let unit = word(i + 2) {
                    switch unit {
                    case "h", "hr", "hrs", "hour", "hours": minutes = Int((n * 60).rounded()); count = 3
                    case "m", "min", "mins", "minute", "minutes": minutes = Int(n.rounded()); count = 3
                    default: break
                    }
                }
            } else {
                minutes = lengthToken(t)
            }
            guard let m = minutes, m > 0 else { return nil }
            duration = m
            take(i, count)
            return count
        }

        // MARK: #tag  !2  /list

        mutating func tryTag(_ i: Int) -> Int? {
            guard !used[i], let g = Run.groups(QuickAddParser.tagWord, tokens[i]), let name = g[1]?.lowercased() else { return nil }
            if !tags.contains(name) { tags.append(name) }
            take(i, 1)
            return 1
        }

        mutating func tryPriority(_ i: Int) -> Int? {
            guard priority == nil, ["!1", "!2", "!3"].contains(tokens[i]) else { return nil }
            priority = Int(tokens[i].dropFirst())
            take(i, 1)
            return 1
        }

        mutating func tryList(_ i: Int) -> Int? {
            let t = tokens[i]
            guard listName == nil, t.count > 1, t.hasPrefix("/") else { return nil }
            let query = t.dropFirst().lowercased()
            let names = parser.lists
            let match = names.first { $0.lowercased() == query }
                ?? names.first { $0.lowercased().hasPrefix(query) }
                ?? names.first { $0.lowercased().contains(query) }
            guard let match else { return nil }
            listName = match
            take(i, 1)
            return 1
        }

        // MARK: result

        static func groups(_ re: Regex<AnyRegexOutput>, _ s: String) -> [String?]? {
            guard let m = s.wholeMatch(of: re) else { return nil }
            return m.output.map { $0.substring.map(String.init) }
        }

        mutating func finish() -> QuickAddResult {
            let today = parser.today
            var planDate: DayKey?, planWeek: DayKey?, someday = false
            switch dateKind {
            case .day(let d)?: planDate = d
            case .week(let w)?: planWeek = w
            case .someday?: someday = true
            case nil: break
            }
            if let rule = recurrence, planDate == nil, planWeek == nil, !someday {
                planDate = firstOccurrence(of: rule, from: today)
            }
            if startMinute != nil, planDate == nil {
                if planWeek != nil || someday {
                    // A week or someday task has no day, so it cannot have a block. Keep the time as text.
                    if let r = timeRange { for k in r { used[k] = false } }
                    startMinute = nil
                } else {
                    planDate = today
                }
            }
            let bucket: TaskBucket = planDate != nil ? .day : planWeek != nil ? .week : someday ? .someday : .inbox

            var result = QuickAddResult(title: zip(tokens, used).filter { !$0.1 }.map(\.0).joined(separator: " "))
            result.bucket = bucket
            result.planDate = planDate
            result.planWeek = planWeek
            result.due = due
            result.startMinute = startMinute
            result.durationMin = duration
            result.tags = tags
            result.priority = priority ?? 0
            result.listName = listName
            result.recurrence = recurrence
            result.chips = chips(for: result, someday: someday)
            return result
        }

        func firstOccurrence(of rule: RecurrenceRule, from day: DayKey) -> DayKey {
            guard rule.freq == .weekly, let days = rule.weekdays, !days.isEmpty else { return day }
            for k in 0..<7 {
                let d = day.adding(days: k)
                if days.contains(d.weekdayIndex) { return d }
            }
            return day
        }

        func chips(for r: QuickAddResult, someday: Bool) -> [QuickAddChip] {
            var out: [QuickAddChip] = []
            if let d = r.planDate {
                out.append(.init(kind: .date, text: "\(QuickAddParser.weekdayShort[d.weekdayIndex]) \(d.day) \(QuickAddParser.monthShort[d.month])"))
            } else if let w = r.planWeek {
                out.append(.init(kind: .date, text: "Week of \(w.day) \(QuickAddParser.monthShort[w.month])"))
            } else if someday {
                out.append(.init(kind: .date, text: "Someday"))
            }
            if let s = r.startMinute { out.append(.init(kind: .time, text: PlannerMath.clock(s))) }
            if let m = r.durationMin { out.append(.init(kind: .duration, text: PlannerMath.duration(m))) }
            if let t = recurrenceText { out.append(.init(kind: .repeats, text: t)) }
            if let due = r.due { out.append(.init(kind: .due, text: "Due " + due.replacingOccurrences(of: "T", with: " "))) }
            if let l = r.listName { out.append(.init(kind: .list, text: l)) }
            for t in r.tags { out.append(.init(kind: .tag, text: "#" + t)) }
            if r.priority > 0 { out.append(.init(kind: .priority, text: "!\(r.priority)")) }
            return out
        }
    }
}
