import Foundation
import GroveCore

/// The screens that can fill the window.
enum Screen: String, CaseIterable, Identifiable {
    case planner, notes
    var id: String { rawValue }
}

/// A note, task or event that mentions another item.
struct LinkedItem: Identifiable, Hashable {
    var ref: ItemRef
    var title: String
    var id: String { ref.id }
}

/// Notes: daily and weekly notes, making and editing, the list, and what links where.
extension AppStore {
    // MARK: Reading

    func note(_ id: String) -> Note? { try? repos.notes.get(id) }

    func noteTags(_ id: String) -> [String] { (try? repos.tags.tags(forNote: id)) ?? [] }

    func allNoteTags() -> [String] { (try? repos.tags.noteTagNames()) ?? [] }

    /// The list on the notes screen: pinned first, then the most recently edited.
    func notes(filter: NoteFilter = .all, query: String = "") -> [Note] {
        var list = (try? repos.notes.all()) ?? []
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            let hits = Set(((try? repos.search.search(q, types: [.note], limit: 200)) ?? []).map(\.ref.id))
            list = list.filter { hits.contains($0.id) }
        }
        return NotesRules.filter(list, filter) { [self] in noteTags($0) }
    }

    /// Items whose text mentions `ref`, tasks and events included.
    func linkedItems(to ref: ItemRef) -> [LinkedItem] {
        let from = (try? repos.links.backlinks(to: ref)) ?? []
        return from.compactMap { src in
            (try? repos.refs.resolve(title: "", id: src.id)).map { LinkedItem(ref: src, title: $0.title) }
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: Daily and weekly notes

    /// The note of a day. It is made the first time it is asked for. That is not an edit, so it cannot be undone.
    @discardableResult
    func dailyNote(for day: DayKey) -> Note {
        if let n = try? repos.notes.daily(day) { return n }
        let n = Note(title: NotesRules.dailyTitle(day), body: NotesRules.template(.daily), kind: .daily, date: day)
        try? repos.notes.save(n)
        revision += 1
        return n
    }

    /// The note of the week that holds `day`.
    @discardableResult
    func weeklyNote(for day: DayKey) -> Note {
        let monday = day.weekStart()
        if let n = try? repos.notes.weekly(monday) { return n }
        let n = Note(title: NotesRules.weeklyTitle(monday), body: NotesRules.template(.weekly), kind: .weekly, date: monday)
        try? repos.notes.save(n)
        revision += 1
        return n
    }

    func openDailyNote(_ day: DayKey) { openNote(dailyNote(for: day).id) }

    func openWeeklyNote(_ day: DayKey) { openNote(weeklyNote(for: day).id) }

    /// Shows a note on the notes screen. A filter that would hide it is cleared.
    func openNote(_ id: String) {
        if !notes(filter: noteFilter, query: noteQuery).contains(where: { $0.id == id }) {
            noteFilter = .all
            noteQuery = ""
        }
        selectedNoteId = id
        screen = .notes
    }

    // MARK: Making and changing

    @discardableResult
    func newNote(title: String? = nil, body: String = "") -> Note {
        let existing = Set(((try? repos.notes.all()) ?? []).map(\.title))
        let n = Note(title: title ?? NotesRules.untitled(existing: existing), body: body)
        var m = Mutation(name: "New Note")
        m.notes.append((nil, n))
        commit(m)
        openNote(n.id)
        return n
    }

    /// Saves the text of a note. Many saves in a row while typing make one undo step.
    func setNoteBody(_ id: String, _ text: String, now: Date = Date()) {
        guard let old = note(id), old.body != text else { return }
        var n = old
        n.body = text
        var m = Mutation(name: "Edit Note")
        m.notes.append((old, n))
        m.mergeKey = "note:\(id)"
        m.at = now
        commit(m)
    }

    /// A daily or weekly note keeps its title. An empty name is refused.
    func renameNote(_ id: String, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let old = note(id), old.kind == .note, !clean.isEmpty, clean != old.title else { return }
        var n = old
        n.title = clean
        var m = Mutation(name: "Rename Note")
        m.notes.append((old, n))
        commit(m)
    }

    func togglePin(_ id: String) {
        guard let old = note(id) else { return }
        var n = old
        n.pinned.toggle()
        var m = Mutation(name: n.pinned ? "Pin Note" : "Unpin Note")
        m.notes.append((old, n))
        commit(m)
    }

    /// A plain copy. The hidden task marks stay with the first note, so one task never has two lines.
    func duplicateNote(_ id: String) {
        guard let old = note(id) else { return }
        let existing = Set(((try? repos.notes.all()) ?? []).map(\.title))
        let copy = Note(title: NotesRules.copyTitle(old.title, existing: existing), body: NoteParser.withoutMarkers(old.body))
        var m = Mutation(name: "Duplicate Note")
        m.notes.append((nil, copy))
        commit(m)
        openNote(copy.id)
    }

    func deleteNote(_ id: String) {
        guard let old = note(id) else { return }
        let list = notes(filter: noteFilter, query: noteQuery)
        var m = Mutation(name: "Delete Note")
        m.notes.append((old, nil))
        guard commit(m) else { return }
        if selectedNoteId == id {
            let next = list.firstIndex(where: { $0.id == id }).flatMap { i in list.indices.contains(i + 1) ? list[i + 1] : (i > 0 ? list[i - 1] : nil) }
            selectedNoteId = next?.id
        }
    }
}
