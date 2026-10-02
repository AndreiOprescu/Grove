import SwiftUI
import GroveCore

/// The window: the task list on the left (it can be hidden) and the planner filling the rest.
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
        }
        .animation(.easeInOut(duration: 0.2), value: tasksOpen)
        .background(theme.bg.ignoresSafeArea())
        .alert("Grove", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
}
