import Testing
import Foundation
import GroveCore
@testable import Grove

/// The store side of the task inspector: saving a body, and undo of typing.
@MainActor
struct InspectorStoreTests {
    func makeStore() throws -> AppStore { AppStore(repos: Repos(db: try Database.inMemory())) }

    @Test func savingABodyStoresItAndKeepsLinks() throws {
        let s = try makeStore()
        let a = try #require(s.quickAdd("A"))
        let b = try #require(s.quickAdd("B"))
        s.setNotes(a.id, "see [[B]]")
        #expect(s.task(a.id)?.notes == "see [[B|\(b.id)]]")
        #expect(try s.repos.links.backlinks(to: ItemRef(.task, b.id)) == [ItemRef(.task, a.id)])
    }

    @Test func typingInOneBodyIsOneUndoStep() throws {
        let s = try makeStore()
        let a = try #require(s.quickAdd("A"))
        s.setNotes(a.id, "h")
        s.setNotes(a.id, "he")
        s.setNotes(a.id, "hello")
        s.undo()
        #expect(s.task(a.id)?.notes == "")
        s.redo()
        #expect(s.task(a.id)?.notes == "hello")
    }

    @Test func aPauseOfAMinuteStartsANewUndoStep() throws {
        let s = try makeStore()
        let a = try #require(s.quickAdd("A"))
        s.setNotes(a.id, "one", now: Date(timeIntervalSince1970: 1000))
        s.setNotes(a.id, "two", now: Date(timeIntervalSince1970: 1090))
        s.undo()
        #expect(s.task(a.id)?.notes == "one")
    }

    @Test func otherChangesBreakTheMerge() throws {
        let s = try makeStore()
        let a = try #require(s.quickAdd("A"))
        s.setNotes(a.id, "one")
        s.editTask(a.id, name: "Set Priority") { $0.priority = 2 }
        s.setNotes(a.id, "two")
        s.undo()
        #expect(s.task(a.id)?.notes == "one" && s.task(a.id)?.priority == 2)
        s.undo()
        #expect(s.task(a.id)?.priority == 0)
    }

    @Test func bodiesOfDifferentTasksAreNotMerged() throws {
        let s = try makeStore()
        let a = try #require(s.quickAdd("A"))
        let b = try #require(s.quickAdd("B"))
        s.setNotes(a.id, "aaa")
        s.setNotes(b.id, "bbb")
        s.undo()
        #expect(s.task(b.id)?.notes == "" && s.task(a.id)?.notes == "aaa")
    }

    @Test func savingTheSameBodyAgainChangesNothing() throws {
        let s = try makeStore()
        let a = try #require(s.quickAdd("A"))
        s.setNotes(a.id, "same")
        let before = s.undoName
        s.setNotes(a.id, "same")
        s.undo()
        #expect(s.task(a.id)?.notes == "")
        #expect(before == "Edit Notes")
    }

    // MARK: Subtasks

    @Test func addingASubtaskReturnsItAndKeepsTheName() throws {
        let s = try makeStore()
        let a = try #require(s.quickAdd("Trip"))
        let id = try #require(s.addSubtask(to: a.id, title: "  Book hotel "))
        #expect(s.addSubtask(to: a.id, title: "   ") == nil)
        let sub = try #require(s.task(id))
        #expect(sub.title == "Book hotel" && sub.parentId == a.id)
        #expect(s.subtasks(of: a.id).map(\.id) == [id])
    }

    @Test func aSubtaskKeepsItsOwnDescriptionAndDuration() throws {
        let s = try makeStore()
        let a = try #require(s.quickAdd("Trip"))
        let id = try #require(s.addSubtask(to: a.id, title: "Book hotel"))
        s.setNotes(id, "Near the station, with breakfast")
        s.editTask(id, name: "Set Length") { $0.estimateMin = 15 }
        let sub = try #require(s.task(id))
        #expect(sub.notes == "Near the station, with breakfast" && sub.estimateMin == 15)
        #expect(s.task(a.id)?.notes == "" && s.task(a.id)?.estimateMin != 15)
    }

