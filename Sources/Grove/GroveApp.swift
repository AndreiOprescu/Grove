import SwiftUI
import GroveCore

@main
struct GroveApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(store)
                .frame(minWidth: 960, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task") { store.requestQuickAdd() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(replacing: .undoRedo) {
                Button(store.undoName.map { "Undo \($0)" } ?? "Undo") { store.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(store.undoName == nil)
                Button(store.redoName.map { "Redo \($0)" } ?? "Redo") { store.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(store.redoName == nil)
            }
        }
    }
}
