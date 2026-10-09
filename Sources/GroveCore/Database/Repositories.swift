import Foundation

/// Builds `INSERT … ON CONFLICT(id) DO UPDATE` so a save never deletes and re-creates a row
/// (a REPLACE would fire ON DELETE CASCADE and wipe child rows).
private func upsertSQL(_ table: String, _ cols: [String]) -> String {
    let marks = Array(repeating: "?", count: cols.count).joined(separator: ",")
    let sets = cols.dropFirst().map { "\($0)=excluded.\($0)" }.joined(separator: ",")
    return "INSERT INTO \(table) (\(cols.joined(separator: ","))) VALUES (\(marks)) ON CONFLICT(\(cols[0])) DO UPDATE SET \(sets)"
}

// MARK: - Tasks

public final class TaskRepo {
    let db: Database
    let search: SearchIndex
    public init(db: Database, search: SearchIndex) { self.db = db; self.search = search }

    private static let cols = ["id", "title", "notes", "list_id", "parent_id", "priority", "status", "bucket",
                               "plan_date", "plan_week", "due", "estimate_min", "recurrence", "source_note_id",
                               "sort", "created_at", "updated_at", "completed_at", "summary", "color"]
    private static let select = "SELECT \(cols.joined(separator: ",")) FROM tasks"
    private static let upsert = upsertSQL("tasks", cols)

    private static func map(_ r: Row) -> TaskItem {
        var t = TaskItem(id: r.text(0), title: r.text(1))
        t.notes = r.text(2)
        t.listId = r.optText(3)
        t.parentId = r.optText(4)
        t.priority = r.int(5)
        t.status = TaskStatus(rawValue: r.text(6)) ?? .open
        t.bucket = TaskBucket(rawValue: r.text(7)) ?? .inbox
        t.planDate = r.optText(8).map { DayKey($0) }
        t.planWeek = r.optText(9).map { DayKey($0) }
        t.due = r.optText(10)
        t.estimateMin = r.int(11)
        t.recurrence = RecurrenceRule.fromJSON(r.optText(12))
        t.sourceNoteId = r.optText(13)
        t.sort = r.double(14)
        t.createdAt = r.text(15)
        t.updatedAt = r.text(16)
        t.completedAt = r.optText(17)
        t.summary = r.text(18)
        t.color = r.text(19)
        return t
    }

    /// Insert or update. Refreshes `updatedAt`.
    public func save(_ task: TaskItem) throws {
        var t = task
        t.updatedAt = Stamp.now()
        try db.transaction {
            try db.execute(Self.upsert, [
                .text(t.id), .text(t.title), .text(t.notes), SQLValue(t.listId), SQLValue(t.parentId),
                .int(t.priority), .text(t.status.rawValue), .text(t.bucket.rawValue),
                SQLValue(t.planDate?.string), SQLValue(t.planWeek?.string), SQLValue(t.due),
                .int(t.estimateMin), SQLValue(t.recurrence?.json()), SQLValue(t.sourceNoteId),
                .real(t.sort), .text(t.createdAt), .text(t.updatedAt), SQLValue(t.completedAt), .text(t.summary), .text(t.color),
            ])
            try search.upsert(.task, id: t.id, title: t.title, body: Self.searchBody(t))
        }
    }

    /// How many tasks are finished. The garden plant grows with this number.
    public func doneCount() throws -> Int {
        try db.queryOne("SELECT COUNT(*) FROM tasks WHERE status = 'done'", map: { $0.int(0) }) ?? 0
    }

    public func get(_ id: String) throws -> TaskItem? {
        try db.queryOne(Self.select + " WHERE id = ?", [.text(id)], map: Self.map)
    }

    /// Case-insensitive exact title match. Open tasks first, then the most recently edited.
    public func byTitle(_ title: String) throws -> TaskItem? {
        try db.queryOne(Self.select + " WHERE title = ? COLLATE NOCASE ORDER BY (status = 'open') DESC, updated_at DESC",
                        [.text(title)], map: Self.map)
    }

