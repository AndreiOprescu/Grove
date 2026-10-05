import Testing
import Foundation
@testable import GroveCore

/// The end-of-day card: open task blocks from yesterday (PLAN §5.1.7).
struct RollOverTests {
    let today = DayKey("2026-10-05")
    var yesterday: DayKey { today.adding(days: -1) }

    func makeRepos() throws -> Repos { Repos(db: try Database.inMemory()) }

    /// An open task planned for `day` with one block at `minute`.
    @discardableResult
    func plan(_ r: Repos, _ title: String, day: DayKey, minute: Int = 540, length: Int = 60,
              status: TaskStatus = .open) throws -> (task: TaskItem, block: EventItem) {
        let t = TaskItem(title: title, status: status, bucket: .day, planDate: day)
        try r.tasks.save(t)
        let b = EventItem(title: title, start: WallTime(day: day, minute: minute), end: WallTime(day: day, minute: minute + length),
                          kind: .block, taskId: t.id)
        try r.events.save(b)
        return (t, b)
    }

    @Test func anOpenTaskWithABlockYesterdayIsOffered() throws {
        let r = try makeRepos()
        let p = try plan(r, "Write report", day: yesterday)
        let items = try RollOver.items(r, today: today)
        #expect(items.map(\.task.id) == [p.task.id])
        #expect(items.first?.blocks.map(\.id) == [p.block.id])
    }

    @Test func doneAndCancelledTasksAreNotOffered() throws {
        let r = try makeRepos()
        try plan(r, "Done one", day: yesterday, status: .done)
        try plan(r, "Dropped one", day: yesterday, status: .cancelled)
        #expect(try RollOver.items(r, today: today).isEmpty)
    }

    @Test func aPlainEventIsNotOffered() throws {
        let r = try makeRepos()
        try r.events.save(EventItem(title: "Dentist", start: WallTime(day: yesterday, minute: 600), end: WallTime(day: yesterday, minute: 660)))
        #expect(try RollOver.items(r, today: today).isEmpty)
    }

    @Test func onlyYesterdayCounts() throws {
        let r = try makeRepos()
        try plan(r, "Two days ago", day: today.adding(days: -2))
        try plan(r, "Today", day: today)
        try plan(r, "Tomorrow", day: today.adding(days: 1))
        #expect(try RollOver.items(r, today: today).isEmpty)
    }

    @Test func twoBlocksOfOneTaskMakeOneItem() throws {
        let r = try makeRepos()
        let p = try plan(r, "Big job", day: yesterday, minute: 540)
        let second = EventItem(title: "Big job", start: WallTime(day: yesterday, minute: 840), end: WallTime(day: yesterday, minute: 900),
                               kind: .block, taskId: p.task.id)
        try r.events.save(second)
        let items = try RollOver.items(r, today: today)
        #expect(items.count == 1)
        #expect(items.first?.blocks.map(\.id) == [p.block.id, second.id])
    }

    @Test func itemsComeInTheOrderOfTheirFirstBlock() throws {
        let r = try makeRepos()
        try plan(r, "Late", day: yesterday, minute: 900)
        try plan(r, "Early", day: yesterday, minute: 480)
        #expect(try RollOver.items(r, today: today).map(\.task.title) == ["Early", "Late"])
    }

    @Test func aBlockOnTheDayBeforeIsFoundByItsStartDay() throws {
        let r = try makeRepos()
        // Ends at midnight: it touches today's first minute but it started yesterday.
        let t = TaskItem(title: "Night owl", bucket: .day, planDate: yesterday)
        try r.tasks.save(t)
        try r.events.save(EventItem(title: "Night owl", start: WallTime(day: yesterday, minute: 1380), end: WallTime(day: today, minute: 0),
                                    kind: .block, taskId: t.id))
        #expect(try RollOver.items(r, today: today).map(\.task.id) == [t.id])
        #expect(try RollOver.items(r, today: today.adding(days: 1)).isEmpty)
    }

    @Test func afterAnAnswerTheCardIsHandledForThatDayOnly() throws {
        let r = try makeRepos()
        #expect(!RollOver.isHandled(r, today: today))
        RollOver.markHandled(r, today: today)
        #expect(RollOver.isHandled(r, today: today))
        #expect(!RollOver.isHandled(r, today: today.adding(days: 1)))
    }
}
