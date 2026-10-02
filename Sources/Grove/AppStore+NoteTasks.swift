import Foundation
import GroveCore

/// Check box lines in notes and the tasks they make (PLAN §5.5 items 1 and 7).
/// A line and its task are tied by the hidden `⟦t:ID⟧` at the end of the line.
extension AppStore {
    /// Where a task made from a line of this note goes when the line names no day.
    func placement(for note: Note) -> TaskPlacement {
        switch (note.kind, note.date) {
        case (.daily, let day?): .day(day)
        case (.weekly, let monday?): .week(monday)
        default: .inbox
        }
    }

    /// The notes field of a task that came from `note`. It is a link back to the note.
    func origin(of note: Note) -> String {
        "From " + ReferenceParser.mention(title: note.title, id: note.id)
    }

    /// Brings the tasks in line with the saved text of a note.
    /// - A box that was ticked or cleared sets the task done or open.
    /// - An open box with words and no mark makes a task, and the mark is added to the line.
    ///   A box with an `@date` is left alone. "Add to planner" makes its task.
    ///   This needs `creating`. Pass it only when the user is done typing, or half-typed words become tasks.
    /// Returns how many tasks it made. The saved text changes when it made some, so show it again.
    @discardableResult
    func syncNoteTasks(_ noteId: String, creating: Bool = true) -> Int {
        guard let saved = note(noteId) else { return 0 }
        for box in NoteParser.checkboxes(in: saved.body) {
            guard let id = box.taskId, let t = task(id), t.isDone != box.checked else { continue }
            toggleDone(taskId: id)
        }
        // Finishing a task can change the text of notes. Read this one again.
        guard creating, let old = note(noteId) else { return 0 }
        let boxes = NoteParser.checkboxes(in: old.body)

        var body = old.body
        var change = Mutation(name: "New Task from Note")
        var made = 0
        for box in boxes where box.taskId == nil && !box.checked {
            // A box with an @date waits for "Add to planner". A task made now would keep the token in its title.
            guard AtDateParser.find(in: box.text) == nil else { continue }
            guard var q = quickAddChange(box.text, default: placement(for: old), notes: origin(of: old)) else { continue }
            // Each task is read from the database before it is saved, so they all get the same sort. Keep their order.
            q.change.tasks[0].after?.sort = q.task.sort + Double(made)
            change.append(q.change)
            body = NoteParser.addingMarker(body, line: box.line, taskId: q.task.id)
            made += 1
        }
        guard made > 0 else { return 0 }
        var marked = old
        marked.body = body
        change.notes.append((old, marked))
        if made > 1 { change.name = "New Tasks from Note" }
        commit(change)
        return made
    }

    /// Makes one task from words in a note (⇧⌘T). Returns its id. The editor writes the line.
    func makeTask(from words: String, inNote noteId: String) -> String? {
        guard let source = note(noteId),
              let made = quickAddChange(words, default: placement(for: source), notes: origin(of: source)) else { return nil }
        var change = made.change
        change.name = "New Task from Note"
        guard commit(change) else { return nil }
        showToast("Task made: \(made.task.title)")
        return made.task.id
    }

    /// A task was finished or reopened, or came back by undo. The notes that hold its line show the same state.
    /// This runs inside the save, so it does not make an undo step of its own: undo changes the task, and the line follows.
    func syncBoxes(of task: TaskItem) throws {
        for n in try repos.notes.withTaskMarker(task.id) {
            var body = n.body
            for box in NoteParser.checkboxes(in: n.body) where box.taskId == task.id && box.checked != task.isDone {
                body = NoteParser.settingChecked(body, line: box.line, to: task.isDone)
            }
            if body != n.body {
                var fixed = n
                fixed.body = body
                try repos.notes.save(fixed, touch: false)
            }
        }
    }
}
