import Foundation

public struct SearchHit: Hashable, Sendable {
    public var ref: ItemRef
    public var title: String
    public var snippet: String
}

/// Full-text search over tasks, events and notes (SQLite FTS5).
public final class SearchIndex {
    let db: Database
    public init(db: Database) { self.db = db }

    public func upsert(_ type: ItemType, id: String, title: String, body: String) throws {
        try db.execute("DELETE FROM search WHERE item_type = ? AND item_id = ?", [.text(type.rawValue), .text(id)])
        try db.execute("INSERT INTO search (item_type, item_id, title, body) VALUES (?, ?, ?, ?)",
                       [.text(type.rawValue), .text(id), .text(title), .text(body)])
    }

    public func remove(_ type: ItemType, id: String) throws {
        try db.execute("DELETE FROM search WHERE item_type = ? AND item_id = ?", [.text(type.rawValue), .text(id)])
    }

    /// Every word is a prefix match; all words must match. Empty query returns nothing.
    public func search(_ query: String, types: Set<ItemType>? = nil, limit: Int = 30) throws -> [SearchHit] {
        let tokens = query.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        guard !tokens.isEmpty else { return [] }
        let match = tokens.map { "\"\($0)\"*" }.joined(separator: " ")
        let rows = try db.query(
            "SELECT item_type, item_id, title, snippet(search, 3, '', '', '…', 10) FROM search WHERE search MATCH ? ORDER BY rank LIMIT ?",
            [.text(match), .int(limit * 3)]
        ) { r -> SearchHit? in
            guard let t = ItemType(rawValue: r.text(0)) else { return nil }
            return SearchHit(ref: ItemRef(t, r.text(1)), title: r.text(2), snippet: r.text(3))
        }
        let hits = rows.compactMap { $0 }.filter { types?.contains($0.ref.type) ?? true }
        return Array(hits.prefix(limit))
    }
}
