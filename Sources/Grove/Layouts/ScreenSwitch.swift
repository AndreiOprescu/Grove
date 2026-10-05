import SwiftUI

extension Screen {
    var title: String {
        switch self {
        case .today: "Today"
        case .planner: "Planner"
        case .calendar: "Calendar"
        case .notes: "Notes"
        case .garden: "Garden"
        }
    }

    var icon: String {
        switch self {
        case .today: "sun.max"
        case .planner: "calendar.day.timeline.left"
        case .calendar: "calendar"
        case .notes: "note.text"
        case .garden: "leaf"
        }
    }
}

/// The screens of the window. Sits in the empty strip at the top. The View menu has a shortcut for each.
struct ScreenSwitch: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Screen.allCases) { screen in
                let on = store.screen == screen
                Button { store.screen = screen } label: {
                    Label(screen.title, systemImage: screen.icon)
                        .font(.system(size: 12, weight: on ? .semibold : .regular, design: .rounded))
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Capsule().fill(on ? theme.accent : Color.clear))
                        .foregroundStyle(on ? theme.surface : theme.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(theme.surface2))
        .overlay(Capsule().strokeBorder(theme.line))
    }
}

/// A short message at the bottom of the window.
struct ToastView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        if let text = store.toast {
            Text(text).font(theme.body(12, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(theme.ink)).foregroundStyle(theme.bg)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
