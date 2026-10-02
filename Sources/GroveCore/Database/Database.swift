import Foundation
import SQLite3

public enum SQLValue {
    case text(String), int(Int), real(Double), blob(Data), null

    public init(_ s: String?) { self = s.map { .text($0) } ?? .null }
    public init(_ i: Int?) { self = i.map { .int($0) } ?? .null }
}

public struct DatabaseError: Error, CustomStringConvertible {
    public let message: String
    public var description: String { message }
}

/// One result row. Column indexes start at 0.
public struct Row {
    let stmt: OpaquePointer

    public func text(_ i: Int) -> String {
        guard let c = sqlite3_column_text(stmt, Int32(i)) else { return "" }
        return String(cString: c)
    }
    public func optText(_ i: Int) -> String? {
        sqlite3_column_type(stmt, Int32(i)) == SQLITE_NULL ? nil : text(i)
    }
    public func int(_ i: Int) -> Int { Int(sqlite3_column_int64(stmt, Int32(i))) }
    public func optInt(_ i: Int) -> Int? {
        sqlite3_column_type(stmt, Int32(i)) == SQLITE_NULL ? nil : int(i)
    }
    public func double(_ i: Int) -> Double { sqlite3_column_double(stmt, Int32(i)) }
    public func blob(_ i: Int) -> Data {
        guard let p = sqlite3_column_blob(stmt, Int32(i)) else { return Data() }
        return Data(bytes: p, count: Int(sqlite3_column_bytes(stmt, Int32(i))))
    }
    public func bool(_ i: Int) -> Bool { int(i) != 0 }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Thin SQLite wrapper. Use from the main actor only; the data set is small.
public final class Database {
    private var db: OpaquePointer?
    private var cache: [String: OpaquePointer] = [:]
    private var inUse: Set<String> = []
    private var savepointCounter = 0

    public let path: String

    public init(path: String) throws {
        self.path = path
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open database"
            throw DatabaseError(message: msg)
        }
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA foreign_keys=ON")
        try Migrations.run(on: self)
    }

    public static func inMemory() throws -> Database { try Database(path: ":memory:") }

    /// ~/Library/Application Support/Grove/
    public static func supportDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("Grove", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func openDefault() throws -> Database {
        try Database(path: supportDirectory().appendingPathComponent("grove.sqlite").path)
    }

    deinit {
        for (_, s) in cache { sqlite3_finalize(s) }
        sqlite3_close(db)
    }

    private var lastError: DatabaseError {
        DatabaseError(message: db.map { String(cString: sqlite3_errmsg($0)) } ?? "no database")
    }

    // MARK: Statements

    private func acquire(_ sql: String) throws -> (stmt: OpaquePointer, cached: Bool) {
        if let s = cache[sql], !inUse.contains(sql) {
            inUse.insert(sql)
            return (s, true)
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else { throw lastError }
        if cache[sql] == nil {
            cache[sql] = s
            inUse.insert(sql)
            return (s, true)
        }
        return (s, false) // same SQL is already running (re-entrant call): use a throwaway statement
    }

    private func release(_ sql: String, _ stmt: OpaquePointer, cached: Bool) {
        if cached {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            inUse.remove(sql)
        } else {
            sqlite3_finalize(stmt)
        }
    }

    private func bind(_ stmt: OpaquePointer, _ args: [SQLValue]) {
        for (i, a) in args.enumerated() {
            let idx = Int32(i + 1)
            switch a {
            case .text(let s): sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
            case .int(let n): sqlite3_bind_int64(stmt, idx, Int64(n))
            case .real(let d): sqlite3_bind_double(stmt, idx, d)
            case .blob(let d):
                if d.isEmpty { sqlite3_bind_zeroblob(stmt, idx, 0) }
                else { d.withUnsafeBytes { _ = sqlite3_bind_blob(stmt, idx, $0.baseAddress, Int32(d.count), SQLITE_TRANSIENT) } }
            case .null: sqlite3_bind_null(stmt, idx)
            }
        }
    }

    // MARK: Public API

    /// Run one statement (any rows it returns are ignored).
    public func execute(_ sql: String, _ args: [SQLValue] = []) throws {
        let (stmt, cached) = try acquire(sql)
        defer { release(sql, stmt, cached: cached) }
        bind(stmt, args)
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW { continue }
            if rc == SQLITE_DONE { return }
            throw lastError
        }
    }

    public func query<T>(_ sql: String, _ args: [SQLValue] = [], map: (Row) throws -> T) throws -> [T] {
        let (stmt, cached) = try acquire(sql)
        defer { release(sql, stmt, cached: cached) }
        bind(stmt, args)
        var out: [T] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW { out.append(try map(Row(stmt: stmt))) }
            else if rc == SQLITE_DONE { return out }
            else { throw lastError }
        }
    }

    public func queryOne<T>(_ sql: String, _ args: [SQLValue] = [], map: (Row) throws -> T) throws -> T? {
        try query(sql, args, map: map).first
    }

    /// Run several statements separated by semicolons (no parameters).
    public func executeScript(_ sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK { throw lastError }
    }

    /// Number of rows changed by the last write.
    public var changes: Int { Int(sqlite3_changes(db)) }

    /// Nested-safe transaction (uses savepoints). Rolls back if `body` throws.
    @discardableResult
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        savepointCounter += 1
        let name = "sp\(savepointCounter)"
        try executeScript("SAVEPOINT \(name)")
        do {
            let result = try body()
            try executeScript("RELEASE \(name)")
            return result
        } catch {
            try? executeScript("ROLLBACK TO \(name)")
            try? executeScript("RELEASE \(name)")
            throw error
        }
    }

    public var userVersion: Int {
        (try? queryOne("PRAGMA user_version") { $0.int(0) }) ?? 0
    }
}
