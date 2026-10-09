import Testing
import Foundation
import GroveCore
@testable import Grove

/// Goals in the store: a target of hours per week, blocks dragged into days, hours added when a block is done.
@MainActor
struct GoalStoreTests {
    func makeStore() throws -> AppStore { AppStore(repos: Repos(db: try Database.inMemory())) }

    // 2026-10-05 is a Monday. The Monday-first week runs to Sunday 2026-10-11.
    let monday = DayKey("2026-10-05")
    let sunday = DayKey("2026-10-11")

    private func progress(_ s: AppStore, _ id: String, sundayFirst: Bool = false) -> (done: Int, planned: Int, target: Int) {
        s.goalProgress(id, weekOf: DayKey("2026-10-07"), sundayFirst: sundayFirst)
    }

    @discardableResult
    private func makeGoal(_ s: AppStore, _ title: String = "Read", target: Int = 300) throws -> GoalItem {
        try #require(s.addGoal(title: title, targetMin: target))
    }

    // MARK: Goals

    @Test func addingAGoalSavesItAndListsItInOrder() throws {
        let s = try makeStore()
        let a = try makeGoal(s, "Read", target: 360)
        let b = try makeGoal(s, "Run", target: 120)
        #expect(a.targetMin == 360 && a.title == "Read" && a.color == "")
        #expect(s.goals().map(\.title) == ["Read", "Run"])
        #expect(b.sort > a.sort)
        #expect(s.undoName == "New Goal")
    }

    @Test func aGoalWithoutATitleIsNotAdded() throws {
        let s = try makeStore()
        #expect(s.addGoal(title: "   ", targetMin: 300) == nil)
        #expect(s.goals().isEmpty)
        #expect(s.undoName == nil)
    }

    @Test func theTitleIsTrimmedAndTheTargetStaysInsideSensibleLimits() throws {
        let s = try makeStore()
        let a = try makeGoal(s, "  Read  ", target: 0)
        let b = try makeGoal(s, "Run", target: 99_999)
        #expect(a.title == "Read")
        #expect(a.targetMin == GoalRules.minTarget)
        #expect(b.targetMin == GoalRules.maxTarget)
    }

    @Test func addingAGoalBumpsTheRevision() throws {
        let s = try makeStore()
        let before = s.revision
        try makeGoal(s)
        #expect(s.revision > before)
    }

