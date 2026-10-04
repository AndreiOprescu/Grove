import SwiftUI
import AppKit
import UniformTypeIdentifiers
import GroveCore

/// The Settings window, ⌘, (PLAN §5.8). View settings are saved with `@AppStorage`, so the planner follows live.
/// The note templates live in the settings table, so they travel in the export file.
struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            PlannerSettings()
                .tabItem { Label("Planner", systemImage: "calendar.day.timeline.left") }
            NotesSettings()
                .tabItem { Label("Notes", systemImage: "note.text") }
            NotificationSettings()
                .tabItem { Label("Notifications", systemImage: "bell") }
            DataSettings()
                .tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .frame(width: 600, height: 470)
    }
}

// MARK: Appearance

private struct AppearanceSettings: View {
    @Environment(AppStore.self) private var store
    @AppStorage("appearance.intensity") private var intensity = 1.0

    var body: some View {
        Form {
            Section("Theme") {
                HStack(spacing: 12) {
                    ForEach(ThemeID.allCases) { id in
                        ThemeCard(spec: ThemeSpec.spec(id), selected: store.themeID == id) { store.setTheme(id) }
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Motion") {
                Toggle("Moving background and small animations", isOn: Binding(get: { store.motionSetting }, set: { store.setMotion($0) }))
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Accent intensity")
                        Slider(value: $intensity, in: SettingsRules.intensityRange)
                        Text(intensity, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                    Text("How strong the soft circles in the background look.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// One theme as a small picture: its background, a card, and its three accent colours.
private struct ThemeCard: View {
    let spec: ThemeSpec
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color(spec.bg))
                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: min(spec.radius, 8))
                            .fill(Color(spec.surface))
                            .overlay(alignment: .leading) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Capsule().fill(Color(spec.ink)).frame(width: 40, height: 4)
                                    Capsule().fill(Color(spec.muted)).frame(width: 28, height: 3)
                                }
                                .padding(.leading, 8)
                            }
                            .overlay(RoundedRectangle(cornerRadius: min(spec.radius, 8)).stroke(Color(spec.line), lineWidth: 1))
                            .frame(height: 30)
                        HStack(spacing: 5) {
                            ForEach(Array([spec.accent, spec.accent2, spec.accent3].enumerated()), id: \.offset) { _, tone in
                                Circle().fill(Color(tone)).frame(width: 10, height: 10)
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(height: 70)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : Color.secondary.opacity(0.3),
                                                                  lineWidth: selected ? 2.5 : 1))
                Text(spec.name).font(.callout.weight(selected ? .bold : .regular))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(spec.name) theme")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: Planner

private struct PlannerSettings: View {
    @AppStorage("planner.snap") private var snap = 5
    @AppStorage("planner.workStart") private var workStart = 9 * 60
    @AppStorage("planner.workEnd") private var workEnd = 18 * 60
    @AppStorage("planner.defaultLength") private var defaultLength = SettingsRules.defaultEventLength
    @AppStorage("planner.hourHeight") private var hourHeight = 64.0
    @AppStorage("calendar.weekStartsSunday") private var sundayFirst = false

    var body: some View {
        Form {
            Section("Time grid") {
                Picker("Snap step", selection: $snap) {
                    ForEach(SettingsRules.snapSteps, id: \.self) { Text("\($0) minutes").tag($0) }
                }
                Picker("New event length", selection: $defaultLength) {
                    ForEach(SettingsRules.eventLengths, id: \.self) { Text(PlannerMath.duration($0)).tag($0) }
                }
                HStack {
                    Text("Hour height")
                    Slider(value: $hourHeight, in: Double(PlannerGeometry.zoomRange.lowerBound)...Double(PlannerGeometry.zoomRange.upperBound))
                    Text("\(Int(hourHeight)) pt").monospacedDigit().frame(width: 52, alignment: .trailing)
                }
            }
            Section("Working hours") {
                Picker("Start", selection: Binding(get: { workStart / 60 }, set: { setHours(start: $0 * 60, end: workEnd, startChanged: true) })) {
                    ForEach(0..<24, id: \.self) { Text(SettingsRules.hourText($0 * 60)).tag($0) }
                }
                Picker("End", selection: Binding(get: { workEnd / 60 }, set: { setHours(start: workStart, end: $0 * 60, startChanged: false) })) {
                    ForEach(1...24, id: \.self) { Text(SettingsRules.hourText($0 * 60)).tag($0) }
                }
            }
            Section("Week") {
                Picker("Week starts on", selection: $sundayFirst) {
                    Text("Monday").tag(false)
                    Text("Sunday").tag(true)
                }
                .pickerStyle(.segmented)
                Text("This changes the month grid, the week strip and the week view. Plans for “this week” still run Monday to Sunday.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func setHours(start: Int, end: Int, startChanged: Bool) {
        let fixed = SettingsRules.workHours(start: start, end: end, startChanged: startChanged)
        workStart = fixed.start
        workEnd = fixed.end
    }
}

// MARK: Notes

private struct NotesSettings: View {
    @Environment(AppStore.self) private var store
    @State private var daily = ""
    @State private var weekly = ""
    @State private var loaded = false

    var body: some View {
        Form {
            templateSection("Daily note", text: $daily, kind: .daily)
            templateSection("Weekly note", text: $weekly, kind: .weekly)
            Text("A new note starts with this text. Notes you already have do not change.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear {
            daily = store.template(.daily)
            weekly = store.template(.weekly)
            loaded = true
        }
        .onChange(of: daily) { _, text in if loaded { store.setTemplate(.daily, text) } }
        .onChange(of: weekly) { _, text in if loaded { store.setTemplate(.weekly, text) } }
    }

    private func templateSection(_ title: String, text: Binding<String>, kind: NoteKind) -> some View {
        Section(title) {
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .frame(height: 96)
                .accessibilityLabel("\(title) template")
            Button("Use the default") {
                store.resetTemplate(kind)
                text.wrappedValue = store.template(kind)
            }
        }
    }
}

// MARK: Notifications

/// Reminders before events and due times (PLAN §5.6).
private struct NotificationSettings: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Form {
            Section("Reminders") {
                Toggle("Remind me about events, blocks and due times", isOn: Binding(
                    get: { store.notifyEnabled },
                    set: { on in
                        store.setNotifyEnabled(on)
                        if on, store.notifyStatus == .notAsked { Task { await store.askForNotifications() } }
                    }))
                Picker("Remind me", selection: Binding(get: { store.notifyLead }, set: { store.setNotifyLead($0) })) {
                    ForEach(ReminderPlanner.leadChoices, id: \.self) { Text(SettingsRules.leadText($0)).tag($0) }
                }
                .disabled(!store.notifyEnabled)
                Text("Grove reminds you about the next 14 days. A task with a due day but no time does not remind.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Permission") {
                Text(SettingsRules.notifyStatusText(store.notifyStatus))
                    .foregroundStyle(store.notifyStatus == .denied ? Color.orange : Color.secondary)
                switch store.notifyStatus {
                case .allowed:
                    EmptyView()
                case .notAsked:
                    Button("Allow notifications") { Task { await store.askForNotifications() } }
                case .denied:
                    Button("Open System Settings") { openSystemSettings() }
                }
            }
        }
        .formStyle(.grouped)
        .task { await store.refreshNotifyStatus() }
    }

    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: Data

private struct DataSettings: View {
    @Environment(AppStore.self) private var store
    @State private var message: String?
    @State private var failed = false
    @State private var backups: [BackupFile] = []

    var body: some View {
        Form {
            Section("Your data") {
                HStack {
                    Button("Export JSON…") { exportJSON() }
                    Button("Import JSON…") { importJSON() }
                    Button("Show data folder") { showFolder() }
                }
                Text("Export saves everything in one file. Import replaces everything with the file you pick.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message {
                    Text(message).foregroundStyle(failed ? Color.red : Color.secondary)
                        .accessibilityLabel(failed ? "Problem: \(message)" : message)
                }
            }
            Section("Daily backups") {
                if backups.isEmpty {
                    Text("No backups yet. Grove makes one each day when it starts and keeps the newest 14.")
                        .foregroundStyle(.secondary)
                } else {
                    List(backups) { file in
                        HStack {
                            Text(file.title)
                            Spacer()
                            Text(file.sizeText).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .frame(height: 130)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { backups = store.backupFiles() }
    }

    private func report(_ text: String, failed: Bool = false) {
        message = text
        self.failed = failed
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = DataExport.suggestedFileName(on: .today())
        panel.message = "Save all your Grove data in one file."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportData().write(to: url, options: .atomic)
            report("Saved \(url.lastPathComponent).")
        } catch {
            report("Grove could not save the file. \(error.localizedDescription)", failed: true)
        }
    }

    private func importJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Pick a file that Grove exported."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let summary = try DataExport.summary(of: data)
            guard confirmReplace(summary) else { return }
            try store.saveSafetyCopy()
            try store.importData(data)
            backups = store.backupFiles()
            report("Imported \(url.lastPathComponent). Your old data is in before-import.sqlite in the data folder.")
        } catch {
            report("\(error.localizedDescription) Nothing was changed.", failed: true)
        }
    }

    /// The dialog says that import replaces everything (PLAN §4.4).
    private func confirmReplace(_ s: DataExport.Summary) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Replace everything in Grove?"
        alert.informativeText = """
            This file has \(s.tasks) tasks, \(s.events) events, \(s.notes) notes and \(s.lists) lists.
            Import replaces ALL your data with the data in this file.
            Grove saves a copy of your data first, in the data folder.
            """
        alert.addButton(withTitle: "Replace Everything")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showFolder() {
        guard let folder = store.dataFolder else { report("Grove cannot find its data folder.", failed: true); return }
        NSWorkspace.shared.open(folder)
    }
}
