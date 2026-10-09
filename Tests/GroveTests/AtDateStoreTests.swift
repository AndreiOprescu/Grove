import Testing
import Foundation
import GroveCore
@testable import Grove

/// Sending an `@date` line of a note to the planner (PLAN §5.5 item 2).
@MainActor
struct AtDateStoreTests {
    func makeStore() throws -> AppStore { AppStore(repos: Repos(db: try Database.inMemory())) }
    let tomorrow = DayKey.today().adding(days: 1)

    private func when(_ day: DayKey, _ start: Int?, _ end: Int?) -> String { AtDatePlanner.whenLabel(day: day, start: start, end: end) }

    // MARK: A plain line

    @Test func aPlainLineMakesAnHourLongEventLinkedToTheNote() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Ideas")
        let line = try #require(s.addToPlanner(line: "Call Sam @tomorrow 3pm", inNote: n.id))
        let e = try #require(s.eventItems(in: tomorrow...tomorrow).first)
        #expect(e.title == "Call Sam" && e.kind == .event && !e.allDay)
        #expect(e.start == WallTime(day: tomorrow, minute: 900) && e.end == WallTime(day: tomorrow, minute: 960))
        #expect(e.notes == "[[Ideas|\(n.id)]]")
        #expect(s.linkedItems(to: ItemRef(.note, n.id)).map(\.ref) == [ItemRef(.event, e.id)])
        #expect(line == "[[Call Sam|\(e.id)]] · \(when(tomorrow, 900, 960))")
    }

    @Test func aLengthInTheTokenIsUsed() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Ideas")
        _ = try #require(s.addToPlanner(line: "Workshop @tomorrow 9am for 2h", inNote: n.id))
        let e = try #require(s.eventItems(in: tomorrow...tomorrow).first)
        #expect(e.start.minute == 540 && e.end.minute == 660)
    }

    @Test func aDayWithNoTimeMakesAnAllDayEvent() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Ideas")
        let line = try #require(s.addToPlanner(line: "Holiday @tomorrow", inNote: n.id))
        let e = try #require(s.eventItems(in: tomorrow...tomorrow).first)
        #expect(e.allDay && e.start.day == tomorrow)
        #expect(line == "[[Holiday|\(e.id)]] · \(when(tomorrow, nil, nil))")
    }

    @Test func aListMarkerStaysOnTheLine() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Ideas")
        let line = try #require(s.addToPlanner(line: "- Lunch @tomorrow 12pm", inNote: n.id))
        #expect(line.hasPrefix("- [[Lunch|"))
    }

    // MARK: A check box

    @Test func anOpenBoxMakesATaskWithAHalfHourBlock() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Ideas")
        let line = try #require(s.addToPlanner(line: "- [ ] Write report @tomorrow 9am", inNote: n.id))
        let t = try #require(try s.repos.tasks.all().first)
        #expect(t.title == "Write report" && t.bucket == .day && t.planDate == tomorrow && t.estimateMin == 30)
        #expect(t.notes == "From [[Ideas|\(n.id)]]")
        let block = try #require(s.blocks(ofTask: t.id).first)
        #expect(block.start == WallTime(day: tomorrow, minute: 540) && block.end == WallTime(day: tomorrow, minute: 570))
        #expect(line == "- [ ] Write report · \(when(tomorrow, 540, 570)) ⟦t:\(t.id)⟧")
        #expect(try s.repos.events.all().filter { $0.kind == .event }.isEmpty)   // a task makes no plain event
    }

    @Test func theBlockTakesTheTypedLengthAndTheTaskKeepsIt() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Ideas")
        _ = try #require(s.addToPlanner(line: "- [ ] Write report @tomorrow 9am for 2h", inNote: n.id))
        let t = try #require(try s.repos.tasks.all().first)
        #expect(t.estimateMin == 120)
        #expect(s.blocks(ofTask: t.id).first?.end.minute == 660)
    }

    @Test func aBoxWithADayAndNoTimeIsPlannedForTheDayWithoutABlock() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Ideas")
        let line = try #require(s.addToPlanner(line: "- [ ] Write report @tomorrow", inNote: n.id))
        let t = try #require(try s.repos.tasks.all().first)
        #expect(t.bucket == .day && t.planDate == tomorrow)
        #expect(s.blocks(ofTask: t.id).isEmpty)
        #expect(line == "- [ ] Write report · \(when(tomorrow, nil, nil)) ⟦t:\(t.id)⟧")
    }

    @Test func otherQuickAddWordsStillWorkOnTheBox() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Ideas")
        _ = try #require(s.addToPlanner(line: "- [ ] Write report #work !1 @tomorrow 9am", inNote: n.id))
        let t = try #require(try s.repos.tasks.all().first)
        #expect(t.title == "Write report" && t.priority == 1)
        #expect(t.planDate == tomorrow)   // the @ day wins
        #expect(s.blocks(ofTask: t.id).count == 1)
    }

    @Test func aBoxThatAlreadyHasATaskIsPlannedNotCopied() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Ideas")
        let t = try #require(s.quickAdd("Write report"))
        let line = try #require(s.addToPlanner(line: "- [ ] Write report @tomorrow 9am ⟦t:\(t.id)⟧", inNote: n.id))
        #expect(try s.repos.tasks.all().count == 1)
        let moved = try #require(s.task(t.id))
        #expect(moved.planDate == tomorrow)
        #expect(s.blocks(ofTask: t.id).count == 1)
        #expect(line == "- [ ] Write report · \(when(tomorrow, 540, 570)) ⟦t:\(t.id)⟧")
    }

    @Test func aTaskThatHasABlockMovesIt() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Ideas")
        let t = try #require(s.quickAdd("Write report"))
        s.schedule(taskId: t.id, day: DayKey.today(), start: 600, length: 45)
        _ = try #require(s.addToPlanner(line: "- [ ] Write report @tomorrow 14:00 ⟦t:\(t.id)⟧", inNote: n.id))
        let blocks = s.blocks(ofTask: t.id)
        #expect(blocks.count == 1)
        #expect(blocks[0].start == WallTime(day: tomorrow, minute: 840) && blocks[0].end == WallTime(day: tomorrow, minute: 885))   // keeps its 45 minutes
    }

    @Test func aDayWithNoTimeTakesTheOldBlockAway() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Ideas")
        let t = try #require(s.quickAdd("Write report"))
        s.schedule(taskId: t.id, day: DayKey.today(), start: 600, length: 45)
        _ = try #require(s.addToPlanner(line: "- [ ] Write report @tomorrow ⟦t:\(t.id)⟧", inNote: n.id))
        #expect(s.task(t.id)?.planDate == tomorrow)
        #expect(s.blocks(ofTask: t.id).isEmpty)
    }

    @Test func extraBlocksOfTheTaskAreRemovedWhenOneIsMoved() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Ideas")
        let t = try #require(s.quickAdd("Write report"))
        s.schedule(taskId: t.id, day: DayKey.today(), start: 600, length: 45)
        try s.repos.events.save(s.blockEvent(for: t, day: DayKey.today().adding(days: 5), start: 900, end: 945))
        _ = try #require(s.addToPlanner(line: "- [ ] Write report @tomorrow 14:00 ⟦t:\(t.id)⟧", inNote: n.id))
        #expect(s.blocks(ofTask: t.id).map(\.start) == [WallTime(day: tomorrow, minute: 840)])
    }

    @Test func aMarkWhoseTaskIsGoneMakesANewTask() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Ideas")
        let line = try #require(s.addToPlanner(line: "- [ ] Write report @tomorrow 9am ⟦t:00000000-0000-0000-0000-000000000000⟧", inNote: n.id))
        let t = try #require(try s.repos.tasks.all().first)
        #expect(line.hasSuffix("⟦t:\(t.id)⟧") && !line.contains("0000-0000"))
    }

    // MARK: The day

    @Test func aTimeAloneUsesTheDayOfADailyNote() throws {
        let s = try makeStore()
        let day = DayKey.today().adding(days: 5)
        let d = s.dailyNote(for: day)
        _ = try #require(s.addToPlanner(line: "Standup @10:00", inNote: d.id))
        #expect(s.eventItems(in: day...day).count == 1)
    }

    @Test func aTimeAloneInAPlainNoteUsesToday() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Ideas")
        _ = try #require(s.addToPlanner(line: "Standup @10:00", inNote: n.id))
        let today = DayKey.today()
        #expect(s.eventItems(in: today...today).count == 1)
    }

    // MARK: Refused lines

    @Test func aTickedBoxIsRefusedAndNothingChanges() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Ideas")
        #expect(s.addToPlanner(line: "- [x] Write report @tomorrow 9am", inNote: n.id) == nil)
        #expect(try s.repos.tasks.all().isEmpty && s.eventItems(in: tomorrow...tomorrow).isEmpty)
        #expect(s.undoName == nil || s.undoName == "New Note")
    }

    @Test func aLineWithNoTokenOrNoNoteIsRefused() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Ideas")
        #expect(s.addToPlanner(line: "Call Sam tomorrow", inNote: n.id) == nil)
        #expect(s.addToPlanner(line: "Call Sam @tomorrow 3pm", inNote: "missing") == nil)
        #expect(try s.repos.events.all().isEmpty)
    }

    @Test func theNewLineHasNothingLeftToAdd() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Ideas")
        let line = try #require(s.addToPlanner(line: "- [ ] Write report @tomorrow 9am", inNote: n.id))
        #expect(s.addToPlanner(line: line, inNote: n.id) == nil)
    }

    // MARK: Undo

    @Test func oneUndoTakesBackAnEventAndAllItsLinks() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Ideas")
        _ = try #require(s.addToPlanner(line: "Call Sam @tomorrow 3pm", inNote: n.id))
        #expect(s.undoName == "Add to Planner")
        s.undo()
        #expect(s.eventItems(in: tomorrow...tomorrow).isEmpty)
        #expect(s.linkedItems(to: ItemRef(.note, n.id)).isEmpty)
    }

    @Test func oneUndoTakesBackATaskAndItsBlock() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Ideas")
        _ = try #require(s.addToPlanner(line: "- [ ] Write report @tomorrow 9am", inNote: n.id))
        s.undo()
        #expect(try s.repos.tasks.all().isEmpty)
        #expect(s.eventItems(in: tomorrow...tomorrow).isEmpty)
        s.redo()
        #expect(try s.repos.tasks.all().count == 1)
        #expect(s.eventItems(in: tomorrow...tomorrow).count == 1)
    }
}
