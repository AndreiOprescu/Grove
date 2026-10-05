import Testing
import Foundation
import GroveCore
@testable import Grove

/// The look of a task: the outline from its priority, and its colour (on the list and on the timeline).
@MainActor
struct TaskLookTests {
    private func makeStore() throws -> AppStore { AppStore(repos: Repos(db: try Database.inMemory())) }
    private let day = DayKey("2099-03-04")

    @Test func lowIsGreenMediumIsYellowHighIsRedNoneHasNoBorder() {
        #expect(TaskFormat.priorityTone(0) == nil)
        #expect(TaskFormat.priorityTone(1) == .green)
        #expect(TaskFormat.priorityTone(2) == .yellow)
        #expect(TaskFormat.priorityTone(3) == .red)
        #expect(TaskFormat.priorityTone(7) == nil)
        #expect(TaskFormat.priorityTone(-1) == nil)
    }

    @Test func theBorderIsThick() {
        #expect(TaskFormat.priorityBorderWidth >= 3)
    }

    @Test func theColourNamesHaveAColourEach() {
        let theme = Theme.grove
        #expect(TaskColor.names.count == 8)
        #expect(Set(TaskColor.names.map { theme.color(named: $0).description }).count == 8)
    }

    @Test func settingAColourIsUndoable() throws {
        let s = try makeStore()
        try s.repos.tasks.save(TaskItem(id: "T1", title: "Paint", bucket: .day, planDate: day))
        s.setTaskColor("T1", "purple")
        #expect(s.task("T1")?.color == "purple")
        #expect(s.undoName == "Set Colour")
        s.undo()
        #expect(s.task("T1")?.color == "")
    }

    @Test func aNameThatIsNotOneOfTheEightIsRefused() throws {
        let s = try makeStore()
        try s.repos.tasks.save(TaskItem(id: "T1", title: "Paint"))
        s.setTaskColor("T1", "mauve")
        #expect(s.task("T1")?.color == "")
    }

    @Test func clearingTheColourWorks() throws {
        let s = try makeStore()
        var t = TaskItem(id: "T1", title: "Paint"); t.color = "red"
        try s.repos.tasks.save(t)
        s.setTaskColor("T1", "")
        #expect(s.task("T1")?.color == "")
    }

    @Test func theTimelineBlockOfATaskTakesTheTasksColourAndPriority() throws {
        let s = try makeStore()
        var t = TaskItem(id: "T1", title: "Paint", priority: 3, bucket: .day, planDate: day); t.color = "teal"
        try s.repos.tasks.save(t)
        try s.repos.events.save(EventItem(title: "Paint", start: WallTime(day: day, minute: 600), end: WallTime(day: day, minute: 660),
                                          kind: .block, taskId: "T1", color: "accent"))
        let b = try #require(s.blocks(for: day...day).first)
        #expect(b.color == "teal")
        #expect(b.priority == 3)
    }

    @Test func aTaskWithNoColourKeepsTheColourOfItsBlock() throws {
        let s = try makeStore()
        try s.repos.tasks.save(TaskItem(id: "T1", title: "Paint", bucket: .day, planDate: day))
        try s.repos.events.save(EventItem(title: "Paint", start: WallTime(day: day, minute: 600), end: WallTime(day: day, minute: 660),
                                          kind: .block, taskId: "T1", color: "accent3"))
        let b = try #require(s.blocks(for: day...day).first)
        #expect(b.color == "accent3")
        #expect(b.priority == 0)
    }

    @Test func aPlainEventHasNoPriority() throws {
        let s = try makeStore()
        try s.repos.events.save(EventItem(title: "Lunch", start: WallTime(day: day, minute: 720), end: WallTime(day: day, minute: 780)))
        #expect(s.blocks(for: day...day).first?.priority == 0)
    }
}

/// The workload bar under the timeline title.
struct WorkloadTests {
    @Test func theLabelIsPlannedOverTheLimit() {
        #expect(Workload.label(planned: 390, limit: 540) == "6h 30m/9h")
        #expect(Workload.label(planned: 0, limit: 540) == "0m/9h")
        #expect(Workload.label(planned: 600, limit: 480) == "10h/8h")
    }

    @Test func theBarFillsFromZeroToFull() {
        #expect(Workload.fraction(planned: 0, limit: 540) == 0)
        #expect(Workload.fraction(planned: 270, limit: 540) == 0.5)
        #expect(Workload.fraction(planned: 540, limit: 540) == 1)
        #expect(Workload.fraction(planned: 900, limit: 540) == 1)
        #expect(Workload.fraction(planned: 60, limit: 0) == 1)
    }

    @Test func itTurnsRedOnlyWhenThePlanIsOverTheLimit() {
        #expect(!Workload.isOver(planned: 540, limit: 540))
        #expect(Workload.isOver(planned: 541, limit: 540))
        #expect(!Workload.isOver(planned: 0, limit: 540))
    }
}

/// The Garden screen.
@MainActor
struct GardenScreenTests {
    @Test func theGardenIsTheLastTab() {
        #expect(Screen.allCases.last == .garden)
        #expect(Screen.garden.title == "Garden")
    }

    @Test func theGardenCountsFinishedTasks() throws {
        let s = AppStore(repos: Repos(db: try Database.inMemory()))
        #expect(s.gardenDone() == 0)
        try s.repos.tasks.save(TaskItem(id: "T1", title: "a"))
        s.toggleDone(taskId: "T1")
        #expect(s.gardenDone() == 1)
        s.toggleDone(taskId: "T1")
        #expect(s.gardenDone() == 0)
    }
}
