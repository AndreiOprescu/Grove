import SwiftUI
import GroveCore

/// A short list of notes under the task list. A note can be dragged from here onto a day and time in the planner
/// (PLAN §5.5 item 8). A click opens it.
struct NotesTray: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @AppStorage("tasks.notesOpen") private var open = false

    /// How many notes show. Pinned notes come first, then the newest.
    private let limit = 12

    var body: some View {
        let _ = store.revision
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.easeInOut(duration: 0.18)) { open.toggle() } } label: {
                HStack(spacing: 4) {
                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .bold))
                    Text("Notes").themedHeading(theme, 12, weight: .bold)
                    Spacer()
                }
                .foregroundStyle(theme.muted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Drag a note onto the planner to give it a time")
            if open { list }
        }
        .padding(.top, 8)
        .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
    }

    @ViewBuilder private var list: some View {
        let notes = Array(store.notes().prefix(limit))
        if notes.isEmpty {
            Text("No notes yet.").font(theme.body(12)).foregroundStyle(theme.muted)
        } else {
            ScrollView {
                VStack(spacing: 4) { ForEach(notes) { row($0) } }
            }
            .scrollIndicators(.hidden)
            .frame(height: min(150, CGFloat(notes.count) * 32))   // a row is about 28 high, with 4 between
            Text("Drag a note onto the planner to give it a time.")
                .font(theme.body(10.5)).foregroundStyle(theme.muted)
        }
    }

    private func row(_ note: Note) -> some View {
        HStack(spacing: 6) {
            Image(systemName: note.kind == .daily ? "sun.max" : note.kind == .weekly ? "calendar" : "note.text")
                .font(.system(size: 10)).foregroundStyle(theme.accent)
            Text(note.title.isEmpty ? "Untitled" : note.title)
                .font(theme.body(12.5)).foregroundStyle(theme.ink).lineLimit(1)
            Spacer(minLength: 0)
            if note.pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(theme.accent2) }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.surface2.opacity(0.6)))
        .contentShape(Rectangle())
        .onTapGesture { store.openNote(note.id) }
        .draggable(DragPayload.note(note.id))
    }
}
