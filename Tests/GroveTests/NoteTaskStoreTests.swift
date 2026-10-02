import Testing
import Foundation
import GroveCore
@testable import Grove

/// Check box lines in notes and the tasks they make (PLAN §5.5 items 1 and 7).
@MainActor
struct NoteTaskStoreTests {
    func makeStore() throws -> AppStore { AppStore(repos: Repos(db: try Database.inMemory())) }
    let friday = DayKey("2026-10-02")

    private func body(_ s: AppStore, _ id: String) -> String { s.note(id)?.body ?? "" }

    // MARK: A box makes a task

    @Test func openBoxesMakeTasksInOrderAndGetMarks() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Trip", body: "## Pack\n- [ ] Buy sunscreen\n- [ ] Book taxi")
        #expect(s.syncNoteTasks(n.id) == 2)

        let tasks = try s.repos.tasks.inbox()
        #expect(tasks.map(\.title) == ["Buy sunscreen", "Book taxi"])
        let boxes = NoteParser.checkboxes(in: body(s, n.id))
        #expect(boxes.map(\.taskId) == tasks.map(\.id))
        // The reader sees the same words as before.
        #expect(NoteParser.withoutMarkers(body(s, n.id)) == "## Pack\n- [ ] Buy sunscreen\n- [ ] Book taxi")
    }

    @Test func aSecondSyncMakesNothingNew() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Trip", body: "- [ ] Buy sunscreen")
        #expect(s.syncNoteTasks(n.id) == 1)
        #expect(s.syncNoteTasks(n.id) == 0)
        #expect(try s.repos.tasks.inbox().count == 1)
    }

    @Test func tickedEmptyAndPlainLinesMakeNoTask() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Trip", body: "- [x] Old thing\n- [ ] \n- not a box\nText")
        #expect(s.syncNoteTasks(n.id) == 0)
        #expect(try s.repos.tasks.inbox().isEmpty)
        #expect(body(s, n.id) == "- [x] Old thing\n- [ ] \n- not a box\nText")
    }

    @Test func aDailyNoteMakesTasksForThatDay() throws {
        let s = try makeStore()
        let d = s.dailyNote(for: friday)
        s.setNoteBody(d.id, "## Plan\n- [ ] Write report\n")
        #expect(s.syncNoteTasks(d.id) == 1)
        let t = try #require(try s.repos.tasks.forDay(friday).first)
        #expect(t.title == "Write report" && t.bucket == .day)
    }

    @Test func aWeeklyNoteMakesTasksForThatWeek() throws {
        let s = try makeStore()
        let w = s.weeklyNote(for: friday)
        s.setNoteBody(w.id, "## Goals\n- [ ] Ship the notes screen\n")
        #expect(s.syncNoteTasks(w.id) == 1)
        let t = try #require(try s.repos.tasks.forWeek(DayKey("2026-09-28")).first)
        #expect(t.title == "Ship the notes screen" && t.bucket == .week)
    }

    @Test func theLineIsReadLikeQuickAdd() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Trip", body: "- [ ] Call Sam tomorrow #home")
        s.syncNoteTasks(n.id)
        let tomorrow = DayKey.today().adding(days: 1)
        let t = try #require(try s.repos.tasks.forDay(tomorrow).first)
        #expect(t.title == "Call Sam")
        #expect(s.tagNames(of: t.id) == ["home"])
    }

    @Test func theTaskLinksBackToTheNote() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Trip", body: "- [ ] Buy sunscreen")
        s.syncNoteTasks(n.id)
        let t = try #require(try s.repos.tasks.inbox().first)
        #expect(t.notes == "From [[Trip|\(n.id)]]")
        #expect(s.linkedItems(to: ItemRef(.note, n.id)).map(\.title) == ["Buy sunscreen"])
    }

    @Test func oneUndoRemovesTheTasksAndTheMarks() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Trip", body: "- [ ] One\n- [ ] Two")
        s.syncNoteTasks(n.id)
        #expect(s.undoName == "New Tasks from Note")
        s.undo()
        #expect(try s.repos.tasks.inbox().isEmpty)
        #expect(body(s, n.id) == "- [ ] One\n- [ ] Two")
        s.redo()
        #expect(try s.repos.tasks.inbox().count == 2)
        #expect(NoteParser.checkboxes(in: body(s, n.id)).allSatisfy { $0.taskId != nil })
    }

    @Test func aSyncWithoutCreatingOnlyFollowsTheBoxes() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Trip", body: "- [ ] Buy sunscreen")
        s.syncNoteTasks(n.id)
        let id = try #require(try s.repos.tasks.inbox().first).id
        s.setNoteBody(n.id, NoteParser.settingChecked(body(s, n.id), line: 0, to: true) + "\n- [ ] Half-typed")
        #expect(s.syncNoteTasks(n.id, creating: false) == 0)
        #expect(s.task(id)?.isDone == true)           // the ticked box still finishes its task
        #expect(try s.repos.tasks.all().count == 1)   // the new line waits
        #expect(s.syncNoteTasks(n.id) == 1)
    }

    // MARK: The two stay in step

    @Test func tickingTheBoxFinishesTheTaskAndClearingItReopensIt() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Trip", body: "- [ ] Buy sunscreen")
        s.syncNoteTasks(n.id)
        let id = try #require(try s.repos.tasks.inbox().first).id

        s.setNoteBody(n.id, NoteParser.settingChecked(body(s, n.id), line: 0, to: true))
        s.syncNoteTasks(n.id)
        #expect(s.task(id)?.isDone == true)

        s.setNoteBody(n.id, NoteParser.settingChecked(body(s, n.id), line: 0, to: false))
        s.syncNoteTasks(n.id)
        #expect(s.task(id)?.isDone == false)
    }

    @Test func finishingTheTaskTicksTheBoxAndUndoClearsIt() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Trip", body: "- [ ] Buy sunscreen")
        s.syncNoteTasks(n.id)
        let id = try #require(try s.repos.tasks.inbox().first).id
        let edited = try #require(s.note(n.id)).updatedAt

        s.toggleDone(taskId: id)
        #expect(NoteParser.checkboxes(in: body(s, n.id)).first?.checked == true)
        #expect(s.note(n.id)?.updatedAt == edited)   // the user did not edit the note

        s.undo()
        #expect(NoteParser.checkboxes(in: body(s, n.id)).first?.checked == false)
        s.redo()
        #expect(NoteParser.checkboxes(in: body(s, n.id)).first?.checked == true)
    }

    @Test func theSameTaskInTwoNotesTicksBoth() throws {
        let s = try makeStore()
        let a = s.newNote(title: "A", body: "- [ ] Shared")
        s.syncNoteTasks(a.id)
        let id = try #require(NoteParser.checkboxes(in: body(s, a.id)).first?.taskId)
        let b = s.newNote(title: "B", body: "- [ ] Shared copy \(NoteParser.marker(for: id))")
        s.toggleDone(taskId: id)
        #expect(NoteParser.checkboxes(in: body(s, a.id)).first?.checked == true)
        #expect(NoteParser.checkboxes(in: body(s, b.id)).first?.checked == true)
    }

    @Test func aTaskThatIsBroughtBackByUndoMatchesItsBox() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Trip", body: "- [ ] Buy sunscreen")
        s.syncNoteTasks(n.id)
        let id = try #require(try s.repos.tasks.inbox().first).id
        s.toggleDone(taskId: id)
        s.deleteTask(id)
        s.undo()   // the task is back, finished
        #expect(s.task(id)?.isDone == true)
        #expect(NoteParser.checkboxes(in: body(s, n.id)).first?.checked == true)
    }

    // MARK: Lines and tasks that go away

    @Test func deletingTheLineKeepsTheTask() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Trip", body: "- [ ] Buy sunscreen")
        s.syncNoteTasks(n.id)
        s.setNoteBody(n.id, "")
        #expect(s.syncNoteTasks(n.id) == 0)
        #expect(try s.repos.tasks.inbox().count == 1)
    }

    @Test func deletingTheTaskKeepsTheLineAndMakesNoNewTask() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Trip", body: "- [ ] Buy sunscreen")
        s.syncNoteTasks(n.id)
        let id = try #require(try s.repos.tasks.inbox().first).id
        s.deleteTask(id)
        #expect(s.syncNoteTasks(n.id) == 0)
        #expect(try s.repos.tasks.inbox().isEmpty)
        #expect(NoteParser.checkboxes(in: body(s, n.id)).count == 1)
    }

    @Test func aTitleChangeOnOneSideDoesNotChangeTheOther() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Trip", body: "- [ ] Buy sunscreen")
        s.syncNoteTasks(n.id)
        let id = try #require(try s.repos.tasks.inbox().first).id
        s.setNoteBody(n.id, body(s, n.id).replacingOccurrences(of: "Buy sunscreen", with: "Buy lotion"))
        s.syncNoteTasks(n.id)
        #expect(s.task(id)?.title == "Buy sunscreen")
    }

    // MARK: Make task (⇧⌘T)

    @Test func makeTaskGivesAnIdAndLinksToTheNote() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Trip", body: "Call Sam about the trip")
        let id = try #require(s.makeTask(from: "Call Sam", inNote: n.id))
        let t = try #require(s.task(id))
        #expect(t.title == "Call Sam" && t.bucket == .inbox)
        #expect(t.notes == "From [[Trip|\(n.id)]]")
        #expect(s.linkedItems(to: ItemRef(.note, n.id)).map(\.title) == ["Call Sam"])
        #expect(s.undoName == "New Task from Note")
        s.undo()
        #expect(s.task(id) == nil)
    }

    @Test func makeTaskInADailyNoteLandsOnThatDay() throws {
        let s = try makeStore()
        let d = s.dailyNote(for: friday)
        let id = try #require(s.makeTask(from: "Send the invoice", inNote: d.id))
        #expect(s.task(id)?.planDate == friday)
    }

    @Test func makeTaskWithoutWordsOrNoteMakesNothing() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Trip")
        #expect(s.makeTask(from: "   ", inNote: n.id) == nil)
        #expect(s.makeTask(from: "Call Sam", inNote: "missing") == nil)
        #expect(try s.repos.tasks.inbox().isEmpty)
    }

    @Test func aLineMadeWithMakeTaskIsNotMadeAgainBySync() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Trip", body: "Call Sam about the trip")
        let id = try #require(s.makeTask(from: "Call Sam about the trip", inNote: n.id))
        let target = try #require(MarkdownEdit.taskTarget(in: body(s, n.id), selection: NSRange(location: 0, length: 0)))
        let edit = MarkdownEdit.taskLine(for: target, in: body(s, n.id), taskId: id)
        s.setNoteBody(n.id, (body(s, n.id) as NSString).replacingCharacters(in: edit.range, with: edit.replacement))
        #expect(s.syncNoteTasks(n.id) == 0)
        #expect(try s.repos.tasks.inbox().count == 1)
    }
}
