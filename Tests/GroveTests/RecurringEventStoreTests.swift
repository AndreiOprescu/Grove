import Testing
import Foundation
import GroveCore
@testable import Grove

/// Repeating events on the planner, and the "This event only / All events" choice.
@MainActor
struct RecurringEventStoreTests {
    func makeStore() throws -> AppStore { AppStore(repos: Repos(db: try Database.inMemory())) }

    // 2026-10-05 is a Monday.
    let monday = DayKey("2026-10-05")
    let nextMonday = DayKey("2026-10-12")
    let month = DayKey("2026-10-01")...DayKey("2026-10-31")

    /// A weekly "Standup" on Mondays, 09:00–10:00.
    @discardableResult
    func addStandup(_ s: AppStore, rule: RecurrenceRule = .init(freq: .weekly)) throws -> EventItem {
        let e = EventItem(id: "S1", title: "Standup", start: WallTime(day: monday, minute: 540),
                          end: WallTime(day: monday, minute: 600), color: "accent3", recurrence: rule)
        try s.repos.events.save(e)
        return e
    }

    func ids(_ s: AppStore, _ range: ClosedRange<DayKey>? = nil) -> [String] {
        s.blocks(for: range ?? month).map(\.id)
    }

    @Test func aWeeklyEventShowsOnEveryWeek() throws {
        let s = try makeStore()
        try addStandup(s)
        let blocks = s.blocks(for: month)
        #expect(blocks.map(\.day.string) == ["2026-10-05", "2026-10-12", "2026-10-19", "2026-10-26"])
        #expect(blocks.allSatisfy { $0.startMinute == 540 && $0.endMinute == 600 && $0.title == "Standup" && $0.isRecurring })
        #expect(blocks[1].id == "S1@2026-10-12")
        #expect(s.blocks(for: DayKey("2026-10-06")...DayKey("2026-10-11")).isEmpty)
    }

    @Test func aRepeatingAllDayEventShowsInTheAllDayRow() throws {
        let s = try makeStore()
        let e = EventItem(id: "B1", title: "Birthday", start: WallTime(day: DayKey("2026-10-20"), minute: 0),
                          end: WallTime(day: DayKey("2026-10-20"), minute: 0), allDay: true, recurrence: .init(freq: .yearly))
        try s.repos.events.save(e)
        #expect(s.allDayEvents(for: DayKey("2026-10-19")...DayKey("2026-10-21")).map(\.title) == ["Birthday"])
        #expect(s.allDayEvents(for: DayKey("2027-10-19")...DayKey("2027-10-21")).map(\.id) == ["B1@2027-10-20"])
        #expect(s.blocks(for: DayKey("2026-10-19")...DayKey("2026-10-21")).isEmpty)   // all-day is not a grid block
    }

    @Test func anOccurrenceCanBeFoundById() throws {
        let s = try makeStore()
        try addStandup(s)
        let o = try #require(s.event("S1@2026-10-12"))
        #expect(o.start == WallTime(day: nextMonday, minute: 540))
        #expect(s.event("S1@2026-10-13") == nil)       // not a Monday
        #expect(s.event("S1@2026-09-28") == nil)       // before the series began
    }

    // MARK: Move and resize

    @Test func movingAnOccurrenceAsksFirst() throws {
        let s = try makeStore()
        try addStandup(s)
        s.applyEdits([BlockEdit(id: "S1@2026-10-12", day: nextMonday, start: 600, end: 660)], ripple: false, name: "Move Block")
        #expect(s.recurringPrompt != nil)
        #expect(s.blocks(for: nextMonday...nextMonday).first?.startMinute == 540)   // nothing changed yet
        #expect(s.undoName == nil)
    }

    @Test func onlyThisEventMovesOneDay() throws {
        let s = try makeStore()
        let series = try addStandup(s)
        s.applyEdits([BlockEdit(id: "S1@2026-10-12", day: nextMonday, start: 600, end: 690)], ripple: false, name: "Move Block")
        s.answerRecurring(.only)

        let blocks = s.blocks(for: month)
        #expect(blocks.count == 4)
        let moved = try #require(blocks.first { $0.day == nextMonday })
        #expect(moved.startMinute == 600 && moved.endMinute == 690)
        #expect(moved.isRecurring && moved.id != "S1@2026-10-12")
        #expect(blocks.filter { $0.day != nextMonday }.allSatisfy { $0.startMinute == 540 && $0.endMinute == 600 })

        // The series says: this day is taken out. A one-off copy holds the new time.
        #expect(try s.repos.events.exdates(series.id) == [nextMonday])
        let copy = try #require(try s.repos.events.detached(seriesId: series.id).first)
        #expect(copy.seriesId == "S1" && copy.originalDate == nextMonday && copy.recurrence == nil)
        #expect(copy.id == moved.id)
        #expect(try s.repos.events.get("S1")?.start.minute == 540)    // the series itself did not change
        #expect(s.selection == [copy.id])
    }

