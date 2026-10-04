import Testing
import Foundation
@testable import GroveCore

struct DayKeyTests {
    @Test func weekdayAndWeekStart() {
        let fri = DayKey("2026-10-02")
        #expect(fri.weekdayIndex == 5)
        #expect(fri.weekStart() == DayKey("2026-09-28"))
        #expect(fri.weekStart(mondayFirst: false) == DayKey("2026-09-27"))
        #expect(DayKey("2026-10-04").weekdayIndex == 7)
        #expect(DayKey("2026-10-04").weekStart() == DayKey("2026-09-28"))
    }

    @Test func addingDaysCrossesMonths() {
        #expect(DayKey("2026-10-31").adding(days: 1) == DayKey("2026-11-01"))
        #expect(DayKey("2026-03-01").adding(days: -1) == DayKey("2026-02-28"))
        #expect(DayKey("2026-10-02").days(until: DayKey("2026-10-09")) == 7)
    }

    @Test func parseRejectsBadDates() {
        #expect(DayKey.parse("2026-02-30") == nil)
        #expect(DayKey.parse("2026-1-1") == nil)
        #expect(DayKey.parse("hello") == nil)
        #expect(DayKey.parse("2026-02-28") == DayKey("2026-02-28"))
    }

    @Test func wallTimeRoundTrip() {
        let w = WallTime("2026-10-02T14:05")
        #expect(w?.minute == 14 * 60 + 5)
        #expect(w?.string == "2026-10-02T14:05")
        #expect(WallTime("2026-10-02T25:00") == nil)
        #expect(WallTime(day: "2026-10-02", minute: 1440).string == "2026-10-02T24:00")
    }

    @Test func weekNumber() {
        #expect(DayKey("2026-10-02").weekOfYear == 40)
    }
}

struct DatabaseTests {
    func makeRepos() throws -> Repos { Repos(db: try Database.inMemory()) }

    @Test func migrationsCreateSchema() throws {
        let db = try Database.inMemory()
        #expect(db.userVersion == Migrations.all.count)
        let tables = try db.query("SELECT name FROM sqlite_master WHERE type IN ('table') ORDER BY name") { $0.text(0) }
        for t in ["tasks", "events", "notes", "lists", "links", "tags", "task_tags", "note_tags", "settings", "event_exdates", "search"] {
            #expect(tables.contains(t), "missing table \(t)")
        }
    }

    @Test func migrationsAreIdempotent() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("grove-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("a.sqlite").path
        do { let r = Repos(db: try Database(path: path)); try r.tasks.save(TaskItem(title: "keep me")) }
        let again = Repos(db: try Database(path: path))
        #expect(try again.tasks.all().map(\.title) == ["keep me"])
    }

    @Test func taskCRUD() throws {
        let r = try makeRepos()
        var t = TaskItem(title: "Finish lab report", notes: "use template", priority: 3, bucket: .day,
                         planDate: "2026-10-02", due: "2026-10-03", estimateMin: 90,
                         recurrence: RecurrenceRule(freq: .weekly, interval: 2, weekdays: [1, 3]))
        try r.tasks.save(t)
        let got = try #require(try r.tasks.get(t.id))
        #expect(got.title == "Finish lab report")
        #expect(got.priority == 3)
        #expect(got.planDate == DayKey("2026-10-02"))
        #expect(got.estimateMin == 90)
        #expect(got.recurrence == RecurrenceRule(freq: .weekly, interval: 2, weekdays: [1, 3]))
        t.status = .done
        t.completedAt = "2026-10-02T10:00:00"
        try r.tasks.save(t)
        #expect(try r.tasks.get(t.id)?.status == .done)
        #expect(try r.tasks.all().count == 1)
        try r.tasks.delete(t.id)
        #expect(try r.tasks.get(t.id) == nil)
    }

    @Test func taskQueriesByBucket() throws {
        let r = try makeRepos()
        try r.tasks.save(TaskItem(title: "today", bucket: .day, planDate: "2026-10-02"))
        try r.tasks.save(TaskItem(title: "yesterday", bucket: .day, planDate: "2026-10-01"))
        try r.tasks.save(TaskItem(title: "week", bucket: .week, planWeek: "2026-09-28"))
        try r.tasks.save(TaskItem(title: "inbox"))
        try r.tasks.save(TaskItem(title: "later", bucket: .someday))
        #expect(try r.tasks.forDay("2026-10-02").map(\.title) == ["today"])
        #expect(try r.tasks.overdue(before: "2026-10-02").map(\.title) == ["yesterday"])
        #expect(try r.tasks.forWeek("2026-09-28").map(\.title) == ["week"])
        #expect(try r.tasks.inbox().map(\.title) == ["inbox"])
        #expect(try r.tasks.someday().map(\.title) == ["later"])
        #expect(try r.tasks.inRange("2026-10-01", "2026-10-02").count == 2)
    }

