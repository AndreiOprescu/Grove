import Testing
import Foundation
@testable import GroveCore

struct RecurrenceEngineTests {
    private func next(_ from: String, _ rule: RecurrenceRule) -> String? {
        RecurrenceEngine.next(after: DayKey(from), rule: rule)?.string
    }

    // 2026-10-02 is a Friday. 2026-10-05 is a Monday.

    @Test func daily() {
        #expect(next("2026-10-02", .init(freq: .daily)) == "2026-10-03")
        #expect(next("2026-10-02", .init(freq: .daily, interval: 3)) == "2026-10-05")
        #expect(next("2026-12-31", .init(freq: .daily)) == "2027-01-01")
    }

    @Test func weeklyWithoutWeekdaysKeepsTheSameWeekday() {
        #expect(next("2026-10-02", .init(freq: .weekly)) == "2026-10-09")
        #expect(next("2026-10-02", .init(freq: .weekly, interval: 2)) == "2026-10-16")
    }

    @Test func weeklyOnOneWeekday() {
        let monday = RecurrenceRule(freq: .weekly, weekdays: [1])
        #expect(next("2026-10-02", monday) == "2026-10-05")   // from a Friday
        #expect(next("2026-10-05", monday) == "2026-10-12")   // from a Monday
    }

    @Test func everyWeekday() {
        let weekdays = RecurrenceRule(freq: .weekly, weekdays: [1, 2, 3, 4, 5])
        #expect(next("2026-10-02", weekdays) == "2026-10-05")  // Friday → Monday
        #expect(next("2026-10-05", weekdays) == "2026-10-06")  // Monday → Tuesday
        #expect(next("2026-10-03", weekdays) == "2026-10-05")  // Saturday → Monday
    }

    @Test func severalWeekdays() {
        let mwf = RecurrenceRule(freq: .weekly, weekdays: [5, 1, 3])   // order does not matter
        #expect(next("2026-10-05", mwf) == "2026-10-07")
        #expect(next("2026-10-07", mwf) == "2026-10-09")
        #expect(next("2026-10-09", mwf) == "2026-10-12")
    }

    @Test func everyOtherWeekOnMonday() {
        let rule = RecurrenceRule(freq: .weekly, interval: 2, weekdays: [1])
        #expect(next("2026-10-05", rule) == "2026-10-19")
        #expect(next("2026-10-02", rule) == "2026-10-12")
    }

    @Test func monthlyKeepsTheDayAndClampsShortMonths() {
        #expect(next("2026-10-02", .init(freq: .monthly)) == "2026-11-02")
        #expect(next("2026-10-02", .init(freq: .monthly, interval: 2)) == "2026-12-02")
        #expect(next("2026-12-15", .init(freq: .monthly)) == "2027-01-15")
        #expect(next("2026-01-31", .init(freq: .monthly)) == "2026-02-28")
    }

    @Test func yearly() {
        #expect(next("2026-10-02", .init(freq: .yearly)) == "2027-10-02")
        #expect(next("2028-02-29", .init(freq: .yearly)) == "2029-02-28")
    }

    @Test func untilStopsTheSeries() {
        let rule = RecurrenceRule(freq: .daily, until: DayKey("2026-10-03"))
        #expect(next("2026-10-02", rule) == "2026-10-03")
        #expect(next("2026-10-03", rule) == nil)
    }
}
