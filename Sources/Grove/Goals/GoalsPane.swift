import SwiftUI
import GroveCore

/// The Goals panel: recurring work with a weekly target of hours or sessions, and no date.
/// Drag a goal into a day to plan a block of it. Every block in the week adds to the goal.
/// The numbers are for the week that holds the selected day, the week the Planner shows.
/// One goal at a time can be open for editing.
struct GoalsPane: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("calendar.weekStartsSunday") private var sundayFirst = false
    @State private var openGoal: String?

    private var motionOn: Bool { MotionRules.isOn(setting: store.motionSetting, reduceMotion: reduceMotion) }

    var body: some View {
        let _ = store.revision
        let day = store.selectedDay
        let week = GoalRules.week(of: day, sundayFirst: sundayFirst)
        let goals = store.goals()
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Goals").themedHeading(theme, 20, weight: .semibold).foregroundStyle(theme.ink)
                Spacer()
                Text(GoalRules.weekLabel(week, today: .today())).font(theme.body(11)).foregroundStyle(theme.muted)
            }
            GoalAddRow()
            if goals.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(goals) { goal in
                            GoalRow(goal: goal, progress: store.goalProgress(goal.id, weekOf: day, sundayFirst: sundayFirst),
                                    isOpen: openGoal == goal.id, onToggle: { toggle(goal.id) })
                        }
                    }
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .panel()
    }

    /// Opens the goal, or closes it when it is the open one. Opening one closes the other.
    private func toggle(_ id: String) {
        withAnimation(motionOn ? .spring(response: 0.3, dampingFraction: 0.85) : nil) {
            openGoal = openGoal == id ? nil : id
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Image(systemName: "target").font(.system(size: 22)).foregroundStyle(theme.accent)
            Text("No goals yet. A goal is something you want to give hours or sessions to each week.")
                .font(theme.body(12)).foregroundStyle(theme.muted).multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One line to add a goal: a name, Hours or Sessions, and the target per week.
/// Return adds it. Leaving the field with a name in it adds it too.
struct GoalAddRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @State private var text = ""
    @State private var kind = GoalKind.hours
    @State private var target = GoalRules.defaultTarget
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").foregroundStyle(theme.accent)
                TextField("Add a goal…", text: $text)
                    .textFieldStyle(.plain)
                    .font(theme.body(13))
                    .focused($focused)
                    .onSubmit { if save() { focused = true } }
                    .onExitCommand { text = ""; focused = false }
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused, InlineTitleRules.onBlur(text: text) == .commit { save() }
                    }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.surface2))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(focused ? theme.accent : theme.line, lineWidth: focused ? 1.5 : 1))
            GoalKindPicker(kind: kind) { kind = $0; target = GoalRules.defaultTarget(for: $0) }
            TargetStepper(kind: kind, value: target) { target = $0 }
                .padding(.horizontal, 4)
        }
    }

    /// Adds the goal and clears the field. The target goes back to the default of the kind for the next one;
    /// the kind stays, so several goals of one kind are quick to add.
    @discardableResult private func save() -> Bool {
        guard store.addGoal(title: text, kind: kind, target: target) != nil else { return false }
        text = ""
        target = GoalRules.defaultTarget(for: kind)
        return true
    }
}
