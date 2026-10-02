import Foundation

/// Repeat rules. M3 only needs the next date for a repeating task; M4 adds
/// the list of occurrences inside a date range for events.
public enum RecurrenceEngine {
    /// The first date after `date` that the rule produces. Nil when it falls after the rule's end date.
    /// Monthly rules keep the day of `date` and clamp short months (31 Jan → 28 Feb).
    public static func next(after date: DayKey, rule: RecurrenceRule) -> DayKey? {
        let result: DayKey
        switch rule.freq {
        case .daily:
            result = date.adding(days: rule.interval)
        case .weekly:
            let days = Array(Set(rule.weekdays?.filter { (1...7).contains($0) } ?? [])).sorted()
            let wanted = days.isEmpty ? [date.weekdayIndex] : days
            if let later = wanted.first(where: { $0 > date.weekdayIndex }) {
                result = date.adding(days: later - date.weekdayIndex)
            } else {
                // No more chosen days this week: jump `interval` weeks ahead to the first chosen day.
                result = date.weekStart().adding(days: rule.interval * 7 + wanted[0] - 1)
            }
        case .monthly:
            result = shifted(date, .month, rule.interval)
        case .yearly:
            result = shifted(date, .year, rule.interval)
        }
        if let until = rule.until, result > until { return nil }
        return result
    }

    private static func shifted(_ date: DayKey, _ unit: Calendar.Component, _ amount: Int) -> DayKey {
        DayKey(GroveCalendar.cal.date(byAdding: unit, value: amount, to: date.date) ?? date.date)
    }
}
