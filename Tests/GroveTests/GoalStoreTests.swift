import Testing
import Foundation
import GroveCore
@testable import Grove

/// Goals in the store: a weekly target of hours or sessions, blocks dragged into days. Every block in the week counts.
@MainActor
struct GoalStoreTests {
    func makeStore() throws -> AppStore { AppStore(repos: Repos(db: try Database.inMemory())) }

    // 2026-10-05 is a Monday. The Monday-first week runs to Sunday 2026-10-11.
    let monday = DayKey("2026-10-05")
    let sunday = DayKey("2026-10-11")

    private func progress(_ s: AppStore, _ id: String, sundayFirst: Bool = false) -> GoalProgress {
        s.goalProgress(id, weekOf: DayKey("2026-10-07"), sundayFirst: sundayFirst)
    }

    @discardableResult
    private func makeGoal(_ s: AppStore, _ title: String = "Read", target: Int = 300) throws -> GoalItem {
        try #require(s.addGoal(title: title, target: target))
    }

    // MARK: Goals

    @Test func addingAGoalSavesItAndListsItInOrder() throws {
        let s = try makeStore()
        let a = try makeGoal(s, "Read", target: 360)
        let b = try makeGoal(s, "Run", target: 120)
        #expect(a.targetMin == 360 && a.title == "Read" && a.color == "" && a.kind == .hours)
        #expect(s.goals().map(\.title) == ["Read", "Run"])
        #expect(b.sort > a.sort)
        #expect(s.undoName == "New Goal")
    }

    @Test func aGoalWithoutATitleIsNotAdded() throws {
        let s = try makeStore()
        #expect(s.addGoal(title: "   ", target: 300) == nil)
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

    @Test func aSessionGoalKeepsItsCountAndTheDefaultHours() throws {
        let s = try makeStore()
        let g = try #require(s.addGoal(title: "Gym", kind: .sessions, target: 4))
        #expect(g.kind == .sessions && g.targetCount == 4 && g.targetMin == GoalRules.defaultTarget)
        let d = try #require(s.addGoal(title: "Swim", kind: .sessions))
        #expect(d.targetCount == GoalRules.defaultCount)
        let low = try #require(s.addGoal(title: "Yoga", kind: .sessions, target: 0))
        let high = try #require(s.addGoal(title: "Walk", kind: .sessions, target: 500))
        #expect(low.targetCount == GoalRules.minCount && high.targetCount == GoalRules.maxCount)
    }

    @Test func changingTheKindAndCountIsOneUndoStepEach() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.updateGoal(g.id, kind: .sessions)
        #expect(s.goal(g.id)?.kind == .sessions && s.undoName == "Edit Goal")
        s.updateGoal(g.id, targetCount: 5)
        #expect(s.goal(g.id)?.targetCount == 5)
        s.updateGoal(g.id, targetCount: 1000)
        #expect(s.goal(g.id)?.targetCount == GoalRules.maxCount)
        s.undo()
        #expect(s.goal(g.id)?.targetCount == 5)
        s.undo()
        #expect(s.goal(g.id)?.targetCount == 3)
        s.undo()
        #expect(s.goal(g.id)?.kind == .hours)
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
        #expect(progress(s, g.id) == GoalProgress(kind: .hours, done: 0, planned: 0, target: 300))
    }

