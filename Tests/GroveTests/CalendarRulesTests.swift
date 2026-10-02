import Testing
import Foundation
import GroveCore
@testable import Grove

/// The small rules behind the month view, the week strip and the event editor.
struct CalendarRulesTests {
    private func event(_ start: WallTime, _ end: WallTime, allDay: Bool = false) -> EventItem {
        EventItem(title: "E", start: start, end: end, allDay: allDay)
    }
    private func at(_ day: String, _ minute: Int) -> WallTime { WallTime(day: DayKey(day), minute: minute) }

    // MARK: Month grid

    @Test func monthGridStartsOnTheMondayOfTheFirstWeek() {
        let grid = CalendarRules.monthGrid(containing: DayKey("2026-10-15"))
        #expect(grid.count == 42)
        #expect(grid.first == DayKey("2026-09-28"))   // 1 Oct 2026 is a Thursday
        #expect(grid.last == DayKey("2026-11-08"))
    }

    @Test func monthGridWhenTheFirstIsAMonday() {
        let grid = CalendarRules.monthGrid(containing: DayKey("2027-02-10"))
        #expect(grid.first == DayKey("2027-02-01"))
        #expect(grid.last == DayKey("2027-03-14"))
    }

    @Test func monthGridWhenTheFirstIsASunday() {
        let grid = CalendarRules.monthGrid(containing: DayKey("2026-02-20"))   // 1 Feb 2026 is a Sunday
        #expect(grid.first == DayKey("2026-01-26"))
    }

    @Test func movingByMonthsKeepsTheDayWhenItCan() {
        #expect(CalendarRules.addMonths(DayKey("2026-10-15"), 1) == DayKey("2026-11-15"))
        #expect(CalendarRules.addMonths(DayKey("2026-10-15"), -10) == DayKey("2025-12-15"))
        #expect(CalendarRules.addMonths(DayKey("2026-01-31"), 1) == DayKey("2026-02-28"))
        #expect(CalendarRules.addMonths(DayKey("2026-03-31"), -1) == DayKey("2026-02-28"))
    }

    // MARK: Pills

    @Test func pillSlotsGrowWithTheCell() {
        #expect(CalendarRules.pillSlots(cellHeight: 130) == 3)
        #expect(CalendarRules.pillSlots(cellHeight: 97) == 3)
        #expect(CalendarRules.pillSlots(cellHeight: 82) == 2)
        #expect(CalendarRules.pillSlots(cellHeight: 20) == 1)
    }

    @Test func extraEventsBecomePlusN() {
        let list = (1...5).map { EventItem(title: "E\($0)", start: at("2026-10-05", 600), end: at("2026-10-05", 660)) }
        let r = CalendarRules.pills(list, slots: 3)
        #expect(r.shown.map(\.title) == ["E1", "E2", "E3"])
        #expect(r.hidden == 2)
        let few = CalendarRules.pills(Array(list.prefix(2)), slots: 3)
        #expect(few.shown.count == 2 && few.hidden == 0)
    }

    @Test func allDayEventsComeFirstThenByStart() {
        let late = event(at("2026-10-05", 900), at("2026-10-05", 960))
        let early = event(at("2026-10-05", 540), at("2026-10-05", 600))
        let allDay = event(at("2026-10-05", 0), at("2026-10-05", 0), allDay: true)
        #expect(CalendarRules.sorted([late, allDay, early]).map(\.start.minute) == [0, 540, 900])
    }

    @Test func stripDotsStopAtThree() {
        #expect([0, 1, 2, 3, 4, 9].map { CalendarRules.dots($0) } == [0, 1, 2, 3, 3, 3])
    }

    // MARK: Which days an event covers

    @Test func anAllDayEventCoversEveryDayItNames() {
        let e = event(at("2026-10-05", 0), at("2026-10-07", 0), allDay: true)
        #expect(["2026-10-04", "2026-10-05", "2026-10-06", "2026-10-07", "2026-10-08"].map { CalendarRules.covers(e, DayKey($0)) }
                == [false, true, true, true, false])
    }

    @Test func aTimedEventThatEndsAtMidnightStaysOnItsDay() {
        let e = event(at("2026-10-05", 22 * 60), at("2026-10-06", 0))
        #expect(CalendarRules.covers(e, DayKey("2026-10-05")))
        #expect(!CalendarRules.covers(e, DayKey("2026-10-06")))
    }

    @Test func aTimedEventThatRunsPastMidnightCoversBothDays() {
        let e = event(at("2026-10-05", 22 * 60), at("2026-10-06", 120))
        #expect(CalendarRules.covers(e, DayKey("2026-10-05")) && CalendarRules.covers(e, DayKey("2026-10-06")))
    }

    // MARK: The editor's draft

    @Test func turningAllDayOnDropsTheClockTimes() {
        var e = event(at("2026-10-05", 540), at("2026-10-05", 630))
        EventDraft.setAllDay(&e, true)
        #expect(e.allDay && e.start == at("2026-10-05", 0) && e.end == at("2026-10-05", 0))
    }

    @Test func turningAllDayOffGivesAnHourFromNineOnTheFirstDay() {
        var e = event(at("2026-10-05", 0), at("2026-10-07", 0), allDay: true)
        EventDraft.setAllDay(&e, false)
        #expect(!e.allDay && e.start == at("2026-10-05", 540) && e.end == at("2026-10-05", 600))
    }

    @Test func anEndBeforeTheStartIsFixed() {
        var e = event(at("2026-10-05", 600), at("2026-10-05", 540))
        EventDraft.normalize(&e)
        #expect(e.end == at("2026-10-05", 630))   // 30 minutes after the start
        var late = event(at("2026-10-05", 1430), at("2026-10-05", 1400))
        EventDraft.normalize(&late)
        #expect(late.end == at("2026-10-05", 1440))
        var allDay = event(at("2026-10-07", 0), at("2026-10-05", 0), allDay: true)
        EventDraft.normalize(&allDay)
        #expect(allDay.end == at("2026-10-07", 0))
    }

    @Test func aGoodEventIsLeftAlone() {
        var e = event(at("2026-10-05", 540), at("2026-10-05", 600))
        let before = e
        EventDraft.normalize(&e)
        #expect(e == before)
    }

    @Test func wallTimeAndDateRoundTrip() {
        for w in [at("2026-10-05", 0), at("2026-10-05", 541), at("2026-12-31", 1439), at("2026-07-15", 150)] {
            #expect(EventDraft.wallTime(EventDraft.date(w)) == w)
        }
    }

    @Test func endsChoices() {
        #expect(EventDraft.ends(.init(freq: .daily)) == .never)
        #expect(EventDraft.ends(.init(freq: .daily, until: DayKey("2026-12-01"))) == .on)
        #expect(EventDraft.ends(.init(freq: .daily, count: 5)) == .after)
    }
}
