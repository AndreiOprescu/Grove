import 'database.dart';
import 'sync_schema.dart';

/// Ordered schema migrations. Index N takes the database from user_version N to N+1.
/// 1 to 7 are the Mac app's migrations, word for word. 8 to 10 are in this
/// app only (the Mac app has no subtasks of a goal and no persona). The
/// export file carries the number, and an app refuses a file with a higher
/// number than its own: the Mac app does not read a file of this app. Never
/// edit a shipped migration; append a new one.
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

    // 7 — subtasks of one goal block. They hang off the event, not the goal, so each block has its own list.
    // A new table only: no old row changes.
    '''
    CREATE TABLE block_subtasks (
      id TEXT PRIMARY KEY, event_id TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
      title TEXT NOT NULL, done_at TEXT, sort REAL NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL
    );
    CREATE INDEX block_subtasks_event ON block_subtasks(event_id);
    ''',

    // 8 — subtasks of a goal. They hang off the goal, so every block of the goal has the same list.
    // A new table only: no old row changes. Not in the Mac app.
    '''
    CREATE TABLE goal_subtasks (
      id TEXT PRIMARY KEY, goal_id TEXT NOT NULL REFERENCES goals(id) ON DELETE CASCADE,
      title TEXT NOT NULL, done_at TEXT, sort REAL NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL
    );
    CREATE INDEX goal_subtasks_goal ON goal_subtasks(goal_id);
    ''',
    // 9 — a subtask of a goal can be planned in one block of the goal. It stays a row of the goal.
    // A deleted block gives it back: the pointer becomes empty. Not in the Mac app.
    '''
    ALTER TABLE goal_subtasks ADD COLUMN event_id TEXT REFERENCES events(id) ON DELETE SET NULL;
    CREATE INDEX goal_subtasks_event ON goal_subtasks(event_id);
    ''',
    // 10 — the persona: its skills, the rewards on tasks and goals, and the
    // log of earned points. The 8 built-in skills have fixed ids, so two
    // devices have the same rows. An earning points at its task or block with
    // no foreign key: it stays when they are deleted. New tables only. Not in
    // the Mac app.
    '''
    CREATE TABLE skills (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, sort REAL NOT NULL DEFAULT 0,
      hidden INTEGER NOT NULL DEFAULT 0, builtin INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL
    );
    INSERT INTO skills (id, name, sort, builtin, created_at, updated_at) VALUES
      ('skill-strength', 'Strength', 1, 1, '2026-10-15T00:00:00', '2026-10-15T00:00:00'),
      ('skill-mind', 'Mind', 2, 1, '2026-10-15T00:00:00', '2026-10-15T00:00:00'),
      ('skill-social', 'Social', 3, 1, '2026-10-15T00:00:00', '2026-10-15T00:00:00'),
      ('skill-focus', 'Focus', 4, 1, '2026-10-15T00:00:00', '2026-10-15T00:00:00'),
      ('skill-creativity', 'Creativity', 5, 1, '2026-10-15T00:00:00', '2026-10-15T00:00:00'),
      ('skill-health', 'Health', 6, 1, '2026-10-15T00:00:00', '2026-10-15T00:00:00'),
      ('skill-home', 'Home', 7, 1, '2026-10-15T00:00:00', '2026-10-15T00:00:00'),
      ('skill-money', 'Money', 8, 1, '2026-10-15T00:00:00', '2026-10-15T00:00:00');

    CREATE TABLE rewards (
      id TEXT PRIMARY KEY,
      task_id TEXT REFERENCES tasks(id) ON DELETE CASCADE,
      goal_id TEXT REFERENCES goals(id) ON DELETE CASCADE,
      skill_id TEXT NOT NULL REFERENCES skills(id) ON DELETE CASCADE,
      points INTEGER NOT NULL,
      CHECK ((task_id IS NULL) <> (goal_id IS NULL))
    );
    CREATE INDEX rewards_task ON rewards(task_id);
    CREATE INDEX rewards_goal ON rewards(goal_id);

    CREATE TABLE earnings (
      id TEXT PRIMARY KEY,
      skill_id TEXT NOT NULL REFERENCES skills(id) ON DELETE CASCADE,
      points INTEGER NOT NULL, source_kind TEXT NOT NULL, source_id TEXT NOT NULL,
      title TEXT NOT NULL DEFAULT '', earned_at TEXT NOT NULL
    );
    CREATE INDEX earnings_source ON earnings(source_kind, source_id);
    CREATE INDEX earnings_time ON earnings(earned_at);
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
/// They have their own number in `sync_meta`, so they do not raise
/// `user_version`.
abstract final class SyncMigrations {
  /// The tables the sync columns go on. The same list as `DataExport.tables`.
  /// A table comes after the tables it points at: the sync sends them in
  /// this order. `goal_subtasks` points at `goals` and at `events`.
  static const syncedTables = [
    'lists',
    'notes',
    'goals',
    'tasks',
    'events',
    'block_subtasks',
    'goal_subtasks',
    'skills',
    'rewards',
    'earnings',
    'event_exdates',
    'links',
    'tags',
    'task_tags',
    'note_tags',
    'settings',
    'attachments',
  ];

  /// Tables that already had `updated_at` in the shared schema.
  static const _hadUpdatedAt = {
    'notes',
    'goals',
    'tasks',
    'events',
    'block_subtasks',
    'goal_subtasks',
    'skills',
  };

  /// The columns each sync migration added, by table. The export leaves them out.
  static final Map<String, Set<String>> addedColumns = {
    for (final t in syncedTables)
      t: {'deleted', 'user_id', if (!_hadUpdatedAt.contains(t)) 'updated_at'},
  };

  /// Index N takes the sync schema from version N to N+1.
  static final all = <void Function(Database db)>[
    // 1 — a soft-delete flag, the owner and an edit time on every synced table.
    (db) => db.executeScript(
      [
        for (final t in syncedTables) ...[
          'ALTER TABLE $t ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0;',
          'ALTER TABLE $t ADD COLUMN user_id TEXT;',
          if (!_hadUpdatedAt.contains(t))
            "ALTER TABLE $t ADD COLUMN updated_at TEXT NOT NULL DEFAULT '';",
        ],
      ].join('\n'),
    ),
    // 2 — the outbox: the local changes that the remote does not have yet.
    SyncSchema.createOutbox,
    // 3 — `block_subtasks` (shared migration 7) joins the sync. A database
    // from before it has the table with no sync columns and no outbox lines.
    // On a new database, 1 and 2 did the work and this changes nothing.
    (db) => SyncSchema.addTable(db, 'block_subtasks'),
    // 4 — `goal_subtasks` (shared migration 8) joins the sync, in the same
    // way.
    (db) => SyncSchema.addTable(db, 'goal_subtasks'),
    // 5 — the persona tables (shared migration 10) join the sync. The
    // built-in skills stay out of the outbox: every device makes them in
    // shared migration 10, so only a change of one is sent.
    (db) {
      for (final t in const ['skills', 'rewards', 'earnings']) {
        SyncSchema.addTable(db, t);
      }
      db.executeScript(
        "DELETE FROM outbox WHERE tbl = 'skills' "
        'AND pk IN (SELECT id FROM skills WHERE builtin = 1)',
      );
    },
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
        all[index](db);
        db.execute(
          'INSERT INTO sync_meta (key, value) VALUES (?, ?) '
          'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
          [_key, '${index + 1}'],
        );
      });
    }
    SyncSchema.ensureTriggers(db);
  }
}
