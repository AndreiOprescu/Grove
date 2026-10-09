import Testing
import Foundation
import GroveCore
@testable import Grove

/// The end-of-day card in the store (PLAN §5.1.7).
@MainActor
struct RollOverStoreTests {
    private let today = DayKey("2026-10-05")
    private var yesterday: DayKey { today.adding(days: -1) }

    private func makeStore() throws -> AppStore {
        let s = AppStore(repos: Repos(db: try Database.inMemory()), notifier: FakeNotifier())
        s.clockOverride = WallTime(day: today, minute: 8 * 60)
        return s
    }

    @discardableResult
    private func plan(_ s: AppStore, _ title: String, minute: Int = 540) throws -> (task: TaskItem, block: EventItem) {
        let t = TaskItem(title: title, bucket: .day, planDate: yesterday)
        try s.repos.tasks.save(t)
        let b = EventItem(title: title, start: WallTime(day: yesterday, minute: minute), end: WallTime(day: yesterday, minute: minute + 60),
                          kind: .block, taskId: t.id)
        try s.repos.events.save(b)
        return (t, b)
    }

    @Test func theCardListsOpenBlocksFromYesterday() throws {
        let s = try makeStore()
        try plan(s, "Write report")
        #expect(s.rollOverItems().map(\.task.title) == ["Write report"])
    }

    @Test func noBlocksYesterdayMeansNoCard() throws {
        let s = try makeStore()
        #expect(s.rollOverItems().isEmpty)
    }

    @Test func moveSendsTheTasksToTodayAndTakesTheBlocksAway() throws {
        let s = try makeStore()
        let p = try plan(s, "Write report")
        s.moveRollOver()
        let t = try #require(s.task(p.task.id))
        #expect(t.bucket == .day)
        #expect(t.planDate == today)
        #expect(s.blocks(ofTask: p.task.id).isEmpty)          // it is a sticky note now
        #expect(s.rollOverItems().isEmpty)
    }

    @Test func moveLeavesTheTaskNoBlockAtAll() throws {
        let s = try makeStore()
        let p = try plan(s, "Write report")
        // A second block of the same task, on another day, goes too.
        try s.repos.events.save(s.blockEvent(for: p.task, day: today.adding(days: 2), start: 600, end: 660))
        s.moveRollOver()
        #expect(s.blocks(ofTask: p.task.id).isEmpty)
        #expect(s.task(p.task.id)?.planDate == today)
        s.undo()
        #expect(s.blocks(ofTask: p.task.id).count == 2)
    }

    @Test func moveIsOneUndoStep() throws {
        let s = try makeStore()
        let p = try plan(s, "A")
        try plan(s, "B", minute: 700)
        s.moveRollOver()
        #expect(s.undoName == "Move to Today")
        s.undo()
        #expect(s.task(p.task.id)?.planDate == yesterday)
        #expect(s.blocks(ofTask: p.task.id).count == 1)
        #expect(try s.repos.tasks.all().count == 2)
    }

    @Test func leaveChangesNothingAndHidesTheCard() throws {
        let s = try makeStore()
        let p = try plan(s, "Write report")
        s.leaveRollOver()
        #expect(s.task(p.task.id)?.planDate == yesterday)
        #expect(s.blocks(ofTask: p.task.id).count == 1)
        #expect(s.rollOverItems().isEmpty)
        #expect(s.undoName == nil)
    }

    @Test func theCardStaysHiddenForTheRestOfTheDay() throws {
        let s = try makeStore()
        try plan(s, "Write report")
        s.leaveRollOver()
        try plan(s, "Another one", minute: 800)
        #expect(s.rollOverItems().isEmpty)
    }

    @Test func theCardComesBackOnTheNextDay() throws {
        let s = try makeStore()
        try plan(s, "Write report")
        s.leaveRollOver()
        s.clockOverride = WallTime(day: today.adding(days: 1), minute: 8 * 60)
        // Nothing was planned on the new "yesterday" (today), so there is still nothing to offer.
        #expect(s.rollOverItems().isEmpty)
        try s.repos.tasks.save(TaskItem(id: "T9", title: "Late", bucket: .day, planDate: today))
        try s.repos.events.save(EventItem(title: "Late", start: WallTime(day: today, minute: 600), end: WallTime(day: today, minute: 660),
                                          kind: .block, taskId: "T9"))
        #expect(s.rollOverItems().map(\.task.id) == ["T9"])
    }

    @Test func moveSkipsATaskFinishedSinceTheCardWasShown() throws {
        let s = try makeStore()
        let a = try plan(s, "A")
        let b = try plan(s, "B", minute: 700)
        s.toggleDone(taskId: a.task.id)
        s.moveRollOver()
        #expect(s.task(a.task.id)?.planDate == yesterday)     // done: left where it was
        #expect(s.task(b.task.id)?.planDate == today)
    }
}
