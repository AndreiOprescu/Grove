import SwiftUI
import GroveCore

enum TasksTab: String, CaseIterable, Identifiable {
    case day, week, inbox, someday
    var id: String { rawValue }
}

/// The task list next to the planner. Tabs: the chosen day, the week, the inbox, someday.
struct TasksPane: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @AppStorage("shell.tasksOpen") private var open = true
    @AppStorage("tasks.tab") private var tabRaw = TasksTab.day.rawValue
    @State private var expanded: Set<String> = []
    @State private var showDone = false

    private var tab: TasksTab { TasksTab(rawValue: tabRaw) ?? .day }

    var body: some View {
        let _ = store.revision
        let lists = Dictionary(uniqueKeysWithValues: ((try? store.repos.lists.all(includeArchived: true)) ?? []).map { ($0.id, $0) })
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tasks").font(.system(.title3, design: .serif, weight: .semibold)).foregroundStyle(theme.ink)
                Spacer()
                Button { open = false } label: { Image(systemName: "sidebar.left") }
                    .buttonStyle(.plain).foregroundStyle(theme.muted).help("Hide the task list")
            }
            QuickAddField(placement: defaultPlacement, placementLabel: defaultLabel)
            tabBar
            ScrollView {
                VStack(alignment: .leading, spacing: 14) { content(lists) }
                    .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            NotesTray()
        }
        .padding(12)
        .frame(width: 320)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: theme.radius, style: .continuous).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: theme.radius, style: .continuous).strokeBorder(theme.line))
    }

    // MARK: Defaults for quick add

    private var defaultPlacement: TaskPlacement {
        switch tab {
        case .day: .day(store.selectedDay)
        case .week: .week(store.selectedDay.weekStart())
        case .inbox: .inbox
        case .someday: .someday
        }
    }

    private var defaultLabel: String {
        switch tab {
        case .day: TaskFormat.dayLabel(store.selectedDay)
        case .week: "This week"
        case .inbox: "Inbox"
        case .someday: "Someday"
        }
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(TasksTab.allCases) { t in
                let count = self.count(t)
                Button { tabRaw = t.rawValue } label: {
                    VStack(spacing: 3) {
                        HStack(spacing: 3) {
                            Text(title(t)).lineLimit(1)
                            if count > 0 { Text("\(count)").font(.system(size: 9, weight: .bold)).foregroundStyle(theme.muted) }
                        }
                        .font(.system(size: 12, weight: t == tab ? .bold : .medium, design: .rounded))
                        .foregroundStyle(t == tab ? theme.ink : theme.muted)
                        Capsule().fill(t == tab ? theme.accent : .clear).frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func title(_ t: TasksTab) -> String {
        switch t {
        case .day: TaskFormat.dayLabel(store.selectedDay)
        case .week: "Week"
        case .inbox: "Inbox"
        case .someday: "Someday"
        }
    }

    private func count(_ t: TasksTab) -> Int {
        switch t {
        case .day: return store.openTasks(in: .day(store.selectedDay)).count
        case .week:
            let monday = store.selectedDay.weekStart()
            let days = (try? store.repos.tasks.inRange(monday, monday.adding(days: 6))) ?? []
            return days.filter { $0.status == .open }.count + store.openTasks(in: .week(monday)).count
        case .inbox: return store.openTasks(in: .inbox).count
        case .someday: return store.openTasks(in: .someday).count
        }
    }

    // MARK: Lists

    @ViewBuilder private func content(_ lists: [String: ListItem]) -> some View {
        switch tab {
        case .day:
            let day = store.selectedDay
            let overdue = day == .today() ? ((try? store.repos.tasks.overdue(before: day)) ?? []) : []
            if !overdue.isEmpty {
                TaskSection(title: "Overdue", tint: theme.accent2, placement: nil, tasks: overdue, showDate: true,
                            lists: lists, expanded: $expanded)
            }
            TaskSection(title: TaskFormat.dayLabel(day), placement: .day(day), tasks: store.openTasks(in: .day(day)),
                        contextDay: day, emptyText: "Nothing planned. Add a task above, or drop one here.",
                        lists: lists, expanded: $expanded)
            let done = ((try? store.repos.tasks.forDay(day)) ?? []).filter(\.isDone)
            if !done.isEmpty { doneSection(done, day: day, lists: lists) }
        case .week:
            let monday = store.selectedDay.weekStart()
            ForEach(0..<7, id: \.self) { i in
                let day = monday.adding(days: i)
                TaskSection(title: TaskFormat.dateLabel(day) + (day == .today() ? " · Today" : ""),
                            tint: day == .today() ? theme.accent : nil,
                            placement: .day(day), tasks: store.openTasks(in: .day(day)), contextDay: day,
                            emptyText: "Drop a task here", emptyHeight: 24, lists: lists, expanded: $expanded)
            }
            TaskSection(title: "Anytime this week", placement: .week(monday), tasks: store.openTasks(in: .week(monday)),
                        emptyText: "Tasks for the week with no day yet", emptyHeight: 24, lists: lists, expanded: $expanded)
        case .inbox:
            TaskSection(title: "Inbox", placement: .inbox, tasks: store.openTasks(in: .inbox),
                        emptyText: "Inbox is empty. Tasks with no date land here.", lists: lists, expanded: $expanded)
        case .someday:
            TaskSection(title: "Someday", placement: .someday, tasks: store.openTasks(in: .someday),
                        emptyText: "Ideas for later live here.", lists: lists, expanded: $expanded)
        }
    }

    private func doneSection(_ done: [TaskItem], day: DayKey, lists: [String: ListItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { showDone.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: showDone ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .bold))
                    Text("Done · \(done.count)").font(.system(size: 12, weight: .bold, design: .serif))
                    Spacer()
                }
                .foregroundStyle(theme.muted)
            }
            .buttonStyle(.plain)
            if showDone {
                ForEach(done) { task in
                    TaskRow(task: task, contextDay: day, lists: lists, isExpanded: expanded.contains(task.id),
                            toggleExpanded: { if expanded.contains(task.id) { expanded.remove(task.id) } else { expanded.insert(task.id) } })
                }
            }
        }
    }
}
