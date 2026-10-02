import Foundation
import GroveCore

/// What a daily or weekly note shows beside its text: the day, the finished tasks, the week review and the mood.
extension AppStore {
    // MARK: The day

    /// Everything on `day`, live from the database. See `DayRules.agenda`.
    func agenda(for day: DayKey) -> [AgendaRow] {
        DayRules.agenda(day: day, events: eventItems(in: day...day), dayTasks: (try? repos.tasks.forDay(day)) ?? [],
                        taskFor: { [self] in task($0) })
    }

    /// Tasks finished on `day`, first to last.
    func completedTasks(on day: DayKey) -> [TaskItem] { (try? repos.tasks.completed(on: day)) ?? [] }

    // MARK: The week

    func weekReview(_ monday: DayKey) -> WeekReview {
        let sunday = monday.adding(days: 6)
        let candidates = ((try? repos.tasks.inRange(monday, sunday)) ?? []) + ((try? repos.tasks.forWeek(monday)) ?? [])
        return DayRules.review(monday: monday, done: (try? repos.tasks.completed(from: monday, to: sunday)) ?? [],
                               openCandidates: candidates, events: eventItems(in: monday...sunday), taskFor: { [self] in task($0) })
    }

    /// Writes the week summary under `## Review` of a weekly note. A summary that is there is replaced.
    func insertWeekSummary(_ noteId: String) {
        guard let n = note(noteId), n.kind == .weekly, let monday = n.date else { return }
        let text = DayRules.insert(DayRules.summary(weekReview(monday)), into: n.body)
        guard text != n.body else { return }
        // Its own undo step. `setNoteBody` would join it to the typing before it.
        var changed = n
        changed.body = text
        var m = Mutation(name: "Insert Week Summary")
        m.notes.append((n, changed))
        commit(m)
        showToast("Summary added to the note.")
    }

    // MARK: Mood

    /// Sets the mood of a daily note. The same mood again clears it.
    func setMood(_ noteId: String, _ mood: Mood) {
        guard let old = note(noteId), old.kind == .daily else { return }
        var n = old
        n.mood = old.mood == mood.rawValue ? nil : mood.rawValue
        var m = Mutation(name: "Set Mood")
        m.notes.append((old, n))
        commit(m)
    }
}
