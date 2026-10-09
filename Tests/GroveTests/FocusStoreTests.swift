import Testing
import Foundation
import GroveCore
@testable import Grove

/// Focus mode in the store (PLAN §5.1.7): right-click a block, count down to its end, ask "Mark done?".
@MainActor
struct FocusStoreTests {
    private let future = DayKey("2099-03-04")
    private let past = DayKey("2020-03-04")

    private func makeStore(_ fake: FakeNotifier? = nil) throws -> AppStore {
        AppStore(repos: Repos(db: try Database.inMemory()), notifier: fake ?? FakeNotifier())
    }

    @discardableResult
    private func addBlock(_ s: AppStore, day: DayKey, taskId: String? = "T1") throws -> EventItem {
        if let taskId { try s.repos.tasks.save(TaskItem(id: taskId, title: "Write report", bucket: .day, planDate: day)) }
        let b = EventItem(title: "Write report", start: WallTime(day: day, minute: 600), end: WallTime(day: day, minute: 660),
                          kind: taskId == nil ? .event : .block, taskId: taskId)
        try s.repos.events.save(b)
        return b
    }

    @Test func startingFocusCountsDownToTheEndOfTheBlock() throws {
        let s = try makeStore()
        let b = try addBlock(s, day: future)
        s.startFocus(b)
        let f = try #require(s.focus)
        #expect(f.blockId == b.id)
        #expect(f.taskId == "T1")
        #expect(f.title == "Write report")
        #expect(f.end == FocusRules.endDate(b.end))
        #expect(!f.finished)
    }

    @Test func startingFocusSendsTheEndNotification() async throws {
        let fake = FakeNotifier()
        let s = try makeStore(fake)
        let b = try addBlock(s, day: future)
        s.startFocus(b)
        await s.focusNotify?.value
        let sent = try #require(fake.focusEnds.last)
        #expect(sent.title == "Write report")
        #expect(sent.at == FocusRules.endDate(b.end))
        #expect(sent.taskId == "T1")
    }

    @Test func theNotificationsSwitchCoversTheEndNotification() async throws {
        let fake = FakeNotifier()
        let s = try makeStore(fake)
        s.notifyEnabled = false
        s.startFocus(try addBlock(s, day: future))
        await s.focusNotify?.value
        #expect(s.focus != nil)              // the timer still runs
        #expect(fake.focusEnds.isEmpty)      // but the Mac hears nothing
    }

    @Test func aBlockThatIsOverCannotBeFocused() throws {
        let s = try makeStore()
        let b = try addBlock(s, day: past)
        s.startFocus(b)
        #expect(s.focus == nil)
        #expect(s.toast != nil)
    }

    @Test func stoppingEndsTheSessionAndCancelsTheNotification() async throws {
        let fake = FakeNotifier()
        let s = try makeStore(fake)
        s.startFocus(try addBlock(s, day: future))
        await s.focusNotify?.value
        s.stopFocus()
        await s.focusNotify?.value
        #expect(s.focus == nil)
        #expect(fake.focusCancels >= 1)
    }

    @Test func aSecondSessionReplacesTheFirst() throws {
        let s = try makeStore()
        let a = try addBlock(s, day: future, taskId: "T1")
        let b = try addBlock(s, day: future.adding(days: 1), taskId: "T2")
        s.startFocus(a)
        s.startFocus(b)
        #expect(s.focus?.blockId == b.id)
    }

    @Test func whenTheTimeIsUpTheSessionAsksToMarkDone() throws {
        let s = try makeStore()
        s.startFocus(try addBlock(s, day: future))
        s.focusTimeUp()
        #expect(s.focus?.finished == true)
    }

    @Test func markDoneChecksTheTaskOffAndClosesTheSession() throws {
        let s = try makeStore()
        s.startFocus(try addBlock(s, day: future))
        s.focusTimeUp()
        s.markFocusDone()
        #expect(s.focus == nil)
        #expect(s.task("T1")?.status == .done)
    }

    @Test func notYetClosesTheSessionAndLeavesTheTaskOpen() throws {
        let s = try makeStore()
        s.startFocus(try addBlock(s, day: future))
        s.focusTimeUp()
        s.stopFocus()
        #expect(s.focus == nil)
        #expect(s.task("T1")?.status == .open)
    }

    @Test func markDoneOnAnEventWithNoTaskJustCloses() throws {
        let s = try makeStore()
        s.startFocus(try addBlock(s, day: future, taskId: nil))
        s.markFocusDone()
        #expect(s.focus == nil)
    }

    @Test func theNotificationButtonMarksTheTaskDone() throws {
        let fake = FakeNotifier()
        let s = try makeStore(fake)
        s.startFocus(try addBlock(s, day: future))
        fake.onFocusDone?("T1")
        #expect(s.task("T1")?.status == .done)
        #expect(s.focus == nil)
    }

    @Test func importingDataClosesTheSession() throws {
        let s = try makeStore()
        s.startFocus(try addBlock(s, day: future))
        s.resetAfterReplace()
        #expect(s.focus == nil)
    }
}