    @Test func addingAGoalCanBeUndoneAndRedone() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.undo()
        #expect(s.goals().isEmpty)
        #expect(try s.repos.goals.get(g.id) == nil)
        s.redo()
        #expect(s.goals().map(\.id) == [g.id])
        #expect(try s.repos.goals.get(g.id)?.targetMin == 300)
    }

    @Test func updatingAGoalChangesOnlyWhatIsGivenAndCanBeUndone() throws {
        let s = try makeStore()
        let g = try makeGoal(s, "Read", target: 300)
        s.updateGoal(g.id, title: "Read books", color: "teal", targetMin: 420)
        let now = try #require(s.goal(g.id))
        #expect(now.title == "Read books" && now.targetMin == 420 && now.color == "teal" && now.notes == "")
        s.updateGoal(g.id, notes: "Novels")
        #expect(s.goal(g.id)?.notes == "Novels" && s.goal(g.id)?.title == "Read books")
        s.undo()
        #expect(s.goal(g.id)?.notes == "")
        s.undo()
        #expect(s.goal(g.id)?.title == "Read" && s.goal(g.id)?.targetMin == 300 && s.goal(g.id)?.color == "")
        s.redo()
        #expect(s.goal(g.id)?.title == "Read books")
    }

    @Test func aColourThatIsNotOneOfTheEightIsIgnored() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.updateGoal(g.id, color: "mauve")
        #expect(s.goal(g.id)?.color == "")
        s.updateGoal(g.id, title: "   ")
        #expect(s.goal(g.id)?.title == "Read")
    }

    @Test func anArchivedGoalLeavesTheListButKeepsItsBlocks() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600)
        s.updateGoal(g.id, archived: true)
        #expect(s.goals().isEmpty)
        #expect(s.goals(includeArchived: true).count == 1)
        #expect(s.blocks(for: monday...monday).count == 1)
    }

    // MARK: Scheduling

    @Test func draggingAGoalIntoADayMakesAGoalBlock() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.updateGoal(g.id, color: "teal")
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 90)
        let e = try #require(try s.repos.events.all().first)
        #expect(e.kind == .block && e.goalId == g.id && e.doneAt == nil && e.taskId == nil)
        #expect(e.title == "Read" && e.color == "teal")
        #expect(e.start == WallTime(day: monday, minute: 600) && e.end == WallTime(day: monday, minute: 690))
        #expect(s.selection == [e.id])
        #expect(try s.repos.tasks.all().isEmpty)   // a goal block has no task
    }

    @Test func aGoalWithoutAColourGivesTheBlockTheAccentColour() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600)
        #expect(try s.repos.events.all().first?.color == "accent")
    }

    @Test func theDefaultBlockLengthIsOneHour() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600)
        let e = try #require(try s.repos.events.all().first)
        #expect(e.durationMinutes == 60)
    }

    @Test func aBlockDroppedNearMidnightIsMovedUpToFitTheDay() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 1430, length: 60)
        let e = try #require(try s.repos.events.all().first)
        #expect(e.end.minute <= 1440 && e.durationMinutes == 60)
        #expect(e.start.day == monday && e.end.day == monday)
    }

    @Test func schedulingAGoalCanBeUndoneAndRedone() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600)
        #expect(s.undoName == "Schedule Goal")
        s.undo()
        #expect(try s.repos.events.all().isEmpty)
        s.redo()
        #expect(try s.repos.events.all().count == 1)
        #expect(s.goal(g.id) != nil)
    }

    @Test func schedulingAGoalThatIsGoneDoesNothing() throws {
        let s = try makeStore()
        s.scheduleGoal(goalId: "nope", day: monday, start: 600)
        #expect(try s.repos.events.all().isEmpty)
    }

    @Test func theGoalStaysAndAnotherBlockCanBeAddedInTheSameWeek() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600)
        s.scheduleGoal(goalId: g.id, day: monday.adding(days: 2), start: 600, length: 30)
        #expect(try s.repos.events.all().count == 2)
        #expect(s.goals().count == 1)
        #expect(progress(s, g.id).planned == 90)
    }

    // MARK: Progress

    @Test func aNewGoalHasNoProgressAndShowsItsTarget() throws {
        let s = try makeStore()
        let g = try makeGoal(s, target: 300)
        let p = progress(s, g.id)
        #expect(p.done == 0 && p.planned == 0 && p.target == 300)
    }

    @Test func markingABlockDoneAddsItsHoursAndMarkingAgainTakesThemBack() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 120)
        let id = try #require(s.selection.first)
        #expect(progress(s, g.id) == (done: 0, planned: 120, target: 300))
        s.toggleGoalBlockDone(eventId: id)
        #expect(progress(s, g.id) == (done: 120, planned: 0, target: 300))
        #expect(try s.repos.events.get(id)?.doneAt != nil)
        s.toggleGoalBlockDone(eventId: id)
        #expect(progress(s, g.id) == (done: 0, planned: 120, target: 300))
        #expect(try s.repos.events.get(id)?.doneAt == nil)
    }

    @Test func aDoneGoalBlockShowsAsDoneOnTheGrid() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600)
        let id = try #require(s.selection.first)
        #expect(s.blocks(for: monday...monday).first?.isDone == false)
        s.toggleGoalBlockDone(eventId: id)
        let b = try #require(s.blocks(for: monday...monday).first)
        #expect(b.isDone && b.goalId == g.id && !b.isTaskBlock)
    }

    @Test func markingABlockDoneIsOneUndoStep() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60)
        let id = try #require(s.selection.first)
        s.toggleGoalBlockDone(eventId: id)
        #expect(s.undoName == "Complete Goal Block")
        s.undo()
        #expect(progress(s, g.id).done == 0 && progress(s, g.id).planned == 60)
        s.redo()
        #expect(progress(s, g.id).done == 60 && progress(s, g.id).planned == 0)
        s.toggleGoalBlockDone(eventId: id)
        #expect(s.undoName == "Reopen Goal Block")
        s.undo()
        #expect(progress(s, g.id).done == 60)
    }

    @Test func aSecondBlockInTheSameWeekAddsMoreHours() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60)
        let first = try #require(s.selection.first)
        s.scheduleGoal(goalId: g.id, day: sunday, start: 600, length: 90)
        let second = try #require(s.selection.first)
        s.toggleGoalBlockDone(eventId: first)
        #expect(progress(s, g.id).done == 60)
        s.toggleGoalBlockDone(eventId: second)
        #expect(progress(s, g.id) == (done: 150, planned: 0, target: 300))
    }

    @Test func resizingADoneBlockChangesTheHours() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60)
        let id = try #require(s.selection.first)
        s.toggleGoalBlockDone(eventId: id)
        s.applyEdits([BlockEdit(id: id, day: monday, start: 600, end: 750)], ripple: false, name: "Resize Block")
        #expect(progress(s, g.id).done == 150)
        s.applyEdits([BlockEdit(id: id, day: monday, start: 600, end: 630)], ripple: false, name: "Resize Block")
        #expect(progress(s, g.id).done == 30)
        #expect(try s.repos.events.get(id)?.doneAt != nil)   // resizing keeps it done
    }

    @Test func aNewWeekStartsAtZeroByItself() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60)
        s.toggleGoalBlockDone(eventId: try #require(s.selection.first))
        let nextWeek = DayKey("2026-10-14")
        #expect(s.goalProgress(g.id, weekOf: nextWeek, sundayFirst: false) == (done: 0, planned: 0, target: 300))
        #expect(s.goalProgress(g.id, weekOf: DayKey("2026-09-30"), sundayFirst: false).done == 0)
    }

    @Test func movingADoneBlockToAnotherWeekMovesItsHours() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60)
        let id = try #require(s.selection.first)
        s.toggleGoalBlockDone(eventId: id)
        let later = monday.adding(days: 7)
        s.applyEdits([BlockEdit(id: id, day: later, start: 600, end: 660)], ripple: false, name: "Move Block")
        #expect(progress(s, g.id).done == 0)
        #expect(s.goalProgress(g.id, weekOf: later, sundayFirst: false).done == 60)
    }

    @Test func theWeekRunsMondayToSundayOrSundayToSaturday() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        let sundayBefore = monday.adding(days: -1)   // 2026-10-04
        s.scheduleGoal(goalId: g.id, day: sundayBefore, start: 600, length: 60)
        s.toggleGoalBlockDone(eventId: try #require(s.selection.first))
        s.scheduleGoal(goalId: g.id, day: sunday, start: 600, length: 30)
        s.toggleGoalBlockDone(eventId: try #require(s.selection.first))
        // Monday first: 10-04 belongs to the week before, 10-11 closes this one.
        #expect(progress(s, g.id, sundayFirst: false).done == 30)
        // Sunday first: 10-04 opens this week, 10-11 opens the next.
        #expect(progress(s, g.id, sundayFirst: true).done == 60)
        #expect(s.goalProgress(g.id, weekOf: DayKey("2026-10-12"), sundayFirst: true).done == 30)
    }

    @Test func theWeekSettingIsReadFromTheSameKeyAsThePlanner() throws {
        let key = "calendar.weekStartsSunday"
        let saved = UserDefaults.standard.object(forKey: key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday.adding(days: -1), start: 600, length: 60)
        s.toggleGoalBlockDone(eventId: try #require(s.selection.first))
        UserDefaults.standard.set(false, forKey: key)
        #expect(s.goalProgress(g.id, weekOf: DayKey("2026-10-07")).done == 0)
        UserDefaults.standard.set(true, forKey: key)
        #expect(s.goalProgress(g.id, weekOf: DayKey("2026-10-07")).done == 60)
    }

    @Test func togglingABlockThatIsNotAGoalBlockChangesNothing() throws {
        let s = try makeStore()
        s.createFromDraft(title: "Dentist", day: monday, start: 600, end: 660, asEvent: true)
        let id = try #require(s.blocks(for: monday...monday).first).id
        let before = s.undoName
        s.toggleGoalBlockDone(eventId: id)
        #expect(try s.repos.events.get(id)?.doneAt == nil)
        #expect(s.undoName == before)
    }

    // MARK: Deleting a goal

    @Test func deletingAGoalKeepsItsBlocksAsPlainBlocks() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60)
        let done = try #require(s.selection.first)
        s.scheduleGoal(goalId: g.id, day: monday, start: 720, length: 60)
        s.toggleGoalBlockDone(eventId: done)
        s.deleteGoal(g.id)
        #expect(s.goals().isEmpty && s.goal(g.id) == nil)
        let events = try s.repos.events.all()
        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.goalId == nil && $0.doneAt == nil && $0.kind == .block })
        #expect(s.blocks(for: monday...monday).count == 2)
        #expect(s.blocks(for: monday...monday).allSatisfy { $0.goalId == nil && !$0.isDone })
    }

    @Test func deletingAGoalCanBeUndoneAndTheBlocksComeBackToIt() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60)
        let id = try #require(s.selection.first)
        s.toggleGoalBlockDone(eventId: id)
        s.deleteGoal(g.id)
        #expect(s.undoName == "Delete Goal")
        s.undo()
        #expect(s.goal(g.id)?.title == "Read")
        #expect(try s.repos.events.get(id)?.goalId == g.id)
        #expect(progress(s, g.id).done == 60)
        s.redo()
        #expect(s.goal(g.id) == nil)
        #expect(try s.repos.events.get(id)?.goalId == nil)
    }

    // MARK: Planner

    @Test func aGoalBlockCountsAsPlannedTimeButNotAsATask() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60)
        s.toggleGoalBlockDone(eventId: try #require(s.selection.first))
        s.createFromDraft(title: "Write", day: monday, start: 720, end: 780, asEvent: false)
        let totals = s.dayTotals(monday, blocks: s.blocks(for: monday...monday), workStart: 540, workEnd: 1020)
        #expect(totals.planned == 120)
        #expect(totals.total == 1 && totals.done == 0)   // only the task block
        #expect(s.plannedMinutes(on: monday) == 120)
    }

    @Test func duplicatingADoneGoalBlockMakesAPlannedOne() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60)
        let id = try #require(s.selection.first)
        s.toggleGoalBlockDone(eventId: id)
        s.duplicate(blockIds: [id])
        let events = try s.repos.events.all()
        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.goalId == g.id })
        #expect(progress(s, g.id) == (done: 60, planned: 60, target: 300))
    }

    @Test func splittingADoneGoalBlockKeepsTheHours() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 120)
        let id = try #require(s.selection.first)
        s.toggleGoalBlockDone(eventId: id)
        s.split(blockId: id)
        #expect(progress(s, g.id) == (done: 120, planned: 0, target: 300))
    }

    @Test func deletingAGoalBlockRemovesItsHours() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60)
        let id = try #require(s.selection.first)
        s.toggleGoalBlockDone(eventId: id)
        s.deleteBlocks([id])
        #expect(progress(s, g.id).done == 0)
        #expect(s.goal(g.id) != nil)
    }
}

