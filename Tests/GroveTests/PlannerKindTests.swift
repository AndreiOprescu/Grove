import Testing
import Foundation
import GroveCore
@testable import Grove

/// Each top tab has one fixed view: Today is one day, the Planner is a week, the Calendar is a month.
struct PlannerKindTests {
    private let wednesday = DayKey("2026-10-07")
    private let today = DayKey("2026-10-09")

    @Test func todayShowsOnlyToday() {
        #expect(PlannerKind.today.days(selected: wednesday, today: today, sundayFirst: false) == [today])
        #expect(PlannerKind.today.days(selected: wednesday, today: today, sundayFirst: true) == [today])
    }

    @Test func weekShowsSevenDaysFromMonday() {
        let days = PlannerKind.week.days(selected: wednesday, today: today, sundayFirst: false)
        #expect(days.count == 7)
        #expect(days.first == DayKey("2026-10-05") && days.last == DayKey("2026-10-11"))
    }

    @Test func weekShowsSevenDaysFromSundayWhenSettingsSayso() {
        let days = PlannerKind.week.days(selected: wednesday, today: today, sundayFirst: true)
        #expect(days.count == 7)
        #expect(days.first == DayKey("2026-10-04") && days.last == DayKey("2026-10-10"))
    }

    @Test func aSundayBelongsToTheWeekBeforeItWhenMondayIsFirst() {
        let sunday = DayKey("2026-10-11")
        #expect(PlannerKind.week.days(selected: sunday, today: today, sundayFirst: false).first == DayKey("2026-10-05"))
        #expect(PlannerKind.week.days(selected: sunday, today: today, sundayFirst: true).first == sunday)
    }

    @Test func monthShowsTheSixWeekGrid() {
        let monday = PlannerKind.month.days(selected: wednesday, today: today, sundayFirst: false)
        #expect(monday.count == 42)
        #expect(monday.first == DayKey("2026-09-28") && monday.last == DayKey("2026-11-08"))
        let sunday = PlannerKind.month.days(selected: wednesday, today: today, sundayFirst: true)
        #expect(sunday.first == DayKey("2026-09-27"))
        #expect(monday.contains(wednesday))
    }

    @Test func weekStepsSevenDays() {
        #expect(PlannerKind.week.moved(wednesday, by: 1) == DayKey("2026-10-14"))
        #expect(PlannerKind.week.moved(wednesday, by: -1) == DayKey("2026-09-30"))
    }

    @Test func monthStepsOneMonthAndKeepsTheLastDayOfAShortMonth() {
        #expect(PlannerKind.month.moved(wednesday, by: 1) == DayKey("2026-11-07"))
        #expect(PlannerKind.month.moved(DayKey("2026-01-31"), by: 1) == DayKey("2026-02-28"))
        #expect(PlannerKind.month.moved(DayKey("2026-01-15"), by: -1) == DayKey("2025-12-15"))
    }

    @Test func todayDoesNotMove() {
        #expect(PlannerKind.today.moved(wednesday, by: 1) == wednesday)
        #expect(PlannerKind.today.moved(wednesday, by: -1) == wednesday)
    }
}
