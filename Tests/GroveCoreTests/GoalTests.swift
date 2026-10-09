import Testing
import Foundation
import SQLite3
@testable import GroveCore

/// Goals: a weekly target of hours or of sessions, and no date. Every block of the goal in the week counts.
/// The progress is never stored. It is worked out from the blocks (PLAN: goals).
struct GoalTests {
    private func makeRepos() throws -> Repos { Repos(db: try Database.inMemory()) }

    // 2026-10-05 is a Monday. The Monday-first week runs to Sunday 2026-10-11.
    private let monday = DayKey("2026-10-05")
    private let sunday = DayKey("2026-10-11")

    @discardableResult
    private func block(_ r: Repos, goal: String?, day: DayKey, from: Int = 600, to: Int = 660,
                       done: Bool = false, id: String = UUID().uuidString) throws -> EventItem {
        var e = EventItem(id: id, title: "Block", start: WallTime(day: day, minute: from), end: WallTime(day: day, minute: to),
                          kind: .block, goalId: goal, doneAt: done ? "2026-10-05T12:00:00" : nil)
        e.color = "accent"
        try r.events.save(e)
        return e
    }

    // MARK: The model

    @Test func aNewGoalHasNoColourFiveHoursAndNoNotes() {
        let g = GoalItem(title: "Read")
        #expect(g.color == "" && g.notes == "")
        #expect(g.kind == .hours)
        #expect(g.targetMin == 300 && g.targetCount == 3)
        #expect(!g.archived)
        #expect(g.sort == 0)
        #expect(!g.createdAt.isEmpty && g.createdAt == g.updatedAt)
    }

    @Test func anEventHasNoGoalAndIsNotDoneAtFirst() {
        let e = EventItem(title: "x", start: WallTime(day: monday, minute: 0), end: WallTime(day: monday, minute: 30))
        #expect(e.goalId == nil && e.doneAt == nil)
    }

    @Test func anOccurrenceOfARepeatingEventKeepsTheGoalAndDoneTime() {
        var series = EventItem(id: "S", title: "Read", start: WallTime(day: monday, minute: 600), end: WallTime(day: monday, minute: 660),
                               kind: .block, goalId: "G1", doneAt: "2026-10-05T12:00:00")
        series.recurrence = RecurrenceRule(freq: .daily)
        let day = monday.adding(days: 2)
        let o = RecurrenceEngine.occurrence(of: series, on: day)
        #expect(o.goalId == "G1" && o.doneAt == "2026-10-05T12:00:00")
    }

    // MARK: The repo

    @Test func aGoalIsSavedLoadedChangedAndDeleted() throws {
        let r = try makeRepos()
        var g = GoalItem(id: "G1", title: "Read", notes: "Novels only", color: "teal", targetMin: 360, sort: 2)
        try r.goals.upsert(g)
        let got = try #require(try r.goals.get("G1"))
        #expect(got.title == "Read" && got.notes == "Novels only" && got.color == "teal")
        #expect(got.kind == .hours && got.targetMin == 360 && got.targetCount == 3 && got.sort == 2 && !got.archived)
        g.title = "Read more"
        g.targetMin = 420
        g.kind = .sessions
        g.targetCount = 4
        g.archived = true
        try r.goals.upsert(g)
        #expect(try r.goals.get("G1")?.title == "Read more")
        #expect(try r.goals.get("G1")?.targetMin == 420)
        #expect(try r.goals.get("G1")?.kind == .sessions)
        #expect(try r.goals.get("G1")?.targetCount == 4)
        #expect(try r.goals.get("G1")?.archived == true)
        #expect(try r.db.query("SELECT COUNT(*) FROM goals") { $0.int(0) } == [1])   // an update, not a second row
        try r.goals.delete("G1")
        #expect(try r.goals.get("G1") == nil)
    }

    @Test func savingAGoalAgainRefreshesItsEditTimeAndKeepsTheCreationTime() throws {
        let r = try makeRepos()
        var g = GoalItem(id: "G1", title: "Read")
        g.createdAt = "2026-01-01T08:00:00"
        g.updatedAt = "2026-01-01T08:00:00"
        try r.goals.upsert(g)
        let got = try #require(try r.goals.get("G1"))
        #expect(got.createdAt == "2026-01-01T08:00:00")
        #expect(got.updatedAt != "2026-01-01T08:00:00")
    }

