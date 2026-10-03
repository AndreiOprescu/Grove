import SwiftUI
import GroveCore

/// The card on the right of a daily or weekly note.
private struct SideCard<Content: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    var subtitle = ""
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased()).font(theme.body(10.5, weight: .bold)).tracking(0.8).foregroundStyle(theme.muted)
                if !subtitle.isEmpty {
                    Text(subtitle).font(theme.body(12)).foregroundStyle(theme.ink)
                }
            }
            content
        }
        .padding(14)
        .frame(width: 236, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: theme.radius * 0.8, style: .continuous).fill(theme.surface2.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: theme.radius * 0.8, style: .continuous).strokeBorder(theme.line.opacity(0.8)))
    }
}

/// A daily note's day: events, task blocks and tasks, live (PLAN §5.5 item 4).
struct DayPanel: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    let day: DayKey

    var body: some View {
        let _ = store.revision
        let rows = store.agenda(for: day)
        let events = rows.filter { $0.kind == .event }.count
        let tasks = rows.count - events
        let finished = rows.filter { $0.kind != .event && $0.done }.count
        SideCard(title: day == .today() ? "Today" : "This day", subtitle: summary(events: events, tasks: tasks, finished: finished)) {
            if rows.isEmpty {
                Text("Nothing planned for this day.").font(theme.body(12)).foregroundStyle(theme.muted)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                        if r.kind == .task, i > 0, rows[i - 1].kind != .task {
                            Text("Not scheduled").font(theme.body(10.5, weight: .semibold))
                                .foregroundStyle(theme.muted).padding(.top, 4)
                        }
                        row(r)
                    }
                }
            }
            Button { store.selectedDay = day; store.screen = .planner } label: {
                Label("Open in planner", systemImage: "arrow.up.right").font(theme.body(12, weight: .medium))
            }
            .buttonStyle(.plain).foregroundStyle(theme.accent)
        }
    }

    private func summary(events: Int, tasks: Int, finished: Int) -> String {
        if events == 0, tasks == 0 { return "" }
        var parts: [String] = []
        if events > 0 { parts.append("\(events) event\(events == 1 ? "" : "s")") }
        if tasks > 0 { parts.append("\(finished)/\(tasks) task\(tasks == 1 ? "" : "s") done") }
        return parts.joined(separator: " · ")
    }

    private func icon(_ r: AgendaRow) -> String {
        switch r.kind {
        case .event: "calendar"
        case .block: r.done ? "checkmark.circle.fill" : "clock"
        case .task: r.done ? "checkmark.circle.fill" : "circle"
        }
    }

    private func row(_ r: AgendaRow) -> some View {
        let time = DayRules.timeLabel(r)
        return Button { store.open(r.ref) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: icon(r)).font(.system(size: 11))
                    .foregroundStyle(r.done ? theme.muted : (r.kind == .event ? theme.accent2 : theme.accent)).frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(r.title.isEmpty ? "Untitled" : r.title)
                        .font(theme.body(12.5)).strikethrough(r.done)
                        .foregroundStyle(r.done ? theme.muted : theme.ink).lineLimit(2).multilineTextAlignment(.leading)
                    if !time.isEmpty {
                        Text(time).font(theme.number(10.5)).foregroundStyle(theme.muted)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(r.kind == .event ? "Show this event in the planner" : "Show this task in the planner")
    }
}

