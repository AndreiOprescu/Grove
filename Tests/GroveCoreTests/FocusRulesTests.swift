import Testing
import Foundation
@testable import GroveCore

/// The focus timer arithmetic (PLAN §5.1.7).
struct FocusRulesTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func remainingCountsWholeSecondsAndRoundsUp() {
        #expect(FocusRules.remaining(until: t0.addingTimeInterval(90), now: t0) == 90)
        #expect(FocusRules.remaining(until: t0.addingTimeInterval(89.2), now: t0) == 90)
        #expect(FocusRules.remaining(until: t0.addingTimeInterval(0.1), now: t0) == 1)
    }

    @Test func remainingNeverGoesBelowZero() {
        #expect(FocusRules.remaining(until: t0, now: t0) == 0)
        #expect(FocusRules.remaining(until: t0.addingTimeInterval(-30), now: t0) == 0)
    }

    @Test func clockShowsMinutesAndSeconds() {
        #expect(FocusRules.clock(0) == "0:00")
        #expect(FocusRules.clock(7) == "0:07")
        #expect(FocusRules.clock(1447) == "24:07")
        #expect(FocusRules.clock(3599) == "59:59")
    }

    @Test func clockShowsHoursFromOneHour() {
        #expect(FocusRules.clock(3600) == "1:00:00")
        #expect(FocusRules.clock(3725) == "1:02:05")
        #expect(FocusRules.clock(-5) == "0:00")
    }

    @Test func progressGoesFromZeroToOne() {
        let end = t0.addingTimeInterval(600)
        #expect(FocusRules.progress(start: t0, end: end, now: t0) == 0)
        #expect(FocusRules.progress(start: t0, end: end, now: t0.addingTimeInterval(150)) == 0.25)
        #expect(FocusRules.progress(start: t0, end: end, now: end) == 1)
        #expect(FocusRules.progress(start: t0, end: end, now: end.addingTimeInterval(99)) == 1)
        #expect(FocusRules.progress(start: t0, end: end, now: t0.addingTimeInterval(-5)) == 0)
    }

    @Test func progressOfAnEmptySpanIsOne() {
        #expect(FocusRules.progress(start: t0, end: t0, now: t0) == 1)
    }

    @Test func theEndOfABlockIsItsWallClockTime() {
        let end = FocusRules.endDate(WallTime(day: DayKey("2026-10-05"), minute: 13 * 60 + 30))
        let parts = GroveCalendar.cal.dateComponents([.year, .month, .day, .hour, .minute], from: end ?? .distantPast)
        #expect(parts.year == 2026 && parts.month == 10 && parts.day == 5)
        #expect(parts.hour == 13 && parts.minute == 30)
    }

    @Test func aBlockCanBeFocusedOnlyBeforeItEnds() {
        let day = DayKey("2026-10-05")
        let block = EventItem(title: "Write", start: WallTime(day: day, minute: 600), end: WallTime(day: day, minute: 660), kind: .block)
        let inside = FocusRules.endDate(WallTime(day: day, minute: 630))!
        let after = FocusRules.endDate(WallTime(day: day, minute: 661))!
        #expect(FocusRules.canStart(block, now: inside))
        #expect(!FocusRules.canStart(block, now: after))
        #expect(!FocusRules.canStart(block, now: FocusRules.endDate(block.end)!))   // the very end is too late
    }
}
