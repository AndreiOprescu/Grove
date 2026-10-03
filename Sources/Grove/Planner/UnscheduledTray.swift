import SwiftUI
import GroveCore

/// Open tasks with no block on the chosen day. Drag a row onto the grid, or press Fit.
struct UnscheduledTray: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    let day: DayKey
    let isDropTarget: Bool
    let workStart: Int
    let workEnd: Int
    let snapStep: Int

    var body: some View {
        let _ = store.revision
        let tasks = store.unscheduled(for: day)
        VStack(alignment: .leading, spacing: 8) {
            Text("Unscheduled").themedHeading(theme, 17)
                .foregroundStyle(theme.ink)
            if tasks.isEmpty {
                Text("Nothing waiting. Every open task for this day has a time.")
                    .font(theme.body(12)).foregroundStyle(theme.muted)
            }
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(tasks) { task in row(task) }
                }
            }
            if isDropTarget {
                Label("Release to unschedule", systemImage: "tray.and.arrow.down")
                    .font(theme.body(12, weight: .semibold)).foregroundStyle(theme.accent)
            }
        }
        .padding(12)
        .frame(width: 230)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .panel(border: isDropTarget ? theme.accent : nil, borderWidth: isDropTarget ? 2 : nil)
    }

    private func row(_ task: TaskItem) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(task.title).font(theme.body(12, weight: .semibold)).lineLimit(2)
                    .foregroundStyle(theme.ink)
                Text(PlannerMath.duration(task.estimateMin)).font(theme.body(10))
                    .foregroundStyle(theme.muted)
            }
            Spacer(minLength: 0)
            Button("Fit") {
                store.fit(taskId: task.id, day: day, workStart: workStart, workEnd: workEnd, step: snapStep)
            }
            .buttonStyle(.bordered).controlSize(.small)
            .help("Put this task in the next free gap")
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.surface2))
        .draggable(DragPayload.task(task.id))
        .accessibilityLabel("\(task.title), \(PlannerMath.duration(task.estimateMin)). Drag onto the timeline.")
    }
}
