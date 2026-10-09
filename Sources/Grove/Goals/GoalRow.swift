import SwiftUI
import GroveCore

/// One goal in the panel: colour dot, title, "2.5 / 5 h" or "3 / 5 sessions" and a bar.
/// Click it to open the editor under it; click again to close. Drag it onto a day to plan a block of it.
/// Right-click to edit or delete.
struct GoalRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    let goal: GoalItem
    let progress: GoalProgress
    let isOpen: Bool
    let onToggle: () -> Void

    @State private var confirmDelete = false

    private var tint: Color { theme.color(named: GoalRules.blockColor(of: goal)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary
            if isOpen {
                GoalEditor(goal: goal, onClose: onToggle)
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.surface2))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(isOpen ? theme.accent.opacity(0.6) : .clear))
        .confirmationDialog("Delete “\(goal.title)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Goal", role: .destructive) { store.deleteGoal(goal.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its blocks stay in the planner as plain blocks and no longer count. You can undo this.")
        }
    }

    /// The part that is always there. A click opens or closes the editor; a drag plans a block.
    private var summary: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(tint).frame(width: 10, height: 10).padding(.top, 4)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(goal.title).font(theme.body(13, weight: .semibold)).foregroundStyle(theme.ink).lineLimit(2)
                    Spacer(minLength: 4)
                    Text(GoalRules.progressText(progress))
                        .font(theme.number(11, weight: .semibold)).foregroundStyle(theme.muted)
                        .lineLimit(1).fixedSize()
                }
                GoalBar(fill: GoalRules.bar(value: progress.value, target: progress.target), tint: tint)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .contextMenu {
            Button(isOpen ? "Close Editor" : "Edit…", action: onToggle)
            Divider()
            Button("Delete Goal…", role: .destructive) { confirmDelete = true }
        }
        .draggable(DragPayload.goal(goal.id))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GoalRules.accessibilityText(title: goal.title, progress))
        .accessibilityHint("Click to edit. Drag it into a day to plan time for it")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: isOpen ? "Close editor" : "Edit", onToggle)
        .accessibilityAction(named: "Delete") { confirmDelete = true }
    }
}

/// A thin bar: how much of the week's target is there. Full when the goal is at or over its target.
struct GoalBar: View {
    @Environment(\.theme) private var theme
    let fill: Double
    let tint: Color

    var body: some View {
        Capsule().fill(theme.surface)
            .overlay(alignment: .leading) {
                GeometryReader { g in
                    Capsule().fill(tint).frame(width: g.size.width * fill)
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
    }
}

/// The editor under an open goal row: name, Hours or Sessions, the weekly target and the colour.
/// Each change is saved at once and is one undo step. The name is saved with Return or when the editor closes.
struct GoalEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    private let goalId: String
    private let onClose: () -> Void
    @State private var title: String
    @FocusState private var focused: Bool

    init(goal: GoalItem, onClose: @escaping () -> Void) {
        goalId = goal.id
        self.onClose = onClose
        _title = State(initialValue: goal.title)
    }

    var body: some View {
        let _ = store.revision
        if let goal = store.goal(goalId) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Name", text: $title)
                    .textFieldStyle(.plain).font(theme.body(13)).focused($focused)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(focused ? theme.accent : theme.line))
                    .onSubmit { saveTitle(); onClose() }
                    .onExitCommand { title = goal.title; onClose() }
                    .accessibilityLabel("Goal name")
                GoalKindPicker(kind: goal.kind) { store.updateGoal(goal.id, kind: $0) }
                TargetStepper(kind: goal.kind, value: GoalRules.target(of: goal)) { value in
                    if goal.kind == .hours { store.updateGoal(goal.id, targetMin: value) }
                    else { store.updateGoal(goal.id, targetCount: value) }
                }
                colours(goal)
            }
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
            .buttonStyle(.plain).focusable(false).help("No colour").accessibilityLabel("No colour")
            ForEach(TaskColor.names, id: \.self) { name in
                Button { store.updateGoal(goal.id, color: name) } label: {
                    Circle().fill(TaskPalette.color(named: name) ?? theme.muted).frame(width: 15, height: 15)
                        .overlay(Circle().strokeBorder(theme.ink, lineWidth: goal.color == name ? 2 : 0).padding(-3))
                }
                .buttonStyle(.plain).focusable(false).help(name.capitalized).accessibilityLabel("Colour \(name)")
                .accessibilityAddTraits(goal.color == name ? .isSelected : [])
            }
        }
    }
}

/// Two buttons side by side: Hours or Sessions. They never take the keyboard focus,
/// so a name being typed beside them stays in its field.
struct GoalKindPicker: View {
    @Environment(\.theme) private var theme
    let kind: GoalKind
    let onChange: (GoalKind) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(GoalKind.allCases, id: \.self) { k in
                Button { if k != kind { onChange(k) } } label: {
                    Text(GoalRules.kindName(k)).font(theme.body(11, weight: .semibold))
                        .foregroundStyle(k == kind ? theme.ink : theme.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(k == kind ? theme.surface2 : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(k == .hours ? "Count the hours of the goal's blocks" : "Count the goal's blocks, whatever their length")
                .accessibilityAddTraits(k == kind ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.line))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Goal kind")
    }
}

/// "5 h / week" or "3 sessions / week" with a minus and a plus button.
/// Each click moves half an hour or one session (`GoalRules.stepTarget`).
/// The buttons never take the keyboard focus, so a name being typed beside them stays in its field.
struct TargetStepper: View {
    @Environment(\.theme) private var theme
    let kind: GoalKind
    let value: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(GoalRules.targetText(kind, value)).font(theme.number(12, weight: .semibold)).foregroundStyle(theme.ink)
            Spacer(minLength: 4)
            stepButton("minus", label: kind == .hours ? "Less time" : "Fewer sessions", up: false)
            stepButton("plus", label: kind == .hours ? "More time" : "More sessions", up: true)
        }
        .accessibilityElement(children: .contain)
    }

    private func stepButton(_ symbol: String, label: String, up: Bool) -> some View {
        let next = GoalRules.stepTarget(value, kind: kind, up: up)
        return Button { onChange(next) } label: {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(theme.surface2))
                .overlay(Circle().strokeBorder(theme.line))
                .foregroundStyle(next == value ? theme.muted.opacity(0.5) : theme.ink)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(next == value)
        .help(kind == .hours ? (up ? "Half an hour more per week" : "Half an hour less per week")
                             : (up ? "One more session per week" : "One less session per week"))
        .accessibilityLabel(label)
    }
}