    @Test func allHidesArchivedGoalsUnlessAsked() throws {
        let r = try makeRepos()
        try r.goals.upsert(GoalItem(id: "A", title: "A", sort: 2))
        try r.goals.upsert(GoalItem(id: "B", title: "B", sort: 1))
        try r.goals.upsert(GoalItem(id: "C", title: "C", sort: 3, archived: true))
        #expect(try r.goals.all().map(\.id) == ["B", "A"])
        #expect(try r.goals.all(includeArchived: true).map(\.id) == ["B", "A", "C"])
    }

    @Test func anEventKeepsItsGoalAndDoneTime() throws {
        let r = try makeRepos()
        try block(r, goal: "G1", day: monday, done: true, id: "E1")
        let got = try #require(try r.events.get("E1"))
        #expect(got.goalId == "G1")
        #expect(got.doneAt == "2026-10-05T12:00:00")
        var plain = got
        plain.goalId = nil
        plain.doneAt = nil
        try r.events.save(plain)
        #expect(try r.events.get("E1")?.goalId == nil && r.events.get("E1")?.doneAt == nil)
    }

    // MARK: Progress is worked out from the blocks

    @Test func minutesAddUpEveryBlockOfTheGoalInTheRange() throws {
        let r = try makeRepos()
        try block(r, goal: "G1", day: monday, from: 600, to: 660)                          // 60
        try block(r, goal: "G1", day: monday.adding(days: 2), from: 540, to: 600, done: true) // 60, an old done mark changes nothing
        try block(r, goal: "G1", day: monday.adding(days: 3), from: 540, to: 570)          // 30
        #expect(try r.goals.minutes(goalId: "G1", from: monday, to: sunday) == 150)
    }

    @Test func sessionsCountTheBlocksWhateverTheirLength() throws {
        let r = try makeRepos()
        try block(r, goal: "G1", day: monday, from: 600, to: 615)
        try block(r, goal: "G1", day: monday, from: 700, to: 940)
        try block(r, goal: "G1", day: sunday, from: 800, to: 845, done: true)
        #expect(try r.goals.sessions(goalId: "G1", from: monday, to: sunday) == 3)
    }

    @Test func theFirstAndLastDayOfTheRangeCount() throws {
        let r = try makeRepos()
        try block(r, goal: "G1", day: monday)
        try block(r, goal: "G1", day: sunday)
        #expect(try r.goals.minutes(goalId: "G1", from: monday, to: sunday) == 120)
        #expect(try r.goals.sessions(goalId: "G1", from: monday, to: sunday) == 2)
    }

    @Test func theDayBeforeAndTheDayAfterTheRangeDoNotCount() throws {
        let r = try makeRepos()
        try block(r, goal: "G1", day: monday.adding(days: -1), from: 1380, to: 1440)   // Sunday before, 23:00 to midnight
        try block(r, goal: "G1", day: sunday.adding(days: 1), from: 0, to: 60)         // Monday after
        #expect(try r.goals.minutes(goalId: "G1", from: monday, to: sunday) == 0)
        #expect(try r.goals.sessions(goalId: "G1", from: monday, to: sunday) == 0)
    }

    @Test func aSundayFirstWeekHoldsTheSundayBeforeButNotTheNextOne() throws {
        let r = try makeRepos()
        let firstSunday = monday.adding(days: -1)   // 2026-10-04
        try block(r, goal: "G1", day: firstSunday)
        try block(r, goal: "G1", day: sunday)       // Sunday 2026-10-11 starts the next Sunday-first week
        #expect(try r.goals.minutes(goalId: "G1", from: firstSunday, to: firstSunday.adding(days: 6)) == 60)
        #expect(try r.goals.minutes(goalId: "G1", from: monday, to: sunday) == 60)
    }

    @Test func otherGoalsAndPlainBlocksAreNotCounted() throws {
        let r = try makeRepos()
        try block(r, goal: "G2", day: monday)
        try block(r, goal: nil, day: monday)
        try block(r, goal: "G1", day: monday, from: 600, to: 645)
        #expect(try r.goals.minutes(goalId: "G1", from: monday, to: sunday) == 45)
        #expect(try r.goals.minutes(goalId: "G2", from: monday, to: sunday) == 60)
        #expect(try r.goals.sessions(goalId: "G1", from: monday, to: sunday) == 1)
    }

    @Test func aLongerBlockCountsItsWholeLength() throws {
        let r = try makeRepos()
        try block(r, goal: "G1", day: monday, from: 480, to: 720)
        #expect(try r.goals.minutes(goalId: "G1", from: monday, to: monday) == 240)
    }

