import Testing
import Foundation
import GroveCore
@testable import Grove

/// What the month view and the week strip read, and what the event editor writes.
@MainActor
struct CalendarStoreTests {
    func makeStore() throws -> AppStore { AppStore(repos: Repos(db: try Database.inMemory())) }
    let monday = DayKey("2026-10-05")

    func save(_ s: AppStore, _ e: EventItem) throws { try s.repos.events.save(e) }

    // MARK: Reading a range of days

    @Test func dayInfoCountsEventsTasksAndNotes() throws {
        let s = try makeStore()
        try save(s, EventItem(title: "Dentist", start: WallTime(day: monday, minute: 840), end: WallTime(day: monday, minute: 900)))
        try save(s, EventItem(title: "Birthday", start: WallTime(day: monday, minute: 0), end: WallTime(day: monday, minute: 0), allDay: true))
        let t = TaskItem(title: "Write", bucket: .day, planDate: monday)
        try s.repos.tasks.save(t)
        try s.repos.events.save(s.blockEvent(for: t, day: monday, start: 600, end: 660))   // a block is the task, not an event
        var note = Note(title: "Mon", kind: .daily, date: monday)
        note.body = "Went well."
        try s.repos.notes.save(note)

        let info = s.dayInfo(DayKey("2026-10-04")...DayKey("2026-10-10"))
        let day = try #require(info[monday])
        #expect(day.events.map(\.title) == ["Birthday", "Dentist"])   // all-day first
        #expect(day.openTasks == 1)
        #expect(day.hasNote)
        #expect(day.itemCount == 3)
        #expect(info[DayKey("2026-10-06")]?.itemCount ?? 0 == 0)
    }

    @Test func dayInfoShowsAMultiDayEventOnEveryDay() throws {
        let s = try makeStore()
        try save(s, EventItem(title: "Trip", start: WallTime(day: monday, minute: 0), end: WallTime(day: DayKey("2026-10-07"), minute: 0), allDay: true))
        let info = s.dayInfo(DayKey("2026-10-04")...DayKey("2026-10-10"))
        #expect(["2026-10-04", "2026-10-05", "2026-10-06", "2026-10-07", "2026-10-08"].map { info[DayKey($0)]?.events.count ?? 0 } == [0, 1, 1, 1, 0])
    }

    @Test func dayInfoIncludesDaysOfARepeatingEvent() throws {
        let s = try makeStore()
        try save(s, EventItem(id: "S1", title: "Standup", start: WallTime(day: monday, minute: 540), end: WallTime(day: monday, minute: 600),
                              recurrence: .init(freq: .weekly)))
        let info = s.dayInfo(DayKey("2026-10-01")...DayKey("2026-10-31"))
        let days = info.filter { !$0.value.events.isEmpty }.keys.map(\.string).sorted()
        #expect(days == ["2026-10-05", "2026-10-12", "2026-10-19", "2026-10-26"])
        #expect(info[DayKey("2026-10-12")]?.events.first?.id == "S1@2026-10-12")
    }

    @Test func aTaskThatIsDoneIsNotADot() throws {
        let s = try makeStore()
        var t = TaskItem(title: "Done", bucket: .day, planDate: monday)
        t.status = .done
        try s.repos.tasks.save(t)
        #expect(s.dayInfo(monday...monday)[monday]?.openTasks ?? 0 == 0)
    }

    // MARK: Opening the editor

    @Test func aNewEventStartsAsAnAllDayDraftOnThatDay() throws {
        let s = try makeStore()
        s.newEvent(on: monday)
        let e = try #require(s.editingEvent)
        #expect(e.isNew && e.anchor == "new:2026-10-05")
        #expect(e.item.allDay && e.item.start.day == monday && e.item.end.day == monday)
        #expect(try s.repos.events.all().isEmpty)   // nothing is saved until the user saves
        s.closeEditor()
        #expect(s.editingEvent == nil)
    }

    @Test func editingAnExistingEventUsesItsId() throws {
        let s = try makeStore()
        let e = EventItem(title: "Dentist", start: WallTime(day: monday, minute: 840), end: WallTime(day: monday, minute: 900))
        try save(s, e)
        s.editEvent(e)
        #expect(s.editingEvent?.anchor == e.id && s.editingEvent?.isNew == false)
    }

    // MARK: Saving

    @Test func savingANewEventCreatesItAndUndoRemovesIt() throws {
        let s = try makeStore()
        s.newEvent(on: monday)
        var e = try #require(s.editingEvent).item
        e.title = "Conference"
        s.saveEvent(e, from: nil)
        #expect(try s.repos.events.all().map(\.title) == ["Conference"])
        #expect(s.editingEvent == nil)
        s.undo()
        #expect(try s.repos.events.all().isEmpty)
    }

