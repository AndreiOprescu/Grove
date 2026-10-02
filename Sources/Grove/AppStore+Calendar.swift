import SwiftUI
import GroveCore

/// The event the editor popover shows. `anchor` says which view the popover hangs on.
struct EditingEvent: Equatable {
    var item: EventItem
    var isNew: Bool
    var anchor: String
}

extension AppStore {
    // MARK: Reading

    /// One entry for every day in the range.
    func dayInfo(_ days: ClosedRange<DayKey>) -> [DayKey: DayInfo] {
        var out: [DayKey: DayInfo] = [:]
        let count = days.lowerBound.days(until: days.upperBound)
        for i in 0...max(0, count) { out[days.lowerBound.adding(days: i)] = DayInfo() }
        for e in eventItems(in: days) where e.kind == .event {
            let from = max(e.start.day, days.lowerBound)
            let to = min(e.end.day, days.upperBound)
            guard from <= to else { continue }
            for i in 0...from.days(until: to) {
                let day = from.adding(days: i)
                if CalendarRules.covers(e, day) { out[day]?.events.append(e) }
            }
        }
        for (day, info) in out { out[day]?.events = CalendarRules.sorted(info.events) }
        for (day, n) in (try? repos.tasks.openCounts(from: days.lowerBound, to: days.upperBound)) ?? [:] { out[day]?.openTasks = n }
        for day in (try? repos.notes.daysWithNotes(from: days.lowerBound, to: days.upperBound)) ?? [] { out[day]?.hasNote = true }
        return out
    }

    // MARK: The editor

    /// A new all-day event on `day`. Nothing is stored until the user saves.
    func newEvent(on day: DayKey) {
        let item = EventItem(title: "", start: WallTime(day: day, minute: 0), end: WallTime(day: day, minute: 0), allDay: true)
        editingEvent = EditingEvent(item: item, isNew: true, anchor: "new:\(day.string)")
    }

    func editEvent(_ event: EventItem) {
        editingEvent = EditingEvent(item: draft(for: event), isNew: false, anchor: event.id)
    }

    func closeEditor() { editingEvent = nil }

    // MARK: Writing

    /// Saves the editor's copy. `original` is the event before the edit, or nil for a new event.
    /// A day of a repeating event asks "This event only / All events" first.
    func saveEvent(_ edited: EventItem, from original: EventItem?) {
        var item = edited
        EventDraft.normalize(&item)
        item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let original else {
            if item.title.isEmpty { item.title = "New Event" }
            var m = Mutation(name: "New Event")
            m.events.append((nil, item))
            if commit(m) { selection = [item.id] }
            closeEditor()
            return
        }
        if item.title.isEmpty { item.title = original.title }
        let editor = editingEvent
        if OccurrenceID.parse(original.id) != nil {
            guard item != draft(for: original) else { closeEditor(); return }
            closeEditor()
            changeOccurrences([(original, item)], verb: "Change", name: "Edit Event") { [weak self] in self?.editingEvent = editor }
            return
        }
        if let done = change(original, to: item, scope: .only, name: "Edit Event") { commit(done.mutation) }
        closeEditor()
    }

    func deleteEvent(_ event: EventItem) {
        closeEditor()
        guard OccurrenceID.parse(event.id) != nil else {
            commit(deletion(of: event, scope: .only, name: "Delete Event"))
            return
        }
        askScope("Delete") { [weak self] scope in
            guard let self else { return }
            self.commit(self.deletion(of: event, scope: scope, name: "Delete Event"))
        }
    }

    // MARK: Dropping a task

    /// A task dropped on a day in the week strip or the month view.
    func dropTask(_ id: String, on day: DayKey) {
        moveTask(id, to: .day(day))
        showToast("Planned for " + day.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
    }
}
