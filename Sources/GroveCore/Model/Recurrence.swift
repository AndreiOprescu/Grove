import Foundation

public struct RecurrenceRule: Codable, Hashable, Sendable {
    public enum Freq: String, Codable, Sendable { case daily, weekly, monthly, yearly }

    public var freq: Freq
    public var interval: Int
    /// 1 = Monday … 7 = Sunday. Only used by weekly rules. Empty/nil = same weekday as the start.
    public var weekdays: [Int]?
    public var until: DayKey?
    public var count: Int?

    public init(freq: Freq, interval: Int = 1, weekdays: [Int]? = nil, until: DayKey? = nil, count: Int? = nil) {
        self.freq = freq
        self.interval = max(1, interval)
        self.weekdays = weekdays
        self.until = until
        self.count = count
    }

    public func json() -> String? {
        guard let d = try? JSONEncoder().encode(self) else { return nil }
        return String(data: d, encoding: .utf8)
    }

    public static func fromJSON(_ s: String?) -> RecurrenceRule? {
        guard let s, let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(RecurrenceRule.self, from: d)
    }
}
