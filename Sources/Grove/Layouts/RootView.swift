import SwiftUI
import GroveCore

/// The window: the task list on the left (it can be hidden), the planner in the middle and the task inspector
/// on the right while a task is selected.
/// M8 adds the sidebar, the other screens and the other layouts.
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @AppStorage("shell.tasksOpen") private var tasksOpen = true

    var body: some View {
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
        .animation(.easeInOut(duration: 0.2), value: store.selectedTaskId != nil)
        .animation(.easeInOut(duration: 0.2), value: tasksOpen)
        .background(theme.bg.ignoresSafeArea())
        .alert("Grove", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
}