    public func delete(_ id: String) throws {
        try db.transaction {
            // Subtasks and blocks disappear through ON DELETE CASCADE; clean their search rows first.
            let doomed = try db.query("SELECT id FROM tasks WHERE parent_id = ?", [.text(id)]) { $0.text(0) }
            let blocks = try db.query("SELECT id FROM events WHERE task_id = ?", [.text(id)]) { $0.text(0) }
            for s in doomed { try search.remove(.task, id: s) }
            for b in blocks { try search.remove(.event, id: b) }
            try db.execute("DELETE FROM tasks WHERE id = ?", [.text(id)])
            try search.remove(.task, id: id)
        }
    }

    /// Top-level tasks planned for a day (not cancelled).
    public func forDay(_ day: DayKey) throws -> [TaskItem] {
        try db.query(Self.select + " WHERE bucket = 'day' AND plan_date = ? AND parent_id IS NULL AND status != 'cancelled' ORDER BY sort, created_at, rowid",
                     [.text(day.string)], map: Self.map)
    }

    /// Tasks with a day inside the closed range.
    public func inRange(_ from: DayKey, _ to: DayKey) throws -> [TaskItem] {
        try db.query(Self.select + " WHERE plan_date >= ? AND plan_date <= ? AND parent_id IS NULL AND status != 'cancelled' ORDER BY plan_date, sort, created_at, rowid",
                     [.text(from.string), .text(to.string)], map: Self.map)
    }

    /// "Sometime this week" tasks (no day yet).
    public func forWeek(_ monday: DayKey) throws -> [TaskItem] {
        try db.query(Self.select + " WHERE bucket = 'week' AND plan_week = ? AND parent_id IS NULL AND status != 'cancelled' ORDER BY sort, created_at, rowid",
                     [.text(monday.string)], map: Self.map)
    }

    public func inbox() throws -> [TaskItem] {
        try db.query(Self.select + " WHERE bucket = 'inbox' AND parent_id IS NULL AND status = 'open' ORDER BY sort, created_at, rowid", map: Self.map)
    }

    public func someday() throws -> [TaskItem] {
        try db.query(Self.select + " WHERE bucket = 'someday' AND parent_id IS NULL AND status = 'open' ORDER BY sort, created_at, rowid", map: Self.map)
    }

    /// Every open top-level task, whatever its bucket. The Planner screen's task list.
    public func openTopLevel() throws -> [TaskItem] {
        try db.query(Self.select + " WHERE status = 'open' AND parent_id IS NULL ORDER BY sort, created_at, rowid", map: Self.map)
    }

    /// Open tasks planned for a day before `day`.
    public func overdue(before day: DayKey) throws -> [TaskItem] {
        try db.query(Self.select + " WHERE status = 'open' AND bucket = 'day' AND plan_date < ? AND parent_id IS NULL ORDER BY plan_date, sort",
                     [.text(day.string)], map: Self.map)
    }

    /// Open tasks whose due date has a time ("YYYY-MM-DDTHH:MM"). These are the tasks that can remind.
    public func openWithTimedDue() throws -> [TaskItem] {
        try db.query(Self.select + " WHERE status = 'open' AND due LIKE '%T%' ORDER BY due", map: Self.map)
    }

    public func subtasks(of parentId: String) throws -> [TaskItem] {
        try db.query(Self.select + " WHERE parent_id = ? ORDER BY sort, created_at, rowid", [.text(parentId)], map: Self.map)
    }

    public func completed(on day: DayKey) throws -> [TaskItem] {
        try db.query(Self.select + " WHERE status = 'done' AND completed_at >= ? AND completed_at < ? ORDER BY completed_at",
                     [.text(day.string + "T00:00:00"), .text(day.adding(days: 1).string + "T00:00:00")], map: Self.map)
    }

