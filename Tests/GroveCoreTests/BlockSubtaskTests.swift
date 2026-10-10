import Testing
import Foundation
import SQLite3
@testable import GroveCore

/// Subtasks of one goal block. They belong to that one block (one event), not to the goal.
/// Another block of the same goal has its own list, which starts empty.
struct BlockSubtaskTests {
    private func makeRepos() throws -> Repos { Repos(db: try Database.inMemory()) }

    private let monday = DayKey("2026-10-05")

    @discardableResult
    private func goalBlock(_ r: Repos, goal: String = "G1", day: DayKey, id: String) throws -> EventItem {
        let e = EventItem(id: id, title: "Read", start: WallTime(day: day, minute: 600), end: WallTime(day: day, minute: 660),
                          kind: .block, goalId: goal)
        try r.events.save(e)
        return e
    }

    private func twoBlocksOfOneGoal() throws -> Repos {
        let r = try makeRepos()
        try r.goals.upsert(GoalItem(id: "G1", title: "Read"))
        try goalBlock(r, day: monday, id: "E1")
        try goalBlock(r, day: monday.adding(days: 1), id: "E2")
        return r
    }

    // MARK: The model

    @Test func aNewSubtaskIsOpenAndHasStamps() {
        let s = BlockSubtaskItem(eventId: "E1", title: "Chapter 3")
        #expect(s.eventId == "E1" && s.title == "Chapter 3")
        #expect(s.doneAt == nil && !s.isDone)
        #expect(!s.createdAt.isEmpty && s.createdAt == s.updatedAt)
    }

    // MARK: One instance only

    @Test func subtasksStayOnTheOneGoalBlock() throws {
        let r = try twoBlocksOfOneGoal()
        try r.blockSubtasks.save(BlockSubtaskItem(id: "S1", eventId: "E1", title: "Chapter 3", sort: 1))
        try r.blockSubtasks.save(BlockSubtaskItem(id: "S2", eventId: "E1", title: "Chapter 4", sort: 2))
        #expect(try r.blockSubtasks.forEvent("E1").map(\.title) == ["Chapter 3", "Chapter 4"])
    }

    @Test func anotherBlockOfTheSameGoalHasNone() throws {
        let r = try twoBlocksOfOneGoal()
        try r.blockSubtasks.save(BlockSubtaskItem(id: "S1", eventId: "E1", title: "Chapter 3"))
        #expect(try r.blockSubtasks.forEvent("E2").isEmpty)
        try r.blockSubtasks.save(BlockSubtaskItem(id: "S2", eventId: "E2", title: "Notes"))
        #expect(try r.blockSubtasks.forEvent("E1").map(\.id) == ["S1"])
        #expect(try r.blockSubtasks.forEvent("E2").map(\.id) == ["S2"])
    }

    @Test func theGoalItselfIsNotChanged() throws {
        let r = try twoBlocksOfOneGoal()
        let before = try #require(try r.goals.get("G1"))
        try r.blockSubtasks.save(BlockSubtaskItem(id: "S1", eventId: "E1", title: "Chapter 3"))
        #expect(try r.goals.get("G1") == before)
    }

    @Test func savingTwiceUpdatesTheRowAndTicksItDone() throws {
        let r = try twoBlocksOfOneGoal()
        var s = BlockSubtaskItem(id: "S1", eventId: "E1", title: "Chapter 3")
        try r.blockSubtasks.save(s)
        s.title = "Chapter 3 and 4"
        s.doneAt = "2026-10-05T11:00:00"
        try r.blockSubtasks.save(s)
        let back = try #require(try r.blockSubtasks.get("S1"))
        #expect(back.title == "Chapter 3 and 4" && back.isDone)
        #expect(try r.blockSubtasks.forEvent("E1").count == 1)
    }

    @Test func theListComesInSortOrder() throws {
        let r = try twoBlocksOfOneGoal()
        try r.blockSubtasks.save(BlockSubtaskItem(id: "S2", eventId: "E1", title: "Second", sort: 2))
        try r.blockSubtasks.save(BlockSubtaskItem(id: "S1", eventId: "E1", title: "First", sort: 1))
        #expect(try r.blockSubtasks.forEvent("E1").map(\.id) == ["S1", "S2"])
        #expect(try r.blockSubtasks.forEvents(["E1", "E2"])["E1"]?.map(\.id) == ["S1", "S2"])
        #expect(try r.blockSubtasks.forEvents(["E1", "E2"])["E2"] == nil)
    }

    @Test func deletingASubtaskRemovesOnlyIt() throws {
        let r = try twoBlocksOfOneGoal()
        try r.blockSubtasks.save(BlockSubtaskItem(id: "S1", eventId: "E1", title: "A"))
        try r.blockSubtasks.save(BlockSubtaskItem(id: "S2", eventId: "E1", title: "B"))
        try r.blockSubtasks.delete("S1")
        #expect(try r.blockSubtasks.forEvent("E1").map(\.id) == ["S2"])
    }

    @Test func deletingTheBlockDeletesItsSubtasks() throws {
        let r = try twoBlocksOfOneGoal()
        try r.blockSubtasks.save(BlockSubtaskItem(id: "S1", eventId: "E1", title: "A"))
        try r.blockSubtasks.save(BlockSubtaskItem(id: "S2", eventId: "E2", title: "B"))
        try r.events.delete("E1")
        #expect(try r.blockSubtasks.get("S1") == nil)
        #expect(try r.blockSubtasks.get("S2") != nil)
    }

