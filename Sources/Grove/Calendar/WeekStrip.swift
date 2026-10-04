import SwiftUI
import GroveCore

/// The seven days of the selected week (Monday first, or Sunday first in Settings). Each day has up to three dots for what is on it. A click picks the day.
/// A task dropped on a day is planned for that day.
struct WeekStrip: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    /// The days the planner shows now. They get the soft fill.
    let shown: Set<DayKey>
    @AppStorage("calendar.weekStartsSunday") private var sundayFirst = false
    @State private var targeted: DayKey?

    var body: some View {
        let _ = store.revision
        let start = CalendarRules.weekStart(of: store.selectedDay, sundayFirst: sundayFirst)
        let info = store.dayInfo(start...start.adding(days: 6))
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                let day = start.adding(days: i)
                cell(day, count: info[day]?.itemCount ?? 0)
            }
        }
    }

    private func cell(_ day: DayKey, count: Int) -> some View {
        let isToday = day == .today()
        return VStack(spacing: 2) {
            HStack(spacing: 4) {
                Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(theme.body(11))
                Text(day.date.formatted(.dateTime.day()))
                    .font(theme.body(14, weight: .bold))
            }
            .foregroundStyle(isToday ? theme.accent : theme.ink)
            HStack(spacing: 2) {
                ForEach(0..<CalendarRules.dots(count), id: \.self) { _ in
                    Circle().fill(theme.accent).frame(width: 4, height: 4)
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(theme.accent.opacity(shown.contains(day) ? 0.16 : targeted == day ? 0.10 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(theme.accent, lineWidth: targeted == day ? 1.5 : 0))
        .contentShape(Rectangle())
        .onTapGesture { store.selectedDay = day }
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, raw.hasPrefix(DragPayload.taskPrefix) else { return false }
            store.dropTask(String(raw.dropFirst(DragPayload.taskPrefix.count)), on: day)
            return true
        } isTargeted: { on in
            if on { targeted = day } else if targeted == day { targeted = nil }
        }
        .help(day.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
    }
}
