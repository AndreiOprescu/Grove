import Foundation

/// The id of one occurrence of a repeating event: `"<series id>@<date>"`.
/// An occurrence is not stored. Only a detached copy (one the user changed alone) has its own row and id.
public enum OccurrenceID {
    public static func make(series: String, day: DayKey) -> String { "\(series)@\(day.string)" }

    public static func parse(_ id: String) -> (series: String, day: DayKey)? {
        guard let at = id.lastIndex(of: "@") else { return nil }
        let series = String(id[..<at])
        guard !series.isEmpty, let day = DayKey.parse(String(id[id.index(after: at)...])) else { return nil }
        return (series, day)
    }
}

/// Repeat rules. `next(after:)` gives the next date for a repeating task.
/// `occurrences` and `expand` give the dates and events of a repeating event inside a date range.
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

    // MARK: Events

    /// The dates the rule produces inside `range`, oldest first, without the `exdates`.
    ///
    /// Monthly and yearly rules skip a month or year that has no such day (the 31st skips April;
    /// 29 Feb happens only in leap years). A removed date still counts toward `count`.
    public static func occurrences(rule: RecurrenceRule, seriesStart: DayKey, in range: ClosedRange<DayKey>,
                                   exdates: Set<DayKey> = []) -> [DayKey] {
        let limit = rule.until.map { min($0, range.upperBound) } ?? range.upperBound
        guard seriesStart <= limit else { return [] }
        let step = max(1, rule.interval)
        var period = rule.count == nil ? firstPeriod(rule.freq, step, seriesStart, range.lowerBound) : 0
        var produced = 0
        var out: [DayKey] = []
        while periodStart(rule.freq, step, seriesStart, period) <= limit {
            for day in slots(rule, step, seriesStart, period) {
                if day > limit { return out }
                produced += 1
                if let count = rule.count, produced > count { return out }
                if day >= range.lowerBound, !exdates.contains(day) { out.append(day) }
            }
            period += 1
        }
        return out
    }

    /// The event of a series on one day. Same time of day, same length. Its id is `OccurrenceID`.
    public static func occurrence(of series: EventItem, on day: DayKey) -> EventItem {
        var o = series
        o.id = OccurrenceID.make(series: series.id, day: day)
        o.start = WallTime(day: day, minute: series.start.minute)
        o.end = WallTime(day: day.adding(days: series.start.day.days(until: series.end.day)), minute: series.end.minute)
        o.recurrence = nil
        o.seriesId = series.id
        o.originalDate = day
        return o
    }

    /// Every event of the series that begins inside `range`, or began before it and runs into it.
    /// A one-off copy that replaced a day is a stored event. It is not here.
    public static func expand(_ series: EventItem, exdates: Set<DayKey>, in range: ClosedRange<DayKey>) -> [EventItem] {
        guard let rule = series.recurrence else { return [] }
        let span = max(0, series.start.day.days(until: series.end.day))
        let wide = range.lowerBound.adding(days: -span)...range.upperBound
        return occurrences(rule: rule, seriesStart: series.start.day, in: wide, exdates: exdates)
            .map { occurrence(of: series, on: $0) }
    }

    // MARK: Walking the periods

    /// A period is one step of the rule: a day, a week, a month or a year, counted from the series start.
    private static func firstPeriod(_ freq: RecurrenceRule.Freq, _ step: Int, _ start: DayKey, _ from: DayKey) -> Int {
        let n: Int
        switch freq {
        case .daily: n = start.days(until: from) / step
        case .weekly: n = start.weekStart().days(until: from.weekStart()) / 7 / step
        case .monthly: n = ((from.year - start.year) * 12 + from.month - start.month) / step
        case .yearly: n = (from.year - start.year) / step
        }
        return max(0, n)
    }

    /// The earliest day period `k` can hold. Used to know when to stop.
    private static func periodStart(_ freq: RecurrenceRule.Freq, _ step: Int, _ start: DayKey, _ k: Int) -> DayKey {
        switch freq {
        case .daily: return start.adding(days: k * step)
        case .weekly: return start.weekStart().adding(days: k * step * 7)
        case .monthly:
            let (y, m) = monthOf(start, k * step)
            return DayKey(year: y, month: m, day: 1)
        case .yearly: return DayKey(year: start.year + k * step, month: 1, day: 1)
        }
    }

    private static func monthOf(_ start: DayKey, _ plus: Int) -> (year: Int, month: Int) {
        let total = start.month - 1 + plus
        return (start.year + total / 12, total % 12 + 1)
    }

    /// The days period `k` produces, oldest first, never before the series start.
    private static func slots(_ rule: RecurrenceRule, _ step: Int, _ start: DayKey, _ k: Int) -> [DayKey] {
        switch rule.freq {
        case .daily:
            return [start.adding(days: k * step)]
        case .weekly:
            let chosen = Set(rule.weekdays?.filter { (1...7).contains($0) } ?? [])
            let wanted = chosen.isEmpty ? [start.weekdayIndex] : chosen.sorted()
            let monday = start.weekStart().adding(days: k * step * 7)
            return wanted.map { monday.adding(days: $0 - 1) }.filter { $0 >= start }
        case .monthly:
            let (y, m) = monthOf(start, k * step)
            return real(year: y, month: m, day: start.day)
        case .yearly:
            return real(year: start.year + k * step, month: start.month, day: start.day)
        }
    }

    private static func real(year: Int, month: Int, day: Int) -> [DayKey] {
        day <= DayKey(year: year, month: month, day: 1).daysInMonth ? [DayKey(year: year, month: month, day: day)] : []
    }
}
