import Testing
import Foundation
import GroveCore
@testable import Grove

/// The task list of the Planner screen: every open task. The ones with no day come first, then the rest by day.
struct AllTasksRulesTests {
    private func task(_ title: String, _ bucket: TaskBucket, day: DayKey? = nil, week: DayKey? = nil) -> TaskItem {
        TaskItem(title: title, bucket: bucket, planDate: day, planWeek: week)
    }

    @Test func noDayYetRunsInboxThenWeeksThenSomeday() {
        let input = [task("later A", .someday), task("week 12 Oct", .week, week: "2026-10-12"), task("inbox 1", .inbox),
                     task("week 5 Oct", .week, week: "2026-10-05"), task("inbox 2", .inbox), task("later B", .someday)]
        let split = AllTasksRules.split(input)
        #expect(split.noDay.map(\.title) == ["inbox 1", "inbox 2", "week 5 Oct", "week 12 Oct", "later A", "later B"])
        #expect(split.byDay.isEmpty)
    }

    @Test func tasksOfTheSameWeekKeepTheirListOrder() {
        let input = [task("b", .week, week: "2026-10-05"), task("a", .week, week: "2026-10-05"), task("first", .week, week: "2026-09-28")]
        #expect(AllTasksRules.split(input).noDay.map(\.title) == ["first", "b", "a"])
    }

    @Test func byDayRunsEarliestFirstWithPastDaysOnTop() {
        let input = [task("next week", .day, day: "2026-10-12"), task("today", .day, day: "2026-10-04"),
                     task("last week", .day, day: "2026-09-28")]
        let split = AllTasksRules.split(input)
        #expect(split.byDay.map(\.title) == ["last week", "today", "next week"])
        #expect(split.noDay.isEmpty)
    }

    @Test func tasksOnTheSameDayKeepTheirListOrder() {
        let input = [task("b", .day, day: "2026-10-05"), task("first", .day, day: "2026-10-04"),
                     task("a", .day, day: "2026-10-05"), task("c", .day, day: "2026-10-05")]
        #expect(AllTasksRules.split(input).byDay.map(\.title) == ["first", "b", "a", "c"])
    }

    @Test func aDayTaskWithNoDateHasNoDayYet() {
        let split = AllTasksRules.split([task("odd", .day), task("dated", .day, day: "2026-10-04")])
        #expect(split.noDay.map(\.title) == ["odd"])
        #expect(split.byDay.map(\.title) == ["dated"])
    }
}

@MainActor
@Suite(.serialized)
struct AllTasksStoreTests {
    private func makeStore() throws -> AppStore { AppStore(repos: Repos(db: try Database.inMemory())) }
    private let today = DayKey.today()

    @Test func everyOpenTaskIsInOneOfTheTwoLists() throws {
        let s = try makeStore()
        try s.repos.tasks.save(TaskItem(title: "someday", bucket: .someday, sort: 1))
        try s.repos.tasks.save(TaskItem(title: "tomorrow", bucket: .day, planDate: today.adding(days: 1), sort: 2))
        try s.repos.tasks.save(TaskItem(title: "inbox", sort: 3))
        try s.repos.tasks.save(TaskItem(title: "week", bucket: .week, planWeek: today.weekStart(), sort: 4))
        try s.repos.tasks.save(TaskItem(title: "yesterday", bucket: .day, planDate: today.adding(days: -1), sort: 5))
        let all = s.allOpenTasks()
        #expect(all.noDay.map(\.title) == ["inbox", "week", "someday"])
        #expect(all.byDay.map(\.title) == ["yesterday", "tomorrow"])
    }

    @Test func doneCancelledAndSubtasksAreLeftOut() throws {
        let s = try makeStore()
        let parent = TaskItem(title: "parent", bucket: .day, planDate: today, sort: 1)
        try s.repos.tasks.save(parent)
        try s.repos.tasks.save(TaskItem(title: "sub", parentId: parent.id, sort: 2))
        try s.repos.tasks.save(TaskItem(title: "done", status: .done, sort: 3))
        try s.repos.tasks.save(TaskItem(title: "cancelled", status: .cancelled, bucket: .day, planDate: today, sort: 4))
        let all = s.allOpenTasks()
        #expect(all.noDay.isEmpty)
        #expect(all.byDay.map(\.title) == ["parent"])
    }

    @Test func aTaskCheckedWithLingerStaysInItsPlaceForAMoment() async throws {
        let s = try makeStore()
        let a = try #require(s.quickAdd("Alpha", default: .day(today)))
        let b = try #require(s.quickAdd("Bravo", default: .day(today)))
        let c = try #require(s.quickAdd("Charlie", default: .day(today)))
        s.toggleDone(taskId: b.id, linger: true)
        #expect(s.task(b.id)?.isDone == true)
        #expect(s.allOpenTasks().byDay.map(\.id) == [a.id, b.id, c.id])
        try await Task.sleep(for: .milliseconds(1000))
        #expect(s.allOpenTasks().byDay.map(\.id) == [a.id, c.id])
    }

    @Test func withoutLingerADoneTaskLeavesAtOnce() throws {
        let s = try makeStore()
        let a = try #require(s.quickAdd("Alpha"))
        s.toggleDone(taskId: a.id)
        #expect(s.allOpenTasks().noDay.isEmpty)
    }

    @Test func aLingeringSubtaskDoesNotJoinTheList() throws {
        let s = try makeStore()
        let parent = try #require(s.quickAdd("Parent"))
        s.addSubtask(to: parent.id, title: "Step")
        let sub = try #require(s.subtasks(of: parent.id).first)
        s.toggleDone(taskId: sub.id, linger: true)
        #expect(s.allOpenTasks().noDay.map(\.id) == [parent.id])
    }
}