    @Test func savingAStoredEventChangesItInPlace() throws {
        let s = try makeStore()
        let e = EventItem(title: "Dentist", start: WallTime(day: monday, minute: 840), end: WallTime(day: monday, minute: 900))
        try save(s, e)
        var edited = e
        edited.title = "Dentist (new)"
        edited.location = "Main St"
        s.saveEvent(edited, from: e)
        #expect(s.recurringPrompt == nil)
        #expect(try s.repos.events.get(e.id)?.title == "Dentist (new)")
        #expect(try s.repos.events.get(e.id)?.location == "Main St")
        s.undo()
        #expect(try s.repos.events.get(e.id)?.title == "Dentist")
    }

    @Test func savingWithoutChangesDoesNothing() throws {
        let s = try makeStore()
        let e = EventItem(title: "Dentist", start: WallTime(day: monday, minute: 840), end: WallTime(day: monday, minute: 900))
        try save(s, e)
        s.saveEvent(e, from: e)
        #expect(s.undoName == nil)
    }

    @Test func makingAStoredEventRepeatMakesASeries() throws {
        let s = try makeStore()
        let e = EventItem(title: "Gym", start: WallTime(day: monday, minute: 420), end: WallTime(day: monday, minute: 480))
        try save(s, e)
        var edited = e
        edited.recurrence = .init(freq: .weekly)
        s.saveEvent(edited, from: e)
        #expect(s.blocks(for: DayKey("2026-10-01")...DayKey("2026-10-31")).count == 4)
    }

    @Test func savingADayOfASeriesAsksWhichOnes() throws {
        let s = try makeStore()
        try save(s, EventItem(id: "S1", title: "Standup", start: WallTime(day: monday, minute: 540), end: WallTime(day: monday, minute: 600),
                              recurrence: .init(freq: .weekly)))
        let day = try #require(s.event("S1@2026-10-12"))
        var edited = s.draft(for: day)
        edited.title = "Sync"
        edited.location = "Room 4"
        s.saveEvent(edited, from: day)
        #expect(s.recurringPrompt?.verb == "Change")
        s.answerRecurring(.only)
        let titles = s.blocks(for: DayKey("2026-10-01")...DayKey("2026-10-31")).map(\.title)
        #expect(titles == ["Standup", "Sync", "Standup", "Standup"])
        #expect(try s.repos.events.get("S1")?.location == "")
    }

    @Test func savingADayOfASeriesForAllChangesTheSeries() throws {
        let s = try makeStore()
        try save(s, EventItem(id: "S1", title: "Standup", start: WallTime(day: monday, minute: 540), end: WallTime(day: monday, minute: 600),
                              recurrence: .init(freq: .weekly)))
        let day = try #require(s.event("S1@2026-10-12"))
        var edited = s.draft(for: day)
        edited.title = "Sync"
        edited.recurrence = .init(freq: .weekly, interval: 2)
        s.saveEvent(edited, from: day)
        s.answerRecurring(.all)
        #expect(s.blocks(for: DayKey("2026-10-01")...DayKey("2026-10-31")).map(\.day.string) == ["2026-10-05", "2026-10-19"])
        #expect(try s.repos.events.get("S1")?.title == "Sync")
    }

    @Test func turningRepeatOffForAllEventsLeavesTheFirstEvent() throws {
        let s = try makeStore()
        try save(s, EventItem(id: "S1", title: "Standup", start: WallTime(day: monday, minute: 540), end: WallTime(day: monday, minute: 600),
                              recurrence: .init(freq: .weekly)))
        let day = try #require(s.event("S1@2026-10-12"))
        var edited = s.draft(for: day)
        edited.recurrence = nil
        s.saveEvent(edited, from: day)
        s.answerRecurring(.all)
        // The series keeps its first day. The other days go away.
        #expect(s.blocks(for: DayKey("2026-10-01")...DayKey("2026-10-31")).map(\.day.string) == ["2026-10-05"])
    }

    @Test func deletingAnEventFromTheEditor() throws {
        let s = try makeStore()
        let e = EventItem(title: "Dentist", start: WallTime(day: monday, minute: 840), end: WallTime(day: monday, minute: 900))
        try save(s, e)
        s.editEvent(e)
        s.deleteEvent(e)
        #expect(try s.repos.events.all().isEmpty)
        #expect(s.editingEvent == nil)
        s.undo()
        #expect(try s.repos.events.all().count == 1)
    }

    @Test func deletingADayOfASeriesAsks() throws {
        let s = try makeStore()
        try save(s, EventItem(id: "S1", title: "Standup", start: WallTime(day: monday, minute: 540), end: WallTime(day: monday, minute: 600),
                              recurrence: .init(freq: .weekly)))
        let day = try #require(s.event("S1@2026-10-12"))
        s.deleteEvent(day)
        #expect(s.recurringPrompt?.verb == "Delete")
        #expect(s.editingEvent == nil)
    }

    // MARK: Dropping a task on a day

    @Test func droppingATaskOnADayPlansIt() throws {
        let s = try makeStore()
        let t = TaskItem(title: "Call", bucket: .inbox)
        try s.repos.tasks.save(t)
        s.dropTask(t.id, on: monday)
        let moved = try #require(s.task(t.id))
        #expect(moved.bucket == .day && moved.planDate == monday)
    }
}
