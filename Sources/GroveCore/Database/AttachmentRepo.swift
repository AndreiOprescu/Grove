import Foundation

/// An image stored in the database.
public struct StoredImage: Equatable, Sendable {
    public var id: String
    public var mime: String
    public var data: Data
    public var width: Int
    public var height: Int
    public var createdAt: String
}

/// Images that task bodies, notes and event notes point at with `![alt](grove-image:ID)`.
/// They live in the database so the daily backup and the export carry them.
public final class AttachmentRepo {
    let db: Database
    public init(db: Database) { self.db = db }

    /// Checks, shrinks and stores `raw`. Returns nil when it is not an image.
    public func addImage(_ raw: Data) throws -> StoredImage? {
        guard let prepared = ImageTools.prepare(raw) else { return nil }
        let image = StoredImage(id: UUID().uuidString, mime: prepared.mime, data: prepared.data,
                                width: prepared.width, height: prepared.height, createdAt: Stamp.now())
        try db.execute("INSERT INTO attachments (id, mime, data, width, height, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                       [.text(image.id), .text(image.mime), .blob(image.data), .int(image.width), .int(image.height), .text(image.createdAt)])
        return image
    }

    public func get(_ id: String) throws -> StoredImage? {
        try db.queryOne("SELECT id, mime, data, width, height, created_at FROM attachments WHERE id = ?", [.text(id)]) { r in
            StoredImage(id: r.text(0), mime: r.text(1), data: r.blob(2), width: r.int(3), height: r.int(4), createdAt: r.text(5))
        }
    }

    public func delete(_ id: String) throws {
        try db.execute("DELETE FROM attachments WHERE id = ?", [.text(id)])
    }

    public func count() throws -> Int {
        try db.queryOne("SELECT COUNT(*) FROM attachments") { $0.int(0) } ?? 0
    }

    /// Deletes images that no task body, note or event note uses any more.
    /// An image must be at least `olderThanMinutes` old, so a picture pasted a moment ago
    /// (text not saved yet) or brought back by undo is never lost. Returns how many were deleted.
    @discardableResult
    public func sweepOrphans(olderThanMinutes: Int = 24 * 60, now: Date = Date()) throws -> Int {
        let cutoff = Stamp.string(from: now.addingTimeInterval(-Double(olderThanMinutes) * 60))
        let before = try count()
        try db.execute("""
            DELETE FROM attachments WHERE created_at < ?
              AND NOT EXISTS (SELECT 1 FROM tasks  WHERE instr(notes, 'grove-image:' || attachments.id) > 0)
              AND NOT EXISTS (SELECT 1 FROM notes  WHERE instr(body,  'grove-image:' || attachments.id) > 0)
              AND NOT EXISTS (SELECT 1 FROM events WHERE instr(notes, 'grove-image:' || attachments.id) > 0)
            """, [.text(cutoff)])
        return before - (try count())
    }
}
