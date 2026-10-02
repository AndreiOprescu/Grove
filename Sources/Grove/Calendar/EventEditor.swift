import SwiftUI
import GroveCore

extension View {
    /// Shows the event editor as a popover on this view while the store's editing event has this anchor.
    func eventEditor(anchor: String, edge: Edge = .bottom) -> some View {
        modifier(EventEditorAnchor(anchor: anchor, edge: edge))
    }
}

private struct EventEditorAnchor: ViewModifier {
    @Environment(AppStore.self) private var store
    let anchor: String
    let edge: Edge

    func body(content: Content) -> some View {
        content.popover(
            isPresented: Binding(
                get: { store.editingEvent?.anchor == anchor },
                set: { if !$0, store.editingEvent?.anchor == anchor { store.closeEditor() } }),
            arrowEdge: edge
        ) {
            if let editing = store.editingEvent, editing.anchor == anchor { EventEditor(editing: editing) }
        }
    }
}

/// The popover to make or change an event. Nothing is saved until Save.
struct EventEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    let editing: EditingEvent
    @State private var draft: EventItem
    @FocusState private var titleFocused: Bool

    init(editing: EditingEvent) {
        self.editing = editing
        _draft = State(initialValue: editing.item)
    }

    private var original: EventItem? { editing.isNew ? nil : store.event(editing.item.id) }
    private var isDayOfSeries: Bool { OccurrenceID.parse(editing.item.id) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Event title", text: $draft.title)
                .textFieldStyle(.plain)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .focused($titleFocused)
                .onSubmit(save)
            Toggle("All day", isOn: Binding(get: { draft.allDay }, set: { EventDraft.setAllDay(&draft, $0) }))
                .toggleStyle(.switch).controlSize(.small)
            dateRow("Starts", selection: Binding(
                get: { EventDraft.date(draft.start) },
                set: { EventDraft.setStart(&draft, to: EventDraft.wallTime($0)) }),
                    range: nil)
            dateRow("Ends", selection: Binding(
                get: { EventDraft.date(draft.end) },
                set: { draft.end = EventDraft.wallTime($0) }),
                    range: EventDraft.date(draft.start)...)
            colourRow
            field("Location", text: $draft.location)
            notesField
            repeatSection
            if isDayOfSeries {
                Text("When you save, Grove asks if the change is for this event only or all events.")
                    .font(.system(size: 11, design: .rounded)).foregroundStyle(theme.muted)
            }
            buttons
        }
        .font(.system(size: 12, design: .rounded))
        .padding(16)
        .frame(width: 360)
        .onAppear { titleFocused = editing.isNew }
    }

    // MARK: Rows

    private func dateRow(_ label: String, selection: Binding<Date>, range: PartialRangeFrom<Date>?) -> some View {
        HStack {
            Text(label).foregroundStyle(theme.muted).frame(width: 52, alignment: .leading)
            Spacer(minLength: 0)
            let parts: DatePickerComponents = draft.allDay ? [.date] : [.date, .hourAndMinute]
            if let range {
                DatePicker("", selection: selection, in: range, displayedComponents: parts).labelsHidden().datePickerStyle(.compact)
            } else {
                DatePicker("", selection: selection, displayedComponents: parts).labelsHidden().datePickerStyle(.compact)
            }
        }
    }

    private var colourRow: some View {
        HStack(spacing: 8) {
            Text("Colour").foregroundStyle(theme.muted).frame(width: 52, alignment: .leading)
            ForEach(Theme.blockColorNames, id: \.self) { name in
                Button { draft.color = name } label: {
                    Circle().fill(theme.color(named: name)).frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(theme.ink, lineWidth: draft.color == name ? 2 : 0).padding(-3))
                }
                .buttonStyle(.plain)
                .help(name.capitalized)
            }
            Spacer(minLength: 0)
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label).foregroundStyle(theme.muted).frame(width: 52, alignment: .leading)
            TextField("", text: text).textFieldStyle(.roundedBorder)
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notes").foregroundStyle(theme.muted)
            TextEditor(text: $draft.notes)
                .font(.system(size: 12, design: .rounded))
                .scrollContentBackground(.hidden)
                .padding(4)
                .frame(height: 64)
                .background(RoundedRectangle(cornerRadius: 6).fill(theme.bg))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.line))
        }
    }

    // MARK: Repeat

    /// The repeat rule without its end. The preset list only knows plain rules.
    private var plainRule: RecurrenceRule? {
        guard var r = draft.recurrence else { return nil }
        r.until = nil
        r.count = nil
        return r
    }

    private var repeatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Repeat").foregroundStyle(theme.muted).frame(width: 52, alignment: .leading)
                let current = RepeatPreset.of(plainRule)
                Picker("", selection: Binding(get: { current }, set: setPreset)) {
                    if current == .custom, let rule = plainRule { Text(EventDraft.repeatLabel(rule)).tag(RepeatPreset.custom) }
                    ForEach(RepeatPreset.allCases.filter { $0 != .custom }) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                Spacer(minLength: 0)
            }
            if let rule = draft.recurrence, rule.freq == .weekly { weekdayRow(rule) }
            if let rule = draft.recurrence {
                HStack {
                    Text("Ends").foregroundStyle(theme.muted).frame(width: 52, alignment: .leading)
                    Picker("", selection: Binding(get: { EventDraft.ends(rule) }, set: setEnds)) {
                        Text("Never").tag(EventDraft.Ends.never)
                        Text("On a day").tag(EventDraft.Ends.on)
                        Text("After").tag(EventDraft.Ends.after)
                    }
                    .labelsHidden().fixedSize()
                    endsDetail(rule)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// M T W T F S S. The first event's own weekday is on when there is no list.
    private func weekdayRow(_ rule: RecurrenceRule) -> some View {
        let start = draft.start.day.weekdayIndex
        let on = Set(rule.weekdays ?? [start])
        return HStack(spacing: 4) {
            Text("On").foregroundStyle(theme.muted).frame(width: 52, alignment: .leading)
            ForEach(1...7, id: \.self) { d in
                Button { draft.recurrence = EventDraft.toggleWeekday(rule, d, start: start) } label: {
                    Text(["M", "T", "W", "T", "F", "S", "S"][d - 1])
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .frame(width: 24, height: 24)
                        .foregroundStyle(on.contains(d) ? theme.surface : theme.ink)
                        .background(Circle().fill(on.contains(d) ? theme.accent : theme.line.opacity(0.5)))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private func endsDetail(_ rule: RecurrenceRule) -> some View {
        if let until = rule.until {
            DatePicker("", selection: Binding(
                get: { until.date },
                set: { draft.recurrence?.until = DayKey($0) }), displayedComponents: [.date]).labelsHidden()
        } else if let count = rule.count {
            Stepper("\(count) times", value: Binding(
                get: { count },
                set: { draft.recurrence?.count = max(1, $0) }), in: 1...999)
                .fixedSize()
        }
    }

    private func setPreset(_ preset: RepeatPreset) {
        guard preset != .custom else { return }
        let old = draft.recurrence
        guard var rule = preset.rule else { draft.recurrence = nil; return }
        rule.until = old?.until
        rule.count = old?.count
        draft.recurrence = rule
    }

    private func setEnds(_ ends: EventDraft.Ends) {
        switch ends {
        case .never: draft.recurrence?.until = nil; draft.recurrence?.count = nil
        case .on: draft.recurrence?.until = draft.start.day.adding(days: 30); draft.recurrence?.count = nil
        case .after: draft.recurrence?.until = nil; draft.recurrence?.count = 10
        }
    }

    // MARK: Buttons

    private var buttons: some View {
        HStack {
            if let original {
                Button("Delete", role: .destructive) { store.deleteEvent(original) }
            }
            Spacer()
            Button("Cancel") { store.closeEditor() }.keyboardShortcut(.cancelAction)
            Button("Save", action: save)
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .help("Save (⌘Return)")
        }
    }

    private func save() {
        if editing.isNew {
            store.saveEvent(draft, from: nil)
        } else if let original {
            store.saveEvent(draft, from: original)
        } else {
            store.closeEditor()   // the event is gone
        }
    }
}
