import SwiftUI
import GroveCore

/// A titled group of task rows. Drop a task on the header, the empty area or the end of the list to put it last.
struct TaskSection: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    var tint: Color?
    /// Where dropped tasks go. Nil means this list takes no drops (for example, overdue).
    let placement: TaskPlacement?
    let tasks: [TaskItem]
    var contextDay: DayKey?
    var showDate = false
    var emptyText = "Nothing here."
    var emptyHeight: CGFloat = 34
    let lists: [String: ListItem]
    @Binding var expanded: Set<String>
    @State private var zoneTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title).themedHeading(theme, 12, weight: .bold).foregroundStyle(tint ?? theme.ink)
                if !tasks.isEmpty {
                    Text("\(tasks.count)").font(theme.body(10, weight: .semibold)).foregroundStyle(theme.muted)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 18)
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { items, _ in drop(items, before: nil) } isTargeted: { zoneTargeted = $0 && placement != nil }

            if tasks.isEmpty {
                Text(emptyText)
                    .font(theme.body(11)).foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity, minHeight: emptyHeight)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(zoneTargeted ? theme.accent : theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .contentShape(Rectangle())
                    .dropDestination(for: String.self) { items, _ in drop(items, before: nil) } isTargeted: { zoneTargeted = $0 && placement != nil }
            } else {
                ForEach(tasks) { task in
                    TaskRow(task: task, contextDay: contextDay, showDate: showDate, lists: lists,
                            isExpanded: expanded.contains(task.id),
                            toggleExpanded: { toggle(task.id) },
                            onDrop: placement == nil ? nil : { drop($0, before: task.id) })
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                // the end of the list: a thin strip that takes drops
                Rectangle().fill(.clear).frame(height: 10)
                    .contentShape(Rectangle())
                    .dropDestination(for: String.self) { items, _ in drop(items, before: nil) } isTargeted: { zoneTargeted = $0 && placement != nil }
                    .overlay(alignment: .top) { if zoneTargeted { Capsule().fill(theme.accent).frame(height: 3) } }
            }
        }
        .animation(MotionRules.isOn(setting: store.motionSetting, reduceMotion: reduceMotion) ? .smooth(duration: 0.25) : nil,
                   value: tasks.map(\.id))
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    private func drop(_ items: [String], before: String?) -> Bool {
        guard let placement, let raw = items.first, raw.hasPrefix(DragPayload.taskPrefix) else { return false }
        let id = String(raw.dropFirst(DragPayload.taskPrefix.count))
        guard id != before else { return true }
        store.moveTask(id, to: placement, before: before)
        return true
    }
}