    @Test func onlyThisEventUndoAndRedo() throws {
        let s = try makeStore()
        let series = try addStandup(s)
        s.applyEdits([BlockEdit(id: "S1@2026-10-12", day: nextMonday, start: 600, end: 660)], ripple: false, name: "Move Block")
        s.answerRecurring(.only)
        s.undo()
        #expect(ids(s) == ["S1@2026-10-05", "S1@2026-10-12", "S1@2026-10-19", "S1@2026-10-26"])
        #expect(try s.repos.events.exdates(series.id).isEmpty)
        #expect(try s.repos.events.detached(seriesId: series.id).isEmpty)
        s.redo()
        #expect(s.blocks(for: nextMonday...nextMonday).first?.startMinute == 600)
        #expect(try s.repos.events.exdates(series.id) == [nextMonday])
    }

    @Test func movingOneOccurrenceToAnotherDay() throws {
        let s = try makeStore()
        try addStandup(s)
        let tuesday = DayKey("2026-10-13")
        s.applyEdits([BlockEdit(id: "S1@2026-10-12", day: tuesday, start: 540, end: 600)], ripple: false, name: "Move Block")
        s.answerRecurring(.only)
        #expect(s.blocks(for: nextMonday...nextMonday).isEmpty)
        #expect(s.blocks(for: tuesday...tuesday).count == 1)
        #expect(s.blocks(for: month).count == 4)
    }

    @Test func allEventsChangesTheTimeOfTheSeries() throws {
        let s = try makeStore()
        try addStandup(s)
        s.applyEdits([BlockEdit(id: "S1@2026-10-12", day: nextMonday, start: 600, end: 690)], ripple: false, name: "Move Block")
        s.answerRecurring(.all)
        let blocks = s.blocks(for: month)
        #expect(blocks.map(\.day.string) == ["2026-10-05", "2026-10-12", "2026-10-19", "2026-10-26"])
        #expect(blocks.allSatisfy { $0.startMinute == 600 && $0.endMinute == 690 })
        #expect(blocks[1].id == "S1@2026-10-12")
        #expect(try s.repos.events.exdates("S1").isEmpty)
        s.undo()
        #expect(s.blocks(for: month).allSatisfy { $0.startMinute == 540 && $0.endMinute == 600 })
    }

    @Test func allEventsMovedToAnotherWeekdayMovesTheWholeSeries() throws {
        let s = try makeStore()
        try addStandup(s)
        let tuesday = DayKey("2026-10-13")
        s.applyEdits([BlockEdit(id: "S1@2026-10-12", day: tuesday, start: 540, end: 600)], ripple: false, name: "Move Block")
        s.answerRecurring(.all)
        #expect(s.blocks(for: month).map(\.day.string) == ["2026-10-06", "2026-10-13", "2026-10-20", "2026-10-27"])
        #expect(s.selection == ["S1@2026-10-13"])
    }

    @Test func allEventsMovedToAnotherWeekdayTurnsChosenWeekdays() throws {
        let s = try makeStore()
        try addStandup(s, rule: .init(freq: .weekly, weekdays: [1, 3]))   // Mon and Wed
        // Move Wednesday the 14th to Thursday the 15th: Mon → Tue, Wed → Thu.
        s.applyEdits([BlockEdit(id: "S1@2026-10-14", day: DayKey("2026-10-15"), start: 540, end: 600)], ripple: false, name: "Move Block")
        s.answerRecurring(.all)
        #expect(s.blocks(for: DayKey("2026-10-12")...DayKey("2026-10-18")).map(\.day.string) == ["2026-10-13", "2026-10-15"])
        #expect(try s.repos.events.get("S1")?.recurrence?.weekdays?.sorted() == [2, 4])
    }

