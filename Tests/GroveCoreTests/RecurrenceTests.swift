import Testing
import Foundation
@testable import GroveCore

/// The list of dates a repeating event covers (PLAN §5.3).
struct RecurrenceTests {
    private func dates(_ rule: RecurrenceRule, from start: String, _ lo: String, _ hi: String, except: [String] = []) -> [String] {
        RecurrenceEngine.occurrences(rule: rule, seriesStart: DayKey(start), in: DayKey(lo)...DayKey(hi),
                                     exdates: Set(except.map { DayKey($0) })).map(\.string)
    }

    // 2026-10-02 is a Friday.

    @Test func dailyInsideARange() {
        #expect(dates(.init(freq: .daily), from: "2026-10-02", "2026-10-04", "2026-10-07")
                == ["2026-10-04", "2026-10-05", "2026-10-06", "2026-10-07"])
    }

    @Test func nothingBeforeTheStart() {
        #expect(dates(.init(freq: .daily), from: "2026-10-02", "2026-09-28", "2026-10-03") == ["2026-10-02", "2026-10-03"])
        #expect(dates(.init(freq: .daily), from: "2026-10-02", "2026-09-01", "2026-09-30").isEmpty)
    }

    @Test func dailyWithAnInterval() {
        // Every 3 days from the 2nd: 2, 5, 8, 11. A range that starts in the middle keeps the same rhythm.
        #expect(dates(.init(freq: .daily, interval: 3), from: "2026-10-02", "2026-10-06", "2026-10-12") == ["2026-10-08", "2026-10-11"])
    }

    @Test func weeklyKeepsTheStartWeekday() {
        #expect(dates(.init(freq: .weekly), from: "2026-10-02", "2026-10-01", "2026-10-31")
                == ["2026-10-02", "2026-10-09", "2026-10-16", "2026-10-23", "2026-10-30"])
    }

    @Test func weeklyOnChosenWeekdays() {
        // Mon, Wed, Fri. The start (Friday the 2nd) is the first one.
        let rule = RecurrenceRule(freq: .weekly, weekdays: [5, 1, 3])
        #expect(dates(rule, from: "2026-10-02", "2026-10-01", "2026-10-14")
                == ["2026-10-02", "2026-10-05", "2026-10-07", "2026-10-09", "2026-10-12", "2026-10-14"])
    }

    @Test func weeklyDoesNotStartBeforeTheStartDay() {
        // The series starts on Wednesday the 7th. Monday the 5th is not part of it.
        let rule = RecurrenceRule(freq: .weekly, weekdays: [1, 3])
        #expect(dates(rule, from: "2026-10-07", "2026-10-05", "2026-10-12") == ["2026-10-07", "2026-10-12"])
    }

    @Test func everyOtherWeek() {
        let rule = RecurrenceRule(freq: .weekly, interval: 2, weekdays: [1])
        #expect(dates(rule, from: "2026-10-05", "2026-10-01", "2026-11-10") == ["2026-10-05", "2026-10-19", "2026-11-02"])
        // Starting the range later gives the same dates.
        #expect(dates(rule, from: "2026-10-05", "2026-10-20", "2026-11-10") == ["2026-11-02"])
    }

    @Test func monthlyOnThe31stSkipsShortMonths() {
        let rule = RecurrenceRule(freq: .monthly)
        #expect(dates(rule, from: "2026-01-31", "2026-01-01", "2026-07-31")
                == ["2026-01-31", "2026-03-31", "2026-05-31", "2026-07-31"])
    }

    @Test func monthlyKeepsTheDay() {
        #expect(dates(.init(freq: .monthly), from: "2026-10-15", "2026-10-01", "2027-01-31")
                == ["2026-10-15", "2026-11-15", "2026-12-15", "2027-01-15"])
        #expect(dates(.init(freq: .monthly, interval: 3), from: "2026-10-15", "2026-10-01", "2027-10-31")
                == ["2026-10-15", "2027-01-15", "2027-04-15", "2027-07-15", "2027-10-15"])
    }

    @Test func yearly() {
        #expect(dates(.init(freq: .yearly), from: "2026-10-02", "2026-01-01", "2029-12-31")
                == ["2026-10-02", "2027-10-02", "2028-10-02", "2029-10-02"])
    }

    @Test func yearlyOnFebruary29OnlyInLeapYears() {
        #expect(dates(.init(freq: .yearly), from: "2024-02-29", "2024-01-01", "2033-12-31") == ["2024-02-29", "2028-02-29", "2032-02-29"])
    }

    @Test func untilIncludesTheLastDay() {
        let rule = RecurrenceRule(freq: .daily, until: DayKey("2026-10-04"))
        #expect(dates(rule, from: "2026-10-02", "2026-10-01", "2026-10-31") == ["2026-10-02", "2026-10-03", "2026-10-04"])
    }

    @Test func countStopsTheSeries() {
        let rule = RecurrenceRule(freq: .weekly, count: 3)
        #expect(dates(rule, from: "2026-10-02", "2026-10-01", "2026-12-31") == ["2026-10-02", "2026-10-09", "2026-10-16"])
        // A range after the last one is empty. A range in the middle counts from the start.
        #expect(dates(rule, from: "2026-10-02", "2026-10-17", "2026-12-31").isEmpty)
        #expect(dates(rule, from: "2026-10-02", "2026-10-09", "2026-12-31") == ["2026-10-09", "2026-10-16"])
    }

    @Test func countWithChosenWeekdays() {
        let rule = RecurrenceRule(freq: .weekly, weekdays: [1, 3], count: 3)
        #expect(dates(rule, from: "2026-10-05", "2026-10-01", "2026-12-31") == ["2026-10-05", "2026-10-07", "2026-10-12"])
    }

    @Test func countedDatesThatAreRemovedStillCount() {
        // The 2nd occurrence is removed, but the series still ends after 3 slots.
        let rule = RecurrenceRule(freq: .daily, count: 3)
        #expect(dates(rule, from: "2026-10-02", "2026-10-01", "2026-10-31", except: ["2026-10-03"]) == ["2026-10-02", "2026-10-04"])
    }

    @Test func removedDatesAreLeftOut() {
        #expect(dates(.init(freq: .weekly), from: "2026-10-02", "2026-10-01", "2026-10-31", except: ["2026-10-09", "2026-10-23"])
                == ["2026-10-02", "2026-10-16", "2026-10-30"])
    }

    @Test func aRangeFarFromTheStartIsFast() {
        // Ten years of a daily series. Must not walk every day.
        let rule = RecurrenceRule(freq: .daily)
        let start = Date()
        let found = dates(rule, from: "2016-01-01", "2026-10-02", "2026-10-02")
        #expect(found == ["2026-10-02"])
        #expect(Date().timeIntervalSince(start) < 0.5)
    }

    @Test func aRangeThatEndsBeforeTheStartIsEmpty() {
        #expect(dates(.init(freq: .daily), from: "2026-10-02", "2026-09-01", "2026-09-05").isEmpty)
    }
}

