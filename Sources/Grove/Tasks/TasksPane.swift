import SwiftUI
import GroveCore

/// A task list for the left side of the Today and Planner screens.
/// `.today` is the list of today. `.unscheduled` is the list that feeds the planner: the tasks that are late and the ones with no day.
struct TasksPane: View {
    enum Mode { case today, unscheduled }

    let mode: Mode
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @State private var expanded: Set<String> = []
    @State private var showDone = false

    var body: some View {
        let _ = store.revision
        let lists = Dictionary(uniqueKeysWithValues: ((try? store.repos.lists.all(includeArchived: true)) ?? []).map { ($0.id, $0) })
        let waiting = mode == .unscheduled ? store.unscheduledTasks() : nil
        VStack(alignment: .leading, spacing: 10) {
            switch mode {
            case .today:
                todayHeader(store.plantProgress(on: .today()))
                QuickAddField(placement: .day(.today()), placementLabel: TaskFormat.dayLabel(.today()))
            case .unscheduled:
                unscheduledHeader(count: (waiting?.overdue.count ?? 0) + (waiting?.unscheduled.count ?? 0))
                QuickAddField(placement: .inbox, placementLabel: "Unscheduled")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch mode {
                    case .today:
                        if store.welcomeVisible { WelcomeCard() }
                        let yesterday = store.rollOverItems()
                        if !yesterday.isEmpty { RollOverCard(items: yesterday) }
                        todayContent(lists)
                    case .unscheduled:
                        if let waiting { unscheduledContent(waiting, lists) }
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .panel()
    }

    /// "Tasks", how many of today are done, and a bar for it.
    private func todayHeader(_ progress: PlantProgress) -> some View {
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

    private func unscheduledHeader(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Tasks").themedHeading(theme, 20, weight: .semibold).foregroundStyle(theme.ink)
            Spacer()
            Text(count == 0 ? "Nothing waiting" : "\(count) waiting")
                .font(theme.body(11)).foregroundStyle(theme.muted)
        }
    }

    // MARK: Lists

    /// Today's open tasks, then the ones checked off today. The late ones are in the Tasks panel.
    @ViewBuilder private func todayContent(_ lists: [String: ListItem]) -> some View {
        let day = DayKey.today()
        TaskSection(title: TaskFormat.dayLabel(day), placement: .day(day), tasks: store.openTasks(in: .day(day)),
                    contextDay: day, emptyText: "Nothing planned. Add a task above, or drop one here.",
                    lists: lists, expanded: $expanded)
        let done = ((try? store.repos.tasks.forDay(day)) ?? []).filter { $0.isDone && !store.lingering.contains($0.id) }
        if !done.isEmpty { doneSection(done, day: day, lists: lists) }
    }

    /// The late tasks, then the tasks with no day. The order comes from the plan, so these lists take no drops and cannot be reordered.
    /// Rows can still be dragged to the planner. Below them: the tasks checked off today, so a slip can be undone.
    @ViewBuilder private func unscheduledContent(_ waiting: (overdue: [TaskItem], unscheduled: [TaskItem]),
                                                 _ lists: [String: ListItem]) -> some View {
        if !waiting.overdue.isEmpty {
            TaskSection(title: "Overdue", tint: theme.accent2, placement: nil, tasks: waiting.overdue, showDate: true,
                        lists: lists, expanded: $expanded)
        }
        TaskSection(title: "Unscheduled", placement: nil, tasks: waiting.unscheduled, showDate: true,
                    emptyText: "Nothing waiting. Every task has a day.", lists: lists, expanded: $expanded)
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
