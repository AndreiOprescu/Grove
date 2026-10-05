import SwiftUI
import GroveCore

enum TasksTab: String, CaseIterable, Identifiable {
    case day, week, inbox, someday
    var id: String { rawValue }
}

/// The task list next to the planner. Tabs: the chosen day, the week, the inbox, someday.
/// On the Planner screen it has no tabs and lists every open task (`allTasks`).
struct TasksPane: View {
    /// In the Day Spread the pane is a column that takes the width it is given.
    /// The greeting and the plant are in the page header there, so the pane shows a progress bar instead.
    var spread = false
    /// Every open task in one list: the ones with no day yet on top, then the rest by day, earliest first.
    var allTasks = false
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("shell.tasksOpen") private var open = true
    @AppStorage("tasks.tab") private var tabRaw = TasksTab.day.rawValue
    @State private var expanded: Set<String> = []
    @State private var showDone = false

    private var tab: TasksTab { TasksTab(rawValue: tabRaw) ?? .day }

    var body: some View {
        let _ = store.revision
        let today = store.plantProgress(on: .today())
        let lists = Dictionary(uniqueKeysWithValues: ((try? store.repos.lists.all(includeArchived: true)) ?? []).map { ($0.id, $0) })
        VStack(alignment: .leading, spacing: 10) {
            if spread {
                spreadHeader(store.plantProgress(on: store.selectedDay))
            } else {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Tasks").themedHeading(theme, 20, weight: .semibold).foregroundStyle(theme.ink)
                        Text("\(Greeting.now()) · \(today.growthText)")
                            .font(theme.body(11)).foregroundStyle(theme.muted).lineLimit(1)
                    }
                    Spacer()
                    GrowingPlant(progress: today, height: 38)
                    Button { open = false } label: { Image(systemName: "sidebar.left") }
                        .buttonStyle(.plain).foregroundStyle(theme.muted).help("Hide the task list")
                }
            }
            QuickAddField(placement: allTasks ? .inbox : defaultPlacement, placementLabel: allTasks ? "Inbox" : defaultLabel)
            if !allTasks { tabBar }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if store.welcomeVisible { WelcomeCard() }
                    if !allTasks, store.selectedDay == .today() {
                        let yesterday = store.rollOverItems()
                        if !yesterday.isEmpty { RollOverCard(items: yesterday) }
                    }
                    if allTasks { allContent(lists) } else { content(lists) }
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            NotesTray()
        }
        .padding(12)
        .frame(width: spread ? nil : 320)
        .frame(maxWidth: spread ? .infinity : nil, maxHeight: .infinity, alignment: .topLeading)
        .panel()
    }

    /// "Tasks", how many of the chosen day are done, and a bar for it.
    private func spreadHeader(_ progress: PlantProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tasks").themedHeading(theme, 20, weight: .semibold).foregroundStyle(theme.ink)
                Spacer()
                Text(progress.total == 0 ? "Nothing planned" : "\(progress.done) of \(progress.total) done")
                    .font(theme.body(11)).foregroundStyle(theme.muted)
            }
            ProgressBar(fraction: progress.fraction)
        }
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
            let done = ((try? store.repos.tasks.forDay(day)) ?? []).filter { $0.isDone && !store.lingering.contains($0.id) }
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

    /// Every open task. The order comes from the plan, so these lists take no drops and cannot be reordered.
    /// Rows can still be dragged to the planner. Below them: the tasks checked off today, so a slip can be undone.
    @ViewBuilder private func allContent(_ lists: [String: ListItem]) -> some View {
        let all = store.allOpenTasks()
        TaskSection(title: "No day yet", placement: nil, tasks: all.noDay, showDate: true,
                    emptyText: "Every task has a day", lists: lists, expanded: $expanded)
        TaskSection(title: "By day", placement: nil, tasks: all.byDay, showDate: true,
                    emptyText: "No open tasks with a day", lists: lists, expanded: $expanded)
        let done = ((try? store.repos.tasks.completed(on: .today())) ?? [])
            .filter { $0.parentId == nil && !store.lingering.contains($0.id) }
        if !done.isEmpty { doneSection(done, title: "Done today", day: .today(), lists: lists) }
    }

    private func doneSection(_ done: [TaskItem], title: String = "Done", day: DayKey, lists: [String: ListItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { showDone.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: showDone ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .bold))
                    Text("\(title) · \(done.count)").themedHeading(theme, 12, weight: .bold)
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

/// A thin bar. The filled part is `fraction` of it.
struct ProgressBar: View {
    @Environment(\.theme) private var theme
    let fraction: Double

    var body: some View {
        Capsule().fill(theme.surface2)
            .overlay(alignment: .leading) {
                GeometryReader { g in
                    Capsule().fill(theme.accent).frame(width: g.size.width * min(1, max(0, fraction)))
                }
            }
            .frame(height: 6)
            .accessibilityElement()
            .accessibilityLabel("Progress")
            .accessibilityValue("\(Int((min(1, max(0, fraction)) * 100).rounded())) percent")
    }
}
