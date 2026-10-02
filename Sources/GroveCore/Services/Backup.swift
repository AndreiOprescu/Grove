import Foundation

public enum Backup {
    /// Writes `grove-YYYY-MM-DD.sqlite` into `directory` if today's copy does not exist yet,
    /// then keeps only the newest `keep` copies. Returns the new file, or nil if one already existed.
    @discardableResult
    public static func runDaily(db: Database, directory: URL, today: DayKey, keep: Int = 14) throws -> URL? {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("grove-\(today.string).sqlite")
        var created: URL?
        if !fm.fileExists(atPath: target.path) {
            let escaped = target.path.replacingOccurrences(of: "'", with: "''")
            try db.execute("VACUUM INTO '\(escaped)'")
            created = target
        }
        let files = try fm.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("grove-") && $0.hasSuffix(".sqlite") }
            .sorted()
        if files.count > keep {
            for old in files.prefix(files.count - keep) {
                try? fm.removeItem(at: directory.appendingPathComponent(old))
            }
        }
        return created
    }

    public static func list(directory: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasPrefix("grove-") && $0.hasSuffix(".sqlite") }.sorted(by: >)
            .map { directory.appendingPathComponent($0) }
    }
}