/// Turning a series into events on days, and the id of one such event.
struct OccurrenceTests {
    private func series(_ rule: RecurrenceRule, start: String = "2026-10-05", from: Int = 9 * 60, to: Int = 10 * 60) -> EventItem {
        EventItem(id: "S1", title: "Standup", start: WallTime(day: DayKey(start), minute: from),
                  end: WallTime(day: DayKey(start), minute: to), color: "accent3", location: "Room 4", recurrence: rule)
    }

    @Test func idRoundTrips() {
        let id = OccurrenceID.make(series: "S1", day: DayKey("2026-10-12"))
        #expect(id == "S1@2026-10-12")
        let parsed = OccurrenceID.parse(id)
        #expect(parsed?.series == "S1")
        #expect(parsed?.day == DayKey("2026-10-12"))
    }

    @Test func plainIdsAreNotOccurrences() {
        #expect(OccurrenceID.parse("2D6F1B1C-0000-4000-8000-000000000000") == nil)
        #expect(OccurrenceID.parse("S1@not-a-date") == nil)
    }

    @Test func expandCopiesTheSeriesOntoEachDay() {
        let s = series(.init(freq: .weekly))
        let items = RecurrenceEngine.expand(s, exdates: [], in: DayKey("2026-10-01")...DayKey("2026-10-31"))
        #expect(items.map(\.start.day.string) == ["2026-10-05", "2026-10-12", "2026-10-19", "2026-10-26"])
        #expect(items.map(\.id) == ["S1@2026-10-05", "S1@2026-10-12", "S1@2026-10-19", "S1@2026-10-26"])
        let second = items[1]
        #expect(second.title == "Standup")
        #expect(second.start.minute == 540 && second.end.minute == 600)
        #expect(second.end.day == second.start.day)
        #expect(second.seriesId == "S1")
        #expect(second.originalDate == DayKey("2026-10-12"))
        #expect(second.recurrence == nil)
        #expect(second.color == "accent3" && second.location == "Room 4")
    }

    @Test func expandSkipsRemovedDays() {
        let s = series(.init(freq: .daily))
        let items = RecurrenceEngine.expand(s, exdates: [DayKey("2026-10-06")], in: DayKey("2026-10-05")...DayKey("2026-10-07"))
        #expect(items.map(\.start.day.string) == ["2026-10-05", "2026-10-07"])
    }

    @Test func aMultiDayEventKeepsItsLength() {
        var s = series(.init(freq: .weekly), from: 0, to: 0)
        s.allDay = true
        s.end = WallTime(day: DayKey("2026-10-07"), minute: 0)   // Mon → Wed
        let items = RecurrenceEngine.expand(s, exdates: [], in: DayKey("2026-10-12")...DayKey("2026-10-12"))
        #expect(items.count == 1)
        #expect(items[0].end.day == DayKey("2026-10-14"))
    }

    @Test func anEventThatStartedBeforeTheRangeStillShows() {
        var s = series(.init(freq: .weekly), from: 0, to: 0)
        s.allDay = true
        s.end = WallTime(day: DayKey("2026-10-07"), minute: 0)
        // Range is Tue–Wed. The occurrence that began Monday the 12th covers it.
        let items = RecurrenceEngine.expand(s, exdates: [], in: DayKey("2026-10-13")...DayKey("2026-10-14"))
        #expect(items.map(\.start.day.string) == ["2026-10-12"])
    }

    @Test func oneOccurrenceOnADay() {
        let s = series(.init(freq: .weekly))
        let o = RecurrenceEngine.occurrence(of: s, on: DayKey("2026-10-19"))
        #expect(o.id == "S1@2026-10-19")
        #expect(o.start == WallTime(day: DayKey("2026-10-19"), minute: 540))
        #expect(o.end == WallTime(day: DayKey("2026-10-19"), minute: 600))
    }
}