    public func completed(from: DayKey, to: DayKey) throws -> [TaskItem] {
        try db.query(Self.select + " WHERE status = 'done' AND completed_at >= ? AND completed_at < ? ORDER BY completed_at",
                     [.text(from.string + "T00:00:00"), .text(to.adding(days: 1).string + "T00:00:00")], map: Self.map)
    }

    public func inList(_ listId: String) throws -> [TaskItem] {
        try db.query(Self.select + " WHERE list_id = ? AND parent_id IS NULL AND status = 'open' ORDER BY sort, created_at, rowid",
                     [.text(listId)], map: Self.map)
    }

    public func withTag(_ name: String) throws -> [TaskItem] {
        try db.query(Self.select + " WHERE id IN (SELECT task_id FROM task_tags JOIN tags ON tags.id = tag_id WHERE tags.name = ?) AND status = 'open' ORDER BY sort, created_at, rowid",
                     [.text(name)], map: Self.map)
    }

    /// The text the search index holds for a task (the title is stored beside it).
    static func searchBody(_ t: TaskItem) -> String { t.summary + " " + ReferenceParser.searchText(t.notes) }

    public func all() throws -> [TaskItem] {
        try db.query(Self.select + " ORDER BY created_at", map: Self.map)
    }

    public func openCount() throws -> Int {
        try db.queryOne("SELECT COUNT(*) FROM tasks WHERE status = 'open'") { $0.int(0) } ?? 0
    }

    /// Number of open (not done) top-level tasks per day, for calendar dots.
    public func openCounts(from: DayKey, to: DayKey) throws -> [DayKey: Int] {
        let rows = try db.query("SELECT plan_date, COUNT(*) FROM tasks WHERE status = 'open' AND parent_id IS NULL AND plan_date >= ? AND plan_date <= ? GROUP BY plan_date",
                                [.text(from.string), .text(to.string)]) { (DayKey($0.text(0)), $0.int(1)) }
        return Dictionary(uniqueKeysWithValues: rows)
    }
}

// MARK: - Events

public final class EventRepo {
    let db: Database
    let search: SearchIndex
    public init(db: Database, search: SearchIndex) { self.db = db; self.search = search }

    private static let cols = ["id", "title", "start", "end", "all_day", "kind", "task_id", "color", "location",
                               "notes", "recurrence", "series_id", "original_date", "created_at", "updated_at",
                               "goal_id", "done_at"]
    private static let select = "SELECT \(cols.joined(separator: ",")) FROM events"
    private static let upsert = upsertSQL("events", cols)

    private static func map(_ r: Row) -> EventItem {
        let start = WallTime(r.text(2)) ?? WallTime(day: DayKey.today(), minute: 0)
        let end = WallTime(r.text(3)) ?? start
        var e = EventItem(id: r.text(0), title: r.text(1), start: start, end: end)
        e.allDay = r.bool(4)
        e.kind = EventKind(rawValue: r.text(5)) ?? .event
        e.taskId = r.optText(6)
        e.color = r.text(7)
        e.location = r.text(8)
        e.notes = r.text(9)
        e.recurrence = RecurrenceRule.fromJSON(r.optText(10))
        e.seriesId = r.optText(11)
        e.originalDate = r.optText(12).map { DayKey($0) }
        e.createdAt = r.text(13)
        e.updatedAt = r.text(14)
        e.goalId = r.optText(15)
        e.doneAt = r.optText(16)
        return e
    }

    public func save(_ event: EventItem) throws {
        var e = event
        e.updatedAt = Stamp.now()
        try db.transaction {
            try db.execute(Self.upsert, [
                .text(e.id), .text(e.title), .text(e.start.string), .text(e.end.string),
                .int(e.allDay ? 1 : 0), .text(e.kind.rawValue), SQLValue(e.taskId), .text(e.color),
                .text(e.location), .text(e.notes), SQLValue(e.recurrence?.json()), SQLValue(e.seriesId),
                SQLValue(e.originalDate?.string), .text(e.createdAt), .text(e.updatedAt),
                SQLValue(e.goalId), SQLValue(e.doneAt),
            ])
            if e.kind == .event {
                try search.upsert(.event, id: e.id, title: e.title, body: Self.searchBody(e))
            }
        }
    }

