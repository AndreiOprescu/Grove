import SwiftUI
import GroveCore

/// One goal in the panel: colour dot, title, "2.5 / 5 h", a bar and, when blocks wait, "+1h planned".
/// Drag the row onto a day to plan an hour of it. Right-click to edit or delete.
struct GoalRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    let goal: GoalItem
    let progress: (done: Int, planned: Int, target: Int)

    @State private var editing = false
    @State private var confirmDelete = false

    private var tint: Color { theme.color(named: GoalRules.blockColor(of: goal)) }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(tint).frame(width: 10, height: 10).padding(.top, 4)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(goal.title).font(theme.body(13, weight: .semibold)).foregroundStyle(theme.ink).lineLimit(2)
                    Spacer(minLength: 4)
                    Text(GoalRules.progressText(done: progress.done, target: progress.target))
                        .font(theme.number(11, weight: .semibold)).foregroundStyle(theme.muted)
                        .lineLimit(1).fixedSize()
                }
                GoalBar(done: progress.done, planned: progress.planned, target: progress.target, tint: tint)
                if let planned = GoalRules.plannedText(progress.planned) {
                    Text(planned).font(theme.body(10)).foregroundStyle(theme.muted)
                }
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.surface2))
        .contentShape(Rectangle())
        .draggable(DragPayload.goal(goal.id))
        .contextMenu {
            Button("Edit…") { editing = true }
            Divider()
            Button("Delete Goal…", role: .destructive) { confirmDelete = true }
        }
        .popover(isPresented: $editing, arrowEdge: .trailing) { GoalEditor(goal: goal) }
        .confirmationDialog("Delete “\(goal.title)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Goal", role: .destructive) { store.deleteGoal(goal.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its blocks stay in the planner as plain blocks, and the hours they gave no longer count. You can undo this.")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GoalRules.accessibilityText(title: goal.title, done: progress.done,
                                                        planned: progress.planned, target: progress.target))
        .accessibilityHint("Drag it into a day to plan time for it")
        .accessibilityAction(named: "Edit") { editing = true }
        .accessibilityAction(named: "Delete") { confirmDelete = true }
    }
}

/// A thin bar. The solid part is the hours done, the lighter part the hours planned, both against the target.
struct GoalBar: View {
    @Environment(\.theme) private var theme
    let done: Int
    let planned: Int
    let target: Int
    let tint: Color

    var body: some View {
        let parts = GoalRules.bar(done: done, planned: planned, target: target)
        Capsule().fill(theme.surface)
            .overlay(alignment: .leading) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(tint.opacity(0.35))
                            .frame(width: g.size.width * (parts.done + parts.planned))
                        Capsule().fill(tint)
                            .frame(width: g.size.width * parts.done)
                    }
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
    }
}

/// The popover to change a goal: name, hours per week and colour. Each change is saved at once and is one undo step.
/// The name is saved with Return or when the popover closes.
struct GoalEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    private let goalId: String
    @State private var title: String
    @FocusState private var focused: Bool

    init(goal: GoalItem) {
        goalId = goal.id
        _title = State(initialValue: goal.title)
    }

    var body: some View {
        let _ = store.revision
        if let goal = store.goal(goalId) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Edit goal").themedHeading(theme, 14, weight: .semibold).foregroundStyle(theme.ink)
                TextField("Name", text: $title)
                    .textFieldStyle(.plain).font(theme.body(13)).focused($focused)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.surface2))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(focused ? theme.accent : theme.line))
                    .onSubmit { saveTitle(); dismiss() }
                TargetStepper(minutes: goal.targetMin) { store.updateGoal(goal.id, targetMin: $0) }
                colours(goal)
            }
            .padding(14).frame(width: 260)
            .onDisappear { saveTitle() }
        }
    }

    private func saveTitle() {
        if InlineTitleRules.onBlur(text: title, initial: store.goal(goalId)?.title ?? "") == .commit {
            store.updateGoal(goalId, title: title)
        }
    }

    /// None, then the eight task colours. The chosen one has a ring.
    private func colours(_ goal: GoalItem) -> some View {
        HStack(spacing: 6) {
            Button { store.updateGoal(goal.id, color: "") } label: {
                Image(systemName: "circle.slash").font(.system(size: 15))
                    .foregroundStyle(goal.color.isEmpty ? theme.ink : theme.muted)
            }
            .buttonStyle(.plain).help("No colour").accessibilityLabel("No colour")
            ForEach(TaskColor.names, id: \.self) { name in
                Button { store.updateGoal(goal.id, color: name) } label: {
                    Circle().fill(TaskPalette.color(named: name) ?? theme.muted).frame(width: 15, height: 15)
                        .overlay(Circle().strokeBorder(theme.ink, lineWidth: goal.color == name ? 2 : 0).padding(-3))
                }
                .buttonStyle(.plain).help(name.capitalized).accessibilityLabel("Colour \(name)")
                .accessibilityAddTraits(goal.color == name ? .isSelected : [])
            }
        }
    }
}

/// "5 h / week" with a minus and a plus button. Each click moves half an hour (`GoalRules.stepTarget`).
/// The buttons never take the keyboard focus, so a name being typed beside them stays in its field.
struct TargetStepper: View {
    @Environment(\.theme) private var theme
    let minutes: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(GoalRules.targetText(minutes)).font(theme.number(12, weight: .semibold)).foregroundStyle(theme.ink)
            Spacer(minLength: 4)
            stepButton("minus", label: "Less time", up: false)
            stepButton("plus", label: "More time", up: true)
        }
        .accessibilityElement(children: .contain)
    }

    private func stepButton(_ symbol: String, label: String, up: Bool) -> some View {
        let next = GoalRules.stepTarget(minutes, up: up)
        return Button { onChange(next) } label: {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(theme.surface2))
                .overlay(Circle().strokeBorder(theme.line))
                .foregroundStyle(next == minutes ? theme.muted.opacity(0.5) : theme.ink)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(next == minutes)
        .help(up ? "Half an hour more per week" : "Half an hour less per week")
        .accessibilityLabel(label)
    }
}
