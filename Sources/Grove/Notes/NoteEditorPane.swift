import SwiftUI
import AppKit
import GroveCore

/// One note: title, text, tags and what links here.
struct NoteEditorPane: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    let noteId: String
    /// A narrow column (the Day Spread): a short header with the mood, no side card and a shorter text box.
    var compact = false

    // What the fields show. The store is only written when the user changes something.
    @State private var title = ""
    @State private var text = ""
    @State private var loadedId: String?
    /// True from the first key typed in the text until the text loses the keyboard.
    @State private var typing = false
    @State private var saveTask: Task<Void, Never>?
    @State private var chipToken = 0
    @FocusState private var titleFocus: Bool

    var body: some View {
        let _ = store.revision
        Group {
            if let note = store.note(noteId) {
                content(note)
            } else {
                Text("This note is gone.").foregroundStyle(theme.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .panel()
        .onAppear { load(noteId) }
        .onChange(of: store.revision) { _, _ in
            if !typing { chipToken += 1 }
            if !typing, !titleFocus, let n = store.note(noteId) {
                if n.body != text { text = n.body }
                if n.title != title { title = n.title }
            }
        }
        .onDisappear { flush(noteId, creating: typing) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in flush(noteId, creating: false) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in flush(noteId, creating: typing) }
    }

    // MARK: Loading and saving

    private func load(_ id: String) {
        guard let n = store.note(id) else { return }
        title = n.title
        text = n.body
        typing = false
        loadedId = id
    }

    /// Writes any unsaved title and text of note `id` now. Then the tasks follow the boxes.
    /// `creating` lets open boxes make tasks. Use it only when the user is done typing, and never for text they only looked at.
    /// It adds hidden marks to the saved text, so the caller shows the saved text again after it.
    private func flush(_ id: String, creating: Bool) {
        saveTask?.cancel()
        saveTask = nil
        guard loadedId == id, let n = store.note(id) else { return }
        if text != n.body { store.setNoteBody(id, text) }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.kind == .note, !name.isEmpty, name != n.title { store.renameNote(id, to: name) }
        store.syncNoteTasks(id, creating: creating)
    }

    private func scheduleSave() {
        let id = noteId
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            guard loadedId == id else { return }
            store.setNoteBody(id, text)
            store.syncNoteTasks(id, creating: false)   // a ticked box finishes its task now. New tasks wait until the user stops typing.
        }
    }

    private func bodyEnded() {
        flush(noteId, creating: true)
        typing = false
        if let n = store.note(noteId), n.body != text { text = n.body }   // the saved text has the ids added
        chipToken += 1
    }

    private func commitTitle() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { title = store.note(noteId)?.title ?? title; return }
        store.renameNote(noteId, to: name)
    }

    // MARK: Content

    private func content(_ note: Note) -> some View {
        ScrollView {
            if compact {
                editorColumn(note)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            } else if let side = sidePanel(note) {
                // Daily and weekly notes: the text on the left, the day or the week on the right.
                HStack(alignment: .top, spacing: 20) {
                    editorColumn(note).frame(maxWidth: 720, alignment: .leading)
                    side
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 28).padding(.vertical, 22)
            } else {
                editorColumn(note)
                    .frame(maxWidth: 780, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 28).padding(.vertical, 22)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func editorColumn(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if compact { compactHeader(note) } else { header(note) }
            tagRow(note)
            RichTextField(text: Binding(get: { text }, set: { text = $0; typing = true; scheduleSave() }),
                          services: store.editorServices(excluding: ItemRef(.note, noteId), noteId: noteId),
                          placeholder: "Write something. Type [[ to link a task, note or event.",
                          minHeight: compact ? 200 : 320, refreshToken: chipToken, onEnd: bodyEnded)
            if note.kind == .daily, let day = note.date { DoneLog(day: day) }
            linked
        }
    }

    /// The card beside a daily note (its day) or a weekly note (its week).
    private func sidePanel(_ note: Note) -> AnyView? {
        guard let date = note.date else { return nil }
        switch note.kind {
        case .daily: return AnyView(DayPanel(day: date))
        case .weekly: return AnyView(WeekReviewPanel(monday: date, hasSummary: DayRules.hasSummary(text), onInsert: { insertSummary(note.id) }))
        case .note: return nil
        }
    }

    private func insertSummary(_ id: String) {
        flush(id, creating: false)
        typing = false
        store.insertWeekSummary(id)
        if let n = store.note(id) { text = n.body }
        chipToken += 1
    }

    private func header(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                if note.kind == .note {
                    TextField("Title", text: $title)
                        .textFieldStyle(.plain)
                        .font(theme.heading(28, weight: .semibold))
                        .foregroundStyle(theme.ink)
                        .focused($titleFocus)
                        .onSubmit(commitTitle)
                } else {
                    Text(note.title).themedHeading(theme, 28, weight: .semibold).foregroundStyle(theme.ink)
                }
                Spacer(minLength: 8)
                if note.kind == .daily { MoodPicker(note: note) }
                Button { store.togglePin(note.id) } label: { Image(systemName: note.pinned ? "pin.fill" : "pin") }
                    .buttonStyle(.plain).foregroundStyle(note.pinned ? theme.accent2 : theme.muted)
                    .help(note.pinned ? "Unpin" : "Pin to the top of the list")
                Menu {
                    Button("Duplicate") { store.duplicateNote(note.id) }
                    Divider()
                    Button("Delete note", role: .destructive) { store.deleteNote(note.id); store.showToast("Note deleted. ⌘Z brings it back.") }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(theme.muted)
            }
            Text(kindLine(note)).font(theme.body(12)).foregroundStyle(theme.muted)
        }
    }

    /// "Today's note", the pin and the menu, then the mood.
    private func compactHeader(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(note.date == .today() ? "Today's note" : "Note · \(TaskFormat.dayLabel(note.date ?? .today()))")
                    .themedHeading(theme, 20, weight: .semibold).foregroundStyle(theme.ink)
                Spacer(minLength: 8)
                Button { store.togglePin(note.id) } label: { Image(systemName: note.pinned ? "pin.fill" : "pin") }
                    .buttonStyle(.plain).foregroundStyle(note.pinned ? theme.accent2 : theme.muted)
                    .help(note.pinned ? "Unpin" : "Pin to the top of the list")
                Button { store.openNote(note.id) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(.plain).foregroundStyle(theme.muted)
                    .help("Open in the Notes screen")
            }
            HStack(spacing: 8) {
                MoodPicker(note: note)
                Spacer(minLength: 0)
            }
        }
    }

    private func kindLine(_ note: Note) -> String {
        let edited = "Edited \(TaskFormat.dayLabel(DayKey(String(note.updatedAt.prefix(10))))), \(note.updatedAt.dropFirst(11).prefix(5))"
        switch note.kind {
        case .daily: return "Daily note · \(edited)"
        case .weekly: return "Weekly note · \(edited)"
        case .note: return edited
        }
    }

    @ViewBuilder private func tagRow(_ note: Note) -> some View {
        let tags = store.noteTags(note.id)
        if !tags.isEmpty {
            FlowLayout(spacing: 5) {
                ForEach(tags, id: \.self) { tag in
                    Button { store.noteFilter = .tag(tag) } label: {
                        Text("#\(tag)").font(theme.body(11))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(theme.surface2)).foregroundStyle(theme.muted)
                    }
                    .buttonStyle(.plain)
                    .help("Show notes with this tag")
                }
            }
        }
    }

    @ViewBuilder private var linked: some View {
        let items = store.linkedItems(to: ItemRef(.note, noteId))
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Linked here").themedHeading(theme, 12, weight: .bold).foregroundStyle(theme.ink)
                ForEach(items) { item in
                    Button { store.open(item.ref) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: icon(item.ref.type)).foregroundStyle(theme.accent)
                            Text(item.title).foregroundStyle(theme.ink).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .font(theme.body(12.5))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 6)
        }
    }

    private func icon(_ type: ItemType) -> String {
        switch type {
        case .task: "checkmark.circle"
        case .note: "note.text"
        case .event: "calendar"
        }
    }
}