    public func get(_ id: String) throws -> EventItem? {
        try db.queryOne(Self.select + " WHERE id = ?", [.text(id)], map: Self.map)
    }

    /// Time blocks that belong to a task, earliest first.
    public func blocks(forTask taskId: String) throws -> [EventItem] {
        try db.query(Self.select + " WHERE task_id = ? ORDER BY start", [.text(taskId)], map: Self.map)
    }

    /// Time blocks that belong to a goal, earliest first.
    public func blocks(forGoal goalId: String) throws -> [EventItem] {
        try db.query(Self.select + " WHERE goal_id = ? ORDER BY start", [.text(goalId)], map: Self.map)
    }

    /// Case-insensitive exact title match, most recently edited first.
    public func byTitle(_ title: String) throws -> EventItem? {
        try db.queryOne(Self.select + " WHERE title = ? COLLATE NOCASE ORDER BY updated_at DESC", [.text(title)], map: Self.map)
    }

    public func delete(_ id: String) throws {
        try db.transaction {
            try db.execute("DELETE FROM events WHERE id = ?", [.text(id)])
            try search.remove(.event, id: id)
        }
    }

    /// One-off events and detached occurrences that touch the closed day range.
    /// Series (events with a recurrence rule) come from `recurringSeries()`.
    public func inRange(_ from: DayKey, _ to: DayKey) throws -> [EventItem] {
        try db.query(Self.select + " WHERE recurrence IS NULL AND start < ? AND end >= ? ORDER BY start",
                     [.text(to.adding(days: 1).string + "T00:00"), .text(from.string + "T00:00")], map: Self.map)
    }

    public func recurringSeries() throws -> [EventItem] {
        try db.query(Self.select + " WHERE recurrence IS NOT NULL ORDER BY start", map: Self.map)
    }

    public func forTask(_ taskId: String) throws -> [EventItem] {
        try db.query(Self.select + " WHERE task_id = ? ORDER BY start", [.text(taskId)], map: Self.map)
    }

    public func detached(seriesId: String) throws -> [EventItem] {
        try db.query(Self.select + " WHERE series_id = ? ORDER BY start", [.text(seriesId)], map: Self.map)
    }

    public func exdates(_ eventId: String) throws -> [DayKey] {
        try db.query("SELECT date FROM event_exdates WHERE event_id = ?", [.text(eventId)]) { DayKey($0.text(0)) }
    }

    public func addExdate(_ eventId: String, _ day: DayKey) throws {
        try db.execute("INSERT OR IGNORE INTO event_exdates (event_id, date) VALUES (?, ?)", [.text(eventId), .text(day.string)])
    }

    public func removeExdate(_ eventId: String, _ day: DayKey) throws {
        try db.execute("DELETE FROM event_exdates WHERE event_id = ? AND date = ?", [.text(eventId), .text(day.string)])
    }

    static func searchBody(_ e: EventItem) -> String { ReferenceParser.searchText(e.notes) + " " + e.location }

    public func all() throws -> [EventItem] {
        try db.query(Self.select + " ORDER BY start", map: Self.map)
    }
}

// MARK: - Goals

public final class GoalRepo {
    let db: Database
    public init(db: Database) { self.db = db }

    private static let cols = ["id", "title", "notes", "color", "target_min", "sort", "archived", "created_at", "updated_at"]
    private static let select = "SELECT \(cols.joined(separator: ",")) FROM goals"
    private static let upsertQuery = upsertSQL("goals", cols)

