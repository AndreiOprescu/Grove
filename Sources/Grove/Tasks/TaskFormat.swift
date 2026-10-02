import SwiftUI
import GroveCore

/// Small text and colour helpers for the task list.
enum TaskFormat {
    /// "Today", "Tomorrow", "Yesterday", else "Fri 9 Oct".
    static func dayLabel(_ d: DayKey, today: DayKey = .today()) -> String {
        switch today.days(until: d) {
        case 0: "Today"
        case 1: "Tomorrow"
        case -1: "Yesterday"
        default: dateLabel(d)
        }
    }

    /// "Fri 9 Oct" for any day. Used where "Yesterday" would read oddly, like the week list.
    static func dateLabel(_ d: DayKey) -> String {
        d.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// Text for a due value ("YYYY-MM-DD" or "YYYY-MM-DDTHH:MM") and whether it is already late.
    static func due(_ value: String, today: DayKey = .today(), nowMinute: Int) -> (text: String, late: Bool) {
        let day = DayKey(String(value.prefix(10)))
        var text = "due " + dayLabel(day, today: today)
        var late = day < today
        if let w = WallTime(value) {
            text += " " + PlannerMath.clock(w.minute)
            if day == today { late = w.minute < nowMinute }
        }
        return (text, late)
    }

    static func priorityColor(_ p: Int, _ theme: Theme) -> Color? {
        switch p {
        case 1: theme.muted
        case 2: theme.accent3
        case 3: theme.accent2
        default: nil
        }
    }

    static func symbol(_ kind: QuickAddChip.Kind) -> String {
        switch kind {
        case .date: "calendar"
        case .time: "clock"
        case .duration: "hourglass"
        case .repeats: "repeat"
        case .due: "flag"
        case .list: "folder"
        case .tag: "number"
        case .priority: "exclamationmark"
        }
    }
}

/// A small rounded label.
struct Chip: View {
    @Environment(\.theme) private var theme
    let text: String
    var symbol: String?
    var tint: Color?

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .semibold)) }
            Text(text).lineLimit(1)
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .foregroundStyle(tint ?? theme.muted)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Capsule().fill((tint ?? theme.muted).opacity(0.13)))
    }
}
