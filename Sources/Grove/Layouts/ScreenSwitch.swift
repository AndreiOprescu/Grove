import SwiftUI

extension Screen {
    var title: String { self == .planner ? "Planner" : "Notes" }
    var icon: String { self == .planner ? "calendar.day.timeline.left" : "note.text" }
}

/// The two screens of the window. Sits in the empty strip at the top. ⌘1 and ⌘2 switch too.
struct ScreenSwitch: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(Screen.allCases.enumerated()), id: \.element) { i, screen in
                let on = store.screen == screen
                Button { store.screen = screen } label: {
                    Label(screen.title, systemImage: screen.icon)
                        .font(.system(size: 12, weight: on ? .semibold : .regular, design: .rounded))
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Capsule().fill(on ? theme.accent : Color.clear))
                        .foregroundStyle(on ? theme.surface : theme.muted)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
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
            Text(text).font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(theme.ink)).foregroundStyle(theme.bg)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