    private static func map(_ r: Row) -> GoalItem {
        var g = GoalItem(id: r.text(0), title: r.text(1))
        g.notes = r.text(2)
        g.color = r.text(3)
        g.targetMin = r.int(4)
        g.sort = r.double(5)
        g.archived = r.bool(6)
        g.createdAt = r.text(7)
        g.updatedAt = r.text(8)
        return g
    }

    /// Insert or update. Refreshes `updatedAt`.
    public func upsert(_ goal: GoalItem) throws {
        var g = goal
        g.updatedAt = Stamp.now()
        try db.execute(Self.upsertQuery, [
            .text(g.id), .text(g.title), .text(g.notes), .text(g.color), .int(g.targetMin), .real(g.sort),
            .int(g.archived ? 1 : 0), .text(g.createdAt), .text(g.updatedAt),
        ])
    }

    public func get(_ id: String) throws -> GoalItem? {
        try db.queryOne(Self.select + " WHERE id = ?", [.text(id)], map: Self.map)
    }

    public func all(includeArchived: Bool = false) throws -> [GoalItem] {
        try db.query(Self.select + (includeArchived ? "" : " WHERE archived = 0") + " ORDER BY sort, created_at, rowid", map: Self.map)
    }

    /// Deletes the goal. Its blocks stay as plain blocks: they lose the goal and the done time.
    public func delete(_ id: String) throws {
        try db.transaction {
            try db.execute("UPDATE events SET goal_id = NULL, done_at = NULL WHERE goal_id = ?", [.text(id)])
            try db.execute("DELETE FROM goals WHERE id = ?", [.text(id)])
        }
    }

    /// Minutes of the goal's blocks that are marked done and start on a day of the closed range.
    public func doneMinutes(goalId: String, from: DayKey, to: DayKey) throws -> Int {
        try minutes(goalId: goalId, done: true, from: from, to: to)
    }

    /// Minutes of the goal's blocks that are not done yet and start on a day of the closed range.
    public func plannedMinutes(goalId: String, from: DayKey, to: DayKey) throws -> Int {
        try minutes(goalId: goalId, done: false, from: from, to: to)
    }

    private func minutes(goalId: String, done: Bool, from: DayKey, to: DayKey) throws -> Int {
        let rows = try db.query(
            "SELECT start, end FROM events WHERE goal_id = ? AND done_at IS \(done ? "NOT " : "")NULL AND start >= ? AND start < ?",
            [.text(goalId), .text(from.string + "T00:00"), .text(to.adding(days: 1).string + "T00:00")]) { ($0.text(0), $0.text(1)) }
        return rows.reduce(0) { sum, row in
            guard let start = WallTime(row.0), let end = WallTime(row.1) else { return sum }
            return sum + EventItem(title: "", start: start, end: end).durationMinutes
        }
    }
}

// MARK: - Notes

public final class NoteRepo {
    let db: Database
    let search: SearchIndex
    public init(db: Database, search: SearchIndex) { self.db = db; self.search = search }

    private static let cols = ["id", "title", "body", "kind", "date", "pinned", "mood", "created_at", "updated_at"]
    private static let select = "SELECT \(cols.joined(separator: ",")) FROM notes"
    private static let upsert = upsertSQL("notes", cols)

    private static func map(_ r: Row) -> Note {
        var n = Note(id: r.text(0), title: r.text(1))
        n.body = r.text(2)
        n.kind = NoteKind(rawValue: r.text(3)) ?? .note
        n.date = r.optText(4).map { DayKey($0) }
        n.pinned = r.bool(5)
        n.mood = r.optInt(6)
        n.createdAt = r.text(7)
        n.updatedAt = r.text(8)
        return n
    }