    @Test func aBlockCountsAsSoonAsItIsInTheWeek() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 120)
        #expect(progress(s, g.id) == GoalProgress(kind: .hours, done: 0, planned: 120, target: 300))
        let e = try #require(try s.repos.events.all().first)
        #expect(e.doneAt == nil)
    }

    @Test func aSessionGoalCountsOneForEachBlock() throws {
        let s = try makeStore()
        let g = try #require(s.addGoal(title: "Gym", kind: .sessions, target: 2))
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 30)
        s.scheduleGoal(goalId: g.id, day: sunday, start: 600, length: 240)
        #expect(progress(s, g.id) == GoalProgress(kind: .sessions, done: 0, planned: 2, target: 2))
        s.scheduleGoal(goalId: g.id, day: sunday, start: 900, length: 60)
        #expect(progress(s, g.id).planned == 3)   // over the target is fine
    }

    @Test func switchingTheKindKeepsTheBlocksAndChangesWhatIsCounted() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 90)
        s.scheduleGoal(goalId: g.id, day: monday, start: 800, length: 30)
        #expect(progress(s, g.id) == GoalProgress(kind: .hours, done: 0, planned: 120, target: 300))
        s.updateGoal(g.id, kind: .sessions)
        #expect(progress(s, g.id) == GoalProgress(kind: .sessions, done: 0, planned: 2, target: 3))
        #expect(try s.repos.events.all().count == 2)
    }

    @Test func hoursCanGoOverTheTarget() throws {
        let s = try makeStore()
        let g = try makeGoal(s, target: 60)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 240)
        #expect(progress(s, g.id).planned == 240)
    }

    @Test func tickingAGoalBlockMovesItFromPlannedToDone() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 90)
        s.scheduleGoal(goalId: g.id, day: monday, start: 800, length: 30)
        let id = try #require(s.selection.first)
        s.toggleGoalBlockDone(eventId: id)
        #expect(progress(s, g.id) == GoalProgress(kind: .hours, done: 30, planned: 120, target: 300))
        #expect(s.blocks(for: monday...monday).first { $0.id == id }?.isDone == true)
        #expect(s.undoName == "Complete Goal Block")
        s.toggleGoalBlockDone(eventId: id)
        #expect(progress(s, g.id).done == 0)
        #expect(s.blocks(for: monday...monday).first { $0.id == id }?.isDone == false)
    }

    @Test func tickingIsOneUndoStep() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60)
        let id = try #require(s.selection.first)
        s.toggleGoalBlockDone(eventId: id)
        s.undo()
        #expect(progress(s, g.id).done == 0)
        s.redo()
        #expect(progress(s, g.id).done == 60)
    }

    @Test func aSessionGoalCountsDoneBlocks() throws {
        let s = try makeStore()
        let g = try #require(s.addGoal(title: "Gym", kind: .sessions, target: 3))
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 30)
        let id = try #require(s.selection.first)
        s.scheduleGoal(goalId: g.id, day: sunday, start: 600, length: 240)
        s.toggleGoalBlockDone(eventId: id)
        #expect(progress(s, g.id) == GoalProgress(kind: .sessions, done: 1, planned: 2, target: 3))
    }

    @Test func tickingDoesNothingOnABlockWithoutAGoal() throws {
        let s = try makeStore()
        let e = EventItem(title: "Lunch", start: WallTime(day: monday, minute: 720), end: WallTime(day: monday, minute: 780))
        try s.repos.events.save(e)
        s.toggleGoalBlockDone(eventId: e.id)
        #expect(try s.repos.events.get(e.id)?.doneAt == nil)
        #expect(s.undoName == nil)
    }

    @Test func aGoalStaysInTheListWhenAllItsBlocksAreDone() throws {
        let s = try makeStore()
        let g = try makeGoal(s, target: 60)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60)
        s.toggleGoalBlockDone(eventId: try #require(s.selection.first))
        #expect(progress(s, g.id).done == 60)
        #expect(s.goals().map(\.id) == [g.id])
    }

    @Test func aDuplicateOfADoneBlockIsPlannedNotDone() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60)
        let id = try #require(s.selection.first)
        s.toggleGoalBlockDone(eventId: id)
        s.duplicate(blockIds: [id])
        #expect(progress(s, g.id) == GoalProgress(kind: .hours, done: 60, planned: 120, target: 300))
    }

    @Test func resizingABlockChangesTheHours() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60)
        let id = try #require(s.selection.first)
        s.applyEdits([BlockEdit(id: id, day: monday, start: 600, end: 750)], ripple: false, name: "Resize Block")
        #expect(progress(s, g.id).planned == 150)
        s.applyEdits([BlockEdit(id: id, day: monday, start: 600, end: 630)], ripple: false, name: "Resize Block")
        #expect(progress(s, g.id).planned == 30)
    }

    @Test func aNewWeekStartsAtZeroByItself() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60)
        #expect(s.goalProgress(g.id, weekOf: DayKey("2026-10-14"), sundayFirst: false) == GoalProgress(kind: .hours, done: 0, planned: 0, target: 300))
        #expect(s.goalProgress(g.id, weekOf: DayKey("2026-09-30"), sundayFirst: false).planned == 0)
    }

    @Test func movingABlockToAnotherWeekMovesItsHours() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60)
        let id = try #require(s.selection.first)
        let later = monday.adding(days: 7)
        s.applyEdits([BlockEdit(id: id, day: later, start: 600, end: 660)], ripple: false, name: "Move Block")
        #expect(progress(s, g.id).planned == 0)
        #expect(s.goalProgress(g.id, weekOf: later, sundayFirst: false).planned == 60)
    }

    @Test func theWeekRunsMondayToSundayOrSundayToSaturday() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        let sundayBefore = monday.adding(days: -1)   // 2026-10-04
        s.scheduleGoal(goalId: g.id, day: sundayBefore, start: 600, length: 60)
        s.scheduleGoal(goalId: g.id, day: sunday, start: 600, length: 30)
        // Monday first: 10-04 belongs to the week before, 10-11 closes this one.
        #expect(progress(s, g.id, sundayFirst: false).planned == 30)
        // Sunday first: 10-04 opens this week, 10-11 opens the next.
        #expect(progress(s, g.id, sundayFirst: true).planned == 60)
        #expect(s.goalProgress(g.id, weekOf: DayKey("2026-10-12"), sundayFirst: true).planned == 30)
    }

    @Test func theWeekSettingIsReadFromTheSameKeyAsThePlanner() throws {
        let key = "calendar.weekStartsSunday"
        let saved = UserDefaults.standard.object(forKey: key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday.adding(days: -1), start: 600, length: 60)
        UserDefaults.standard.set(false, forKey: key)
        #expect(s.goalProgress(g.id, weekOf: DayKey("2026-10-07")).planned == 0)
        UserDefaults.standard.set(true, forKey: key)
        #expect(s.goalProgress(g.id, weekOf: DayKey("2026-10-07")).planned == 60)
    }

    // MARK: Deleting a goal

    @Test func deletingAGoalKeepsItsBlocksAsPlainBlocks() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60)
        s.scheduleGoal(goalId: g.id, day: monday, start: 720, length: 60)
        s.deleteGoal(g.id)
        #expect(s.goals().isEmpty && s.goal(g.id) == nil)
        let events = try s.repos.events.all()
        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.goalId == nil && $0.kind == .block })
        #expect(s.blocks(for: monday...monday).count == 2)
        #expect(s.blocks(for: monday...monday).allSatisfy { $0.goalId == nil && !$0.isDone })
    }

    @Test func deletingAGoalCanBeUndoneAndTheBlocksComeBackToIt() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60)
        let id = try #require(s.selection.first)
        s.deleteGoal(g.id)
        #expect(s.undoName == "Delete Goal")
        s.undo()
        #expect(s.goal(g.id)?.title == "Read")
        #expect(try s.repos.events.get(id)?.goalId == g.id)
        #expect(progress(s, g.id).planned == 60)
        s.redo()
        #expect(s.goal(g.id) == nil)
        #expect(try s.repos.events.get(id)?.goalId == nil)
    }

    // MARK: Planner

    @Test func aGoalBlockCountsAsPlannedTimeButNotAsATask() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60)
        s.createFromDraft(title: "Write", day: monday, start: 720, end: 780, asEvent: false)
        let totals = s.dayTotals(monday, blocks: s.blocks(for: monday...monday), workStart: 540, workEnd: 1020)
        #expect(totals.planned == 120)
        #expect(totals.total == 1 && totals.done == 0)   // only the task block
        #expect(s.plannedMinutes(on: monday) == 120)
    }

    @Test func duplicatingAGoalBlockAddsItsHoursAgain() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60)
        let id = try #require(s.selection.first)
        s.duplicate(blockIds: [id])
        let events = try s.repos.events.all()
        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.goalId == g.id })
        #expect(progress(s, g.id).planned == 120)
    }

    @Test func splittingAGoalBlockKeepsTheHoursAndAddsASession() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 120)
        let id = try #require(s.selection.first)
        s.split(blockId: id)
        #expect(progress(s, g.id).planned == 120)
        s.updateGoal(g.id, kind: .sessions)
        #expect(progress(s, g.id).planned == 2)
    }

    @Test func deletingAGoalBlockRemovesItsHours() throws {
        let s = try makeStore()
        let g = try makeGoal(s)
        s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 60)
        let id = try #require(s.selection.first)
        s.deleteBlocks([id])
        #expect(progress(s, g.id).planned == 0)
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

    @Test func aCountStaysBetweenOneAndNinetyNine() {
        #expect(GoalRules.clampCount(0) == 1)
        #expect(GoalRules.clampCount(3) == 3)
        #expect(GoalRules.clampCount(500) == 99)
        #expect(GoalRules.defaultCount == 3)
    }

    @Test func theTargetOfAGoalIsItsHoursOrItsCount() {
        var g = GoalItem(title: "x", targetMin: 240)
        #expect(GoalRules.target(of: g) == 240)
        g.kind = .sessions
        g.targetCount = 4
        #expect(GoalRules.target(of: g) == 4)
    }

    @Test func aBlockUsesTheGoalColourOrTheAccent() {
        #expect(GoalRules.blockColor(of: GoalItem(title: "x")) == "accent")
        #expect(GoalRules.blockColor(of: GoalItem(title: "x", color: "teal")) == "teal")
    }
}
