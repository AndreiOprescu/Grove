import Foundation

/// The focus timer arithmetic (PLAN §5.1.7). A focus session counts down to the end of a block.
public enum FocusRules {
    /// The moment a wall-clock time happens, in the user's time zone.
    public static func endDate(_ t: WallTime) -> Date? {
        GroveCalendar.cal.date(byAdding: .minute, value: t.minute, to: t.day.date)
    }

    /// Whole seconds left, rounded up, never below zero.
    public static func remaining(until end: Date, now: Date) -> Int {
        max(0, Int(end.timeIntervalSince(now).rounded(.up)))
    }

    /// "24:07", or "1:02:05" from one hour.
    public static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = s % 3600 / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// How far a session is, 0 to 1. A span with no length is finished.
    public static func progress(start: Date, end: Date, now: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(start) / total))
    }

    /// A block can be focused on until its end.
    public static func canStart(_ block: EventItem, now: Date) -> Bool {
        guard let end = endDate(block.end) else { return false }
        return end > now
    }
}
