import SwiftUI
import AppKit
import GroveCore

/// The panel on the right for the selected task: title, rich body, plan, tags, subtasks, links.
struct TaskInspector: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    let taskId: String

    // What the fields show. The store is only written when the user changes something.
    @State private var title = ""
    @State private var summary = ""
    @State private var notes = ""
    @State private var loadedId: String?
    /// True from the first key typed in the body until the body loses the keyboard.
    @State private var typing = false
    @State private var saveTask: Task<Void, Never>?
    @State private var summaryTask: Task<Void, Never>?
    @State private var chipToken = 0
    @State private var newSubtask = ""
    /// Subtasks whose description and length are showing.
    @State private var openSubtasks: Set<String> = []
    @State private var newTag = ""
    @FocusState private var titleFocus: Bool
    @FocusState private var summaryFocus: Bool

    var body: some View {
        let _ = store.revision
        Group {
            if let task = store.task(taskId) {
                content(task)
            } else {
                Text("This task is gone.").foregroundStyle(theme.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 340)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .panel()
        .onAppear { load(taskId) }
        .onChange(of: taskId) { old, new in
            flush(old)
            load(new)
        }
        .onChange(of: store.revision) { _, _ in
            if !typing { chipToken += 1 }
            if !typing, !titleFocus, let t = store.task(taskId) {
                if t.notes != notes { notes = t.notes }
                if t.title != title { title = t.title }
            }
            if !summaryFocus, let t = store.task(taskId), t.summary != SummaryText.clean(summary) { summary = t.summary }
        }
        .onDisappear { flush(taskId) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in flush(taskId) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in flush(taskId) }
    }

    // MARK: Loading and saving

    private func load(_ id: String) {
        guard let t = store.task(id) else { return }
        title = t.title
        summary = t.summary
        notes = t.notes
        typing = false
        loadedId = id
        newSubtask = ""
        openSubtasks = []
        newTag = ""
    }

    /// Writes any unsaved title and body of task `id` now.
    private func flush(_ id: String) {
        saveTask?.cancel()
        saveTask = nil
        summaryTask?.cancel()
        summaryTask = nil
        guard loadedId == id, let t = store.task(id) else { return }
        if SummaryText.clean(summary) != t.summary { store.setSummary(id, summary) }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, name != t.title { store.editTask(id, name: "Rename Task") { $0.title = name } }
        if notes != t.notes { store.setNotes(id, notes) }
    }

    private func scheduleSave() {
        let id = taskId
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            if loadedId == id { store.setNotes(id, notes) }
        }
    }


    private func summaryChanged(_ text: String) {
        if text.contains(where: \.isNewline) {   // Return ends the line
            summary = text.filter { !$0.isNewline }
            commitSummary()
            return
        }
        if text.count > SummaryText.maxLength {
            summary = String(text.prefix(SummaryText.maxLength))
            return
        }
        let id = taskId
        summaryTask?.cancel()
        summaryTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            if loadedId == id { store.setSummary(id, summary) }
        }
    }

    private func commitSummary() {
        summaryTask?.cancel()
        summaryTask = nil
        if loadedId == taskId { store.setSummary(taskId, summary) }
    }

    private func bodyEnded() {
        flush(taskId)
        typing = false
        if let t = store.task(taskId), t.notes != notes { notes = t.notes }   // the saved text has the ids added
        chipToken += 1
    }

    private func commitTitle() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { title = store.task(taskId)?.title ?? title; return }
        store.editTask(taskId, name: "Rename Task") { $0.title = name }
    }

    // MARK: Content

    private func content(_ task: TaskItem) -> some View {
        let lists = (try? store.repos.lists.all()) ?? []
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(task)
                section("Short description") { summaryField }
                section("Description") {
                    RichTextField(text: Binding(get: { notes }, set: { notes = $0; typing = true; scheduleSave() }),
                                  services: store.editorServices(excluding: ItemRef(.task, taskId)),
                                  placeholder: "The longer description. Type [[ to mention a task.",
                                  minHeight: 90, refreshToken: chipToken, onEnd: bodyEnded)
                        .id(taskId)
                }
                plan(task)
                details(task, lists: lists)
                tags(task)
                subtasks(task)
                links(task)
            }
            .padding(14)
        }
        .scrollIndicators(.hidden)
    }

    private func header(_ task: TaskItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button { store.toggleDone(taskId: task.id) } label: {
                CheckBox(isOn: task.isDone, size: 20)
            }
            .buttonStyle(.plain)
            .help(task.isDone ? "Mark as not done" : "Mark as done")
            .accessibilityLabel(task.isDone ? "Mark as not done" : "Mark as done")

            TextField("Title", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(theme.heading(16, weight: .semibold))
                .strikethrough(task.isDone)
                .lineLimit(1...4)
                .focused($titleFocus)
                .onSubmit { commitTitle() }
                .onChange(of: titleFocus) { _, now in if !now { commitTitle() } }

            Button { store.selectedTaskId = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(theme.muted).help("Close  (Esc)").accessibilityLabel("Close")
                .keyboardShortcut(.cancelAction)
        }
    }


    private var summaryField: some View {
        TextField("One short line. It shows on the planner.", text: $summary, axis: .vertical)
            .textFieldStyle(.plain)
            .font(theme.body(13))
            .lineLimit(1...3)
            .focused($summaryFocus)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.surface2))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(summaryFocus ? theme.accent : theme.line, lineWidth: 1))
            .onChange(of: summary) { _, new in summaryChanged(new) }
            .onSubmit { commitSummary() }
            .onChange(of: summaryFocus) { _, now in if !now { commitSummary() } }
    }

    // MARK: Plan

    private func plan(_ task: TaskItem) -> some View {
        let date = task.planDate ?? task.planWeek ?? store.selectedDay
        return section("Plan") {
            HStack(spacing: 8) {
                Picker("", selection: Binding(
                    get: { task.bucket },
                    set: { store.moveTask(task.id, to: InspectorOptions.placement(bucket: $0, date: date)) })) {
                    Text("Inbox").tag(TaskBucket.inbox)
                    Text("Day").tag(TaskBucket.day)
                    Text("Week").tag(TaskBucket.week)
                    Text("Someday").tag(TaskBucket.someday)
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            if task.bucket == .day || task.bucket == .week {
                HStack {
                    Text(task.bucket == .day ? "Day" : "Week of").foregroundStyle(theme.muted)
                    Spacer()
                    DatePicker("", selection: Binding(
                        get: { date.date },
                        set: { store.moveTask(task.id, to: InspectorOptions.placement(bucket: task.bucket, date: DayKey($0))) }),
                               displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.compact)
                }
                .font(theme.body(12))
            }
        }
    }

    private func details(_ task: TaskItem, lists: [ListItem]) -> some View {
        section("Details") {
            row("Priority") {
                Picker("", selection: Binding(get: { task.priority }, set: { p in store.editTask(task.id, name: "Set Priority") { $0.priority = p } })) {
                    Text("None").tag(0)
                    Text("Low").tag(1)
                    Text("Med").tag(2)
                    Text("High").tag(3)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 190)
            }
            row("Colour") { colourPicker(task) }
            row("Takes") {
                Picker("", selection: Binding(get: { task.estimateMin }, set: { m in store.editTask(task.id, name: "Set Length") { $0.estimateMin = m } })) {
                    ForEach(InspectorOptions.estimates(including: task.estimateMin), id: \.self) { Text(PlannerMath.duration($0)).tag($0) }
                }
                .labelsHidden().frame(width: 120)
            }
            row("Due") {
                if let day = InspectorOptions.dueDay(task.due) {
                    DatePicker("", selection: Binding(
                        get: { day.date },
                        set: { d in store.editTask(task.id, name: "Set Due Date") { $0.due = InspectorOptions.dueString(day: DayKey(d), keepingTimeOf: $0.due) } }),
                               displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.compact)
                    Button { store.editTask(task.id, name: "Clear Due Date") { $0.due = nil } } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(theme.muted).help("Remove the due date").accessibilityLabel("Remove the due date")
                } else {
                    Button("Add a due date") { store.editTask(task.id, name: "Set Due Date") { $0.due = (task.planDate ?? store.selectedDay).string } }
                        .buttonStyle(.plain).foregroundStyle(theme.accent)
                }
            }
            row("Repeat") {
                let current = RepeatPreset.of(task.recurrence)
                Picker("", selection: Binding(get: { current }, set: { p in
                    guard p != .custom else { return }
                    store.editTask(task.id, name: "Set Repeat") { $0.recurrence = p.rule }
                })) {
                    ForEach(RepeatPreset.allCases.filter { $0 != .custom || current == .custom }) { Text($0.label).tag($0) }
                }
                .labelsHidden().frame(width: 150)
            }
            row("List") {
                Picker("", selection: Binding(get: { task.listId ?? "" }, set: { id in store.editTask(task.id, name: "Set List") { $0.listId = id.isEmpty ? nil : id } })) {
                    Text("No list").tag("")
                    ForEach(lists) { Text(($0.emoji.isEmpty ? "" : $0.emoji + " ") + $0.name).tag($0.id) }
                }
                .labelsHidden().frame(width: 150)
            }
        }
    }

    // MARK: Tags

    private func tags(_ task: TaskItem) -> some View {
        let names = store.tagNames(of: task.id)
        return section("Tags") {
            FlowLayout(spacing: 4) {
                ForEach(names, id: \.self) { name in
                    HStack(spacing: 3) {
                        Text("#" + name)
                        Button { store.setTags(taskId: task.id, to: names.filter { $0 != name }) } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).help("Remove this tag").accessibilityLabel("Remove tag \(name)")
                    }
                    .font(theme.body(11, weight: .medium))
                    .foregroundStyle(theme.accent2)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .chipBackground(theme.accent2)
                }
            }
            TextField("Add a tag", text: $newTag)
                .textFieldStyle(.plain).font(theme.body(12))
                .onSubmit {
                    store.setTags(taskId: task.id, to: names + [newTag])
                    newTag = ""
                }
        }
    }

    // MARK: Subtasks

    private func subtasks(_ task: TaskItem) -> some View {
        let subs = store.subtasks(of: task.id)
        return section(SubtaskRules.header(subs)) {
            ForEach(subs) { sub in
                SubtaskRow(sub: sub, expanded: openSubtasks.contains(sub.id)) {
                    if openSubtasks.contains(sub.id) { openSubtasks.remove(sub.id) } else { openSubtasks.insert(sub.id) }
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "plus").foregroundStyle(theme.muted)
                TextField("Add a subtask", text: $newSubtask)
                    .textFieldStyle(.plain)
                    .onSubmit { addSubtask(to: task.id) }
            }
            .font(theme.body(12))
        }
    }

    /// Adds the typed subtask. It opens at once, and the others close, so its description and length can be set.
    private func addSubtask(to id: String) {
        guard let new = store.addSubtask(to: id, title: newSubtask) else { return }
        newSubtask = ""
        openSubtasks = [new]
    }

    // MARK: Links

    @ViewBuilder private func links(_ task: TaskItem) -> some View {
        let here = (try? store.repos.links.backlinks(to: ItemRef(.task, task.id))) ?? []
        let source = task.sourceNoteId.flatMap { try? store.repos.notes.get($0) }
        if !here.isEmpty || source != nil {
            section("Linked here") {
                if let source {
                    linkRow(icon: "note.text", text: "Created from note “\(source.title)”") { store.open(ItemRef(.note, source.id)) }
                }
                ForEach(here, id: \.self) { ref in
                    if let target = try? store.repos.refs.resolve(title: "", id: ref.id) {
                        linkRow(icon: icon(ref.type), text: target.title) { store.open(ref) }
                    }
                }
            }
        }
    }

    private func linkRow(icon: String, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(theme.accent)
                Text(text).foregroundStyle(theme.ink).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(theme.body(12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func icon(_ type: ItemType) -> String {
        switch type {
        case .task: "checkmark.circle"
        case .note: "note.text"
        case .event: "calendar"
        }
    }

    // MARK: Pieces

    /// None, then the eight colours. The chosen one has a ring.
    private func colourPicker(_ task: TaskItem) -> some View {
        HStack(spacing: 6) {
            Button { store.setTaskColor(task.id, "") } label: {
                Image(systemName: "circle.slash").font(.system(size: 15))
                    .foregroundStyle(task.color.isEmpty ? theme.ink : theme.muted)
            }
            .buttonStyle(.plain).help("No colour").accessibilityLabel("No colour")
            ForEach(TaskColor.names, id: \.self) { name in
                Button { store.setTaskColor(task.id, name) } label: {
                    Circle().fill(TaskPalette.color(named: name) ?? theme.muted).frame(width: 15, height: 15)
                        .overlay(Circle().strokeBorder(theme.ink, lineWidth: task.color == name ? 2 : 0).padding(-3))
                }
                .buttonStyle(.plain).help(name.capitalized).accessibilityLabel("Colour \(name)")
                .accessibilityAddTraits(task.color == name ? .isSelected : [])
            }
        }
    }

    private func section<Content: View>(_ name: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name).themedHeading(theme, 12, weight: .bold).foregroundStyle(theme.ink)
            content()
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label).foregroundStyle(theme.muted).frame(width: 56, alignment: .leading)
            Spacer(minLength: 0)
            content()
        }
        .font(theme.body(12))
    }
}
