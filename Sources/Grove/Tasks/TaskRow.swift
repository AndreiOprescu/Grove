import SwiftUI
import GroveCore

/// One task in the list: check box, title, small labels, and its subtasks when opened.
/// Drag it onto the planner to give it a time, or onto another row to put it there.
struct TaskRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let task: TaskItem
    /// The day this list stands for. Picks which time block to show.
    var contextDay: DayKey?
    /// Show the planned date as a label (used in the overdue list).
    var showDate = false
    let lists: [String: ListItem]
    let isExpanded: Bool
    let toggleExpanded: () -> Void
    /// Called with what was dropped on this row. Nil means the row takes no drops.
    var onDrop: (([String]) -> Bool)?

    @State private var renaming = false
    @State private var draft = ""
    @State private var targeted = false
    @State private var newSubtask = ""
    @FocusState private var renameFocus: Bool
    @FocusState private var subtaskFocus: Bool

    var body: some View {
        let _ = store.revision
        let subtasks = store.subtasks(of: task.id)
        let selected = store.selectedTaskId == task.id
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                checkbox(task)
                VStack(alignment: .leading, spacing: 4) {
                    titleView
                    if !task.isDone { labels }
                }
                Spacer(minLength: 0)
                if !subtasks.isEmpty || isExpanded { subtaskToggle(subtasks) }
            }
            if isExpanded { subtaskList(subtasks) }
        }
        .padding(.vertical, 8).padding(.leading, 12).padding(.trailing, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.surface2))
        .overlay(alignment: .leading) {
            if let color = TaskFormat.priorityColor(task.priority, theme), !task.isDone {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3).padding(.vertical, 6).padding(.leading, 3)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(selected ? theme.accent : .clear, lineWidth: 1.5))
        .overlay(alignment: .top) {
            if targeted { Capsule().fill(theme.accent).frame(height: 3).offset(y: -3) }
        }
        .contentShape(Rectangle())
        .onTapGesture { store.selectedTaskId = selected ? nil : task.id }
        .draggable(DragPayload.task(task.id))
        .dropDestination(for: String.self) { items, _ in onDrop?(items) ?? false } isTargeted: { targeted = $0 && onDrop != nil }
        .contextMenu { menu(subtasks) }
        .accessibilityElement(children: .contain)
    }

    private var motionOn: Bool { MotionRules.isOn(setting: store.motionSetting, reduceMotion: reduceMotion) }

    // MARK: Pieces

    private func checkbox(_ t: TaskItem) -> some View {
        Button { store.toggleDone(taskId: t.id, linger: motionOn) } label: {
            CheckBox(isOn: t.isDone, size: 17)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t.isDone ? "Mark \(t.title) as not done" : "Mark \(t.title) as done")
    }

    @ViewBuilder private var titleView: some View {
        if renaming {
            TextField("Title", text: $draft)
                .textFieldStyle(.plain)
                .font(theme.body(13, weight: .semibold))
                .focused($renameFocus)
                .onSubmit { commitRename() }
                .onExitCommand { renaming = false }
                .onChange(of: renameFocus) { _, now in if !now { commitRename() } }
        } else {
            Text(task.title)
                .font(theme.body(13, weight: .semibold))
                .strikethrough(task.isDone)
                .foregroundStyle(task.isDone ? theme.muted : theme.ink)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
    }

    private var labels: some View {
        let tags = store.tagNames(of: task.id)
        let blocks = store.blocks(ofTask: task.id).sorted { $0.start < $1.start }
        let shown = blocks.first { $0.start.day == contextDay } ?? blocks.first
        let now = store.nowMinute()
        return FlowLayout(spacing: 4) {
            if showDate, let d = task.planDate { Chip(text: TaskFormat.dayLabel(d), symbol: "calendar", tint: theme.accent2) }
            if let shown {
                let more = blocks.count - 1
                Chip(text: PlannerMath.clock(shown.start.minute) + "–" + PlannerMath.clock(shown.end.minute) + (more > 0 ? " +\(more)" : ""),
                     symbol: "clock", tint: theme.accent)
            } else if task.estimateMin != 30 {
                Chip(text: PlannerMath.duration(task.estimateMin), symbol: "hourglass")
            }
            if let due = task.due {
                let d = TaskFormat.due(due, nowMinute: now)
                Chip(text: d.text, symbol: "flag", tint: d.late ? theme.accent2 : nil)
            }
            if task.recurrence != nil { Chip(text: "Repeats", symbol: "repeat") }
            if let l = task.listId.flatMap({ lists[$0] }) { Chip(text: l.name, symbol: "folder") }
            if !task.notes.isEmpty { Chip(text: "Notes", symbol: "text.alignleft") }
            ForEach(tags, id: \.self) { Chip(text: "#" + $0) }
        }
    }

    private func subtaskToggle(_ subtasks: [TaskItem]) -> some View {
        Button(action: toggleExpanded) {
            HStack(spacing: 3) {
                if !subtasks.isEmpty {
                    Text("\(subtasks.filter(\.isDone).count)/\(subtasks.count)")
                        .font(theme.body(10, weight: .semibold))
                }
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(theme.muted)
            .padding(.top, 3)
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Hide subtasks" : "Show subtasks")
    }

    private func subtaskList(_ subtasks: [TaskItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(subtasks) { sub in
                HStack(spacing: 6) {
                    checkbox(sub).scaleEffect(0.85)
                    Text(sub.title)
                        .font(theme.body(12))
                        .strikethrough(sub.isDone)
                        .foregroundStyle(sub.isDone ? theme.muted : theme.ink)
                    Spacer(minLength: 0)
                }
                .contextMenu { Button("Delete Subtask", role: .destructive) { store.deleteTask(sub.id) } }
            }
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(theme.muted).frame(width: 17)
                TextField("Add a subtask", text: $newSubtask)
                    .textFieldStyle(.plain)
                    .font(theme.body(12))
                    .focused($subtaskFocus)
                    .onSubmit {
                        store.addSubtask(to: task.id, title: newSubtask)
                        newSubtask = ""
                        subtaskFocus = true
                    }
            }
        }
        .padding(.leading, 25)
    }

    // MARK: Menu and actions

    @ViewBuilder private func menu(_ subtasks: [TaskItem]) -> some View {
        Button(task.isDone ? "Mark Not Done" : "Mark Done") { store.toggleDone(taskId: task.id) }
        Divider()
        Menu("Move To") {
            Button("Today") { store.moveTask(task.id, to: .day(.today())) }
            Button("Tomorrow") { store.moveTask(task.id, to: .day(.today().adding(days: 1))) }
            Button("This Week") { store.moveTask(task.id, to: .week(.today())) }
            Button("Next Week") { store.moveTask(task.id, to: .week(.today().weekStart().adding(days: 7))) }
            Divider()
            Button("Inbox") { store.moveTask(task.id, to: .inbox) }
            Button("Someday") { store.moveTask(task.id, to: .someday) }
        }
        Menu("Priority") {
            ForEach([(0, "None"), (1, "Low"), (2, "Medium"), (3, "High")], id: \.0) { value, name in
                Button((task.priority == value ? "✓ " : "") + name) {
                    store.editTask(task.id, name: "Set Priority") { $0.priority = value }
                }
            }
        }
        Button("Add Subtask") { if !isExpanded { toggleExpanded() }; subtaskFocus = true }
        Button("Rename") { draft = task.title; renaming = true; renameFocus = true }
        Divider()
        Button("Delete", role: .destructive) { store.deleteTask(task.id) }
    }

    private func commitRename() {
        guard renaming else { return }
        renaming = false
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { store.editTask(task.id, name: "Rename Task") { $0.title = name } }
    }
}
