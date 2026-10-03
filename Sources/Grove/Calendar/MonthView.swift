import SwiftUI
import GroveCore

/// Six weeks, Monday first. Each day shows its events, a dot for each open task (up to three)
/// and a leaf when it has a daily note. A click opens the day. A double-click makes an all-day event.
struct MonthView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    /// Called after a click on a day, so the planner can switch to its day view.
    let openDay: (DayKey) -> Void
    @State private var targeted: DayKey?
    /// Colours each day by the mood of its daily note. The planner header turns it on and off.
    @AppStorage("calendar.moodTint") private var moodTint = false

    var body: some View {
        let _ = store.revision
        let grid = CalendarRules.monthGrid(containing: store.selectedDay)
        let info = store.dayInfo(grid[0]...grid[41])
        let month = store.selectedDay.month
        VStack(spacing: 0) {
            weekdayRow(grid)
            GeometryReader { proxy in
                let height = proxy.size.height / 6
                VStack(spacing: 0) {
                    ForEach(0..<6, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { col in
                                let day = grid[row * 7 + col]
                                cell(day, info: info[day] ?? DayInfo(), inMonth: day.month == month, height: height)
                            }
                        }
                    }
                }
            }
        }
    }

    private func weekdayRow(_ grid: [DayKey]) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                Text(grid[i].date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(theme.body(11, weight: .semibold))
                    .foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
    }

    // MARK: Cell

    private func moodBackground(_ info: DayInfo) -> Color {
        guard moodTint, let m = info.mood.flatMap(Mood.init(rawValue:)) else { return .clear }
        return m.tint.opacity(0.2)
    }

    private func cell(_ day: DayKey, info: DayInfo, inMonth: Bool, height: CGFloat) -> some View {
        let slots = CalendarRules.pillSlots(cellHeight: Double(height))
        let pills = CalendarRules.pills(info.events, slots: slots)
        let isSelected = day == store.selectedDay
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                dayNumber(day)
                Spacer(minLength: 0)
                if info.hasNote {
                    Image(systemName: "leaf.fill").font(.system(size: 9)).foregroundStyle(theme.accent)
                        .help("This day has a note")
                }
                HStack(spacing: 2) {
                    ForEach(0..<CalendarRules.dots(info.openTasks), id: \.self) { _ in
                        Circle().fill(theme.accent2).frame(width: 4, height: 4)
                    }
                }
                .help(info.openTasks == 0 ? "" : "\(info.openTasks) open task\(info.openTasks == 1 ? "" : "s")")
            }
            ForEach(pills.shown) { pill($0, on: day) }
            if pills.hidden > 0 {
                Text("+\(pills.hidden) more").font(theme.body(10)).foregroundStyle(theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(moodBackground(info))
        .background(targeted == day ? theme.accent.opacity(0.12) : isSelected ? theme.accent.opacity(0.07) : Color.clear)
        .overlay(Rectangle().strokeBorder(theme.line.opacity(0.7), lineWidth: 0.5))
        .overlay(Rectangle().strokeBorder(theme.accent, lineWidth: targeted == day ? 1.5 : 0))
        .opacity(inMonth ? 1 : 0.5)
        .contentShape(Rectangle())
        .gesture(TapGesture(count: 2).onEnded { store.newEvent(on: day) }
            .exclusively(before: TapGesture().onEnded { store.selectedDay = day; openDay(day) }))
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, raw.hasPrefix(DragPayload.taskPrefix) else { return false }
            store.dropTask(String(raw.dropFirst(DragPayload.taskPrefix.count)), on: day)
            return true
        } isTargeted: { on in
            if on { targeted = day } else if targeted == day { targeted = nil }
        }
        .eventEditor(anchor: "new:\(day.string)")
    }

    private func dayNumber(_ day: DayKey) -> some View {
        let isToday = day == .today()
        return Text("\(day.day)")
            .font(.system(size: 12, weight: isToday ? .bold : .semibold, design: .rounded))
            .foregroundStyle(isToday ? theme.surface : theme.ink)
            .frame(minWidth: 20, minHeight: 20)
            .background(Circle().fill(isToday ? theme.accent : Color.clear))
    }

    private func pill(_ e: EventItem, on day: DayKey) -> some View {
        let anchor = "\(e.id)#\(day.string)"
        let time = !e.allDay && e.start.day == day ? PlannerMath.clock(e.start.minute) + " " : ""
        return (Text(time).foregroundStyle(theme.muted) + Text(e.title.isEmpty ? "New Event" : e.title))
            .font(theme.body(10.5, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(theme.ink)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(theme.color(named: e.color).opacity(0.25)))
            .contentShape(Rectangle())
            .onTapGesture { store.editEvent(e, anchor: anchor) }
            .eventEditor(anchor: anchor)
    }
}
