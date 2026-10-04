import Testing
import Foundation
import GroveCore
@testable import Grove

/// The "Now" and "Next" lines in the menu bar window (PLAN §5.7).
struct NowNextTests {
    private let day = DayKey("2026-10-05")

    private func block(_ id: String, _ title: String, _ start: Int, _ end: Int, done: Bool = false, task: Bool = false) -> PlannerBlock {
        PlannerBlock(id: id, title: title, day: day, startMinute: start, endMinute: end,
                     kind: task ? .block : .event, taskId: task ? "T-\(id)" : nil, isDone: done, color: "accent", isRecurring: false)
    }

    @Test func aBlockThatIsRunningIsNow() {
        let r = NowNextRules.make(blocks: [block("a", "Standup", 540, 600)], minute: 560)
        #expect(r.now == "Now: Standup")
    }

    @Test func theStartMinuteCountsAndTheEndMinuteDoesNot() {
        let blocks = [block("a", "Standup", 540, 600)]
        #expect(NowNextRules.make(blocks: blocks, minute: 540).now == "Now: Standup")
        #expect(NowNextRules.make(blocks: blocks, minute: 599).now == "Now: Standup")
        #expect(NowNextRules.make(blocks: blocks, minute: 600).now == "Nothing planned right now")
        #expect(NowNextRules.make(blocks: blocks, minute: 539).now == "Nothing planned right now")
    }

    @Test func theNextBlockShowsHowLongItTakes() {
        let r = NowNextRules.make(blocks: [block("a", "Write report", 600, 660)], minute: 575)
        #expect(r.next == "Next: Write report in 25 min")
    }

    @Test func longWaitsUseHoursAndMinutes() {
        let b = [block("a", "Gym", 1080, 1140)]
        #expect(NowNextRules.make(blocks: b, minute: 1020).next == "Next: Gym in 1 h")
        #expect(NowNextRules.make(blocks: b, minute: 990).next == "Next: Gym in 1 h 30 min")
        #expect(NowNextRules.make(blocks: b, minute: 1079).next == "Next: Gym in 1 min")
    }

    @Test func theNextBlockIsTheEarliestOneThatStartsLater() {
        let blocks = [block("c", "Late", 900, 960), block("b", "Soon", 620, 650), block("a", "Now", 540, 600)]
        let r = NowNextRules.make(blocks: blocks, minute: 560)
        #expect(r.now == "Now: Now")
        #expect(r.next == "Next: Soon in 1 h")
    }

    @Test func whenBlocksOverlapNowIsTheOneThatStartedLast() {
        let blocks = [block("a", "Long", 540, 700), block("b", "Short", 600, 630)]
        #expect(NowNextRules.make(blocks: blocks, minute: 610).now == "Now: Short")
    }

    @Test func nothingElseTodayWhenTheDayIsOver() {
        let r = NowNextRules.make(blocks: [block("a", "Standup", 540, 600)], minute: 700)
        #expect(r.now == "Nothing planned right now")
        #expect(r.next == "Nothing else today")
    }

    @Test func anEmptyDayHasBothQuietLines() {
        let r = NowNextRules.make(blocks: [], minute: 700)
        #expect(r == NowNext(now: "Nothing planned right now", next: "Nothing else today"))
    }

    @Test func aBlockOfADoneTaskIsLeftOut() {
        let blocks = [block("a", "Write report", 540, 600, done: true, task: true), block("b", "Call", 620, 650)]
        let r = NowNextRules.make(blocks: blocks, minute: 560)
        #expect(r.now == "Nothing planned right now")
        #expect(r.next == "Next: Call in 1 h")
    }
}

/// The menu bar window on a real store.
@MainActor
struct MenuBarStoreTests {
    private func makeStore() throws -> AppStore { AppStore(repos: Repos(db: try Database.inMemory())) }

    @Test func quickAddFromTheMenuBarGoesToToday() throws {
        let s = try makeStore()
        let t = try #require(s.menuBarAdd("Buy milk"))
        #expect(t.planDate == .today())
        #expect(t.bucket == .day)
        #expect(try s.repos.tasks.forDay(.today()).map(\.title) == ["Buy milk"])
    }

    @Test func aDateInTheTextStillWins() throws {
        let s = try makeStore()
        let t = try #require(s.menuBarAdd("Dentist tomorrow"))
        #expect(t.planDate == DayKey.today().adding(days: 1))
    }

    @Test func emptyTextAddsNothing() throws {
        let s = try makeStore()
        #expect(s.menuBarAdd("   ") == nil)
        #expect(try s.repos.tasks.all().isEmpty)
    }

    @Test func theLinesCoverTheBlocksOfToday() throws {
        let s = try makeStore()
        let today = DayKey.today()
        try s.repos.events.save(EventItem(id: "E1", title: "Standup", start: WallTime(day: today, minute: 540),
                                          end: WallTime(day: today, minute: 600), color: "accent3"))
        let lines = s.menuBarLines(minute: 560)
        #expect(lines.now == "Now: Standup")
        #expect(lines.next == "Nothing else today")
    }
}
