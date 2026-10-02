import Testing
import Foundation
import GroveCore
@testable import Grove

/// A note dragged from the list onto a day and time in the planner (PLAN §5.5 item 8).
@MainActor
struct NoteDropTests {
    func makeStore() throws -> AppStore { AppStore(repos: Repos(db: try Database.inMemory())) }
    let day = DayKey("2026-10-06")

    @Test func aNoteMakesAHalfHourEventLinkedToIt() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Trip plan")
        let e = try #require(s.addNoteToPlanner(n.id, on: day, at: 600))
        let saved = try #require(s.event(e.id))
        #expect(saved.title == "📝 Trip plan" && saved.kind == .event && !saved.allDay)
        #expect(saved.start == WallTime(day: day, minute: 600) && saved.end == WallTime(day: day, minute: 630))
        #expect(saved.notes == "[[Trip plan|\(n.id)]]")
        #expect(s.linkedItems(to: ItemRef(.note, n.id)).map(\.ref) == [ItemRef(.event, e.id)])
        #expect(s.selection == [e.id])
        #expect(s.undoName == "Add Note to Planner")
    }

    @Test func aDropNearMidnightStaysInsideTheDay() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Late")
        let e = try #require(s.addNoteToPlanner(n.id, on: day, at: 1435))
        #expect(e.end.minute <= 1440 && e.end.minute - e.start.minute == 30 && e.start.day == day && e.end.day == day)
    }

    @Test func aNoteWithNoTitleGetsAName() throws {
        let s = try makeStore()
        let n = s.newNote(title: "  ")
        let e = try #require(s.addNoteToPlanner(n.id, on: day, at: 600))
        #expect(e.title == "📝 Untitled")
    }

    @Test func aMissingNoteMakesNothing() throws {
        let s = try makeStore()
        #expect(s.addNoteToPlanner("missing", on: day, at: 600) == nil)
        #expect(try s.repos.events.all().isEmpty)
    }

    @Test func oneUndoRemovesTheEventAndTheLink() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Trip plan")
        _ = try #require(s.addNoteToPlanner(n.id, on: day, at: 600))
        s.undo()
        #expect(s.eventItems(in: day...day).isEmpty)
        #expect(s.linkedItems(to: ItemRef(.note, n.id)).isEmpty)
        s.redo()
        #expect(s.eventItems(in: day...day).count == 1)
        #expect(s.linkedItems(to: ItemRef(.note, n.id)).count == 1)
    }

    @Test func theSameNoteCanGoOnTwice() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Trip plan")
        _ = s.addNoteToPlanner(n.id, on: day, at: 600)
        _ = s.addNoteToPlanner(n.id, on: day, at: 900)
        #expect(s.eventItems(in: day...day).count == 2)
    }

    @Test func theDragTextHoldsTheNoteIdAndNotATaskId() {
        #expect(DragPayload.noteId(from: DragPayload.note("ABC")) == "ABC")
        #expect(DragPayload.noteId(from: DragPayload.task("ABC")) == nil)
        #expect(DragPayload.noteId(from: "plain text") == nil)
        #expect(DragPayload.note("ABC") != DragPayload.task("ABC"))
    }
}
