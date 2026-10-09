import Testing
import Foundation
import GroveCore
@testable import Grove

/// The text and numbers of the Goals panel.
struct GoalPaneRulesTests {
    @Test func hoursShowHalvesAndTrimZeros() {
        #expect(GoalRules.hours(0) == "0")
        #expect(GoalRules.hours(30) == "0.5")
        #expect(GoalRules.hours(60) == "1")
        #expect(GoalRules.hours(150) == "2.5")
        #expect(GoalRules.hours(300) == "5")
        #expect(GoalRules.hours(15) == "0.25")
        #expect(GoalRules.hours(90) == "1.5")
        #expect(GoalRules.hours(45) == "0.75")
        #expect(GoalRules.hours(20) == "0.33")
        #expect(GoalRules.hours(2400) == "40")
    }

    @Test func progressTextIsDoneOverTargetInHours() {
        #expect(GoalRules.progressText(done: 150, target: 300) == "2.5 / 5 h")
        #expect(GoalRules.progressText(done: 0, target: 300) == "0 / 5 h")
        #expect(GoalRules.progressText(done: 360, target: 300) == "6 / 5 h")   // over target is fine
    }

    @Test func plannedTextAppearsOnlyWhenSomethingIsPlanned() {
        #expect(GoalRules.plannedText(0) == nil)
        #expect(GoalRules.plannedText(60) == "+1h planned")
        #expect(GoalRules.plannedText(90) == "+1.5h planned")
    }

    @Test func targetTextIsHoursPerWeek() {
        #expect(GoalRules.targetText(300) == "5 h / week")
        #expect(GoalRules.targetText(150) == "2.5 h / week")
    }

    @Test func theBarHasADonePartAndALighterPlannedPart() {
        let a = GoalRules.bar(done: 150, planned: 60, target: 300)
        #expect(abs(a.done - 0.5) < 1e-9 && abs(a.planned - 0.2) < 1e-9)
        let none = GoalRules.bar(done: 0, planned: 0, target: 300)
        #expect(none.done == 0 && none.planned == 0)
    }

    @Test func theBarStopsAtFull() {
        let over = GoalRules.bar(done: 360, planned: 60, target: 300)
        #expect(over.done == 1 && over.planned == 0)
        let clipped = GoalRules.bar(done: 240, planned: 120, target: 300)
        #expect(abs(clipped.done - 0.8) < 1e-9 && abs(clipped.planned - 0.2) < 1e-9)
        let zero = GoalRules.bar(done: 10, planned: 10, target: 0)
        #expect(zero.done == 0 && zero.planned == 0)
        let negative = GoalRules.bar(done: -5, planned: -5, target: 300)
        #expect(negative.done == 0 && negative.planned == 0)
    }

    @Test func theWeekLabelSaysThisWeekOrNamesTheDays() {
        let week = DayKey("2026-10-05")...DayKey("2026-10-11")
        #expect(GoalRules.weekLabel(week, today: DayKey("2026-10-09")) == "This week")
        #expect(GoalRules.weekLabel(week, today: DayKey("2026-10-05")) == "This week")
        #expect(GoalRules.weekLabel(week, today: DayKey("2026-10-11")) == "This week")
        #expect(GoalRules.weekLabel(week, today: DayKey("2026-10-12")) == "5–11 Oct")
        #expect(GoalRules.weekLabel(week, today: DayKey("2026-09-30")) == "5–11 Oct")
        let across = DayKey("2026-09-28")...DayKey("2026-10-04")
        #expect(GoalRules.weekLabel(across, today: DayKey("2026-10-09")) == "28 Sep–4 Oct")
    }

    @Test func theTargetStepperMovesInHalfHours() {
        #expect(GoalRules.stepTarget(300, up: true) == 330)
        #expect(GoalRules.stepTarget(300, up: false) == 270)
        #expect(GoalRules.stepTarget(GoalRules.targetStep, up: false) == GoalRules.targetStep)   // never below half an hour
        #expect(GoalRules.stepTarget(GoalRules.maxTarget, up: true) == GoalRules.maxTarget)
        #expect(GoalRules.defaultTarget == 300)
    }

    @Test func aGoalRowReadsAsOneSentenceForVoiceOver() {
        #expect(GoalRules.accessibilityText(title: "Read", done: 150, planned: 60, target: 300)
                == "Read, 2.5 / 5 h, +1h planned")
        #expect(GoalRules.accessibilityText(title: "Run", done: 0, planned: 0, target: 120) == "Run, 0 / 2 h")
    }

    @Test func theDurationMenuOffersFourHours() {
        #expect(PlannerLayoutRules.durationChoices.contains(240))
        #expect(PlannerLayoutRules.durationChoices == PlannerLayoutRules.durationChoices.sorted())
    }
}

/// A goal dragged out of the panel is plain text with its own prefix.
struct GoalDragPayloadTests {
    @Test func aGoalPayloadIsParsedBackToItsId() {
        #expect(DragPayload.goalPrefix == "grove-goal:")
        #expect(DragPayload.goal("ABC") == "grove-goal:ABC")
        #expect(DragPayload.goalId(from: DragPayload.goal("ABC")) == "ABC")
    }

    @Test func otherPayloadsAndTextAreNotGoals() {
        #expect(DragPayload.goalId(from: DragPayload.task("ABC")) == nil)
        #expect(DragPayload.goalId(from: DragPayload.note("ABC")) == nil)
        #expect(DragPayload.goalId(from: "plain text") == nil)
        #expect(DragPayload.goalId(from: "grove-goal:") == nil)   // no id
    }

