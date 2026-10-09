import SwiftUI
import GroveCore

/// The panels that can open on the left of the Today and Planner screens. One at a time.
/// The choice is saved as text in `shell.leftPane`; empty text means closed.
enum LeftPane: String, CaseIterable, Identifiable {
    case notes, tasks, goals

    var id: String { rawValue }

    static let storageKey = "shell.leftPane"
    /// How wide the panel is on the Planner screen. On Today the user drags the width (`SpreadRules.tasksRange`).
    static let plannerWidth: CGFloat = 320

    var title: String {
        switch self {
        case .notes: "Notes"
        case .tasks: "Tasks"
        case .goals: "Goals"
        }
    }

    var icon: String {
        switch self {
        case .notes: "note.text"
        case .tasks: "checklist"
        case .goals: "target"
        }
    }

    /// The tooltip of the button: it names the action the next click does.
    func tooltip(isOpen: Bool) -> String { isOpen ? "Hide \(title.lowercased())" : "Show \(title.lowercased())" }

    var help: String { tooltip(isOpen: false) }

    /// The panel after a click on `tapped`: the same one closes, any other one replaces the open one.
    static func toggled(current: LeftPane?, tapped: LeftPane) -> LeftPane? {
        current == tapped ? nil : tapped
    }

    /// The panel named by saved text. Empty or unknown text is closed.
    init?(saved: String) { self.init(rawValue: saved) }

    static func savedText(_ pane: LeftPane?) -> String { pane?.rawValue ?? "" }

    /// Only these two screens have a left side. The Calendar, the Notes and the Garden fill the window.
    static func isAvailable(on screen: Screen) -> Bool { screen == .today || screen == .planner }
}

/// Three small buttons at the top left, level with the screen switch. Each opens its panel; a click on the open one closes it.
struct LeftDock: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @AppStorage(LeftPane.storageKey) private var saved = ""

    var body: some View {
        if LeftPane.isAvailable(on: store.screen) {
            let current = LeftPane(saved: saved)
            HStack(spacing: 2) {
                ForEach(LeftPane.allCases) { pane in
                    let on = current == pane
                    Button { saved = LeftPane.savedText(LeftPane.toggled(current: current, tapped: pane)) } label: {
                        Image(systemName: pane.icon)
                            .font(.system(size: 12, weight: on ? .semibold : .regular))
                            .frame(width: 28, height: 22)
                            .background(Capsule().fill(on ? theme.accent : Color.clear))
                            .foregroundStyle(on ? theme.surface : theme.muted)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(pane.tooltip(isOpen: on))
                    .accessibilityLabel(pane.title)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(2)
            .background(Capsule().fill(theme.surface2))
            .overlay(Capsule().strokeBorder(theme.line))
        }
    }
}

/// The left side of a screen: the open panel, or what the screen shows when none is open.
/// On Today that is the list of today's tasks and the slot takes the width the screen gives it.
/// On the Planner the slot is empty when closed and 320 pt wide when open, and it pushes the week grid aside.
struct LeftSlot: View {
    enum Place { case today, planner }
    let place: Place
    @AppStorage(LeftPane.storageKey) private var saved = ""

    var body: some View {
        switch (LeftPane(saved: saved), place) {
        case (.notes?, _): framed(NotesPane())
        case (.tasks?, _): framed(TasksPane(mode: .unscheduled))
        case (.goals?, _): framed(GoalsPane())
        case (nil, .today): framed(TasksPane(mode: .today))
        case (nil, .planner): EmptyView()
        }
    }

    @ViewBuilder private func framed(_ pane: some View) -> some View {
        switch place {
        case .today:
            pane
        case .planner:
            pane
                .frame(width: LeftPane.plannerWidth)
                .padding(.leading, 16).padding(.top, 34).padding(.bottom, 16)
                .transition(.move(edge: .leading).combined(with: .opacity))
        }
    }
}
