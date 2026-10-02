import SwiftUI
import GroveCore

/// M2 shell: the planner fills the window. M8 adds the sidebar and the other screens.
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        PlannerView()
            .background(theme.bg.ignoresSafeArea())
            .alert("Grove", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("OK") { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
    }
}
