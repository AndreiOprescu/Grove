import Foundation

/// Ordered schema migrations. Index N takes the database from user_version N to N+1.
/// Never edit a shipped migration; append a new one.
enum Migrations {
    static let all: [String] = [
        // 1 — initial schema
        """
        CREATE TABLE lists (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, emoji TEXT NOT NULL DEFAULT '',
          color TEXT NOT NULL DEFAULT 'accent', sort INTEGER NOT NULL DEFAULT 0,
          archived INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE tasks (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          notes TEXT NOT NULL DEFAULT '',
          list_id TEXT REFERENCES lists(id) ON DELETE SET NULL,
          parent_id TEXT REFERENCES tasks(id) ON DELETE CASCADE,
          priority INTEGER NOT NULL DEFAULT 0,
          status TEXT NOT NULL DEFAULT 'open',
          bucket TEXT NOT NULL DEFAULT 'inbox',
          plan_date TEXT,
          plan_week TEXT,
          due TEXT,
          estimate_min INTEGER NOT NULL DEFAULT 30,
          recurrence TEXT,
          source_note_id TEXT REFERENCES notes(id) ON DELETE SET NULL,
          sort REAL NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL, completed_at TEXT
        );
        CREATE INDEX tasks_plan_date ON tasks(plan_date);
        CREATE INDEX tasks_plan_week ON tasks(plan_week);
        CREATE INDEX tasks_parent ON tasks(parent_id);

        CREATE TABLE events (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          start TEXT NOT NULL,
          end TEXT NOT NULL,
          all_day INTEGER NOT NULL DEFAULT 0,
          kind TEXT NOT NULL DEFAULT 'event',
          task_id TEXT REFERENCES tasks(id) ON DELETE CASCADE,
          color TEXT NOT NULL DEFAULT 'accent2',
          location TEXT NOT NULL DEFAULT '',
          notes TEXT NOT NULL DEFAULT '',
          recurrence TEXT,
          series_id TEXT REFERENCES events(id) ON DELETE CASCADE,
          original_date TEXT,
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL
        );
        CREATE INDEX events_start ON events(start);
        CREATE INDEX events_task ON events(task_id);

        CREATE TABLE event_exdates (event_id TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
          date TEXT NOT NULL, PRIMARY KEY(event_id, date));

        CREATE TABLE notes (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          body TEXT NOT NULL DEFAULT '',
          kind TEXT NOT NULL DEFAULT 'note',
          date TEXT,
          pinned INTEGER NOT NULL DEFAULT 0,
          mood INTEGER,
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL
        );
        CREATE UNIQUE INDEX notes_daily ON notes(kind, date) WHERE kind IN ('daily','weekly');

        CREATE TABLE links (
          src_type TEXT NOT NULL, src_id TEXT NOT NULL,
          dst_type TEXT NOT NULL, dst_id TEXT NOT NULL,
          origin TEXT NOT NULL DEFAULT 'manual',
          PRIMARY KEY (src_type, src_id, dst_type, dst_id)
        );
        CREATE INDEX links_dst ON links(dst_type, dst_id);

        CREATE TABLE tags (id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE COLLATE NOCASE);
        CREATE TABLE task_tags (task_id TEXT REFERENCES tasks(id) ON DELETE CASCADE,
          tag_id TEXT REFERENCES tags(id) ON DELETE CASCADE, PRIMARY KEY(task_id, tag_id));
        CREATE TABLE note_tags (note_id TEXT REFERENCES notes(id) ON DELETE CASCADE,
          tag_id TEXT REFERENCES tags(id) ON DELETE CASCADE, PRIMARY KEY(note_id, tag_id));

        CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);

        CREATE VIRTUAL TABLE search USING fts5(item_type UNINDEXED, item_id UNINDEXED, title, body,
          tokenize='unicode61 remove_diacritics 2');
        """,

        // 2 — images in task bodies and notes; links are cleaned up when an item is deleted
        """
        CREATE TABLE attachments (
          id TEXT PRIMARY KEY, mime TEXT NOT NULL, data BLOB NOT NULL,
          width INTEGER NOT NULL DEFAULT 0, height INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL
        );

        CREATE TRIGGER links_cleanup_task AFTER DELETE ON tasks BEGIN
          DELETE FROM links WHERE (src_type = 'task' AND src_id = old.id) OR (dst_type = 'task' AND dst_id = old.id);
        END;
        CREATE TRIGGER links_cleanup_note AFTER DELETE ON notes BEGIN
          DELETE FROM links WHERE (src_type = 'note' AND src_id = old.id) OR (dst_type = 'note' AND dst_id = old.id);
        END;
        CREATE TRIGGER links_cleanup_event AFTER DELETE ON events BEGIN
          DELETE FROM links WHERE (src_type = 'event' AND src_id = old.id) OR (dst_type = 'event' AND dst_id = old.id);
        END;
        """,

        // 3 — a short description on each task (the notes column stays the long description)
        """
        ALTER TABLE tasks ADD COLUMN summary TEXT NOT NULL DEFAULT '';
        """,
    ]

    static func run(on db: Database) throws {
        let current = db.userVersion
        guard current < all.count else { return }
        for index in current..<all.count {
            try db.transaction {
                try db.executeScript(all[index])
                try db.executeScript("PRAGMA user_version = \(index + 1)")
            }
        }
    }
}
