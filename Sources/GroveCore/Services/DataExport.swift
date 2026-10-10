import Foundation
import SQLite3

/// All data in one JSON file, and back (PLAN §4.4).
/// Import replaces everything. A bad file leaves the data as it was.
public enum DataExport {
    public static let format = "grove-export"
    public static let version = 1

    /// The tables in the file. The import fills them in this order, so a table comes after the tables it points to.
    /// The search index is not in the file. The import builds it again.
    public static let tables = ["lists", "notes", "goals", "tasks", "events", "block_subtasks", "event_exdates", "links",
                                "tags", "task_tags", "note_tags", "settings", "attachments"]

    public enum Failure: Error, Equatable, LocalizedError {
        case notAGroveFile
        case newerFile
        case newerSchema
        case badData(String)

        public var errorDescription: String? {
            switch self {
            case .notAGroveFile: "This is not a Grove export file."
            case .newerFile: "This file comes from a newer Grove. Update Grove first."
            case .newerSchema: "This file comes from a newer Grove. Update Grove first."
            case .badData(let why): "The file has a problem. \(why)"
            }
        }
    }

    /// What is in a file. The confirm dialog shows it before anything is replaced.
    public struct Summary: Equatable, Sendable {
        public var tasks: Int, events: Int, notes: Int, lists: Int, images: Int
        public init(tasks: Int, events: Int, notes: Int, lists: Int, images: Int) {
            self.tasks = tasks; self.events = events; self.notes = notes; self.lists = lists; self.images = images
        }
    }

    /// "grove-export-2026-10-04.json"
    public static func suggestedFileName(on day: DayKey) -> String { "grove-export-\(day).json" }

    // MARK: Export

    public static func export(from db: Database) throws -> Data {
        var out: [String: Any] = [:]
        for table in tables {
            out[table] = try db.query("SELECT * FROM \(table) ORDER BY rowid") { r -> [String: Any] in
                var row: [String: Any] = [:]
                for i in 0..<Int(sqlite3_column_count(r.stmt)) {
                    let name = String(cString: sqlite3_column_name(r.stmt, Int32(i)))
                    switch sqlite3_column_type(r.stmt, Int32(i)) {
                    case SQLITE_INTEGER: row[name] = r.int(i)
                    case SQLITE_FLOAT: row[name] = r.double(i)
                    case SQLITE_BLOB: row[name] = r.blob(i).base64EncodedString()
                    case SQLITE_NULL: row[name] = NSNull()
                    default: row[name] = r.text(i)
                    }
                }
                return row
            }
        }
        let root: [String: Any] = ["format": format, "version": version, "schema": db.userVersion,
                                   "exportedAt": Stamp.now(), "tables": out]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    // MARK: Look inside

    /// Counts what a file holds. Throws when it is not a usable file. Changes nothing.
    public static func summary(of data: Data) throws -> Summary {
        let tables = try readRoot(data).tables
        func count(_ name: String) -> Int { (tables[name] as? [Any])?.count ?? 0 }
        return Summary(tasks: count("tasks"), events: count("events"), notes: count("notes"),
                       lists: count("lists"), images: count("attachments"))
    }

    // MARK: Import

    /// Replaces all data with the data in `data`. All or nothing.
    public static func importData(_ data: Data, into repos: Repos) throws {
        let db = repos.db
        let root = try readRoot(data)
        if root.schema > db.userVersion { throw Failure.newerSchema }
        let inserts = try prepareInserts(root.tables, db: db)
        try db.transaction {
            // Rows may come in any order inside a table (a subtask before its parent). Check the links at the end.
            try db.executeScript("PRAGMA defer_foreign_keys = ON")
            for table in tables.reversed() { try db.execute("DELETE FROM \(table)") }
            try db.execute("DELETE FROM search")
            for insert in inserts { try db.execute(insert.sql, insert.args) }
            try repos.rebuildSearch()
        }
    }

    // MARK: Reading the file

    private static func readRoot(_ data: Data) throws -> (schema: Int, tables: [String: Any]) {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              root["format"] as? String == format,
              let fileVersion = root["version"] as? Int, fileVersion >= 1,
              let schema = root["schema"] as? Int,
              let tables = root["tables"] as? [String: Any] else { throw Failure.notAGroveFile }
        if fileVersion > version { throw Failure.newerFile }
        return (schema, tables)
    }

    private struct Insert { var sql: String; var args: [SQLValue] }

    /// Turns every row into one INSERT. All checks happen here, before anything is deleted.
    private static func prepareInserts(_ fileTables: [String: Any], db: Database) throws -> [Insert] {
        for name in fileTables.keys where !tables.contains(name) {
            throw Failure.badData("It has a table that Grove does not know: \(name).")
        }
        var inserts: [Insert] = []
        for table in tables {
            guard let value = fileTables[table] else { continue }   // a missing table is an empty table
            guard let rows = value as? [[String: Any]] else { throw Failure.badData("The table \(table) is not a list of rows.") }
            let known = try columns(of: table, in: db)
            for row in rows {
                var names: [String] = [], args: [SQLValue] = []
                for (column, raw) in row.sorted(by: { $0.key < $1.key }) {
                    guard let isBlob = known[column] else { throw Failure.badData("The table \(table) has a column that Grove does not know: \(column).") }
                    names.append("\"\(column)\"")
                    args.append(try sqlValue(raw, isBlob: isBlob, where: "\(table).\(column)"))
                }
                guard !names.isEmpty else { throw Failure.badData("The table \(table) has an empty row.") }
                let marks = Array(repeating: "?", count: names.count).joined(separator: ", ")
                inserts.append(Insert(sql: "INSERT INTO \(table) (\(names.joined(separator: ", "))) VALUES (\(marks))", args: args))
            }
        }
        return inserts
    }

    /// Column name to "is it a BLOB column".
    private static func columns(of table: String, in db: Database) throws -> [String: Bool] {
        let list = try db.query("PRAGMA table_info(\(table))") { ($0.text(1), $0.text(2).uppercased() == "BLOB") }
        return Dictionary(uniqueKeysWithValues: list)
    }

    private static func sqlValue(_ raw: Any, isBlob: Bool, where place: String) throws -> SQLValue {
        if raw is NSNull { return .null }
        if let text = raw as? String {
            guard isBlob else { return .text(text) }
            guard let bytes = Data(base64Encoded: text) else { throw Failure.badData("The picture data in \(place) is damaged.") }
            return .blob(bytes)
        }
        if let number = raw as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .int(number.boolValue ? 1 : 0) }
            if isBlob { throw Failure.badData("The picture data in \(place) is damaged.") }
            switch String(cString: number.objCType) {
            case "d", "f": return .real(number.doubleValue)
            default: return .int(number.intValue)
            }
        }
        throw Failure.badData("The value in \(place) is not text or a number.")
    }
}
