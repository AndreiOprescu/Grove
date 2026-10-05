import SwiftUI
import GroveCore

/// The small timer that floats at the bottom right of the window while a focus session runs (PLAN §5.1.7).
struct FocusCard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    let session: FocusSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "timer").foregroundStyle(theme.accent)
                Text(session.title).font(theme.body(12, weight: .semibold)).foregroundStyle(theme.ink).lineLimit(1)
                Spacer(minLength: 8)
                Button { store.stopFocus() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(theme.muted)
                    .help("Stop focus")
                    .accessibilityLabel("Stop focus")
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = FocusRules.remaining(until: session.end, now: context.date)
                if session.finished || left == 0 {
                    finished
                } else {
                    running(left, progress: FocusRules.progress(start: session.start, end: session.end, now: context.date))
                }
            }
        }
        .padding(12)
        .frame(width: 230, alignment: .leading)
        .panel()
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Focus timer")
        .task(id: "\(session.blockId)-\(session.end.timeIntervalSince1970)") {
            try? await Task.sleep(for: .seconds(max(0, session.end.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            store.focusTimeUp()
        }
    }

    private func running(_ left: Int, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(FocusRules.clock(left))
                .font(theme.number(30, weight: .semibold)).foregroundStyle(theme.ink)
                .accessibilityLabel("Time left")
                .accessibilityValue(FocusRules.clock(left))
            ProgressBar(fraction: progress)
        }
    }

    private var finished: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.taskId == nil ? "Time is up." : "Time is up. Mark done?")
                .font(theme.body(13, weight: .semibold)).foregroundStyle(theme.ink)
            HStack(spacing: 8) {
                if session.taskId != nil {
                    Button("Mark done") { store.markFocusDone() }
                        .buttonStyle(.borderedProminent).tint(theme.accent)
                    Button("Not yet") { store.stopFocus() }
                        .buttonStyle(.bordered)
                } else {
                    Button("OK") { store.stopFocus() }
                        .buttonStyle(.borderedProminent).tint(theme.accent)
                }
            }
            .controlSize(.small)
        }
    }
}
