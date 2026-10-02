import Foundation

/// Turns `[[mentions]]` in a body into real links between tasks, notes and events.
public final class ReferenceIndexer {
    let db: Database
    let tasks: TaskRepo
    let notes: NoteRepo
    let events: EventRepo
    let links: LinkRepo
    let search: SearchIndex

    public init(db: Database, tasks: TaskRepo, notes: NoteRepo, events: EventRepo, links: LinkRepo, search: SearchIndex) {
        self.db = db; self.tasks = tasks; self.notes = notes; self.events = events; self.links = links; self.search = search
    }

    public struct Target: Equatable, Sendable {
        public var ref: ItemRef
        public var title: String
    }

    /// Finds what a mention points at.
    /// With an id, only that id counts: a deleted target stays unresolved and never moves to another item.
    /// Without an id, the exact title (any letter case) is used. A note wins over a task, a task over an event.
    public func resolve(_ mention: Mention) throws -> Target? {
        if let id = mention.id { return try target(id: id) }
        if let n = try notes.byTitle(mention.title) { return Target(ref: ItemRef(.note, n.id), title: n.title) }
        if let t = try tasks.byTitle(mention.title) { return Target(ref: ItemRef(.task, t.id), title: t.title) }
        if let e = try events.byTitle(mention.title) { return Target(ref: ItemRef(.event, e.id), title: e.title) }
        return nil
    }

    public func title(of ref: ItemRef) throws -> String? {
        try target(id: ref.id).flatMap { $0.ref == ref ? $0.title : nil }
    }

    private func target(id: String) throws -> Target? {
        try db.queryOne("""
            SELECT 'task', id, title FROM tasks WHERE id = ?
            UNION ALL SELECT 'note', id, title FROM notes WHERE id = ?
            UNION ALL SELECT 'event', id, title FROM events WHERE id = ?
            """, [.text(id), .text(id), .text(id)]) { r in
            ItemType(rawValue: r.text(0)).map { Target(ref: ItemRef($0, r.text(1)), title: r.text(2)) }
        } ?? nil
    }

    /// The text with every resolvable mention written as `[[Current title|ID]]`, plus what the mentions point at.
    /// Mentions that cannot be resolved stay exactly as typed.
    public func canonicalize(_ text: String) throws -> (text: String, targets: [ItemRef]) {
        var out = text
        var found: [ItemRef] = []
        for m in ReferenceParser.mentions(in: text).reversed() {
            guard let t = try resolve(m) else { continue }
            out.replaceSubrange(m.range, with: ReferenceParser.mention(title: t.title, id: t.ref.id))
            found.append(t.ref)
        }
        var seen = Set<ItemRef>()
        return (out, found.reversed().filter { seen.insert($0).inserted })
    }

    /// Call after every save of a body. Replaces the item's parsed links and returns the canonical text,
    /// which the caller should store. Manual links are kept.
    @discardableResult
    public func reindex(_ src: ItemRef, text: String) throws -> String {
        let result = try canonicalize(text)
        try links.replaceParsed(src: src, with: result.targets)
        return result.text
    }

    /// Rebuilds the links that other bodies make to `ref`. Call after `ref` was brought back (undo of a delete),
    /// because deleting an item also removes the link rows that point at it.
    public func rebuildIncoming(to ref: ItemRef) throws {
        let needle = "|\(ref.id)]]"
        let args: [SQLValue] = [.text(needle)]
        let found: [(ItemRef, String)] = try
            db.query("SELECT id, notes FROM tasks WHERE instr(notes, ?) > 0", args) { (ItemRef(.task, $0.text(0)), $0.text(1)) }
            + db.query("SELECT id, body FROM notes WHERE instr(body, ?) > 0", args) { (ItemRef(.note, $0.text(0)), $0.text(1)) }
            + db.query("SELECT id, notes FROM events WHERE instr(notes, ?) > 0", args) { (ItemRef(.event, $0.text(0)), $0.text(1)) }
        for (src, text) in found { try reindex(src, text: text) }
    }

    /// Call after an item was renamed and saved. Rewrites the title inside every body that mentions it.
    /// The linking items keep their "last edited" time, so a rename does not reshuffle the notes list.
    public func renamed(_ ref: ItemRef, to newTitle: String) throws {
        try db.transaction {
            for src in try links.backlinks(to: ref) {
                switch src.type {
                case .task:
                    guard let t = try tasks.get(src.id) else { continue }
                    let body = ReferenceParser.rewriting(t.notes, id: ref.id, to: newTitle)
                    guard body != t.notes else { continue }
                    try db.execute("UPDATE tasks SET notes = ? WHERE id = ?", [.text(body), .text(t.id)])
                    try search.upsert(.task, id: t.id, title: t.title, body: ReferenceParser.searchText(body))
                case .note:
                    guard let n = try notes.get(src.id) else { continue }
                    let body = ReferenceParser.rewriting(n.body, id: ref.id, to: newTitle)
                    guard body != n.body else { continue }
                    try db.execute("UPDATE notes SET body = ? WHERE id = ?", [.text(body), .text(n.id)])
                    try search.upsert(.note, id: n.id, title: n.title, body: ReferenceParser.searchText(body))
                case .event:
                    guard let e = try events.get(src.id) else { continue }
                    let body = ReferenceParser.rewriting(e.notes, id: ref.id, to: newTitle)
                    guard body != e.notes else { continue }
                    try db.execute("UPDATE events SET notes = ? WHERE id = ?", [.text(body), .text(e.id)])
                    try search.upsert(.event, id: e.id, title: e.title, body: ReferenceParser.searchText(body) + " " + e.location)
                }
            }
        }
    }
}
