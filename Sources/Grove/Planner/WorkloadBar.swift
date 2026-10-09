import SwiftUI
import GroveCore

/// A bar under the timeline title: planned work against the busy-day limit, with "6h 30m/9h" next to it.
/// It turns bright red when there is more planned than the limit.
struct WorkloadBar: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let planned: Int
    let limit: Int
    /// Shown as a tooltip.
    var detail = ""

    private static let brightRed = Color(red: 1.0, green: 0.10, blue: 0.10)

    private var over: Bool { Workload.isOver(planned: planned, limit: limit) }
    private var label: String { Workload.label(planned: planned, limit: limit) }
    private var motionOn: Bool { MotionRules.isOn(setting: store.motionSetting, reduceMotion: reduceMotion) }

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.surface2)
                    Capsule().strokeBorder(over ? Self.brightRed.opacity(0.6) : theme.line, lineWidth: 1)
                    Capsule()
                        .fill(over ? Self.brightRed : theme.accent)
                        .frame(width: max(over || planned > 0 ? 8 : 0, g.size.width * Workload.fraction(planned: planned, limit: limit)))
                        .shadow(color: over ? Self.brightRed.opacity(0.6) : .clear, radius: 3)
                }
            }
            .frame(height: 8)
            Text(label)
                .font(.system(size: 11, weight: over ? .bold : .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(over ? Self.brightRed : theme.muted)
                .lineLimit(1).fixedSize()
        }
        .animation(motionOn ? .easeOut(duration: 0.25) : nil, value: planned)
        .help(detail.isEmpty ? "Work planned today, against your busy-day limit" : detail)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Work planned")
        .accessibilityValue(over ? "\(label). That is too much." : label)
    }
}