    @Test func deletingTaskCascadesToSubtasksAndBlocks() throws {
        let r = try makeRepos()
        let parent = TaskItem(title: "parent")
        let child = TaskItem(title: "child", parentId: parent.id)
        try r.tasks.save(parent)
        try r.tasks.save(child)
        let block = EventItem(title: "parent", start: WallTime(day: "2026-10-02", minute: 600),
                              end: WallTime(day: "2026-10-02", minute: 660), kind: .block, taskId: parent.id)
        try r.events.save(block)
        try r.tasks.delete(parent.id)
        #expect(try r.tasks.get(child.id) == nil)
        #expect(try r.events.get(block.id) == nil)
    }

    @Test func savingAgainDoesNotWipeChildren() throws {
        let r = try makeRepos()
        var parent = TaskItem(title: "parent")
        try r.tasks.save(parent)
        try r.tasks.save(TaskItem(title: "child", parentId: parent.id))
        parent.title = "renamed"
        try r.tasks.save(parent)
        #expect(try r.tasks.subtasks(of: parent.id).count == 1)
    }

    @Test func eventsInRangeAndSeries() throws {
        let r = try makeRepos()
        let a = EventItem(title: "Dentist", start: WallTime(day: "2026-10-02", minute: 840), end: WallTime(day: "2026-10-02", minute: 900))
        let b = EventItem(title: "Next week", start: WallTime(day: "2026-10-09", minute: 540), end: WallTime(day: "2026-10-09", minute: 600))
        let series = EventItem(title: "Standup", start: WallTime(day: "2026-09-28", minute: 570), end: WallTime(day: "2026-09-28", minute: 585),
                               recurrence: RecurrenceRule(freq: .daily))
        for e in [a, b, series] { try r.events.save(e) }
        #expect(try r.events.inRange("2026-10-02", "2026-10-02").map(\.title) == ["Dentist"])
        #expect(try r.events.inRange("2026-10-01", "2026-10-10").count == 2)
        #expect(try r.events.recurringSeries().map(\.title) == ["Standup"])
        try r.events.addExdate(series.id, "2026-10-01")
        try r.events.addExdate(series.id, "2026-10-01")
        #expect(try r.events.exdates(series.id) == [DayKey("2026-10-01")])
        try r.events.removeExdate(series.id, "2026-10-01")
        #expect(try r.events.exdates(series.id).isEmpty)
    }

    @Test func eventDuration() {
        let e = EventItem(title: "x", start: WallTime(day: "2026-10-02", minute: 660), end: WallTime(day: "2026-10-02", minute: 750))
        #expect(e.durationMinutes == 90)
    }

