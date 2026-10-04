import Testing
import Foundation
@testable import GroveCore

/// Export to one JSON file and import from it (PLAN §4.4). Import replaces everything.
struct DataExportTests {
    private func makeRepos() throws -> Repos { Repos(db: try Database.inMemory()) }

    /// A small world that touches every table.
    private func fill(_ r: Repos) throws {
        let day = DayKey("2026-10-05")
        try r.lists.save(ListItem(id: "L1", name: "Home", emoji: "🌿"))
        try r.notes.save(Note(id: "N1", title: "Garden ideas", body: "Plant #herbs and see [[Water plants|T1]]"))
        try r.notes.save(Note(id: "N2", title: "Monday", body: "Daily", kind: .daily, date: day, mood: 3))
        let parent = TaskItem(id: "T1", title: "Water plants", summary: "every other day", notes: "Use rain water",
                              listId: "L1", bucket: .day, planDate: day, estimateMin: 20,
                              recurrence: RecurrenceRule(freq: .weekly, weekdays: [1, 4]), sourceNoteId: "N1")
        try r.tasks.save(parent)
        try r.tasks.save(TaskItem(id: "T2", title: "Fill the can", parentId: "T1"))
        try r.tags.setTags(taskId: "T1", names: ["garden"])
        try r.tags.setTags(noteId: "N1", names: ["herbs"])
        let series = EventItem(id: "E1", title: "Stand-up", start: WallTime(day: day, minute: 570), end: WallTime(day: day, minute: 600),
                               recurrence: RecurrenceRule(freq: .daily))
        try r.events.save(series)
        try r.events.addExdate("E1", day.adding(days: 1))
        try r.events.save(EventItem(id: "E2", title: "Water plants", start: WallTime(day: day, minute: 660), end: WallTime(day: day, minute: 680),
                                    kind: .block, taskId: "T1"))
        try r.links.addManual(src: ItemRef(.note, "N1"), dst: ItemRef(.task, "T1"))
        try r.settings.set("welcome.shown", "1")
        try r.db.execute("INSERT INTO attachments (id, mime, data, width, height, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                         [.text("A1"), .text("image/png"), .blob(Data([0, 1, 2, 255, 254])), .int(4), .int(3), .text("2026-10-05T08:00:00")])
    }

    private func json(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: The file

    @Test func theFileNamesItsFormatAndHoldsEveryTable() throws {
        let r = try makeRepos(); try fill(r)
        let obj = try json(DataExport.export(from: r.db))
        #expect(obj["format"] as? String == "grove-export")
        #expect(obj["version"] as? Int == 1)
        #expect(obj["schema"] as? Int == r.db.userVersion)
        let tables = try #require(obj["tables"] as? [String: [[String: Any]]])
        #expect(Set(tables.keys) == Set(DataExport.tables))
        #expect(tables["tasks"]?.count == 2 && tables["events"]?.count == 2 && tables["notes"]?.count == 2)
        #expect(tables["event_exdates"]?.count == 1 && tables["attachments"]?.count == 1)
    }

    @Test func theSearchIndexIsNotInTheFile() throws {
        let r = try makeRepos(); try fill(r)
        let obj = try json(DataExport.export(from: r.db))
        let tables = try #require(obj["tables"] as? [String: Any])
        #expect(tables["search"] == nil)
    }

    @Test func theFileTellsWhatIsInsideWithoutChangingAnything() throws {
        let r = try makeRepos(); try fill(r)
        let s = try DataExport.summary(of: DataExport.export(from: r.db))
        #expect(s == DataExport.Summary(tasks: 2, events: 2, notes: 2, lists: 1, images: 1))
    }

    // MARK: Round trip

    @Test func importGivesBackEverythingThatWasExported() throws {
        let a = try makeRepos(); try fill(a)
        let b = try makeRepos()
        try DataExport.importData(DataExport.export(from: a.db), into: b)
        #expect(Set(try b.tasks.all()) == Set(try a.tasks.all()))
        #expect(Set(try b.events.all()) == Set(try a.events.all()))
        #expect(Set(try b.notes.all()) == Set(try a.notes.all()))
        #expect(try b.lists.all() == a.lists.all())
        #expect(try b.tags.tags(forTask: "T1") == ["garden"])
        #expect(try b.tags.tags(forNote: "N1") == ["herbs"])
        #expect(try b.events.exdates("E1") == [DayKey("2026-10-06")])
        #expect(try b.links.backlinks(to: ItemRef(.task, "T1")).contains(ItemRef(.note, "N1")))
        #expect(try b.settings.get("welcome.shown") == "1")
        #expect(try b.attachments.get("A1")?.data == Data([0, 1, 2, 255, 254]))
        #expect(try b.attachments.get("A1")?.width == 4)
    }

    @Test func aTaskKeepsItsRepeatRuleAndItsParent() throws {
        let a = try makeRepos(); try fill(a)
        let b = try makeRepos()
        try DataExport.importData(DataExport.export(from: a.db), into: b)
        #expect(try b.tasks.get("T1")?.recurrence == RecurrenceRule(freq: .weekly, weekdays: [1, 4]))
        #expect(try b.tasks.get("T2")?.parentId == "T1")
        #expect(try b.events.get("E2")?.taskId == "T1")
    }

    @Test func searchWorksAfterAnImport() throws {
        let a = try makeRepos(); try fill(a)
        let b = try makeRepos()
        try DataExport.importData(DataExport.export(from: a.db), into: b)
        let hits = try b.search.search("garden")
        #expect(hits.map(\.ref) == [ItemRef(.note, "N1")])
        #expect(try b.search.search("rain").map(\.ref) == [ItemRef(.task, "T1")])
    }

    @Test func importReplacesWhatWasThere() throws {
        let a = try makeRepos(); try fill(a)
        let b = try makeRepos()
        try b.tasks.save(TaskItem(id: "OLD", title: "Old task"))
        try b.notes.save(Note(id: "OLDN", title: "Old note"))
        try DataExport.importData(DataExport.export(from: a.db), into: b)
        #expect(try b.tasks.get("OLD") == nil && b.notes.get("OLDN") == nil)
        #expect(try b.search.search("Old").isEmpty)
        #expect(try b.tasks.all().count == 2)
    }

    @Test func importingTwiceChangesNothing() throws {
        let a = try makeRepos(); try fill(a)
        let data = try DataExport.export(from: a.db)
        try DataExport.importData(data, into: a)
        #expect(try a.tasks.all().count == 2 && a.events.all().count == 2 && a.attachments.count() == 1)
    }

    // MARK: Bad files change nothing

    private func expectRefused(_ data: Data, keeps r: Repos) throws {
        #expect(throws: (any Error).self) { try DataExport.importData(data, into: r) }
        #expect(try r.tasks.get("KEEP")?.title == "Keep me")
        #expect(try r.search.search("Keep").count == 1)
    }

    private func keeper() throws -> Repos {
        let r = try makeRepos()
        try r.tasks.save(TaskItem(id: "KEEP", title: "Keep me"))
        return r
    }

    @Test func textThatIsNotJSONIsRefused() throws {
        try expectRefused(Data("not a file".utf8), keeps: try keeper())
    }

    @Test func anotherKindOfJSONIsRefused() throws {
        try expectRefused(Data(#"{"format":"something-else","version":1,"schema":3,"tables":{}}"#.utf8), keeps: try keeper())
    }

    @Test func aNewerFileFormatIsRefused() throws {
        try expectRefused(Data(#"{"format":"grove-export","version":99,"schema":3,"tables":{}}"#.utf8), keeps: try keeper())
    }

    @Test func aFileFromANewerSchemaIsRefused() throws {
        let r = try keeper()
        let data = Data(#"{"format":"grove-export","version":1,"schema":\#(r.db.userVersion + 1),"tables":{}}"#.utf8)
        try expectRefused(data, keeps: r)
    }

    @Test func aTableThatDoesNotExistIsRefused() throws {
        let data = Data(#"{"format":"grove-export","version":1,"schema":1,"tables":{"sqlite_master":[{"name":"x"}]}}"#.utf8)
        try expectRefused(data, keeps: try keeper())
    }

    @Test func aBrokenRowStopsTheImportAndKeepsTheOldData() throws {
        // A task with no title breaks the NOT NULL rule half way through the import.
        let a = try makeRepos(); try fill(a)
        var obj = try json(DataExport.export(from: a.db))
        var tables = try #require(obj["tables"] as? [String: [[String: Any]]])
        tables["tasks"] = [["id": "BAD"]]
        obj["tables"] = tables
        let data = try JSONSerialization.data(withJSONObject: obj)
        try expectRefused(data, keeps: try keeper())
    }

    @Test func aRowThatPointsAtNothingIsRefused() throws {
        // A task in a list that is not in the file breaks the link rule when the import ends.
        let a = try makeRepos(); try fill(a)
        var obj = try json(DataExport.export(from: a.db))
        var tables = try #require(obj["tables"] as? [String: [[String: Any]]])
        tables["lists"] = []
        obj["tables"] = tables
        try expectRefused(JSONSerialization.data(withJSONObject: obj), keeps: try keeper())
    }

    @Test func aDamagedPictureIsRefused() throws {
        let a = try makeRepos(); try fill(a)
        var obj = try json(DataExport.export(from: a.db))
        var tables = try #require(obj["tables"] as? [String: [[String: Any]]])
        tables["attachments"]?[0]["data"] = "***not base64***"
        obj["tables"] = tables
        try expectRefused(JSONSerialization.data(withJSONObject: obj), keeps: try keeper())
    }

    @Test func theSuggestedFileNameHasTheDay() {
        #expect(DataExport.suggestedFileName(on: "2026-10-04") == "grove-export-2026-10-04.json")
    }

    @Test func aMissingTableIsTheSameAsAnEmptyOne() throws {
        let a = try makeRepos(); try fill(a)
        var obj = try json(DataExport.export(from: a.db))
        var tables = try #require(obj["tables"] as? [String: [[String: Any]]])
        tables["settings"] = nil
        obj["tables"] = tables
        let b = try keeper()
        try DataExport.importData(JSONSerialization.data(withJSONObject: obj), into: b)
        #expect(try b.tasks.get("KEEP") == nil && b.tasks.all().count == 2)
        #expect(try b.settings.get("welcome.shown") == nil)
    }
}
