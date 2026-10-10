import 'database.dart';
import 'migrations.dart';

/// A column of a synced table that points at a row of another table.
class SyncForeignKey {
  const SyncForeignKey({
    required this.column,
    required this.parent,
    required this.setsNull,
  });

  final String column;

  /// The table the column points at.
  final String parent;

  /// True for `ON DELETE SET NULL`. False: the row goes with its parent.
  final bool setsNull;
}

/// The shape of one synced table, read from the database itself.
class SyncTable {
  const SyncTable({
    required this.name,
    required this.columns,
    required this.keyColumns,
    required this.foreignKeys,
  });

  factory SyncTable.read(Database db, String name) {
    final skip = SyncMigrations.addedColumns[name] ?? const <String>{};
    final info = db.query(
      'PRAGMA table_info($name)',
      const [],
      (r) => (name: r.text(1), key: r.asInt(5)),
    );
    final keys = info.where((c) => c.key > 0).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return SyncTable(
      name: name,
      columns: [
        for (final c in info)
          if (!skip.contains(c.name)) c.name,
      ],
      keyColumns: [for (final c in keys) c.name],
      foreignKeys: {
        for (final fk in db.query(
          'PRAGMA foreign_key_list($name)',
          const [],
          (r) => (
            id: r.asInt(0),
            parent: r.text(2),
            from: r.text(3),
            onDelete: r.text(6),
          ),
        ))
          fk.id: SyncForeignKey(
            column: fk.from,
            parent: fk.parent,
            setsNull: fk.onDelete.toUpperCase() == 'SET NULL',
          ),
      },
    );
  }

  final String name;

  /// The data columns, in table order. The sync-only columns are not in it.
  final List<String> columns;

  /// The columns of the primary key, in key order.
  final List<String> keyColumns;

  /// By the number that `PRAGMA foreign_key_check` gives.
  final Map<int, SyncForeignKey> foreignKeys;

  /// The key of [row], or null when a key column is missing or is not text.
  String? keyOf(Map<String, Object?> row) {
    final parts = <String>[];
    for (final c in keyColumns) {
      final v = row[c];
      if (v is! String) return null;
      parts.add(v);
    }
    return SyncSchema.key(parts);
  }
}

/// The outbox and the triggers that fill it (cross-platform plan F11).
///
/// Every insert, update and delete on a synced table writes one line in the
/// `outbox` table: which row, when, and if the row is gone. The triggers see
/// every write: the repositories, the import, and the rows that SQLite itself
/// changes when a parent row is deleted.
abstract final class SyncSchema {
  /// Goes between the parts of a key with more than one column.
  static final separator = String.fromCharCode(31);

  static String key(List<String> parts) => parts.join(separator);

  static List<String> keyParts(String key) => key.split(separator);

  /// The time now, in milliseconds since 1970 (UTC).
  static const _now =
      "(CAST(strftime('%s','now') AS INTEGER) * 1000 + "
      "CAST(substr(strftime('%f','now'), 4, 3) AS INTEGER))";

  /// Moves the clock of this device forward. It never goes back and never
  /// gives the same time twice, so a later change always has a higher stamp.
  static const tick =
      'UPDATE sync_meta SET value = max(CAST(value AS INTEGER) + 1, $_now) '
      "WHERE key = 'clock'";

  static const _clock =
      "(SELECT CAST(value AS INTEGER) FROM sync_meta WHERE key = 'clock')";

  /// Writes the line for one row. Two statements and no `OR REPLACE`: inside
  /// a trigger SQLite uses the conflict rule of the outer statement, and the
  /// repositories use `INSERT OR IGNORE`.
  static String _record(String table, String keySql, {required bool deleted}) =>
      "DELETE FROM outbox WHERE tbl = '$table' AND pk = $keySql;\n"
      'INSERT INTO outbox (tbl, pk, stamp, deleted) '
      "VALUES ('$table', $keySql, $_clock, ${deleted ? 1 : 0});";

  static String _keySql(SyncTable t, String row) =>
      t.keyColumns.map((c) => "ifnull($row.$c, '')").join(' || char(31) || ');

  static String _triggers(SyncTable t) {
    final n = t.name;
    final oldKey = _keySql(t, 'OLD'), newKey = _keySql(t, 'NEW');
    final changed = t.columns.map((c) => 'OLD.$c IS NOT NEW.$c').join(' OR ');
    return '''
      DROP TRIGGER IF EXISTS sync_${n}_insert;
      DROP TRIGGER IF EXISTS sync_${n}_update;
      DROP TRIGGER IF EXISTS sync_${n}_delete;
      CREATE TRIGGER sync_${n}_insert AFTER INSERT ON $n BEGIN
        $tick;
        ${_record(n, newKey, deleted: false)}
      END;
      CREATE TRIGGER sync_${n}_update AFTER UPDATE ON $n WHEN $changed BEGIN
        $tick;
        DELETE FROM outbox WHERE tbl = '$n' AND pk = $oldKey AND $oldKey IS NOT $newKey;
        INSERT INTO outbox (tbl, pk, stamp, deleted)
          SELECT '$n', $oldKey, $_clock, 1 WHERE $oldKey IS NOT $newKey;
        ${_record(n, newKey, deleted: false)}
      END;
      CREATE TRIGGER sync_${n}_delete AFTER DELETE ON $n BEGIN
        $tick;
        ${_record(n, oldKey, deleted: true)}
      END;
    ''';
  }

  /// Sync migration 2: the outbox table, the clock and the pull cursor. Rows
  /// that are already there go in the outbox with stamp 0: the remote takes
  /// them only when it has no such row.
  static void createOutbox(Database db) {
    db.executeScript('''
      CREATE TABLE outbox (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        tbl TEXT NOT NULL,
        pk TEXT NOT NULL,
        stamp INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        UNIQUE (tbl, pk)
      );
      INSERT OR IGNORE INTO sync_meta (key, value) VALUES ('clock', '0'), ('cursor', '0');
    ''');
    for (final name in SyncMigrations.syncedTables) {
      final keySql = _keySql(SyncTable.read(db, name), name);
      db.executeScript(
        'INSERT INTO outbox (tbl, pk, stamp, deleted) '
        "SELECT '$name', $keySql, 0, 0 FROM $name ORDER BY rowid",
      );
    }
  }

  /// Raise this number when the trigger text changes.
  static const _triggerVersion = 1;

  /// Makes the triggers again when the columns of a synced table changed (or
  /// the trigger text did). Runs at every open, so a new column is never
  /// left unwatched.
  static void ensureTriggers(Database db) {
    final tables = [
      for (final name in SyncMigrations.syncedTables) SyncTable.read(db, name),
    ];
    final signature = [
      'v$_triggerVersion',
      for (final t in tables) '${t.name}:${t.columns.join(',')}',
    ].join(';');
    final saved = db.queryOne(
      "SELECT value FROM sync_meta WHERE key = 'triggers'",
      const [],
      (r) => r.text(0),
    );
    if (saved == signature) return;
    db.transaction(() {
      for (final t in tables) {
        db.executeScript(_triggers(t));
      }
      db.execute(
        "INSERT INTO sync_meta (key, value) VALUES ('triggers', ?) "
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
        [signature],
      );
    });
  }
}