    @Test func doneOnOneSubtaskLeavesTheOthersAndTheParentAlone() throws {
        let s = try makeStore()
        let a = try #require(s.quickAdd("Trip"))
        let one = try #require(s.addSubtask(to: a.id, title: "One"))
        let two = try #require(s.addSubtask(to: a.id, title: "Two"))
        s.toggleDone(taskId: one)
        #expect(s.task(one)?.isDone == true && s.task(one)?.completedAt != nil)
        #expect(s.task(two)?.isDone == false)
        #expect(s.task(a.id)?.isDone == false)
        s.toggleDone(taskId: one)
        #expect(s.task(one)?.isDone == false && s.task(one)?.completedAt == nil)
    }

    @Test func theParentStaysOpenWhenEverySubtaskIsDone() throws {
        let s = try makeStore()
        let a = try #require(s.quickAdd("Trip"))
        let one = try #require(s.addSubtask(to: a.id, title: "One"))
        let two = try #require(s.addSubtask(to: a.id, title: "Two"))
        s.toggleDone(taskId: one)
        s.toggleDone(taskId: two)
        #expect(s.subtasks(of: a.id).allSatisfy { $0.isDone })
        #expect(s.task(a.id)?.isDone == false)
    }

    @Test func undoRevertsASubtaskEdit() throws {
        let s = try makeStore()
        let a = try #require(s.quickAdd("Trip"))
        let id = try #require(s.addSubtask(to: a.id, title: "Book hotel"))
        let before = try #require(s.task(id)).estimateMin
        s.editTask(id, name: "Set Length") { $0.estimateMin = 90 }
        s.undo()
        #expect(s.task(id)?.estimateMin == before)
        s.setNotes(id, "N")
        s.setNotes(id, "Near")
        s.setNotes(id, "Near the station")   // one burst of typing
        s.undo()
        #expect(s.task(id)?.notes == "")
        #expect(s.task(id)?.title == "Book hotel")
    }
}

/// The text rules behind the subtask list in the task panel.
struct SubtaskRulesTests {
    private func sub(_ minutes: Int, done: Bool = false) -> TaskItem {
        var t = TaskItem(title: "s", estimateMin: minutes)
        if done { t.status = .done }
        return t
    }

    @Test func noSubtasksGivesPlainHeader() {
        #expect(SubtaskRules.summary([]) == "")
        #expect(SubtaskRules.header([]) == "Subtasks")
    }

    @Test func headerShowsDoneOfTotalAndTotalTime() {
        let subs = [sub(15, done: true), sub(30, done: true), sub(10), sub(20)]
        #expect(SubtaskRules.summary(subs) == "2/4 \u{B7} 1h 15m")
        #expect(SubtaskRules.header(subs) == "Subtasks  2/4 \u{B7} 1h 15m")
    }

    @Test func noTimeLeavesTheTimeOut() {
        #expect(SubtaskRules.summary([sub(0), sub(0, done: true)]) == "1/2")
    }

    @Test func chipShowsTheDurationAndHidesZero() {
        #expect(SubtaskRules.chip(15) == "15m")
        #expect(SubtaskRules.chip(90) == "1h 30m")
        #expect(SubtaskRules.chip(0) == nil)
    }

    @Test func durationChoicesAreFixedAndKeepAnOddCurrentValue() {
        #expect(SubtaskRules.durations(including: 30) == [5, 10, 15, 30, 45, 60, 90, 120])
        #expect(SubtaskRules.durations(including: 20) == [5, 10, 15, 20, 30, 45, 60, 90, 120])
    }

    @Test func aRenameNeedsANewNonEmptyName() {
        #expect(SubtaskRules.renamed("  ", from: "Book hotel") == nil)
        #expect(SubtaskRules.renamed("Book hotel", from: "Book hotel") == nil)
        #expect(SubtaskRules.renamed(" Book flight ", from: "Book hotel") == "Book flight")
    }
}
