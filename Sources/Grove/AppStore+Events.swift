import SwiftUI
import GroveCore

/// What an edit of a repeating event applies to.
enum RecurringScope { case only, all }

/// The question "This event only / All events", waiting for an answer. `verb` is Move, Resize, Delete, Change or Rename.
struct RecurringPrompt {
    var verb: String
    var run: (RecurringScope) -> Void
    /// Runs when the user cancels. The event editor uses it to open again with the same edits.
    var onCancel: (() -> Void)?
}

extension AppStore {
    // MARK: Reading

    /// Every event that touches the days: stored events, one-off copies and the days of repeating events.
    func eventItems(in days: ClosedRange<DayKey>) -> [EventItem] {
        var out = (try? repos.events.inRange(days.lowerBound, days.upperBound)) ?? []
        for series in (try? repos.events.recurringSeries()) ?? [] where series.start.day <= days.upperBound {
            let gone = Set((try? repos.events.exdates(series.id)) ?? [])
            out += RecurrenceEngine.expand(series, exdates: gone, in: days)
        }
        return out.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    /// A copy of an event to edit. A day of a repeating event carries the repeat rule of its series,
    /// so a change can say "keep repeating" (the rule stays) or "stop" (the rule is removed).
    func draft(for item: EventItem) -> EventItem {
        var d = item
        if let p = OccurrenceID.parse(item.id), let series = event(p.series) { d.recurrence = series.recurrence }
        return d
    }

    // MARK: The question

    func askScope(_ verb: String, onCancel: (() -> Void)? = nil, _ run: @escaping (RecurringScope) -> Void) {
        recurringPrompt = RecurringPrompt(verb: verb, run: run, onCancel: onCancel)
    }

    func answerRecurring(_ scope: RecurringScope) {
        guard let prompt = recurringPrompt else { return }
        recurringPrompt = nil
        prompt.run(scope)
    }

    func cancelRecurring() {
        let prompt = recurringPrompt
        recurringPrompt = nil
        prompt?.onCancel?()
    }

    /// Asks "This event only / All events", then commits the changes as one undo step.
    func changeOccurrences(_ pairs: [(old: EventItem, new: EventItem)], verb: String, name: String, onCancel: (() -> Void)? = nil) {
        guard !pairs.isEmpty else { return }
        askScope(verb, onCancel: onCancel) { [weak self] scope in
            guard let self else { return }
            var all = Mutation(name: name)
            var ids = Set<String>()
            var seenSeries = Set<String>()
            for pair in pairs {
                if scope == .all, let p = OccurrenceID.parse(pair.old.id), !seenSeries.insert(p.series).inserted { continue }
                guard let done = self.change(pair.old, to: pair.new, scope: scope, name: name) else { continue }
                all.append(done.mutation)
                ids.insert(done.id)
            }
            if self.commit(all), !ids.isEmpty { self.selection = ids }
        }
    }

    // MARK: Building the changes

    /// The change that turns `original` into `edited`, and the id the result has afterwards.
    /// For a day of a repeating event, `scope` says: that day only (it becomes a one-off copy and the day is
    /// taken out of the series), or the whole series. A stored event changes in place.
    func change(_ original: EventItem, to edited: EventItem, scope: RecurringScope, name: String) -> (mutation: Mutation, id: String)? {
        var m = Mutation(name: name)
        guard let p = OccurrenceID.parse(original.id) else {
            var new = edited
            new.id = original.id
            guard let old = event(original.id) else { return nil }
            new.createdAt = old.createdAt   // a save stamps the time, so compare without the stamps
            new.updatedAt = old.updatedAt
            guard new != old else { return nil }
            m.events.append((old, new))
            return (m, new.id)
        }
        guard let series = event(p.series) else { return nil }
        switch scope {
        case .only:
            var copy = edited
            copy.id = UUID().uuidString
            copy.recurrence = nil
            copy.seriesId = series.id
            copy.originalDate = p.day
            m.exdates.append((series.id, p.day, true))
            m.events.append((nil, copy))
            return (m, copy.id)
        case .all:
            var new = series
            new.title = edited.title
            new.allDay = edited.allDay
            new.color = edited.color
            new.location = edited.location
            new.notes = edited.notes
            let delta = original.start.day.days(until: edited.start.day)
            new.start = WallTime(day: series.start.day.adding(days: delta), minute: edited.start.minute)
            new.end = WallTime(day: new.start.day.adding(days: edited.start.day.days(until: edited.end.day)), minute: edited.end.minute)
            new.recurrence = edited.recurrence
            if delta != 0, var rule = new.recurrence, rule == series.recurrence, rule.freq == .weekly, let days = rule.weekdays, !days.isEmpty {
                // Moving every Wednesday to Thursday moves every other chosen weekday one day too.
                rule.weekdays = days.map { (($0 - 1 + delta) % 7 + 7) % 7 + 1 }
                new.recurrence = rule
            }
            guard new != series else { return nil }
            m.events.append((series, new))   // the series first: copies point at it
            if delta != 0 {
                // Days taken out of the series, and the one-off copies that replaced them, move along.
                let gone = (try? repos.events.exdates(series.id)) ?? []
                for d in gone { m.exdates.append((series.id, d, false)) }
                for d in gone { m.exdates.append((series.id, d.adding(days: delta), true)) }
                for copy in (try? repos.events.detached(seriesId: series.id)) ?? [] {
                    var moved = copy
                    moved.originalDate = copy.originalDate?.adding(days: delta)
                    if moved != copy { m.events.append((copy, moved)) }
                }
            }
            let id = new.recurrence == nil ? new.id : OccurrenceID.make(series: new.id, day: edited.start.day)
            return (m, id)
        }
    }

    /// The change that removes a day of a repeating event (`.only`), the whole series (`.all`), or a stored event.
    func deletion(of original: EventItem, scope: RecurringScope, name: String) -> Mutation {
        var m = Mutation(name: name)
        guard let p = OccurrenceID.parse(original.id) else {
            if let old = event(original.id) { m.events.append((old, nil)) }
            return m
        }
        guard let series = event(p.series) else { return m }
        switch scope {
        case .only:
            m.exdates.append((series.id, p.day, true))
        case .all:
            m.events.append((series, nil))   // the series first, as in `change`
            for copy in (try? repos.events.detached(seriesId: series.id)) ?? [] { m.events.append((copy, nil)) }
            for d in (try? repos.events.exdates(series.id)) ?? [] { m.exdates.append((series.id, d, false)) }
        }
        return m
    }
}