/// The small rules behind goals.
struct GoalRulesTests {
    @Test func aTargetStaysBetweenOneStepAndAWeek() {
        #expect(GoalRules.clampTarget(0) == 15)
        #expect(GoalRules.clampTarget(-30) == 15)
        #expect(GoalRules.clampTarget(300) == 300)
        #expect(GoalRules.clampTarget(100_000) == 10_080)
    }

    @Test func theWeekIsSevenDaysFromMondayOrFromSunday() {
        let wednesday = DayKey("2026-10-07")
        let monday = GoalRules.week(of: wednesday, sundayFirst: false)
        #expect(monday.lowerBound == DayKey("2026-10-05") && monday.upperBound == DayKey("2026-10-11"))
        let sunday = GoalRules.week(of: wednesday, sundayFirst: true)
        #expect(sunday.lowerBound == DayKey("2026-10-04") && sunday.upperBound == DayKey("2026-10-10"))
    }

    @Test func aSundayClosesAMondayWeekAndOpensASundayWeek() {
        let day = DayKey("2026-10-11")
        #expect(GoalRules.week(of: day, sundayFirst: false).lowerBound == DayKey("2026-10-05"))
        #expect(GoalRules.week(of: day, sundayFirst: true).lowerBound == day)
    }

    @Test func aBlockUsesTheGoalColourOrTheAccent() {
        #expect(GoalRules.blockColor(of: GoalItem(title: "x")) == "accent")
        #expect(GoalRules.blockColor(of: GoalItem(title: "x", color: "teal")) == "teal")
    }
}
