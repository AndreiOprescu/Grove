import Testing
import Foundation
import GroveCore
@testable import Grove

/// What the notes screen reads from the store, and what it writes.
@MainActor
struct NoteStoreTests {
    func makeStore() throws -> AppStore { AppStore(repos: Repos(db: try Database.inMemory())) }
    let friday = DayKey("2026-10-02")

    // MARK: Daily and weekly notes

    @Test func aDailyNoteIsMadeOnceFromTheTemplate() throws {
        let s = try makeStore()
        let a = s.dailyNote(for: friday)
        let b = s.dailyNote(for: friday)
        #expect(a.id == b.id)
        #expect(a.kind == .daily && a.date == friday)
        #expect(a.title == "Friday, 2 October 2026")
        #expect(a.body == "## Plan\n\n## Notes\n\n## Reflection\n")
        #expect(try s.repos.notes.all().count == 1)
        #expect(s.undoName == nil)   // opening a day is not an edit
    }

    @Test func aWeeklyNoteUsesTheMonday() throws {
        let s = try makeStore()
        let w = s.weeklyNote(for: friday)
        #expect(w.kind == .weekly && w.date == DayKey("2026-09-28"))
        #expect(w.title == "Week 40 · 28 Sep – 4 Oct")
        #expect(s.weeklyNote(for: DayKey("2026-10-04")).id == w.id)   // the Sunday is in the same week
    }

    @Test func openingTheDailyNoteShowsIt() throws {
        let s = try makeStore()
        s.openDailyNote(friday)
        #expect(s.screen == .notes)
        #expect(s.selectedNoteId == s.dailyNote(for: friday).id)
    }

    // MARK: Making, editing, deleting

    @Test func newNotesGetFreshTitlesAndUndoRemovesThem() throws {
        let s = try makeStore()
        let a = s.newNote()
        let b = s.newNote()
        #expect(a.title == "Untitled" && b.title == "Untitled 2")
        #expect(s.selectedNoteId == b.id && s.screen == .notes)
        s.undo()
        #expect(s.note(b.id) == nil && s.note(a.id) != nil)
    }

    @Test func typingMakesOneUndoStep() throws {
        let s = try makeStore()
        let n = s.newNote()
        let t0 = Date()
        s.setNoteBody(n.id, "a", now: t0)
        s.setNoteBody(n.id, "ab", now: t0.addingTimeInterval(1))
        s.setNoteBody(n.id, "abc", now: t0.addingTimeInterval(2))
        #expect(s.note(n.id)?.body == "abc")
        s.undo()
        #expect(s.note(n.id)?.body == "")
        s.redo()
        #expect(s.note(n.id)?.body == "abc")
    }

    @Test func savingTheSameTextChangesNothing() throws {
        let s = try makeStore()
        let n = s.newNote()
        s.setNoteBody(n.id, "", now: Date())
        #expect(s.undoName == "New Note")
    }

    @Test func renamingANote() throws {
        let s = try makeStore()
        let n = s.newNote()
        s.renameNote(n.id, to: "  Trip ideas ")
        #expect(s.note(n.id)?.title == "Trip ideas")
        s.renameNote(n.id, to: "   ")   // an empty name is refused
        #expect(s.note(n.id)?.title == "Trip ideas")
        s.undo()
        #expect(s.note(n.id)?.title == "Untitled")
    }

    @Test func aDailyNoteKeepsItsTitle() throws {
        let s = try makeStore()
        let d = s.dailyNote(for: friday)
        s.renameNote(d.id, to: "Other")
        #expect(s.note(d.id)?.title == "Friday, 2 October 2026")
    }

    @Test func renamingUpdatesTheMentions() throws {
        let s = try makeStore()
        let a = s.newNote(title: "Alpha")
        let b = s.newNote(title: "Beta")
        s.setNoteBody(b.id, "See [[Alpha]]", now: Date())
        s.renameNote(a.id, to: "Gamma")
        #expect(s.note(b.id)?.body == "See [[Gamma|\(a.id)]]")
    }

