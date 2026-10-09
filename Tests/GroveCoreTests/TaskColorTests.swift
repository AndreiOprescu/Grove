import Testing
import Foundation
@testable import GroveCore

/// The colour of a task: one of eight names, or none (PLAN §5.1 board colours).
struct TaskColorTests {
    private func makeRepos() throws -> Repos { Repos(db: try Database.inMemory()) }

    @Test func thereAreEightDifferentColours() {
        #expect(TaskColor.names.count == 8)
        #expect(Set(TaskColor.names).count == 8)
    }

    @Test func aTaskHasNoColourAtFirst() {
        #expect(TaskItem(title: "x").color == "")
    }

    @Test func noColourAndTheEightNamesAreValid() {
        #expect(TaskColor.isValid(""))
        for name in TaskColor.names { #expect(TaskColor.isValid(name)) }
        #expect(!TaskColor.isValid("mauve"))
        #expect(!TaskColor.isValid("Red"))
    }

    @Test func theColourIsSavedWithTheTask() throws {
        let r = try makeRepos()
        var t = TaskItem(id: "T1", title: "Paint")
        t.color = "teal"
        try r.tasks.save(t)
        #expect(try r.tasks.get("T1")?.color == "teal")
        #expect(try r.tasks.all().first?.color == "teal")
    }

    @Test func theColourComesBackFromAnExportFile() throws {
        let a = try makeRepos()
        var t = TaskItem(id: "T1", title: "Paint")
        t.color = "pink"
        try a.tasks.save(t)
        let b = try makeRepos()
        try DataExport.importData(DataExport.export(from: a.db), into: b)
        #expect(try b.tasks.get("T1")?.color == "pink")
    }

    @Test func aFileFromBeforeColoursStillImports() throws {
        let b = try makeRepos()
        let old = """
        {"format":"grove-export","version":1,"schema":3,"tables":{"tasks":[
          {"id":"T1","title":"Old","notes":"","summary":"","priority":2,"status":"open","bucket":"inbox",
           "estimate_min":30,"sort":0,"created_at":"2026-10-01T08:00:00","updated_at":"2026-10-01T08:00:00"}]}}
        """
        try DataExport.importData(Data(old.utf8), into: b)
        #expect(try b.tasks.get("T1")?.color == "")
        #expect(try b.tasks.get("T1")?.priority == 2)
    }
}
