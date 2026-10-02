import Foundation
import GroveCore

/// The repeat choices in the inspector. Anything else is shown as "Custom" and left alone.
enum RepeatPreset: String, CaseIterable, Identifiable {
    case none, daily, weekdays, weekly, biweekly, monthly, yearly, custom
    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "Does not repeat"
        case .daily: "Every day"
        case .weekdays: "Every weekday"
        case .weekly: "Every week"
        case .biweekly: "Every 2 weeks"
        case .monthly: "Every month"
        case .yearly: "Every year"
        case .custom: "Custom"
        }
    }

    var rule: RecurrenceRule? {
        switch self {
        case .none, .custom: nil
        case .daily: RecurrenceRule(freq: .daily)
        case .weekdays: RecurrenceRule(freq: .weekly, weekdays: [1, 2, 3, 4, 5])
        case .weekly: RecurrenceRule(freq: .weekly)
        case .biweekly: RecurrenceRule(freq: .weekly, interval: 2)
        case .monthly: RecurrenceRule(freq: .monthly)
        case .yearly: RecurrenceRule(freq: .yearly)
        }
    }

    static func of(_ rule: RecurrenceRule?) -> RepeatPreset {
        guard let rule else { return .none }
        return allCases.first { $0 != .none && $0 != .custom && $0.rule == rule } ?? .custom
    }
}

/// Small pure rules behind the inspector fields.
enum InspectorOptions {
    static func estimates(including current: Int) -> [Int] {
        var set = Set([5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240, 300, 480])
        set.insert(current)
        return set.sorted()
    }

    /// The day part of a due value ("2026-10-05" or "2026-10-05T14:30").
    static func dueDay(_ due: String?) -> DayKey? {
        due.flatMap { DayKey.parse(String($0.prefix(10))) }
    }

    /// A new due day that keeps the clock time of the old value, if it had one.
    static func dueString(day: DayKey, keepingTimeOf old: String?) -> String {
        if let old, old.count > 10 { return day.string + old.dropFirst(10) }
        return day.string
    }

    static func placement(bucket: TaskBucket, date: DayKey) -> TaskPlacement {
        switch bucket {
        case .inbox: .inbox
        case .someday: .someday
        case .day: .day(date)
        case .week: .week(date.weekStart())
        }
    }
}