    @Test func aSubtaskNeedsABlockThatExists() throws {
        let r = try makeRepos()
        #expect(throws: (any Error).self) { try r.blockSubtasks.save(BlockSubtaskItem(eventId: "nope", title: "A")) }
    }

    @Test func deletingTheGoalKeepsTheBlockAndItsSubtasks() throws {
        let r = try twoBlocksOfOneGoal()
        try r.blockSubtasks.save(BlockSubtaskItem(id: "S1", eventId: "E1", title: "A"))
        try r.goals.delete("G1")
        #expect(try r.events.get("E1")?.goalId == nil)
        #expect(try r.blockSubtasks.forEvent("E1").map(\.id) == ["S1"])
    }

    @Test func movingTheBlockKeepsItsSubtasks() throws {
        let r = try twoBlocksOfOneGoal()
        try r.blockSubtasks.save(BlockSubtaskItem(id: "S1", eventId: "E1", title: "A"))
        var e = try #require(try r.events.get("E1"))
        e.start = WallTime(day: monday, minute: 720)
        e.end = WallTime(day: monday, minute: 780)
        try r.events.save(e)   // an upsert, not a replace, so the cascade does not fire
        #expect(try r.blockSubtasks.forEvent("E1").map(\.id) == ["S1"])
    }

    // MARK: The database upgrade

    @Test func upgradingAVersionSixDatabaseKeepsItsData() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("grove-m7-\(UUID().uuidString).sqlite").path
        defer { for s in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + s) } }
        var handle: OpaquePointer?
        #expect(sqlite3_open(path, &handle) == SQLITE_OK)
        let seed = Migrations.all[0...5].joined(separator: ";") + """
            ;PRAGMA user_version = 6;
            INSERT INTO goals (id, title, target_min, kind, target_count, created_at, updated_at)
              VALUES ('g1', 'Read', 360, 'sessions', 4, '2026-10-01T09:00:00', '2026-10-01T09:00:00');
            INSERT INTO tasks (id, title, notes, created_at, updated_at) VALUES ('t1', 'Old task', 'body', '2026-10-01T09:00:00', '2026-10-01T09:00:00');
            INSERT INTO events (id, title, start, end, kind, goal_id, done_at, created_at, updated_at)
              VALUES ('e1', 'Read', '2026-10-01T09:00', '2026-10-01T10:00', 'block', 'g1', '2026-10-01T10:00:00', '2026-10-01T09:00:00', '2026-10-01T09:00:00');
            """
        #expect(sqlite3_exec(handle, seed, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(handle)
        #expect(Migrations.all.count >= 7)
        let r = Repos(db: try Database(path: path))
        #expect(r.db.userVersion == Migrations.all.count)
        let g = try #require(try r.goals.get("g1"))
        #expect(g.title == "Read" && g.kind == .sessions && g.targetCount == 4 && g.targetMin == 360)
        #expect(try r.tasks.get("t1")?.notes == "body")
        let e = try #require(try r.events.get("e1"))
        #expect(e.goalId == "g1" && e.doneAt == "2026-10-01T10:00:00" && e.title == "Read")
        #expect(try r.blockSubtasks.forEvent("e1").isEmpty)
        try r.blockSubtasks.save(BlockSubtaskItem(id: "s1", eventId: "e1", title: "Chapter 3"))
        #expect(try r.blockSubtasks.forEvent("e1").map(\.title) == ["Chapter 3"])
    }

    // MARK: Export and import

    @Test func subtasksOfABlockComeBackFromAnExportFile() throws {
        let a = try twoBlocksOfOneGoal()
        try a.blockSubtasks.save(BlockSubtaskItem(id: "S1", eventId: "E1", title: "A", sort: 1))
        var done = BlockSubtaskItem(id: "S2", eventId: "E1", title: "B", sort: 2)
        done.doneAt = "2026-10-05T11:00:00"
        try a.blockSubtasks.save(done)
        #expect(DataExport.tables.contains("block_subtasks"))
        let b = try makeRepos()
        try DataExport.importData(DataExport.export(from: a.db), into: b)
        #expect(try b.blockSubtasks.forEvent("E1") == a.blockSubtasks.forEvent("E1"))
        #expect(try b.blockSubtasks.forEvent("E2").isEmpty)
    }

    @Test func anOlderExportFileWithoutTheTableStillImports() throws {
        let a = try twoBlocksOfOneGoal()
        var obj = try #require(try JSONSerialization.jsonObject(with: DataExport.export(from: a.db)) as? [String: Any])
        var tables = try #require(obj["tables"] as? [String: Any])
        tables["block_subtasks"] = nil
        obj["tables"] = tables
        obj["schema"] = 6
        let b = try makeRepos()
        try b.blockSubtasks.save(BlockSubtaskItem(id: "X", eventId: try goalBlock(b, day: monday, id: "OLD").id, title: "Old"))
        try DataExport.importData(JSONSerialization.data(withJSONObject: obj), into: b)
        #expect(try b.events.get("E1") != nil)
        #expect(try b.blockSubtasks.get("X") == nil)
    }
}
