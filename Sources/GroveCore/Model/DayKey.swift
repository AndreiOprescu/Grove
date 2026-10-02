import Foundation

public enum GroveCalendar {
    /// Gregorian calendar in the user's time zone. Stored dates are local wall-clock strings.
    public static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        c.firstWeekday = 2
        return c
    }()
}

/// A calendar day, stored as "YYYY-MM-DD".
public struct DayKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let string: String

    public init(_ string: String) { self.string = string }
    public init(stringLiteral value: String) { self.string = value }

    public init(_ date: Date) {
        let c = GroveCalendar.cal.dateComponents([.year, .month, .day], from: date)
        self.string = String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    public init(year: Int, month: Int, day: Int) {
        self.string = String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Validating parse. Returns nil for text that is not a real date.
    public static func parse(_ s: String) -> DayKey? {
        let parts = s.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2 else { return nil }
        let key = DayKey(year: y, month: m, day: d)
        return DayKey(key.date) == key ? key : nil
    }

    public static func today() -> DayKey { DayKey(Date()) }

    public var description: String { string }
    public static func < (a: DayKey, b: DayKey) -> Bool { a.string < b.string }

    public init(from decoder: Decoder) throws {
        self.string = try decoder.singleValueContainer().decode(String.self)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(string)
    }

    public var year: Int { Int(string.prefix(4)) ?? 1970 }
    public var month: Int { Int(string.dropFirst(5).prefix(2)) ?? 1 }
    public var day: Int { Int(string.suffix(2)) ?? 1 }

    /// Midnight at the start of this day, local time.
    public var date: Date {
        GroveCalendar.cal.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    public func adding(days: Int) -> DayKey {
        DayKey(GroveCalendar.cal.date(byAdding: .day, value: days, to: date) ?? date)
    }

    /// 1 = Monday … 7 = Sunday.
    public var weekdayIndex: Int {
        let w = GroveCalendar.cal.component(.weekday, from: date) // 1 = Sunday
        return ((w + 5) % 7) + 1
    }

    public func weekStart(mondayFirst: Bool = true) -> DayKey {
        let offset = mondayFirst ? weekdayIndex - 1 : weekdayIndex % 7
        return adding(days: -offset)
    }

    /// Number of days from `self` to `other` (positive when other is later).
    public func days(until other: DayKey) -> Int {
        GroveCalendar.cal.dateComponents([.day], from: date, to: other.date).day ?? 0
    }

    public var daysInMonth: Int {
        GroveCalendar.cal.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    /// ISO week number (Monday-first weeks).
    public var weekOfYear: Int {
        Calendar(identifier: .iso8601).component(.weekOfYear, from: date)
    }

    public func range(through end: DayKey) -> [DayKey] {
        guard self <= end else { return [] }
        var out: [DayKey] = []
        var d = self
        while d <= end { out.append(d); d = d.adding(days: 1) }
        return out
    }
}

/// A day plus a minute of the day (0…1440). Stored as "YYYY-MM-DDTHH:MM".
public struct WallTime: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public var day: DayKey
    public var minute: Int

    public init(day: DayKey, minute: Int) {
        self.day = day
        self.minute = minute
    }

    public init?(_ string: String) {
        let parts = string.split(separator: "T")
        guard parts.count == 2, let day = DayKey.parse(String(parts[0])) else { return nil }
        let hm = parts[1].split(separator: ":")
        guard hm.count == 2, let h = Int(hm[0]), let m = Int(hm[1]), (0...24).contains(h), (0..<60).contains(m) else { return nil }
        self.day = day
        self.minute = h * 60 + m
    }

    public var string: String {
        String(format: "%@T%02d:%02d", day.string, minute / 60, minute % 60)
    }
    public var description: String { string }
    public static func < (a: WallTime, b: WallTime) -> Bool { a.string < b.string }

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let w = WallTime(s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad WallTime \(s)"))
        }
        self = w
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(string)
    }
}

public enum Stamp {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()
    /// Local timestamp for created/updated columns.
    public static func now() -> String { formatter.string(from: Date()) }
    public static func string(from date: Date) -> String { formatter.string(from: date) }
}
