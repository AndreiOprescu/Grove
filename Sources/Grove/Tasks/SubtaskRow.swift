import SwiftUI
import GroveCore

/// One subtask in the task panel. Collapsed: check box, name, duration chip, chevron.
/// Open: also a description, a duration menu and a delete button.
/// The name saves on Return and when the field loses the keyboard. The description saves after a short pause
/// and on blur; one burst of typing is one undo step (see `AppStore.setNotes`).
struct SubtaskRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    let sub: TaskItem
    let expanded: Bool
    let toggleExpanded: () -> Void

    @State private var title: String
    @State private var notes: String
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var titleFocus: Bool
    @FocusState private var notesFocus: Bool

    init(sub: TaskItem, expanded: Bool, toggleExpanded: @escaping () -> Void) {
        self.sub = sub
        self.expanded = expanded
        self.toggleExpanded = toggleExpanded
        _title = State(initialValue: sub.title)
        _notes = State(initialValue: sub.notes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button { store.toggleDone(taskId: sub.id) } label: { CheckBox(isOn: sub.isDone, size: 14) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(sub.isDone ? "Mark \(sub.title) as not done" : "Mark \(sub.title) as done")
                TextField("Name", text: $title)
                    .textFieldStyle(.plain)
                    .strikethrough(sub.isDone)
                    .foregroundStyle(sub.isDone ? theme.muted : theme.ink)
                    .focused($titleFocus)
                    .onSubmit { commitTitle() }
                    .onChange(of: titleFocus) { _, now in if !now { commitTitle() } }
                if !expanded, let chip = SubtaskRules.chip(sub.estimateMin) {
                    Text(chip)
                        .font(theme.body(11, weight: .medium))
                        .foregroundStyle(theme.accent2)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .chipBackground(theme.accent2)
                }
                Button(action: toggleExpanded) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain).foregroundStyle(theme.muted)
                .help(expanded ? "Hide the description and length" : "Show the description and length")
                .accessibilityLabel(expanded ? "Hide details of \(sub.title)" : "Show details of \(sub.title)")
            }
            if expanded { details }
        }
        .font(theme.body(12))
        .onChange(of: sub.title) { _, new in if !titleFocus { title = new } }
        .onChange(of: sub.notes) { _, new in if !notesFocus, saveTask == nil { notes = new } }
        .onDisappear {
            commitTitle()
            saveNotes()
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Description", text: $notes, axis: .vertical)
                .textFieldStyle(.plain)
                .font(theme.body(12))
                .lineLimit(2...6)
                .focused($notesFocus)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.surface2))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(notesFocus ? theme.accent : theme.line, lineWidth: 1))
                .onChange(of: notes) { _, _ in scheduleNotesSave() }
                .onChange(of: notesFocus) { _, now in
                    guard !now else { return }
                    saveNotes()
                    if let t = store.task(sub.id) { notes = t.notes }   // the saved text can have link ids added
                }
            HStack(spacing: 8) {
                Text("Takes").foregroundStyle(theme.muted)
                Menu {
                    ForEach(SubtaskRules.durations(including: sub.estimateMin), id: \.self) { m in
                        Button {
                            store.editTask(sub.id, name: "Set Length") { $0.estimateMin = m }
                        } label: {
                            if m == sub.estimateMin {
                                Label(PlannerMath.duration(m), systemImage: "checkmark")
                            } else {
                                Text(PlannerMath.duration(m))
                            }
                        }
                    }
                } label: {
                    Text(PlannerMath.duration(sub.estimateMin))
                }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("Length of \(sub.title)")
                Spacer(minLength: 0)
                Button { store.deleteTask(sub.id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).foregroundStyle(theme.muted)
                    .help("Delete this subtask").accessibilityLabel("Delete subtask \(sub.title)")
            }
        }
        .padding(.leading, 22)
    }

    // MARK: Saving

    private func commitTitle() {
        guard let current = store.task(sub.id) else { return }
        if let name = SubtaskRules.renamed(title, from: current.title) {
            store.editTask(sub.id, name: "Rename Subtask") { $0.title = name }
            title = name
        } else {
            title = current.title   // empty or unchanged: show what is saved
        }
    }

    private func scheduleNotesSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            saveNotes()
        }
    }

    private func saveNotes() {
        saveTask?.cancel()
        saveTask = nil
        store.setNotes(sub.id, notes)
    }
}