    @Test func aBlockThatRunsPastMidnightCountsOnItsStartDayWithItsWholeLength() throws {
        let r = try makeRepos()
        var e = EventItem(id: "N", title: "Night", start: WallTime(day: sunday, minute: 1380), end: WallTime(day: sunday.adding(days: 1), minute: 60),
                          kind: .block, goalId: "G1")
        e.color = "accent"
        try r.events.save(e)
        #expect(try r.goals.minutes(goalId: "G1", from: monday, to: sunday) == 120)
        #expect(try r.goals.minutes(goalId: "G1", from: sunday.adding(days: 1), to: sunday.adding(days: 7)) == 0)
        #expect(try r.goals.sessions(goalId: "G1", from: monday, to: sunday) == 1)
    }

    // MARK: Deleting a goal

    @Test func deletingAGoalKeepsItsBlocksAsPlainBlocks() throws {
        let r = try makeRepos()
        try r.goals.upsert(GoalItem(id: "G1", title: "Read"))
        try r.goals.upsert(GoalItem(id: "G2", title: "Run"))
        try block(r, goal: "G1", day: monday, done: true, id: "E1")
        try block(r, goal: "G1", day: monday, done: false, id: "E2")
        try block(r, goal: "G2", day: monday, done: true, id: "E3")
        try r.goals.delete("G1")
        #expect(try r.goals.get("G1") == nil)
        for id in ["E1", "E2"] {
            let e = try #require(try r.events.get(id))
            #expect(e.goalId == nil && e.doneAt == nil && e.kind == .block)
        }
        #expect(try r.events.get("E3")?.goalId == "G2")
        #expect(try r.goals.minutes(goalId: "G1", from: monday, to: sunday) == 0)
        #expect(try r.goals.minutes(goalId: "G2", from: monday, to: sunday) == 60)
    }

    // MARK: The database upgrade