/// The tasks finished on a day, with the time. It is built from the tasks. It is not saved in the note (PLAN §5.5 item 5).
struct DoneLog: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    let day: DayKey

    var body: some View {
        let _ = store.revision
        let tasks = store.completedTasks(on: day)
        VStack(alignment: .leading, spacing: 8) {
            Text(day == .today() ? "Done today" : "Done this day")
                .font(theme.heading(12, weight: .bold)).foregroundStyle(theme.ink)
            if tasks.isEmpty {
                Text("Nothing finished yet.").font(theme.body(12)).foregroundStyle(theme.muted)
            }
            ForEach(tasks) { t in
                Button { store.open(ItemRef(.task, t.id)) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent)
                        Text(DayRules.finishedClock(t)).monospacedDigit().foregroundStyle(theme.muted)
                        Text(t.title).foregroundStyle(theme.ink).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .font(theme.body(12.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 6)
    }
}

/// Three icons: rough, okay, good. A second click on the same icon clears it (PLAN §5.5 item 12).
struct MoodPicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    let note: Note

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Mood.allCases) { m in
                let on = note.mood == m.rawValue
                Button { store.setMood(note.id, m) } label: {
                    Image(systemName: m.symbol).symbolVariant(on ? .fill : .none)
                        .font(.system(size: 14))
                        .foregroundStyle(on ? m.tint : theme.muted)
                        .frame(width: 26, height: 24)
                        .background(Capsule().fill(on ? m.tint.opacity(0.16) : Color.clear))
                }
                .buttonStyle(.plain)
                .help(on ? "\(m.label). Click again to clear it." : m.label)
            }
        }
        .padding(2)
        .background(Capsule().fill(theme.surface2))
    }
}

/// A weekly note's week: what was done, what is open, hours and the busiest day (PLAN §5.5 item 10).
struct WeekReviewPanel: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    let monday: DayKey
    let hasSummary: Bool
    let onInsert: () -> Void

    var body: some View {
        let _ = store.revision
        let r = store.weekReview(monday)
        SideCard(title: "Week review", subtitle: "\(monday.date.formatted(.dateTime.day().month(.abbreviated))) – \(monday.adding(days: 6).date.formatted(.dateTime.day().month(.abbreviated)))") {
            HStack(spacing: 10) {
                number(r.done.count, "done")
                number(r.open.count, "still open")
            }
            time(r)
            if let b = r.busiest {
                Label("Busiest: \(NotesRules.weekdayName(b.day)), \(PlannerMath.duration(b.minutes))", systemImage: "flame")
                    .font(theme.body(12)).foregroundStyle(theme.ink)
            }
            list("Finished", r.done, icon: "checkmark.circle.fill")
            list("Left open", r.open, icon: "circle")
            Button(action: onInsert) {
                Label(hasSummary ? "Update summary" : "Insert summary", systemImage: "text.append")
                    .font(theme.body(12, weight: .medium))
            }
            .buttonStyle(.bordered).controlSize(.small)
            .help("Write this review under ## Review in the note")
        }
    }

    private func number(_ n: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(n)").themedHeading(theme, 24, weight: .semibold).foregroundStyle(theme.ink)
            Text(label).font(theme.body(11)).foregroundStyle(theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func time(_ r: WeekReview) -> some View {
        if r.plannedMinutes == 0 {
            Text("No task blocks planned.").font(theme.body(12)).foregroundStyle(theme.muted)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(PlannerMath.duration(r.doneMinutes)) finished of \(PlannerMath.duration(r.plannedMinutes)) planned")
                    .font(theme.body(12)).foregroundStyle(theme.ink)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.line)
                        Capsule().fill(theme.accent).frame(width: geo.size.width * CGFloat(r.doneMinutes) / CGFloat(r.plannedMinutes))
                    }
                }
                .frame(height: 5)
            }
        }
    }

    @ViewBuilder private func list(_ title: String, _ tasks: [TaskItem], icon: String) -> some View {
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(theme.body(10.5, weight: .semibold)).foregroundStyle(theme.muted)
                ForEach(tasks.prefix(5)) { t in
                    Button { store.open(ItemRef(.task, t.id)) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: icon).font(.system(size: 10.5)).foregroundStyle(theme.accent)
                            Text(t.title).font(theme.body(12)).foregroundStyle(theme.ink).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if tasks.count > 5 {
                    Text("and \(tasks.count - 5) more").font(theme.body(11)).foregroundStyle(theme.muted)
                }
            }
        }
    }
}
