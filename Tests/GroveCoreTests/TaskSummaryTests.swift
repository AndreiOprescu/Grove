import Testing
import Foundation
import SQLite3
@testable import GroveCore

/// The short description of a task.
struct TaskSummaryTests {
    @Test func aSummarySavesAndLoads() throws {
        let r = Repos(db: try Database.inMemory())
        var t = TaskItem(title: "Plan trip")
        t.summary = "Flights and hotel"
        t.notes = "Long text"
        try r.tasks.save(t)
        let back = try #require(try r.tasks.get(t.id))
        #expect(back.summary == "Flights and hotel")
        #expect(back.notes == "Long text")
    }

    @Test func aNewTaskHasNoSummary() {
        #expect(TaskItem(title: "x").summary == "")
    }

    @Test func searchFindsATaskByItsSummary() throws {
        let r = Repos(db: try Database.inMemory())
        var t = TaskItem(title: "Plan trip")
        t.summary = "Flights and hotel"
        try r.tasks.save(t)
        let hits = try r.search.search("hotel")
        #expect(hits.contains { $0.ref.id == t.id })
    }

    @Test func upgradingAVersionTwoDatabaseKeepsItsTasks() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("grove-m3-\(UUID().uuidString).sqlite").path
        defer { for s in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + s) } }
        var handle: OpaquePointer?
        #expect(sqlite3_open(path, &handle) == SQLITE_OK)
        let seed = Migrations.all[0] + ";" + Migrations.all[1] + """
            ;PRAGMA user_version = 2;
            INSERT INTO tasks (id, title, notes, created_at, updated_at) VALUES ('t1', 'Old task', 'body', '2026-10-01T09:00:00', '2026-10-01T09:00:00');
            """
        #expect(sqlite3_exec(handle, seed, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(handle)
        let r = Repos(db: try Database(path: path))
        #expect(r.db.userVersion == Migrations.all.count)
        let old = try #require(try r.tasks.get("t1"))
        #expect(old.title == "Old task")
        #expect(old.notes == "body")
        #expect(old.summary == "")
    }
}
