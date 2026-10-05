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

    /// "Week of 5 Oct" for a week task. `monday` is the stored week (its Monday).
    static func weekLabel(_ monday: DayKey) -> String {
        "Week of " + monday.date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// Where a task is planned, for its date label: the day, "Week of 5 Oct" or "Someday". Nil for the inbox.
    static func planLabel(_ task: TaskItem, today: DayKey = .today()) -> String? {
        switch task.bucket {
        case .day: task.planDate.map { dayLabel($0, today: today) }
        case .week: task.planWeek.map(weekLabel)
        case .someday: "Someday"
        case .inbox: nil
        }
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

    /// The colour of a task's outline. Low is green, medium is yellow, high is red. No priority has no outline.
    enum PriorityTone: Equatable { case green, yellow, red }

    static func priorityTone(_ p: Int) -> PriorityTone? {
        switch p {
        case 1: .green
        case 2: .yellow
        case 3: .red
        default: nil
        }
    }

    /// The same colours in every theme, so "red" always means "high".
    static func priorityColor(_ p: Int) -> Color? {
        switch priorityTone(p) {
        case .green: Color(red: 0.20, green: 0.72, blue: 0.35)
        case .yellow: Color(red: 0.98, green: 0.80, blue: 0.10)
        case .red: Color(red: 0.92, green: 0.18, blue: 0.18)
        case nil: nil
        }
    }

    /// A thick outline, so the priority can be read from across the room.
    static let priorityBorderWidth: CGFloat = 3.5

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
        .font(theme.body(10, weight: .medium))
        .foregroundStyle(tint ?? theme.muted)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .chipBackground(tint ?? theme.muted)
    }
}