    @Test func tasksAndNotesIgnoreAGoalPayload() {
        let raw = DragPayload.goal("ABC")
        #expect(!raw.hasPrefix(DragPayload.taskPrefix))
        #expect(DragPayload.noteId(from: raw) == nil)
    }
}

/// Drop a goal, tick it, hours go up (PLAN: goals panel).
@MainActor
struct GoalDropFlowTests {
    func makeStore() throws -> AppStore { AppStore(repos: Repos(db: try Database.inMemory())) }

    // 2026-10-05 is a Monday.
    let monday = DayKey("2026-10-05")
    let wednesday = DayKey("2026-10-07")
    let nextMonday = DayKey("2026-10-12")

    private func week(_ s: AppStore, _ id: String) -> (done: Int, planned: Int, target: Int) {
        s.goalProgress(id, weekOf: wednesday, sundayFirst: false)
    }

    @Test func dropTickAddUntickAndNextWeek() throws {
        let s = try makeStore()
        let g = try #require(s.addGoal(title: "Read", targetMin: GoalRules.defaultTarget))

        // First drop: one hour by default. It is planned, not done.
        s.dropGoalOnPlanner(raw: DragPayload.goal(g.id), day: monday, minute: 600)
        let first = try #require(s.selection.first)
        #expect(week(s, g.id) == (done: 0, planned: 60, target: 300))

        s.toggleGoalBlockDone(eventId: first)
        #expect(week(s, g.id) == (done: 60, planned: 0, target: 300))

        // A second block, longer, the same week. The goal is still there.
        s.dropGoalOnPlanner(raw: DragPayload.goal(g.id), day: wednesday, minute: 840)
        let second = try #require(s.selection.first)
        s.setDuration(blockIds: [second], minutes: 240)
        #expect(week(s, g.id) == (done: 60, planned: 240, target: 300))
        s.toggleGoalBlockDone(eventId: second)
        #expect(week(s, g.id) == (done: 300, planned: 0, target: 300))
        #expect(s.goals().map(\.id) == [g.id])

        // Un-tick takes the hours back.
        s.toggleGoalBlockDone(eventId: first)
        #expect(week(s, g.id) == (done: 240, planned: 60, target: 300))

        // A block next week does not count this week.
        s.dropGoalOnPlanner(raw: DragPayload.goal(g.id), day: nextMonday, minute: 600)
        s.toggleGoalBlockDone(eventId: try #require(s.selection.first))
        #expect(week(s, g.id) == (done: 240, planned: 60, target: 300))
        #expect(s.goalProgress(g.id, weekOf: nextMonday, sundayFirst: false) == (done: 60, planned: 0, target: 300))
    }

    @Test func theDropKeepsTheDurationMenuChoiceAndTheDoneMark() throws {
        let s = try makeStore()
        let g = try #require(s.addGoal(title: "Run", targetMin: 120))
        s.dropGoalOnPlanner(raw: DragPayload.goal(g.id), day: monday, minute: 480)
        let id = try #require(s.selection.first)
        s.toggleGoalBlockDone(eventId: id)
        s.setDuration(blockIds: [id], minutes: 90)
        #expect(try s.repos.events.get(id)?.goalId == g.id)
        #expect(try s.repos.events.get(id)?.doneAt != nil)
        #expect(week(s, g.id).done == 90)
    }

    @Test func aDropSnapsToTheMinuteItIsGiven() throws {
        let s = try makeStore()
        let g = try #require(s.addGoal(title: "Read"))
        s.dropGoalOnPlanner(raw: DragPayload.goal(g.id), day: monday, minute: 615)
        let e = try #require(try s.repos.events.all().first)
        #expect(e.start == WallTime(day: monday, minute: 615) && e.durationMinutes == GoalRules.defaultBlockLength)
    }

    @Test func aDropThatIsNotAGoalOrIsGoneDoesNothing() throws {
        let s = try makeStore()
        let g = try #require(s.addGoal(title: "Read"))
        #expect(!s.dropGoalOnPlanner(raw: DragPayload.task("x"), day: monday, minute: 600))
        #expect(!s.dropGoalOnPlanner(raw: "hello", day: monday, minute: 600))
        #expect(!s.dropGoalOnPlanner(raw: DragPayload.goal("gone"), day: monday, minute: 600))
        #expect(try s.repos.events.all().isEmpty)
        #expect(s.dropGoalOnPlanner(raw: DragPayload.goal(g.id), day: monday, minute: 600))
        #expect(try s.repos.events.all().count == 1)
    }

    @Test func theProgressNumbersChangeTheRevisionSoThePanelRedraws() throws {
        let s = try makeStore()
        let g = try #require(s.addGoal(title: "Read"))
        var seen = s.revision
        s.dropGoalOnPlanner(raw: DragPayload.goal(g.id), day: monday, minute: 600)
        #expect(s.revision > seen); seen = s.revision
        let id = try #require(s.selection.first)
        s.toggleGoalBlockDone(eventId: id)
        #expect(s.revision > seen); seen = s.revision
        s.applyEdits([BlockEdit(id: id, day: monday, start: 600, end: 720)], ripple: false, name: "Resize Block")
        #expect(s.revision > seen)
    }

    @Test func aGoalBlockClickOnlySelectsItAndDoesNotOpenATask() throws {
        let s = try makeStore()
        let g = try #require(s.addGoal(title: "Read"))
        s.dropGoalOnPlanner(raw: DragPayload.goal(g.id), day: monday, minute: 600)
        s.selection = []
        let block = try #require(s.blocks(for: monday...monday).first)
        s.selectBlock(block, extend: false)
        #expect(s.selection == [block.id])
        #expect(s.selectedTaskId == nil)
        #expect(s.editingEvent == nil)
    }
}
