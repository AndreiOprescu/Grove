import SwiftUI
import GroveCore

/// The notes screen: the list on the left, the chosen note on the right.
struct NotesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        let _ = store.revision
        HStack(alignment: .top, spacing: 16) {
            NotesList()
            Group {
                if let id = store.selectedNoteId, store.note(id) != nil {
                    NoteEditorPane(noteId: id).id(id)
                } else {
                    empty
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 34).padding(.bottom, 16)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "leaf").font(.system(size: 30)).foregroundStyle(theme.accent)
            Text("Pick a note, or start a new one.").font(.system(.title3, design: .serif)).foregroundStyle(theme.ink)
            Button("New note") { store.newNote() }.buttonStyle(.borderedProminent).tint(theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: theme.radius, style: .continuous).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: theme.radius, style: .continuous).strokeBorder(theme.line))
    }
}

/// Search, filters and the notes themselves.
struct NotesList: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        let _ = store.revision
        @Bindable var store = store
        let notes = store.notes(filter: store.noteFilter, query: store.noteQuery)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Notes").font(.system(.title3, design: .serif, weight: .semibold)).foregroundStyle(theme.ink)
                Spacer()
                Button { store.newNote() } label: { Image(systemName: "square.and.pencil") }
                    .buttonStyle(.plain).foregroundStyle(theme.accent).help("New note")
            }
            HStack(spacing: 6) {
                pill("Today", icon: "sun.max") { store.openDailyNote(.today()) }
                pill("This week", icon: "calendar") { store.openWeeklyNote(.today()) }
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.muted)
                TextField("Search notes", text: $store.noteQuery).textFieldStyle(.plain)
                if !store.noteQuery.isEmpty {
                    Button { store.noteQuery = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(theme.muted)
                }
            }
            .font(.system(size: 13, design: .rounded))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.surface2))
            filters
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(notes) { note in row(note) }
                    if notes.isEmpty {
                        Text(store.noteQuery.isEmpty ? "No notes here yet." : "Nothing matches.")
                            .font(.system(size: 12, design: .rounded)).foregroundStyle(theme.muted).padding(.top, 14)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: theme.radius, style: .continuous).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: theme.radius, style: .continuous).strokeBorder(theme.line))
    }

    // MARK: Pieces

    private func pill(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .medium, design: .rounded))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(theme.accent.opacity(0.14)))
                .foregroundStyle(theme.accent)
        }
        .buttonStyle(.plain)
    }

    private var filters: some View {
        let tags = store.allNoteTags()
        let all: [(String, NoteFilter)] = [("All", .all), ("Daily", .daily), ("Weekly", .weekly), ("Pinned", .pinned)]
            + tags.map { ("#\($0)", NoteFilter.tag($0)) }
        return FlowLayout(spacing: 5) {
            ForEach(all, id: \.0) { name, filter in
                let on = store.noteFilter == filter
                Button { store.noteFilter = filter } label: {
                    Text(name).font(.system(size: 11, weight: on ? .semibold : .regular, design: .rounded))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(on ? theme.accent : theme.surface2))
                        .foregroundStyle(on ? theme.surface : theme.muted)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func row(_ note: Note) -> some View {
        let selected = store.selectedNoteId == note.id
        let preview = NotesRules.preview(note.body)
        return Button { store.openNote(note.id) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: icon(note)).font(.system(size: 10)).foregroundStyle(theme.accent)
                    Text(note.title).font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(1)
                    Spacer(minLength: 0)
                    if note.pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(theme.accent2) }
                }
                if !preview.isEmpty {
                    Text(preview).font(.system(size: 11.5, design: .rounded)).foregroundStyle(theme.muted).lineLimit(2)
                }
                Text(TaskFormat.dayLabel(DayKey(String(note.updatedAt.prefix(10)))))
                    .font(.system(size: 10.5, design: .rounded)).foregroundStyle(theme.muted.opacity(0.8))
            }
            .foregroundStyle(theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(selected ? theme.accent.opacity(0.16) : theme.surface2.opacity(0.6)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(note.pinned ? "Unpin" : "Pin") { store.togglePin(note.id) }
            Button("Duplicate") { store.duplicateNote(note.id) }
            Divider()
            Button("Delete", role: .destructive) { store.deleteNote(note.id) }
        }
    }

    private func icon(_ note: Note) -> String {
        switch note.kind {
        case .daily: "sun.max"
        case .weekly: "calendar"
        case .note: "note.text"
        }
    }
}
