import Testing
import Foundation
import GroveCore
@testable import Grove

/// The day panel, the done log, the weekly review and the mood, on a real store (PLAN §5.5 items 4, 5, 10 and 12).
@MainActor
struct DayStoreTests {
    func makeStore() throws -> AppStore { AppStore(repos: Repos(db: try Database.inMemory())) }
    let today = DayKey.today()
    var monday: DayKey { today.weekStart() }

    // MARK: The day panel

    @Test func theAgendaHoldsEventsBlocksAndLooseTasks() throws {
        let s = try makeStore()
        let day = today.adding(days: 3)
        s.createFromDraft(title: "Write report", day: day, start: 600, end: 660, asEvent: false)
        s.createFromDraft(title: "Dentist", day: day, start: 540, end: 600, asEvent: true)
        _ = s.quickAdd("Buy stamps", default: .day(day))
        let rows = s.agenda(for: day)
        #expect(rows.map(\.title) == ["Dentist", "Write report", "Buy stamps"])
        #expect(rows.map(\.kind) == [.event, .block, .task])
    }

    @Test func theAgendaFollowsChanges() throws {
        let s = try makeStore()
        let day = today.adding(days: 3)
        let t = try #require(s.quickAdd("Buy stamps", default: .day(day)))
        #expect(s.agenda(for: day).first?.done == false)
        s.toggleDone(taskId: t.id)
        #expect(s.agenda(for: day).first?.done == true)
    }

    // MARK: The done log

    @Test func completedTasksListsWhatWasFinishedOnTheDay() throws {
        let s = try makeStore()
        let a = try #require(s.quickAdd("First"))
        let b = try #require(s.quickAdd("Second"))
        _ = try #require(s.quickAdd("Not done"))
        s.toggleDone(taskId: a.id)
        s.toggleDone(taskId: b.id)
        #expect(Set(s.completedTasks(on: today).map(\.title)) == ["First", "Second"])
        #expect(s.completedTasks(on: today.adding(days: -1)).isEmpty)
        s.toggleDone(taskId: a.id)   // reopened
        #expect(s.completedTasks(on: today).map(\.title) == ["Second"])
    }

    // MARK: The weekly review

    @Test func theReviewShowsDoneOpenHoursAndTheBusiestDay() throws {
        let s = try makeStore()
        let tue = monday.adding(days: 1)
        s.createFromDraft(title: "Write report", day: monday, start: 600, end: 720, asEvent: false)   // 2h
        s.createFromDraft(title: "Call Sam", day: tue, start: 540, end: 600, asEvent: false)          // 1h
        s.createFromDraft(title: "Workshop", day: tue, start: 780, end: 900, asEvent: true)           // 2h, not a task
        _ = s.quickAdd("Plan the trip", default: .week(monday))
        let report = try #require(try s.repos.tasks.all().first { $0.title == "Write report" })
        s.toggleDone(taskId: report.id)

        let r = s.weekReview(monday)
        #expect(r.done.map(\.title) == ["Write report"])
        #expect(Set(r.open.map(\.title)) == ["Call Sam", "Plan the trip"])
        #expect(r.open.first?.title == "Call Sam")   // the task with a day comes first
        #expect(r.plannedMinutes == 180 && r.doneMinutes == 120)
        #expect(r.busiest == BusyDay(day: tue, minutes: 180))
    }

    @Test func theReviewIgnoresOtherWeeks() throws {
        let s = try makeStore()
        s.createFromDraft(title: "Next week", day: monday.adding(days: 8), start: 600, end: 660, asEvent: false)
        let r = s.weekReview(monday)
        #expect(r.open.isEmpty && r.plannedMinutes == 0 && r.busiest == nil)
    }

    @Test func insertingTheSummaryWritesItUnderReviewAndUndoTakesItBack() throws {
        let s = try makeStore()
        let w = s.weeklyNote(for: today)
        s.setNoteBody(w.id, "## Goals\n- Ship it\n")
        s.insertWeekSummary(w.id)
        let body = try #require(s.note(w.id)).body
        #expect(body.contains("## Review\n**Week summary**\n- Done: 0 tasks"))
        #expect(body.hasPrefix("## Goals\n- Ship it\n"))
        #expect(DayRules.hasSummary(body))
        s.undo()
        #expect(s.note(w.id)?.body == "## Goals\n- Ship it\n")
    }

    @Test func theSummaryIsItsOwnUndoStepEvenRightAfterTyping() throws {
        let s = try makeStore()
        let w = s.weeklyNote(for: today)
        s.setNoteBody(w.id, "## Goals\n")
        s.insertWeekSummary(w.id)
        #expect(s.undoName == "Insert Week Summary")
        s.undo()
        #expect(s.note(w.id)?.body == "## Goals\n")   // the typing before it stays
        s.setNoteBody(w.id, "## Goals\nMore")
        s.insertWeekSummary(w.id)
        s.setNoteBody(w.id, (s.note(w.id)?.body ?? "") + "\nAfter")
        s.undo()
        #expect(DayRules.hasSummary(s.note(w.id)?.body ?? ""))   // typing after it is its own step too
    }