    /// `touch: false` keeps the edit time. Use it for changes the user did not make in the note itself.
    public func save(_ note: Note, touch: Bool = true) throws {
        var n = note
        if touch { n.updatedAt = Stamp.now() }
        try db.transaction {
            try db.execute(Self.upsert, [
                .text(n.id), .text(n.title), .text(n.body), .text(n.kind.rawValue), SQLValue(n.date?.string),
                .int(n.pinned ? 1 : 0), SQLValue(n.mood), .text(n.createdAt), .text(n.updatedAt),
            ])
            try search.upsert(.note, id: n.id, title: n.title, body: Self.searchBody(n))
        }
    }

    public func get(_ id: String) throws -> Note? {
        try db.queryOne(Self.select + " WHERE id = ?", [.text(id)], map: Self.map)
    }

    public func delete(_ id: String) throws {
        try db.transaction {
            try db.execute("DELETE FROM notes WHERE id = ?", [.text(id)])
            try search.remove(.note, id: id)
        }
    }

    static func searchBody(_ n: Note) -> String { ReferenceParser.searchText(NoteParser.withoutMarkers(n.body)) }

    /// Pinned first, then most recently edited.
    public func all() throws -> [Note] {
        try db.query(Self.select + " ORDER BY pinned DESC, updated_at DESC", map: Self.map)
    }

    /// Notes with a check box line that is tied to task `taskId`.
    public func withTaskMarker(_ taskId: String) throws -> [Note] {
        try db.query(Self.select + " WHERE instr(body, ?) > 0", [.text(NoteParser.marker(for: taskId))], map: Self.map)
    }

    public func daily(_ day: DayKey) throws -> Note? {
        try db.queryOne(Self.select + " WHERE kind = 'daily' AND date = ?", [.text(day.string)], map: Self.map)
    }

    public func weekly(_ monday: DayKey) throws -> Note? {
        try db.queryOne(Self.select + " WHERE kind = 'weekly' AND date = ?", [.text(monday.string)], map: Self.map)
    }

    /// Case-insensitive exact title match, newest first.
    public func byTitle(_ title: String) throws -> Note? {
        try db.queryOne(Self.select + " WHERE title = ? COLLATE NOCASE ORDER BY updated_at DESC", [.text(title)], map: Self.map)
    }

    public func titles(prefix: String, limit: Int = 8) throws -> [Note] {
        try db.query(Self.select + " WHERE title LIKE ? ESCAPE '\\' ORDER BY updated_at DESC LIMIT ?",
                     [.text(Self.escapeLike(prefix) + "%"), .int(limit)], map: Self.map)
    }

    /// Days that have a daily note with some text beyond the template headings.
    public func daysWithNotes(from: DayKey, to: DayKey) throws -> Set<DayKey> {
        let rows = try db.query("SELECT date FROM notes WHERE kind = 'daily' AND date >= ? AND date <= ? AND LENGTH(TRIM(REPLACE(REPLACE(REPLACE(REPLACE(body, '## Plan', ''), '## Notes', ''), '## Reflection', ''), char(10), ''))) > 0",
                                [.text(from.string), .text(to.string)]) { DayKey($0.text(0)) }
        return Set(rows)
    }

    /// The mood of each daily note that has one, by day.
    public func moods(from: DayKey, to: DayKey) throws -> [DayKey: Int] {
        let rows = try db.query("SELECT date, mood FROM notes WHERE kind = 'daily' AND mood IS NOT NULL AND date >= ? AND date <= ?",
                                [.text(from.string), .text(to.string)]) { (DayKey($0.text(0)), $0.int(1)) }
        return Dictionary(rows, uniquingKeysWith: { first, _ in first })
    }

    private static func escapeLike(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
    }
}

// MARK: - Lists, tags, links, settings

public final class ListRepo {
    let db: Database
    public init(db: Database) { self.db = db }
    private static let upsert = upsertSQL("lists", ["id", "name", "emoji", "color", "sort", "archived"])

