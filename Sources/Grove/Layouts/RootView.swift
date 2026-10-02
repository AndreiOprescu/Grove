import SwiftUI
import GroveCore

/// The window: the task list on the left (it can be hidden), the planner in the middle and the task inspector
/// on the right while a task is selected.
/// M8 adds the sidebar, the other screens and the other layouts.
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @AppStorage("shell.tasksOpen") private var tasksOpen = true

    /// The question went away without a button (a click outside). Wait one beat: when a button was pressed
    /// its action may not have run yet, and it must win.
    private func dismissedQuestion(_ shown: Bool) {
        guard !shown, let id = store.recurringPrompt?.id else { return }
        DispatchQueue.main.async {
            if store.recurringPrompt?.id == id { store.cancelRecurring() }
        }
    }

    var body: some View {
        Group {
            switch store.screen {
            case .planner:
                HStack(spacing: 0) {
                    if tasksOpen {
                        TasksPane()
                            .padding(.leading, 16).padding(.top, 34).padding(.bottom, 16)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    PlannerView()
                    if let id = store.selectedTaskId {
                        TaskInspector(taskId: id)
                            .padding(.trailing, 16).padding(.top, 34).padding(.bottom, 16)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            case .notes:
                NotesView()
            }
        }
        .overlay(alignment: .top) { ScreenSwitch().padding(.top, 5) }
        .overlay(alignment: .bottom) { ToastView() }
        .animation(.easeInOut(duration: 0.2), value: store.selectedTaskId != nil)
        .animation(.easeInOut(duration: 0.2), value: tasksOpen)
        .background(theme.bg.ignoresSafeArea())
        .confirmationDialog(
            store.recurringPrompt.map { "\($0.verb) a repeating event" } ?? "",
            isPresented: Binding(get: { store.recurringPrompt != nil }, set: dismissedQuestion),
            titleVisibility: .visible, presenting: store.recurringPrompt
        ) { prompt in
            Button("This event only") { store.answerRecurring(prompt, .only) }
            Button("All events") { store.answerRecurring(prompt, .all) }
            Button("Cancel", role: .cancel) { store.cancelRecurring() }
        } message: { _ in
            Text("Change only this day, or every day of the series?")
        }
        .alert("Grove", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
}
