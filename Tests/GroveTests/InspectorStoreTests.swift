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
}