    public func save(_ l: ListItem) throws {
        try db.execute(Self.upsert, [.text(l.id), .text(l.name), .text(l.emoji), .text(l.color), .int(l.sort), .int(l.archived ? 1 : 0)])
    }
    public func all(includeArchived: Bool = false) throws -> [ListItem] {
        try db.query("SELECT id, name, emoji, color, sort, archived FROM lists \(includeArchived ? "" : "WHERE archived = 0") ORDER BY sort, name") {
            ListItem(id: $0.text(0), name: $0.text(1), emoji: $0.text(2), color: $0.text(3), sort: $0.int(4), archived: $0.bool(5))
        }
    }
    public func get(_ id: String) throws -> ListItem? { try all(includeArchived: true).first { $0.id == id } }
    public func delete(_ id: String) throws { try db.execute("DELETE FROM lists WHERE id = ?", [.text(id)]) }
}

public final class TagRepo {
    let db: Database
    public init(db: Database) { self.db = db }

    /// Finds a tag by name (case-insensitive) or creates it.
    @discardableResult
    public func upsert(_ name: String) throws -> Tag {
        let clean = name.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespacesAndNewlines))
        if let t = try db.queryOne("SELECT id, name FROM tags WHERE name = ?", [.text(clean)], map: { Tag(id: $0.text(0), name: $0.text(1)) }) {
            return t
        }
        let t = Tag(name: clean)
        try db.execute("INSERT INTO tags (id, name) VALUES (?, ?)", [.text(t.id), .text(t.name)])
        return t
    }

    public func all() throws -> [Tag] {
        try db.query("SELECT id, name FROM tags ORDER BY name") { Tag(id: $0.text(0), name: $0.text(1)) }
    }

    public func setTags(taskId: String, names: [String]) throws {
        try db.transaction {
            try db.execute("DELETE FROM task_tags WHERE task_id = ?", [.text(taskId)])
            for n in names where !n.isEmpty {
                let t = try upsert(n)
                try db.execute("INSERT OR IGNORE INTO task_tags (task_id, tag_id) VALUES (?, ?)", [.text(taskId), .text(t.id)])
            }
        }
    }

    public func tags(forTask id: String) throws -> [String] {
        try db.query("SELECT tags.name FROM tags JOIN task_tags ON tags.id = tag_id WHERE task_id = ? ORDER BY tags.name", [.text(id)]) { $0.text(0) }
    }

    public func setTags(noteId: String, names: [String]) throws {
        try db.transaction {
            try db.execute("DELETE FROM note_tags WHERE note_id = ?", [.text(noteId)])
            for n in names where !n.isEmpty {
                let t = try upsert(n)
                try db.execute("INSERT OR IGNORE INTO note_tags (note_id, tag_id) VALUES (?, ?)", [.text(noteId), .text(t.id)])
            }
        }
    }

    public func tags(forNote id: String) throws -> [String] {
        try db.query("SELECT tags.name FROM tags JOIN note_tags ON tags.id = tag_id WHERE note_id = ? ORDER BY tags.name", [.text(id)]) { $0.text(0) }
    }

    /// Every tag that at least one note uses, A to Z.
    public func noteTagNames() throws -> [String] {
        try db.query("SELECT DISTINCT tags.name FROM tags JOIN note_tags ON tags.id = tag_id ORDER BY tags.name COLLATE NOCASE") { $0.text(0) }
    }
}

public final class LinkRepo {
    let db: Database
    public init(db: Database) { self.db = db }

    /// Replace every parsed link that starts at `src` (used each time a note is saved).
    public func replaceParsed(src: ItemRef, with targets: [ItemRef]) throws {
        try db.transaction {
            try db.execute("DELETE FROM links WHERE src_type = ? AND src_id = ? AND origin = 'parsed'", [.text(src.type.rawValue), .text(src.id)])
            for t in Set(targets) where t != src {
                try db.execute("INSERT OR IGNORE INTO links (src_type, src_id, dst_type, dst_id, origin) VALUES (?, ?, ?, ?, 'parsed')",
                               [.text(src.type.rawValue), .text(src.id), .text(t.type.rawValue), .text(t.id)])
            }
        }
    }

