import SwiftUI
import GroveCore

/// The Goals panel: recurring work with a target of hours per week and no date.
/// Drag a goal into a day to plan an hour of it. A block that is marked done adds its hours to the goal.
/// The numbers are for the week that holds the selected day, the week the Planner shows.
struct GoalsPane: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @AppStorage("calendar.weekStartsSunday") private var sundayFirst = false

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
                            GoalRow(goal: goal, progress: store.goalProgress(goal.id, weekOf: day, sundayFirst: sundayFirst))
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

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Image(systemName: "target").font(.system(size: 22)).foregroundStyle(theme.accent)
            Text("No goals yet. A goal is something you want to give hours to each week.")
                .font(theme.body(12)).foregroundStyle(theme.muted).multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One line to add a goal: a name and the hours per week. Return adds it. Leaving the field with a name in it adds it too.
struct GoalAddRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @State private var text = ""
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
            TargetStepper(minutes: target) { target = $0 }
                .padding(.horizontal, 4)
        }
    }

    /// Adds the goal and clears the field. The hours go back to the default for the next one.
    @discardableResult private func save() -> Bool {
        guard store.addGoal(title: text, targetMin: target) != nil else { return false }
        text = ""
        target = GoalRules.defaultTarget
        return true
    }
}
