import Foundation

/// What a brand new Grove holds on first launch (PLAN §9): three lists and three sample tasks for today.
/// The flags live in the `settings` table, so they travel in the export file and an import never seeds twice.
public enum FirstRun {
    static let doneKey = "firstrun.done"
    static let dismissedKey = "firstrun.welcomeDismissed"
    static let samplesKey = "firstrun.sampleTaskIds"

    /// The titles of the three sample tasks, in the order they show.
    public static let sampleTitles = [
        "Drag me onto the planner to give me a time",
        "Type [[ in a note to link a task, a note or an event",
        "Press ⌘K to find anything or run a command",
    ]

    /// Fills an empty database. Returns true when it did.
    /// A database that has any list, task, event or note is left alone, and so is one that was seeded before
    /// (the person may have emptied it on purpose).
    @discardableResult
    public static func seedIfNew(_ r: Repos, today: DayKey) throws -> Bool {
        if try r.settings.get(doneKey) != nil { return false }
        let hasData = try !r.lists.all(includeArchived: true).isEmpty || !r.tasks.all().isEmpty
            || !r.events.all().isEmpty || !r.notes.all().isEmpty
        try r.settings.set(doneKey, "1")
        if hasData { return false }

        let lists = [("Home", "🌿"), ("Work", "💼"), ("Personal", "✨")]
        for (i, l) in lists.enumerated() { try r.lists.save(ListItem(name: l.0, emoji: l.1, sort: i)) }

        var ids: [String] = []
        for (i, title) in sampleTitles.enumerated() {
            let t = TaskItem(title: title, bucket: .day, planDate: today, sort: Double(i + 1))
            try r.tasks.save(t)
            ids.append(t.id)
        }
        try r.settings.set(samplesKey, String(decoding: try JSONEncoder().encode(ids), as: UTF8.self))
        return true
    }

    /// The welcome card shows while there are sample tasks and the person has not dismissed it.
    public static func welcomeVisible(_ r: Repos) -> Bool {
        guard !sampleTaskIds(r).isEmpty else { return false }
        return (try? r.settings.get(dismissedKey)) == nil
    }

    /// The ids of the sample tasks that "Remove samples" deletes.
    public static func sampleTaskIds(_ r: Repos) -> [String] {
        guard let text = (try? r.settings.get(samplesKey)) ?? nil, let data = text.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    /// Hides the card. The sample tasks stay.
    public static func dismissWelcome(_ r: Repos) {
        try? r.settings.set(dismissedKey, "1")
    }

    /// Hides the card and forgets the sample ids (after "Remove samples").
    public static func forgetSamples(_ r: Repos) {
        try? r.settings.remove(samplesKey)
        try? r.settings.set(dismissedKey, "1")
    }
}
