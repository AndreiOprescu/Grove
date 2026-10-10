import 'database.dart';

/// Ordered schema migrations. Index N takes the database from user_version N to N+1.
/// These are the Mac app's migrations, word for word. Both apps read the same
/// number, and an export file carries it. Never edit a shipped migration; append
/// a new one, in the Mac app and here.
abstract final class Migrations {
  static const all = <String>[
    // 1 — initial schema
    '''
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
    ''',

    // 2 — images in task bodies and notes; links are cleaned up when an item is deleted
    '''
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
    ''',

    // 3 — a short description on each task (the notes column stays the long description)
    '''
    ALTER TABLE tasks ADD COLUMN summary TEXT NOT NULL DEFAULT '';
    ''',

    // 4 — a colour on each task ('' means none)
    '''
    ALTER TABLE tasks ADD COLUMN color TEXT NOT NULL DEFAULT '';
    ''',

    // 5 — goals: recurring work with a target of minutes per week and no date.
    // A block with goal_id set adds to the goal when done_at is set. The progress is worked out from the blocks, never stored.
    '''
    CREATE TABLE goals (
      id TEXT PRIMARY KEY, title TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '', color TEXT NOT NULL DEFAULT '',
      target_min INTEGER NOT NULL DEFAULT 300, sort REAL NOT NULL DEFAULT 0, archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL
    );
    ALTER TABLE events ADD COLUMN goal_id TEXT;
    ALTER TABLE events ADD COLUMN done_at TEXT;
    CREATE INDEX events_goal ON events(goal_id);
    ''',

    // 6 — a goal counts hours or sessions. Old goals are hours goals.
    '''
    ALTER TABLE goals ADD COLUMN kind TEXT NOT NULL DEFAULT 'hours';
    ALTER TABLE goals ADD COLUMN target_count INTEGER NOT NULL DEFAULT 3;
    ''',
  ];

  static void run(Database db) {
    final current = db.userVersion;
    for (var index = current; index < all.length; index++) {
      db.transaction(() {
        db.executeScript(all[index]);
        db.userVersion = index + 1;
      });
    }
  }
}

/// Changes that only this app makes, for sync (cross-platform plan F11).
/// They have their own number in `sync_meta`, so `user_version` stays the Mac
/// app's number and the Mac app can still read our export files.
abstract final class SyncMigrations {
  /// The tables the sync columns go on. The same list as `DataExport.tables`.
  static const syncedTables = [
    'lists',
    'notes',
    'goals',
    'tasks',
    'events',
    'event_exdates',
    'links',
    'tags',
    'task_tags',
    'note_tags',
    'settings',
    'attachments',
  ];

  /// Tables that already had `updated_at` in the shared schema.
  static const _hadUpdatedAt = {'notes', 'goals', 'tasks', 'events'};

  /// The columns each sync migration added, by table. The export leaves them out.
  static final Map<String, Set<String>> addedColumns = {
    for (final t in syncedTables)
      t: {'deleted', 'user_id', if (!_hadUpdatedAt.contains(t)) 'updated_at'},
  };

  static final all = <String>[
    // 1 — a soft-delete flag, the owner and an edit time on every synced table.
    [
      for (final t in syncedTables) ...[
        'ALTER TABLE $t ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0;',
        'ALTER TABLE $t ADD COLUMN user_id TEXT;',
        if (!_hadUpdatedAt.contains(t))
          "ALTER TABLE $t ADD COLUMN updated_at TEXT NOT NULL DEFAULT '';",
      ],
    ].join('\n'),
  ];

  static const _key = 'schema';

  static void _ensureTable(Database db) => db.executeScript(
    'CREATE TABLE IF NOT EXISTS sync_meta '
    '(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  );

  static int version(Database db) {
    _ensureTable(db);
    final v = db.queryOne('SELECT value FROM sync_meta WHERE key = ?', const [
      _key,
    ], (r) => r.text(0));
    return int.tryParse(v ?? '') ?? 0;
  }

  static void run(Database db) {
    final current = version(db);
    for (var index = current; index < all.length; index++) {
      db.transaction(() {
        db.executeScript(all[index]);
        db.execute(
          'INSERT INTO sync_meta (key, value) VALUES (?, ?) '
          'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
          [_key, '${index + 1}'],
        );
      });
    }
  }
}