    @Test func aSecondInsertUpdatesTheSummaryInPlace() throws {
        let s = try makeStore()
        let w = s.weeklyNote(for: today)
        s.insertWeekSummary(w.id)
        _ = s.quickAdd("New thing", default: .day(monday))
        s.insertWeekSummary(w.id)
        let body = try #require(s.note(w.id)).body
        #expect(body.components(separatedBy: "**Week summary**").count == 2)   // one summary
        #expect(body.contains("- Still open: 1 task"))
    }

    @Test func theSummaryOnlyGoesInAWeeklyNote() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Plain", body: "text")
        s.insertWeekSummary(n.id)
        #expect(s.note(n.id)?.body == "text")
        let d = s.dailyNote(for: today)
        s.insertWeekSummary(d.id)
        #expect(!DayRules.hasSummary(s.note(d.id)?.body ?? ""))
    }

    // MARK: Mood

    @Test func aMoodIsSetChangedAndClearedByTheSameClick() throws {
        let s = try makeStore()
        let d = s.dailyNote(for: today)
        #expect(s.note(d.id)?.mood == nil)
        s.setMood(d.id, .sun)
        #expect(s.note(d.id)?.mood == 3)
        s.setMood(d.id, .rain)
        #expect(s.note(d.id)?.mood == 1)
        s.setMood(d.id, .rain)
        #expect(s.note(d.id)?.mood == nil)
    }

    @Test func aMoodChangeIsOneUndoStepAndKeepsTheText() throws {
        let s = try makeStore()
        let d = s.dailyNote(for: today)
        s.setNoteBody(d.id, "A good day")
        s.setMood(d.id, .cloud)
        #expect(s.undoName == "Set Mood")
        s.undo()
        #expect(s.note(d.id)?.mood == nil)
        #expect(s.note(d.id)?.body == "A good day")
        s.redo()
        #expect(s.note(d.id)?.mood == 2)
    }

    @Test func onlyADailyNoteTakesAMood() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Plain")
        s.setMood(n.id, .sun)
        #expect(s.note(n.id)?.mood == nil)
        let w = s.weeklyNote(for: today)
        s.setMood(w.id, .sun)
        #expect(s.note(w.id)?.mood == nil)
    }

    @Test func theCalendarKnowsTheMoodOfEachDay() throws {
        let s = try makeStore()
        let d = s.dailyNote(for: today)
        let other = s.dailyNote(for: today.adding(days: 1))
        s.setNoteBody(other.id, "A note with no mood")
        s.setMood(d.id, .sun)
        let info = s.dayInfo(today...today.adding(days: 2))
        #expect(info[today]?.mood == 3)
        #expect(info[today.adding(days: 1)]?.mood == nil)   // a note with no mood
        #expect(info[today.adding(days: 1)]?.hasNote == true)
        #expect(info[today.adding(days: 2)]?.mood == nil)
    }

    @Test func theMoodQueryReturnsOnlyDaysInRangeWithAMood() throws {
        let s = try makeStore()
        s.setMood(s.dailyNote(for: today).id, .cloud)
        s.setMood(s.dailyNote(for: today.adding(days: 5)).id, .rain)
        s.setMood(s.dailyNote(for: today.adding(days: 40)).id, .sun)
        let moods = try s.repos.notes.moods(from: today, to: today.adding(days: 10))
        #expect(moods == [today: 2, today.adding(days: 5): 1])
    }

    // MARK: Opening things from a note

    @Test func openingATaskOnAnotherDayShowsThatDayOnThePlanner() throws {
        let s = try makeStore()
        let day = today.adding(days: 2)
        let t = try #require(s.quickAdd("Buy stamps", default: .day(day)))
        s.screen = .notes
        s.open(ItemRef(.task, t.id))
        #expect(s.screen == .planner && s.selectedTaskId == t.id && s.selectedDay == day)
    }

    @Test func openingATaskOfTodayShowsTheTodayScreen() throws {
        let s = try makeStore()
        let t = try #require(s.quickAdd("Buy stamps", default: .day(today)))
        s.screen = .notes
        s.open(ItemRef(.task, t.id))
        #expect(s.screen == .today && s.selectedTaskId == t.id && s.selectedDay == today)
    }

    @Test func openingAnEventOnAnotherDayShowsThatDayOnThePlanner() throws {
        let s = try makeStore()
        let day = today.adding(days: 2)
        s.createFromDraft(title: "Dentist", day: day, start: 540, end: 600, asEvent: true)
        let e = try #require(s.eventItems(in: day...day).first)
        s.screen = .notes
        s.open(ItemRef(.event, e.id))
        #expect(s.screen == .planner && s.selection == [e.id] && s.selectedDay == day)
    }
}
