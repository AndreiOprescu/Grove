import SwiftUI
import GroveCore

/// The Notes panel on the left of the Today and Planner screens: every note, pinned ones first, then the newest.
/// A note can be dragged from here onto a day and time in the planner (PLAN §5.5 item 8). A click opens it.
struct NotesPane: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        let _ = store.revision
        let notes = store.notes()   // the store lists pinned notes first, then the newest
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Notes").themedHeading(theme, 20, weight: .semibold).foregroundStyle(theme.ink)
                Spacer()
                Text(notes.isEmpty ? "No notes" : "\(notes.count) \(notes.count == 1 ? "note" : "notes")")
                    .font(theme.body(11)).foregroundStyle(theme.muted)
            }
            if notes.isEmpty {
                Text("No notes yet.")
                    .font(theme.body(12)).foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 34)
            } else {
                ScrollView {
                    VStack(spacing: 4) { ForEach(notes) { row($0) } }
                        .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)
                Text("Drag a note onto the planner to give it a time.")
                    .font(theme.body(10.5)).foregroundStyle(theme.muted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .panel()
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