    public func addManual(src: ItemRef, dst: ItemRef) throws {
        try db.execute("INSERT OR IGNORE INTO links (src_type, src_id, dst_type, dst_id, origin) VALUES (?, ?, ?, ?, 'manual')",
                       [.text(src.type.rawValue), .text(src.id), .text(dst.type.rawValue), .text(dst.id)])
    }

    public func remove(src: ItemRef, dst: ItemRef) throws {
        try db.execute("DELETE FROM links WHERE src_type = ? AND src_id = ? AND dst_type = ? AND dst_id = ?",
                       [.text(src.type.rawValue), .text(src.id), .text(dst.type.rawValue), .text(dst.id)])
    }

    /// Items that link TO `dst`.
    public func backlinks(to dst: ItemRef) throws -> [ItemRef] {
        try db.query("SELECT src_type, src_id FROM links WHERE dst_type = ? AND dst_id = ?", [.text(dst.type.rawValue), .text(dst.id)]) {
            r -> ItemRef? in ItemType(rawValue: r.text(0)).map { ItemRef($0, r.text(1)) }
        }.compactMap { $0 }
    }

    /// Items that `src` links to.
    public func outgoing(from src: ItemRef) throws -> [ItemRef] {
        try db.query("SELECT dst_type, dst_id FROM links WHERE src_type = ? AND src_id = ?", [.text(src.type.rawValue), .text(src.id)]) {
            r -> ItemRef? in ItemType(rawValue: r.text(0)).map { ItemRef($0, r.text(1)) }
        }.compactMap { $0 }
    }
}

public final class SettingsRepo {
    let db: Database
    public init(db: Database) { self.db = db }

    public func get(_ key: String) throws -> String? {
        try db.queryOne("SELECT value FROM settings WHERE key = ?", [.text(key)]) { $0.text(0) }
    }
    public func remove(_ key: String) throws {
        try db.execute("DELETE FROM settings WHERE key = ?", [.text(key)])
    }
    public func set(_ key: String, _ value: String) throws {
        try db.execute("INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", [.text(key), .text(value)])
    }
}

/// All repositories on one database.
public final class Repos {
    public let db: Database
    public let search: SearchIndex
    public let tasks: TaskRepo
    public let events: EventRepo
    public let notes: NoteRepo
    public let goals: GoalRepo
    public let lists: ListRepo
    public let tags: TagRepo
    public let links: LinkRepo
    public let settings: SettingsRepo
    public let attachments: AttachmentRepo
    public let refs: ReferenceIndexer

    public init(db: Database) {
        self.db = db
        let s = SearchIndex(db: db)
        self.search = s
        self.tasks = TaskRepo(db: db, search: s)
        self.events = EventRepo(db: db, search: s)
        self.notes = NoteRepo(db: db, search: s)
        self.goals = GoalRepo(db: db)
        self.lists = ListRepo(db: db)
        self.tags = TagRepo(db: db)
        self.links = LinkRepo(db: db)
        self.settings = SettingsRepo(db: db)
        self.attachments = AttachmentRepo(db: db)
        self.refs = ReferenceIndexer(db: db, tasks: tasks, notes: notes, events: events, links: links, search: s)
    }

    /// Throws the search index away and builds it again from the tables.
    /// Time blocks are not searched, only real events.
    public func rebuildSearch() throws {
        try db.transaction {
            try db.execute("DELETE FROM search")
            for t in try tasks.all() { try search.upsert(.task, id: t.id, title: t.title, body: TaskRepo.searchBody(t)) }
            for e in try events.all() where e.kind == .event {
                try search.upsert(.event, id: e.id, title: e.title, body: EventRepo.searchBody(e))
            }
            for n in try notes.all() { try search.upsert(.note, id: n.id, title: n.title, body: NoteRepo.searchBody(n)) }
        }
    }
}
