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

    @Test func progressTextIsHoursOverTarget() {
        #expect(GoalRules.progressText(GoalProgress(kind: .hours, value: 150, target: 300)) == "2.5 / 5 h")
        #expect(GoalRules.progressText(GoalProgress(kind: .hours, value: 0, target: 300)) == "0 / 5 h")
        #expect(GoalRules.progressText(GoalProgress(kind: .hours, value: 420, target: 300)) == "7 / 5 h")   // over target is fine
    }

    @Test func progressTextIsSessionsOverTarget() {
        #expect(GoalRules.progressText(GoalProgress(kind: .sessions, value: 3, target: 5)) == "3 / 5 sessions")
        #expect(GoalRules.progressText(GoalProgress(kind: .sessions, value: 0, target: 1)) == "0 / 1 session")
        #expect(GoalRules.progressText(GoalProgress(kind: .sessions, value: 7, target: 5)) == "7 / 5 sessions")
    }

    @Test func targetTextIsPerWeek() {
        #expect(GoalRules.targetText(.hours, 300) == "5 h / week")
        #expect(GoalRules.targetText(.hours, 150) == "2.5 h / week")
        #expect(GoalRules.targetText(.sessions, 3) == "3 sessions / week")
        #expect(GoalRules.targetText(.sessions, 1) == "1 session / week")
    }

    @Test func theKindsHaveShortNames() {
        #expect(GoalRules.kindName(.hours) == "Hours")
        #expect(GoalRules.kindName(.sessions) == "Sessions")
    }

    @Test func theBarFillsUpToTheTargetAndStopsAtFull() {
        #expect(abs(GoalRules.bar(value: 150, target: 300) - 0.5) < 1e-9)
        #expect(GoalRules.bar(value: 0, target: 300) == 0)
        #expect(GoalRules.bar(value: 360, target: 300) == 1)
        #expect(GoalRules.bar(value: 10, target: 0) == 0)
        #expect(GoalRules.bar(value: -5, target: 300) == 0)
        #expect(abs(GoalRules.bar(value: 2, target: 5) - 0.4) < 1e-9)
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
        #expect(GoalRules.stepTarget(300, kind: .hours, up: true) == 330)
        #expect(GoalRules.stepTarget(300, kind: .hours, up: false) == 270)
        #expect(GoalRules.stepTarget(GoalRules.targetStep, kind: .hours, up: false) == GoalRules.targetStep)   // never below half an hour
        #expect(GoalRules.stepTarget(GoalRules.maxTarget, kind: .hours, up: true) == GoalRules.maxTarget)
        #expect(GoalRules.defaultTarget == 300)
    }

    @Test func theSessionStepperMovesByOne() {
        #expect(GoalRules.stepTarget(3, kind: .sessions, up: true) == 4)
        #expect(GoalRules.stepTarget(3, kind: .sessions, up: false) == 2)
        #expect(GoalRules.stepTarget(1, kind: .sessions, up: false) == 1)
        #expect(GoalRules.stepTarget(99, kind: .sessions, up: true) == 99)
    }

    @Test func aGoalRowReadsAsOneSentenceForVoiceOver() {
        #expect(GoalRules.accessibilityText(title: "Read", GoalProgress(kind: .hours, value: 150, target: 300)) == "Read, 2.5 / 5 h")
        #expect(GoalRules.accessibilityText(title: "Gym", GoalProgress(kind: .sessions, value: 1, target: 3)) == "Gym, 1 / 3 sessions")
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

/// Drop a goal, the tally goes up (PLAN: goals panel).
@MainActor
struct GoalDropFlowTests {
    func makeStore() throws -> AppStore { AppStore(repos: Repos(db: try Database.inMemory())) }

    // 2026-10-05 is a Monday.
    let monday = DayKey("2026-10-05")
    let wednesday = DayKey("2026-10-07")
    let nextMonday = DayKey("2026-10-12")

    private func week(_ s: AppStore, _ id: String) -> GoalProgress {
        s.goalProgress(id, weekOf: wednesday, sundayFirst: false)
    }

    @Test func dropResizeAddAndNextWeek() throws {
        let s = try makeStore()
        let g = try #require(s.addGoal(title: "Read"))

        // First drop: one hour by default. It counts at once.
        s.dropGoalOnPlanner(raw: DragPayload.goal(g.id), day: monday, minute: 600)
        #expect(week(s, g.id) == GoalProgress(kind: .hours, value: 60, target: 300))

        // A second block, made longer, the same week. The goal is still there.
        s.dropGoalOnPlanner(raw: DragPayload.goal(g.id), day: wednesday, minute: 840)
        let second = try #require(s.selection.first)
        s.setDuration(blockIds: [second], minutes: 240)
        #expect(week(s, g.id) == GoalProgress(kind: .hours, value: 300, target: 300))
        #expect(s.goals().map(\.id) == [g.id])

        // Past the target is fine.
        s.dropGoalOnPlanner(raw: DragPayload.goal(g.id), day: wednesday, minute: 600)
        #expect(week(s, g.id).value == 360)

        // A block next week does not count this week.
        s.dropGoalOnPlanner(raw: DragPayload.goal(g.id), day: nextMonday, minute: 600)
        #expect(week(s, g.id).value == 360)
        #expect(s.goalProgress(g.id, weekOf: nextMonday, sundayFirst: false).value == 60)
    }

    @Test func aSessionGoalCountsEachDrop() throws {
        let s = try makeStore()
        let g = try #require(s.addGoal(title: "Gym", kind: .sessions, target: 3))
        s.dropGoalOnPlanner(raw: DragPayload.goal(g.id), day: monday, minute: 480)
        let id = try #require(s.selection.first)
        s.setDuration(blockIds: [id], minutes: 90)
        #expect(week(s, g.id) == GoalProgress(kind: .sessions, value: 1, target: 3))
        s.dropGoalOnPlanner(raw: DragPayload.goal(g.id), day: wednesday, minute: 480)
        #expect(week(s, g.id).value == 2)
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
