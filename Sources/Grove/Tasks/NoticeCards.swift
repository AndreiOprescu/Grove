import SwiftUI
import GroveCore

/// The look of the two small cards at the top of the task list.
private struct NoticeStyle: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius, style: .continuous)
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(theme.surface2))
            .overlay(shape.strokeBorder(theme.line, lineWidth: theme.hairlines ? 0.5 : 1))
    }
}

private extension View {
    func noticeStyle() -> some View { modifier(NoticeStyle()) }
}

/// First launch (PLAN §9): says what the three sample tasks are for.
struct WelcomeCard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill").foregroundStyle(theme.accent)
                Text("Welcome to Grove").themedHeading(theme, 15).foregroundStyle(theme.ink)
            }
            Text("Three sample tasks wait on today's list. Each one shows a trick.")
                .font(theme.body(12)).foregroundStyle(theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Got it") { store.dismissWelcome() }
                    .buttonStyle(.borderedProminent).tint(theme.accent)
                Button("Remove samples") { store.removeSamples() }
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .noticeStyle()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome to Grove")
    }
}

/// End of day (PLAN §5.1.7): open tasks that had a time block yesterday.
struct RollOverCard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    let items: [RollOverItem]

    private var title: String { items.count == 1 ? "1 thing from yesterday" : "\(items.count) things from yesterday" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sunrise").foregroundStyle(theme.accent2)
                Text(title).themedHeading(theme, 15).foregroundStyle(theme.ink)
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(items.prefix(3)) { item in
                    Text(item.task.title).font(theme.body(12)).foregroundStyle(theme.muted).lineLimit(1)
                }
                if items.count > 3 {
                    Text("and \(items.count - 3) more").font(theme.body(12)).foregroundStyle(theme.muted)
                }
            }
            HStack(spacing: 8) {
                Button("Move to today") { store.moveRollOver() }
                    .buttonStyle(.borderedProminent).tint(theme.accent)
                Button("Leave") { store.leaveRollOver() }
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .noticeStyle()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