    @Test func notesDailyIsUniquePerDay() throws {
        let r = try makeRepos()
        try r.notes.save(Note(title: "Fri", kind: .daily, date: "2026-10-02"))
        #expect(throws: (any Error).self) {
            try r.notes.save(Note(title: "Fri again", kind: .daily, date: "2026-10-02"))
        }
        #expect(try r.notes.daily("2026-10-02")?.title == "Fri")
        try r.notes.save(Note(title: "Lab 4 — notes", body: "std dev"))
        #expect(try r.notes.byTitle("lab 4 — NOTES")?.body == "std dev")
        #expect(try r.notes.titles(prefix: "Lab").count == 1)
    }

    @Test func tagsAreCaseInsensitiveAndReplaceable() throws {
        let r = try makeRepos()
        let t = TaskItem(title: "x")
        try r.tasks.save(t)
        try r.tags.setTags(taskId: t.id, names: ["Home", "#errands"])
        #expect(try r.tags.tags(forTask: t.id) == ["errands", "Home"])
        try r.tags.setTags(taskId: t.id, names: ["home"])
        #expect(try r.tags.tags(forTask: t.id) == ["Home"])
        #expect(try r.tags.all().count == 2)
        #expect(try r.tasks.withTag("home").count == 1)
    }

    @Test func linksReplaceAndBacklink() throws {
        let r = try makeRepos()
        let a = ItemRef(.note, "A"), b = ItemRef(.note, "B"), t = ItemRef(.task, "T")
        try r.links.replaceParsed(src: a, with: [b, t, b])
        #expect(Set(try r.links.backlinks(to: b)) == [a])
        #expect(Set(try r.links.outgoing(from: a)) == [b, t])
        try r.links.replaceParsed(src: a, with: [t])
        #expect(try r.links.backlinks(to: b).isEmpty)
        try r.links.addManual(src: a, dst: b)
        try r.links.replaceParsed(src: a, with: [])
        #expect(try r.links.backlinks(to: b) == [a]) // manual links survive re-parsing
    }

    @Test func searchFindsWordsAndPrefixes() throws {
        let r = try makeRepos()
        try r.notes.save(Note(title: "Lab 4", body: "Error bars must use standard deviation"))
        let t = TaskItem(title: "Buy oat milk")
        try r.tasks.save(t)
        #expect(try r.search.search("deviation").first?.ref.type == .note)
        #expect(try r.search.search("stand dev").count == 1)
        #expect(try r.search.search("oat").first?.ref == ItemRef(.task, t.id))
        #expect(try r.search.search("oat", types: [.note]).isEmpty)
        #expect(try r.search.search("   ").isEmpty)
        try r.tasks.delete(t.id)
        #expect(try r.search.search("oat").isEmpty)
    }

    @Test func settingsRoundTrip() throws {
        let r = try makeRepos()
        #expect(try r.settings.get("theme") == nil)
        try r.settings.set("theme", "vintage")
        try r.settings.set("theme", "grove")
        #expect(try r.settings.get("theme") == "grove")
    }

    @Test func transactionRollsBackOnError() throws {
        let r = try makeRepos()
        struct Boom: Error {}
        #expect(throws: Boom.self) {
            try r.db.transaction {
                try r.tasks.save(TaskItem(title: "ghost"))
                throw Boom()
            }
        }
        #expect(try r.tasks.all().isEmpty)
    }

    @Test func thousandTasksQueryIsFast() throws {
        let r = try makeRepos()
        try r.db.transaction {
            for i in 0..<1000 {
                let day = DayKey("2026-10-02").adding(days: i % 30)
                try r.tasks.save(TaskItem(title: "Task \(i)", bucket: .day, planDate: day))
            }
        }
        let clock = ContinuousClock()
        var count = 0
        let elapsed = try clock.measure { count = try r.tasks.forDay("2026-10-05").count }
        #expect(count > 0)
        #expect(elapsed < .milliseconds(50))
    }

    @Test func dailyBackupIsCreatedOnceAndTrimmed() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("grove-backup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = try makeRepos()
        try r.tasks.save(TaskItem(title: "backed up"))
        #expect(try Backup.runDaily(db: r.db, directory: dir, today: "2026-10-02") != nil)
        #expect(try Backup.runDaily(db: r.db, directory: dir, today: "2026-10-02") == nil)
        for i in 3...6 { try Backup.runDaily(db: r.db, directory: dir, today: DayKey("2026-10-0\(i)"), keep: 3) }
        let names = Backup.list(directory: dir).map(\.lastPathComponent)
        #expect(names == ["grove-2026-10-06.sqlite", "grove-2026-10-05.sqlite", "grove-2026-10-04.sqlite"])
        let copy = Repos(db: try Database(path: dir.appendingPathComponent("grove-2026-10-06.sqlite").path))
        #expect(try copy.tasks.all().map(\.title) == ["backed up"])
    }

    @Test func theCopyBeforeAnImportReplacesTheOlderOneAndStaysOutOfTheDailyList() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("grove-safety-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = try makeRepos()
        try r.tasks.save(TaskItem(title: "first"))
        let one = try Backup.safetyCopy(db: r.db, directory: dir)
        try r.tasks.save(TaskItem(title: "second"))
        let two = try Backup.safetyCopy(db: r.db, directory: dir)
        #expect(one == two && two.lastPathComponent == "before-import.sqlite")
        #expect(Backup.list(directory: dir).isEmpty)
        let copy = Repos(db: try Database(path: two.path))
        #expect(Set(try copy.tasks.all().map(\.title)) == ["first", "second"])
    }
}