    @Test func resizingAsksTheSameQuestion() throws {
        let s = try makeStore()
        try addStandup(s)
        s.applyEdits([BlockEdit(id: "S1@2026-10-19", day: DayKey("2026-10-19"), start: 540, end: 660)], ripple: false, name: "Resize Block")
        #expect(s.recurringPrompt?.verb == "Resize")
        s.answerRecurring(.all)
        #expect(s.blocks(for: month).allSatisfy { $0.endMinute == 660 })
    }

    @Test func aDetachedCopyMovesWithoutAsking() throws {
        let s = try makeStore()
        try addStandup(s)
        s.applyEdits([BlockEdit(id: "S1@2026-10-12", day: nextMonday, start: 600, end: 660)], ripple: false, name: "Move Block")
        s.answerRecurring(.only)
        let copyId = try #require(s.blocks(for: nextMonday...nextMonday).first).id
        s.applyEdits([BlockEdit(id: copyId, day: nextMonday, start: 720, end: 780)], ripple: false, name: "Move Block")
        #expect(s.recurringPrompt == nil)
        #expect(s.blocks(for: nextMonday...nextMonday).first?.startMinute == 720)
    }

    // MARK: Delete, colour, other

    @Test func deleteOnlyThisEventHidesOneDay() throws {
        let s = try makeStore()
        try addStandup(s)
        s.deleteBlocks(["S1@2026-10-19"], name: "Delete Event")
        #expect(s.recurringPrompt?.verb == "Delete")
        s.answerRecurring(.only)
        #expect(ids(s) == ["S1@2026-10-05", "S1@2026-10-12", "S1@2026-10-26"])
        s.undo()
        #expect(ids(s).count == 4)
    }

    @Test func deleteAllEventsRemovesTheSeriesAndItsCopies() throws {
        let s = try makeStore()
        try addStandup(s)
        s.applyEdits([BlockEdit(id: "S1@2026-10-12", day: nextMonday, start: 600, end: 660)], ripple: false, name: "Move Block")
        s.answerRecurring(.only)
        s.deleteBlocks(["S1@2026-10-19"], name: "Delete Event")
        s.answerRecurring(.all)
        #expect(s.blocks(for: month).isEmpty)
        #expect(try s.repos.events.get("S1") == nil)
        #expect(try s.repos.events.all().isEmpty)
        // Undo brings back the series, the moved copy and the removed day.
        s.undo()
        #expect(s.blocks(for: month).count == 4)   // three from the series and the moved copy
        #expect(try s.repos.events.detached(seriesId: "S1").count == 1)
        #expect(try s.repos.events.exdates("S1") == [nextMonday])
    }

    @Test func deletingADetachedCopyDoesNotBringTheOriginalBack() throws {
        let s = try makeStore()
        try addStandup(s)
        s.applyEdits([BlockEdit(id: "S1@2026-10-12", day: nextMonday, start: 600, end: 660)], ripple: false, name: "Move Block")
        s.answerRecurring(.only)
        let copyId = try #require(s.blocks(for: nextMonday...nextMonday).first).id
        s.deleteBlocks([copyId], name: "Delete Event")
        #expect(s.recurringPrompt == nil)
        #expect(s.blocks(for: nextMonday...nextMonday).isEmpty)
    }

    @Test func colourOfOneOccurrenceOrAll() throws {
        let s = try makeStore()
        try addStandup(s)
        s.setColor(blockIds: ["S1@2026-10-19"], name: "accent")
        #expect(s.recurringPrompt?.verb == "Change")
        s.answerRecurring(.only)
        let blocks = s.blocks(for: month)
        #expect(blocks.filter { $0.color == "accent" }.map(\.day.string) == ["2026-10-19"])
        s.setColor(blockIds: ["S1@2026-10-05"], name: "accent2")
        s.answerRecurring(.all)
        #expect(try s.repos.events.get("S1")?.color == "accent2")
    }

    @Test func splitAndDuplicateSayNo() throws {
        let s = try makeStore()
        try addStandup(s)
        s.duplicate(blockIds: ["S1@2026-10-19"])
        s.split(blockId: "S1@2026-10-19")
        #expect(try s.repos.events.all().count == 1)
        #expect(s.toast != nil)
    }

    @Test func repeatingEventsCountAsPlannedTime() throws {
        let s = try makeStore()
        try addStandup(s)
        #expect(s.plannedMinutes(on: nextMonday) == 60)
    }
}
