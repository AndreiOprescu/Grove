import SwiftUI
import GroveCore

extension View {
    /// Shows the subtask popover on this goal block while the store's open block has this id.
    func blockSubtaskEditor(anchor: String, edge: Edge = .trailing) -> some View {
        modifier(BlockSubtaskEditorAnchor(anchor: anchor, edge: edge))
    }
}

private struct BlockSubtaskEditorAnchor: ViewModifier {
    @Environment(AppStore.self) private var store
    let anchor: String
    let edge: Edge

    func body(content: Content) -> some View {
        content.popover(
            isPresented: Binding(
                get: { store.editingBlockSubtasks == anchor },
                set: { if !$0, store.editingBlockSubtasks == anchor { store.closeBlockSubtasks() } }),
            arrowEdge: edge
        ) {
            BlockSubtaskEditor(eventId: anchor)
        }
    }
}

/// The subtasks of one goal block: tick, rename, delete, add. Only this block has them,
/// not the other blocks of the goal. Each change saves at once and is one undo step.
struct BlockSubtaskEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    let eventId: String
    @State private var newSubtask = ""
    @FocusState private var addFocused: Bool

    var body: some View {
        let _ = store.revision
        let subs = store.blockSubtasks(of: eventId)
        VStack(alignment: .leading, spacing: 8) {
            Text(store.event(eventId)?.title ?? "Goal block")
                .font(theme.heading(15, weight: .semibold))
            Text(subs.isEmpty ? "Subtasks" : "Subtasks  \(subs.filter(\.isDone).count)/\(subs.count)")
                .font(theme.body(11, weight: .semibold)).foregroundStyle(theme.muted)
            Text("Only this block has these. Other blocks of the goal keep their own.")
                .font(theme.body(11)).foregroundStyle(theme.muted)
            ForEach(subs) { sub in BlockSubtaskRow(sub: sub) }
            HStack(spacing: 8) {
                Image(systemName: "plus").foregroundStyle(theme.muted)
                TextField("Add a subtask", text: $newSubtask)
                    .textFieldStyle(.plain)
                    .focused($addFocused)
                    .onSubmit {
                        if store.addBlockSubtask(to: eventId, title: newSubtask) != nil { newSubtask = "" }
                        addFocused = true
                    }
            }
        }
        .font(theme.body(12))
        .padding(16)
        .frame(width: 280)
        .onAppear { addFocused = subs.isEmpty }
    }
}

/// One subtask in the popover: check box, name, delete. The name saves on Return and when the field loses the keyboard.
private struct BlockSubtaskRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    let sub: BlockSubtaskItem
    @State private var title: String
    @FocusState private var titleFocus: Bool

    init(sub: BlockSubtaskItem) {
        self.sub = sub
        _title = State(initialValue: sub.title)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button { store.toggleBlockSubtask(sub.id) } label: { CheckBox(isOn: sub.isDone, size: 14) }
                .buttonStyle(.plain)
                .accessibilityLabel(sub.isDone ? "Mark \(sub.title) as not done" : "Mark \(sub.title) as done")
            TextField("Name", text: $title)
                .textFieldStyle(.plain)
                .strikethrough(sub.isDone)
                .foregroundStyle(sub.isDone ? theme.muted : theme.ink)
                .focused($titleFocus)
                .onSubmit { commitTitle() }
                .onChange(of: titleFocus) { _, now in if !now { commitTitle() } }
            Button { store.deleteBlockSubtask(sub.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).foregroundStyle(theme.muted)
                .help("Delete this subtask").accessibilityLabel("Delete subtask \(sub.title)")
        }
        .onChange(of: sub.title) { _, new in if !titleFocus { title = new } }
        .onDisappear { commitTitle() }
    }

    private func commitTitle() {
        guard let current = try? store.repos.blockSubtasks.get(sub.id) else { return }
        if SubtaskRules.renamed(title, from: current.title) != nil {
            store.renameBlockSubtask(sub.id, to: title)
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            title = current.title   // empty or unchanged: show what is saved
        }
    }
}
