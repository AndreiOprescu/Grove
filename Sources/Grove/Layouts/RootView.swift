import SwiftUI
import GroveCore

/// The window. The screen switch at the top picks what fills it:
/// Today (the Day Spread), the Planner (task list, time grid and task panel), the Calendar and the Notes.
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @AppStorage(LeftPane.storageKey) private var leftPane = ""

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
            case .today:
                DaySpreadView()
            case .planner:
                HStack(spacing: 0) {
                    LeftSlot(place: .planner)   // empty when no panel is open; pushes the grid when one is
                    PlannerView(kind: .week)
                    if let id = store.selectedTaskId {
                        TaskInspector(taskId: id)
                            .padding(.trailing, 16).padding(.top, 34).padding(.bottom, 16)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            case .calendar:
                PlannerView(kind: .month)
            case .notes:
                NotesView()
            case .garden:
                GardenView()
            }
        }
        .overlay(alignment: .top) { ScreenSwitch().padding(.top, 5) }
        .overlay(alignment: .topLeading) { LeftDock().padding(.top, 5).padding(.leading, 84) }   // the window buttons take the first 84 pt
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 6) { PaletteButton(); SettingsButton() }.padding(.top, 5).padding(.trailing, 16)
        }
        .overlay { if store.paletteOpen { CommandPalette().transition(.opacity) } }
        .overlay(alignment: .bottom) { ToastView() }
        .overlay(alignment: .bottomTrailing) {
            if let session = store.focus {
                FocusCard(session: session).padding(16).transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.focus != nil)
        .animation(.easeInOut(duration: 0.2), value: store.selectedTaskId != nil)
        .animation(.easeInOut(duration: 0.2), value: leftPane)
        .animation(.easeOut(duration: 0.12), value: store.paletteOpen)
        .background {
            ZStack {
                theme.bg
                AmbientBackground()
                if theme.gridLines { BackgroundGrid() }
                if theme.paper { PaperTexture() }
            }
            .ignoresSafeArea()
        }
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
