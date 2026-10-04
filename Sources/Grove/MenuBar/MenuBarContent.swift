import SwiftUI
import AppKit
import GroveCore

/// The window under the leaf in the menu bar (PLAN §5.7): what is on now, what is next,
/// how much of today has grown, a box to add a task, and a button to open Grove.
struct MenuBarContent: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.openWindow) private var openWindow
    @State private var text = ""
    @State private var added = false

    var body: some View {
        // The lines change as time passes, so look again every 30 seconds.
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let _ = store.revision
            let lines = store.menuBarLines(minute: store.nowMinute())
            let progress = store.plantProgress(on: .today())
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(lines.now).font(theme.body(13, weight: .semibold))
                    Text(lines.next).font(theme.body(12)).foregroundStyle(theme.muted)
                }
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress.fraction).tint(theme.accent)
                        .accessibilityLabel("Progress today")
                        .accessibilityValue(progress.growthText)
                    Text(progress.growthText).font(theme.body(11)).foregroundStyle(theme.muted)
                }
                TextField("Add a task for today", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                    .accessibilityLabel("Add a task for today")
                if added {
                    Text("Added to today.").font(theme.body(11)).foregroundStyle(theme.accent)
                }
                Divider()
                Button("Open Grove", action: openGrove)
                    .buttonStyle(.borderless)
                    .keyboardShortcut("o", modifiers: .command)
            }
            .padding(14)
            .frame(width: 280)
        }
    }

    private func add() {
        guard store.menuBarAdd(text) != nil else { return }
        text = ""
        added = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            added = false
        }
    }

    /// Bring the main window to the front. Open a new one when none exists.
    private func openGrove() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = MainWindow.find() {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }
}

/// Finds the main Grove window among all windows. The menu bar window and the Settings window are not it.
enum MainWindow {
    static func find() -> NSWindow? {
        let candidates = NSApp.windows.filter { $0.canBecomeMain && !isSettings($0) }
        return candidates.first { $0.identifier?.rawValue.hasPrefix("main") == true } ?? candidates.first
    }

    private static func isSettings(_ w: NSWindow) -> Bool {
        (w.identifier?.rawValue.localizedCaseInsensitiveContains("settings") ?? false) || w.title == "Settings"
    }
}