    @Test func deletingANoteCanBeUndone() throws {
        let s = try makeStore()
        let a = s.newNote(title: "Alpha")
        let b = s.newNote(title: "Beta")
        s.setNoteBody(a.id, "See [[Beta]]", now: Date())
        #expect(s.linkedItems(to: ItemRef(.note, b.id)).map(\.title) == ["Alpha"])
        s.deleteNote(b.id)
        #expect(s.note(b.id) == nil)
        #expect(s.selectedNoteId != b.id)
        s.undo()
        #expect(s.note(b.id)?.title == "Beta")
        #expect(s.linkedItems(to: ItemRef(.note, b.id)).map(\.title) == ["Alpha"])   // the link is back
    }

    // MARK: Links and tags

    @Test func aBodyMakesLinksAndTags() throws {
        let s = try makeStore()
        let a = s.newNote(title: "Alpha")
        let b = s.newNote(title: "Beta")
        s.setNoteBody(a.id, "Call about [[Beta]] #work #Plan", now: Date())
        #expect(s.note(a.id)?.body == "Call about [[Beta|\(b.id)]] #work #Plan")
        #expect(s.noteTags(a.id) == ["Plan", "work"])
        let back = s.linkedItems(to: ItemRef(.note, b.id))
        #expect(back.count == 1 && back[0].ref == ItemRef(.note, a.id) && back[0].title == "Alpha")
    }

    @Test func undoBringsTheOldTagsBack() throws {
        let s = try makeStore()
        let n = s.newNote()
        s.setNoteBody(n.id, "#one", now: Date().addingTimeInterval(-300))
        s.setNoteBody(n.id, "#two", now: Date())
        #expect(s.noteTags(n.id) == ["two"])
        s.undo()
        #expect(s.noteTags(n.id) == ["one"])
    }

    @Test func aTaskThatMentionsANoteIsABacklink() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Trip")
        let t = TaskItem(title: "Book flights", bucket: .inbox)
        try s.repos.tasks.save(t)
        s.setNotes(t.id, "Details are in [[Trip]]")
        let items = s.linkedItems(to: ItemRef(.note, n.id))
        #expect(items.map(\.title) == ["Book flights"] && items[0].ref.type == .task)
    }

    // MARK: The list

    @Test func pinnedNotesComeFirst() throws {
        let s = try makeStore()
        let a = s.newNote(title: "A")
        _ = s.newNote(title: "B")
        s.togglePin(a.id)
        #expect(s.notes().first?.id == a.id)
        #expect(s.notes(filter: .pinned).map(\.title) == ["A"])
        s.undo()
        #expect(s.notes(filter: .pinned).isEmpty)
    }

    @Test func theListSearchesTitlesAndText() throws {
        let s = try makeStore()
        let a = s.newNote(title: "Groceries")
        _ = s.newNote(title: "Other")
        s.setNoteBody(a.id, "buy oat milk", now: Date())
        #expect(s.notes(query: "milk").map(\.title) == ["Groceries"])
        #expect(s.notes(query: "other").map(\.title) == ["Other"])
        #expect(s.notes(query: "nothing here").isEmpty)
    }

    @Test func filteringByTag() throws {
        let s = try makeStore()
        let a = s.newNote(title: "A")
        _ = s.newNote(title: "B")
        s.setNoteBody(a.id, "#home", now: Date())
        #expect(s.notes(filter: .tag("Home")).map(\.title) == ["A"])
        #expect(s.allNoteTags() == ["home"])
    }

    @Test func duplicatingANote() throws {
        let s = try makeStore()
        let a = s.newNote(title: "Ideas")
        s.setNoteBody(a.id, "- [ ] one ⟦t:T1⟧", now: Date())
        s.togglePin(a.id)
        s.duplicateNote(a.id)
        let copy = try #require(s.selectedNoteId.flatMap { s.note($0) })
        #expect(copy.id != a.id && copy.title == "Ideas copy" && copy.kind == .note && !copy.pinned)
        #expect(copy.body == "- [ ] one")   // the hidden task marker stays with the first note
    }

    // MARK: Opening

    @Test func aMentionOfANoteOpensTheNotesScreen() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Trip")
        s.screen = .planner
        s.selectedNoteId = nil
        s.open(ItemRef(.note, n.id))
        #expect(s.screen == .notes && s.selectedNoteId == n.id)
    }

    @Test func openingANoteTheListHidesResetsTheFilter() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Trip")
        s.noteFilter = .pinned
        s.openNote(n.id)
        #expect(s.noteFilter == .all)
    }
}
