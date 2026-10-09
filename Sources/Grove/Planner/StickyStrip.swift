import SwiftUI
import GroveCore

/// The strip under the day numbers: each day's open tasks that have no time yet, as sticky notes.
/// Drag a note onto the grid to give it a time. Drag a task block up here to take its time away.
/// Drop a task from a list on a day to plan it for that day with no time.
struct StickyStrip: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    let days: [DayKey]
    let gutterWidth: CGFloat
    /// A task block is dragged over the strip. Letting go unschedules it.
    let isDropTarget: Bool
    let workStart: Int
    let workEnd: Int

    @AppStorage("planner.stickyOpen") private var open = true
    @State private var contentHeight: CGFloat = 0
    @State private var width: CGFloat = 800
    @State private var targeted: DayKey?

    private var cellWidth: CGFloat { max(60, (width - gutterWidth) / CGFloat(max(days.count, 1))) }

    var body: some View {
        let _ = store.revision
        let notes = store.timeless(for: days)
        let total = notes.values.reduce(0) { $0 + $1.count }
        let expanded = open && total > 0
        // The notes are drawn in an overlay on purpose, like the grid's layers. A long title wants a wide note,
        // and as normal content that would make the whole planner ask for more width. This base only takes what it is offered.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: expanded ? StickyRules.stripHeight(content: contentHeight) : StickyRules.foldedHeight)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { w in
                if abs(w - width) > 0.5 { width = w }
            }
            .overlay(alignment: .topLeading) {
                HStack(alignment: .top, spacing: 0) {
                    foldButton(total)
                    if expanded {
                        ScrollView(.vertical) {
                            cells(notes, expanded: true)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                        }
                    } else {
                        cells(notes, expanded: false)
                            .overlay {
                                if total == 0 {
                                    Text("Tasks with no time land here")
                                        .font(theme.body(11)).foregroundStyle(theme.muted)
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                }
            }
        .background(theme.accent.opacity(isDropTarget ? 0.10 : 0))
        .overlay {
            if isDropTarget {
                ZStack {
                    Rectangle().strokeBorder(theme.accent, lineWidth: 2)
                    Label("Release to unschedule", systemImage: "tray.and.arrow.down")
                        .font(theme.body(12, weight: .semibold)).foregroundStyle(theme.bg)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(theme.accent))
                }
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
    }

    private func foldButton(_ total: Int) -> some View {
        Button { open.toggle() } label: {
            HStack(spacing: 3) {
                Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .bold))
                Text("\(total)").font(theme.number(11, weight: .bold))
            }
            .foregroundStyle(total > 0 ? theme.ink : theme.muted)
            .frame(width: gutterWidth, height: StickyRules.foldedHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(open ? "Hide the tasks with no time" : "Show the tasks with no time")
        .accessibilityLabel("\(total) task\(total == 1 ? "" : "s") with no time. \(open ? "Hide" : "Show")")
    }

    private func cells(_ notes: [DayKey: [TaskItem]], expanded: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element) { index, day in
                cell(day, notes[day] ?? [], expanded: expanded)
                    .overlay(alignment: .leading) {
                        if index > 0 { Rectangle().fill(theme.line).frame(width: 1) }   // the same column lines as the grid
                    }
            }
        }
        // Every day is as tall as the fullest day, so the column lines and the drop areas reach the bottom.
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func cell(_ day: DayKey, _ tasks: [TaskItem], expanded: Bool) -> some View {
        Group {
            if expanded {
                let columns = Array(repeating: GridItem(.flexible(), spacing: StickyRules.spacing, alignment: .top),
                                    count: StickyRules.columns(cellWidth: cellWidth))
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(tasks) { StickyNote(task: $0, day: day, workStart: workStart, workEnd: workEnd) }
                }
                .padding(StickyRules.spacing)
            } else if !tasks.isEmpty {
                Text("\(tasks.count) with no time")
                    .font(theme.body(11)).foregroundStyle(theme.muted).lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(height: StickyRules.foldedHeight)
            } else {
                Color.clear.frame(height: StickyRules.foldedHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.accent.opacity(targeted == day ? 0.10 : 0))
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, raw.hasPrefix(DragPayload.taskPrefix) else { return false }
            store.dropTask(String(raw.dropFirst(DragPayload.taskPrefix.count)), on: day)
            return true
        } isTargeted: { on in
            if on { targeted = day } else if targeted == day { targeted = nil }
        }
    }
}

/// One task with no time, drawn as a sticky note. Click opens the task. Drag it onto the grid to give it a time.
private struct StickyNote: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    let task: TaskItem
    let day: DayKey
    let workStart: Int
    let workEnd: Int

    var body: some View {
        let tint = [theme.accent, theme.accent2, theme.accent3][StickyRules.colorIndex(for: task.id)]
        let length = PlannerMath.duration(PlannerMath.blockLength(task.estimateMin))
        VStack(alignment: .leading, spacing: 4) {
            Text(task.title)
                .font(theme.body(12, weight: .semibold)).foregroundStyle(theme.ink)
                .lineLimit(3).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Text(length).font(theme.body(10)).foregroundStyle(theme.muted)
                Spacer(minLength: 0)
                Button {
                    store.fit(taskId: task.id, day: day, workStart: workStart, workEnd: workEnd, step: PlannerMath.step)
                } label: {
                    Image(systemName: "arrow.down.to.line").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(tint)
                .help("Put this task in the next free gap")
                .accessibilityLabel("Fit \(task.title) in the next free gap")
            }
        }
        .padding(.horizontal, 8).padding(.top, 11).padding(.bottom, 6)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .background(paper(tint))
        .overlay {
            if store.selectedTaskId == task.id {
                Rectangle().strokeBorder(theme.accent, lineWidth: 1.5)
            }
        }
        .rotationEffect(.degrees(StickyRules.tilt(for: task.id)))
        .contentShape(Rectangle())
        .onTapGesture { store.selectedTaskId = store.selectedTaskId == task.id ? nil : task.id }
        .contextMenu {
            Button(task.isDone ? "Mark Not Done" : "Mark Done") { store.toggleDone(taskId: task.id) }
            Button("Fit in Next Gap") {
                store.fit(taskId: task.id, day: day, workStart: workStart, workEnd: workEnd, step: PlannerMath.step)
            }
            Divider()
            Button("Delete Task", role: .destructive) { store.deleteTask(task.id) }
        }
        .draggable(DragPayload.task(task.id))
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Delete task") { store.deleteTask(task.id) }
        .accessibilityLabel("\(task.title), \(length), no time yet. Drag onto the timeline.")
    }

    /// Square paper in the note's colour, a darker band of glue on top, and a soft shadow.
    private func paper(_ tint: Color) -> some View {
        ZStack(alignment: .top) {
            Rectangle().fill(theme.surface)
            Rectangle().fill(tint.opacity(0.22))
            Rectangle().fill(tint.opacity(0.32)).frame(height: 7)
        }
        .shadow(color: .black.opacity(0.14), radius: 3, x: 0, y: 2)
    }
}
