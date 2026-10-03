import SwiftUI
import GroveCore

@main
struct GroveApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(store)
                .environment(\.theme, store.theme)
                .preferredColorScheme(store.colorScheme)
                .frame(minWidth: 1100, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task") { store.run(.newTask) }
                    .keyboardShortcut("n", modifiers: .command)
                Button("New Note") { store.newNote() }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                Button("New Event") { store.newEventNow() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(before: .toolbar) {
                Button("Today") { store.showToday() }
                    .keyboardShortcut("t", modifiers: .command)
                Button("Planner") { store.screen = .planner }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Tasks") { store.showTasks() }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Calendar") { store.screen = .calendar }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Notes") { store.screen = .notes }
                    .keyboardShortcut("4", modifiers: .command)
                Divider()
                Button("Day") { store.showMode(.day) }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button("3 Days") { store.showMode(.threeDay) }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Button("Week") { store.showMode(.week) }
                    .keyboardShortcut("3", modifiers: [.command, .option])
                Divider()
                Button("Zoom In") { store.zoomPlanner(by: 1.2) }
                    .keyboardShortcut("=", modifiers: .command)
                Button("Zoom Out") { store.zoomPlanner(by: 1 / 1.2) }
                    .keyboardShortcut("-", modifiers: .command)
                Divider()
            }
            CommandGroup(after: .toolbar) {
                Menu("Theme") {
                    Picker("Theme", selection: Binding(get: { store.themeID }, set: { store.setTheme($0) })) {
                        ForEach(ThemeID.allCases) { Text(ThemeSpec.spec($0).name).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
                Toggle("Motion", isOn: Binding(get: { store.motionSetting }, set: { store.setMotion($0) }))
            }
            CommandMenu("Go") {
                Button("Command Palette") { store.togglePalette() }
                    .keyboardShortcut("k", modifiers: .command)
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