    @Test func upgradingAVersionFourDatabaseKeepsItsData() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("grove-m5-\(UUID().uuidString).sqlite").path
        defer { for s in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + s) } }
        var handle: OpaquePointer?
        #expect(sqlite3_open(path, &handle) == SQLITE_OK)
        let seed = Migrations.all[0...3].joined(separator: ";") + """
            ;PRAGMA user_version = 4;
            INSERT INTO tasks (id, title, notes, created_at, updated_at) VALUES ('t1', 'Old task', 'body', '2026-10-01T09:00:00', '2026-10-01T09:00:00');
            INSERT INTO events (id, title, start, end, kind, task_id, created_at, updated_at)
              VALUES ('e1', 'Old block', '2026-10-01T09:00', '2026-10-01T10:00', 'block', 't1', '2026-10-01T09:00:00', '2026-10-01T09:00:00');
            """
        #expect(sqlite3_exec(handle, seed, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(handle)
        #expect(Migrations.all.count >= 5)
        let r = Repos(db: try Database(path: path))
        #expect(r.db.userVersion == Migrations.all.count)
        #expect(try r.tasks.get("t1")?.title == "Old task")
        let old = try #require(try r.events.get("e1"))
        #expect(old.title == "Old block" && old.taskId == "t1")
        #expect(old.goalId == nil && old.doneAt == nil)
        #expect(try r.goals.all().isEmpty)
        try r.goals.upsert(GoalItem(id: "g1", title: "Read"))
        #expect(try r.goals.get("g1")?.title == "Read")
    }

    @Test func upgradingAVersionFiveDatabaseMakesTheOldGoalsHourGoals() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("grove-m6-\(UUID().uuidString).sqlite").path
        defer { for s in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + s) } }
        var handle: OpaquePointer?
        #expect(sqlite3_open(path, &handle) == SQLITE_OK)
        let seed = Migrations.all[0...4].joined(separator: ";") + """
            ;PRAGMA user_version = 5;
            INSERT INTO goals (id, title, target_min, created_at, updated_at) VALUES ('g1', 'Read', 360, '2026-10-01T09:00:00', '2026-10-01T09:00:00');
            """
        #expect(sqlite3_exec(handle, seed, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(handle)
        let r = Repos(db: try Database(path: path))
        #expect(r.db.userVersion == Migrations.all.count)
        let g = try #require(try r.goals.get("g1"))
        #expect(g.title == "Read" && g.kind == .hours && g.targetMin == 360 && g.targetCount == 3)
    }

    // MARK: Export and import

    private func fill(_ r: Repos) throws {
        try r.goals.upsert(GoalItem(id: "G1", title: "Read", notes: "Novels", color: "blue", targetMin: 360, sort: 1))
        try r.goals.upsert(GoalItem(id: "G2", title: "Run", targetMin: 180, sort: 2, archived: true, kind: .sessions, targetCount: 4))
        try block(r, goal: "G1", day: monday, from: 600, to: 690, done: true, id: "E1")
        try block(r, goal: "G1", day: monday.adding(days: 1), from: 600, to: 660, done: false, id: "E2")
        try r.tasks.save(TaskItem(id: "T1", title: "Write"))
    }

    @Test func goalsAndTheirBlocksComeBackFromAnExportFile() throws {
        let a = try makeRepos(); try fill(a)
        let b = try makeRepos()
        try DataExport.importData(DataExport.export(from: a.db), into: b)
        #expect(try b.goals.all(includeArchived: true) == a.goals.all(includeArchived: true))
        #expect(try b.goals.get("G1")?.notes == "Novels")
        #expect(try b.goals.get("G2")?.archived == true)
        #expect(try b.goals.get("G2")?.kind == .sessions && b.goals.get("G2")?.targetCount == 4)
        let e1 = try #require(try b.events.get("E1"))
        #expect(e1.goalId == "G1")
        #expect(try b.goals.minutes(goalId: "G1", from: monday, to: sunday) == 150)
        #expect(try b.goals.sessions(goalId: "G1", from: monday, to: sunday) == 2)
    }

    @Test func theFileHoldsTheGoalsTable() throws {
        let a = try makeRepos(); try fill(a)
        #expect(DataExport.tables.contains("goals"))
        let obj = try #require(try JSONSerialization.jsonObject(with: DataExport.export(from: a.db)) as? [String: Any])
        let tables = try #require(obj["tables"] as? [String: [[String: Any]]])
        #expect(tables["goals"]?.count == 2)
        #expect(tables["events"]?.first?["goal_id"] as? String == "G1")
    }

    @Test func importingReplacesTheGoalsThatWereThere() throws {
        let a = try makeRepos(); try fill(a)
        let b = try makeRepos()
        try b.goals.upsert(GoalItem(id: "OLD", title: "Old goal"))
        try DataExport.importData(DataExport.export(from: a.db), into: b)
        #expect(try b.goals.get("OLD") == nil)
        #expect(try b.goals.all(includeArchived: true).count == 2)
    }

    @Test func anExportFileWithGoalsButNoKindImportsThemAsHourGoals() throws {
        let a = try makeRepos(); try fill(a)
        var obj = try #require(try JSONSerialization.jsonObject(with: DataExport.export(from: a.db)) as? [String: Any])
        var tables = try #require(obj["tables"] as? [String: [[String: Any]]])
        tables["goals"] = tables["goals"]?.map { row in          // a version 5 file has no kind and no count
            var row = row
            row["kind"] = nil
            row["target_count"] = nil
            return row
        }
        obj["tables"] = tables
        obj["schema"] = 5
        let b = try makeRepos()
        try DataExport.importData(JSONSerialization.data(withJSONObject: obj), into: b)
        let goals = try b.goals.all(includeArchived: true)
        #expect(goals.count == 2 && goals.allSatisfy { $0.kind == .hours && $0.targetCount == 3 })
        #expect(try b.goals.get("G2")?.targetMin == 180)
    }

    @Test func anOldExportFileWithoutGoalsStillImports() throws {
        let a = try makeRepos(); try fill(a)
        var obj = try #require(try JSONSerialization.jsonObject(with: DataExport.export(from: a.db)) as? [String: Any])
        var tables = try #require(obj["tables"] as? [String: [[String: Any]]])
        tables["goals"] = nil                                      // the table is not in an old file
        tables["events"] = tables["events"]?.map { row in          // nor are the two columns
            var row = row
            row["goal_id"] = nil
            row["done_at"] = nil
            return row
        }
        obj["tables"] = tables
        obj["schema"] = 4
        let b = try makeRepos()
        try b.goals.upsert(GoalItem(id: "OLD", title: "Old goal"))
        try DataExport.importData(JSONSerialization.data(withJSONObject: obj), into: b)
        #expect(try b.goals.all(includeArchived: true).isEmpty)
        let e = try #require(try b.events.get("E1"))
        #expect(e.goalId == nil && e.doneAt == nil && e.title == "Block")
        #expect(try b.tasks.get("T1")?.title == "Write")
    }
}
