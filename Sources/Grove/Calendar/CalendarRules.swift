import Foundation
import GroveCore

/// What one day shows in the month view and the week strip.
struct DayInfo: Equatable {
    /// Events that touch the day, all-day first. Task blocks are not here: the task is counted in `openTasks`.
    var events: [EventItem] = []
    var openTasks = 0
    var hasNote = false
    var itemCount: Int { events.count + openTasks }
}

/// The small rules behind the month view and the week strip.
enum CalendarRules {
    /// Six full weeks, Monday first, that hold the month of `day`.
    static func monthGrid(containing day: DayKey) -> [DayKey] {
        let first = DayKey(year: day.year, month: day.month, day: 1).weekStart()
        return (0..<42).map { first.adding(days: $0) }
    }

    /// The same day number in another month. A short month gives its last day.
    static func addMonths(_ day: DayKey, _ months: Int) -> DayKey {
        let index = day.year * 12 + (day.month - 1) + months
        let first = DayKey(year: index / 12, month: index % 12 + 1, day: 1)
        return DayKey(year: first.year, month: first.month, day: min(day.day, first.daysInMonth))
    }

    /// How many event lines fit in a month cell. The day number and the "+N more" line take 40 points.
    static func pillSlots(cellHeight: Double) -> Int {
        min(3, max(1, Int((cellHeight - 40) / 19)))
    }

    static func pills(_ events: [EventItem], slots: Int) -> (shown: [EventItem], hidden: Int) {
        (Array(events.prefix(slots)), max(0, events.count - slots))
    }

    /// All-day events first, then by start.
    static func sorted(_ events: [EventItem]) -> [EventItem] {
        events.sorted { (($0.allDay ? 0 : 1), $0.start, $0.title) < (($1.allDay ? 0 : 1), $1.start, $1.title) }
    }

    /// Dots under a day in the week strip. At most three.
    static func dots(_ count: Int) -> Int { min(3, max(0, count)) }

    /// Does the event touch `day`? A timed event that ends at midnight does not touch the next day.
    static func covers(_ e: EventItem, _ day: DayKey) -> Bool {
        guard day >= e.start.day else { return false }
        if e.allDay { return day <= e.end.day }
        return day == e.start.day || WallTime(day: day, minute: 0) < e.end
    }
}

/// Changes the event editor makes to its copy of an event.
enum EventDraft {
    enum Ends { case never, on, after }

    static func ends(_ rule: RecurrenceRule) -> Ends {
        if rule.until != nil { return .on }
        if rule.count != nil { return .after }
        return .never
    }

    private static let weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    /// The rule in words: "Every 2 weeks", "Every week on Mon, Wed, Fri".
    static func repeatLabel(_ rule: RecurrenceRule) -> String {
        let days = (rule.weekdays ?? []).sorted()
        if rule.freq == .weekly, rule.interval == 1, days == [1, 2, 3, 4, 5] { return "Every weekday" }
        let noun: String
        switch rule.freq {
        case .daily: noun = "day"
        case .weekly: noun = "week"
        case .monthly: noun = "month"
        case .yearly: noun = "year"
        }
        var text = rule.interval == 1 ? "Every \(noun)" : "Every \(rule.interval) \(noun)s"
        if rule.freq == .weekly, !days.isEmpty { text += " on " + days.map { weekdayNames[$0 - 1] }.joined(separator: ", ") }
        return text
    }

    /// Turns one weekday on or off. `start` is the weekday of the first event: a weekly rule without a list means that day.
    /// The last day cannot be turned off. A list that is only the start day becomes "no list".
    static func toggleWeekday(_ rule: RecurrenceRule, _ weekday: Int, start: Int) -> RecurrenceRule {
        var set = Set(rule.weekdays ?? [start])
        if set.contains(weekday) {
            if set.count > 1 { set.remove(weekday) }
        } else {
            set.insert(weekday)
        }
        var out = rule
        out.weekdays = set == [start] ? nil : set.sorted()
        return out
    }

    /// All-day events keep their days and drop the clock. Turning it off gives one hour from 09:00 on the first day.
    static func setAllDay(_ e: inout EventItem, _ on: Bool) {
        e.allDay = on
        if on {
            e.start = WallTime(day: e.start.day, minute: 0)
            e.end = WallTime(day: e.end.day, minute: 0)
        } else {
            e.start = WallTime(day: e.start.day, minute: 9 * 60)
            e.end = WallTime(day: e.start.day, minute: 10 * 60)
        }
    }

    /// Moves the start and keeps the length. All-day events keep their number of days.
    static func setStart(_ e: inout EventItem, to new: WallTime) {
        if e.allDay {
            let span = e.start.day.days(until: e.end.day)
            e.start = WallTime(day: new.day, minute: 0)
            e.end = WallTime(day: new.day.adding(days: span), minute: 0)
        } else {
            let length = max(0, e.durationMinutes)
            e.start = new
            e.end = wallTime(GroveCalendar.cal.date(byAdding: .minute, value: length, to: date(new)) ?? date(new))
        }
    }

    /// An end that is not after the start becomes 30 minutes after it (or the end of the day). An all-day end before the start becomes the start.
    static func normalize(_ e: inout EventItem) {
        if e.allDay {
            if e.end < e.start { e.end = e.start }
        } else if e.end <= e.start {
            e.end = WallTime(day: e.start.day, minute: min(1440, e.start.minute + 30))
        }
    }

    static func date(_ w: WallTime) -> Date {
        GroveCalendar.cal.date(byAdding: .minute, value: w.minute, to: w.day.date) ?? w.day.date
    }

    static func wallTime(_ date: Date) -> WallTime {
        let c = GroveCalendar.cal.dateComponents([.hour, .minute], from: date)
        return WallTime(day: DayKey(date), minute: (c.hour ?? 0) * 60 + (c.minute ?? 0))
    }
}
