import '../data/database.dart';
import '../data/migrations.dart';
import '../data/sync_schema.dart';

/// What a column holds.
enum RemoteType { text, integer, real, bytes }

/// One data column of a synced table.
class RemoteColumn {
  const RemoteColumn(this.name, this.type);

  final String name;
  final RemoteType type;
}

/// One synced table, as the remote keeps it.
class RemoteTable {
  const RemoteTable({
    required this.name,
    required this.columns,
    required this.keyColumns,
  });

  final String name;

  /// The data columns of the app, in table order. The key columns are in it.
  final List<RemoteColumn> columns;

  /// The columns of the primary key, in key order.
  final List<String> keyColumns;

  /// The columns the remote table has. Bytes are not in a remote table (the
  /// bytes of an image go to the file store).
  Iterable<RemoteColumn> get stored =>
      columns.where((c) => c.type != RemoteType.bytes);

  RemoteColumn? column(String name) {
    for (final c in columns) {
      if (c.name == name) return c;
    }
    return null;
  }
}

/// The synced tables and their columns, read from the database of the app.
/// The SQL for Supabase is made from this (`supabaseSql`), and the Supabase
/// remote uses it to send and read each value with the correct type.
class RemoteSchema {
  const RemoteSchema({required this.version, required this.tables});

  factory RemoteSchema.read(Database db) => RemoteSchema(
    version: Migrations.all.length,
    tables: [for (final name in SyncMigrations.syncedTables) _table(db, name)],
  );

  /// The number of the data schema of the app (the count of shared
  /// migrations). The remote refuses an app with another number.
  final int version;

  /// Parents first, as in `SyncMigrations.syncedTables`.
  final List<RemoteTable> tables;

  RemoteTable? table(String name) {
    for (final t in tables) {
      if (t.name == name) return t;
    }
    return null;
  }

  static RemoteTable _table(Database db, String name) {
    final shape = SyncTable.read(db, name);
    final declared = {
      for (final c in db.query(
        'PRAGMA table_info($name)',
        const [],
        (r) => (name: r.text(1), type: r.text(2)),
      ))
        c.name: c.type,
    };
    return RemoteTable(
      name: name,
      columns: [
        for (final c in shape.columns) RemoteColumn(c, _type(declared[c]!)),
      ],
      keyColumns: shape.keyColumns,
    );
  }

  /// The rule of SQLite for the type of a column, from its declared type.
  static RemoteType _type(String declared) {
    final d = declared.toUpperCase();
    if (d.contains('INT')) return RemoteType.integer;
    if (d.contains('CHAR') || d.contains('CLOB') || d.contains('TEXT')) {
      return RemoteType.text;
    }
    if (d.contains('BLOB')) return RemoteType.bytes;
    if (d.contains('REAL') || d.contains('FLOA') || d.contains('DOUB')) {
      return RemoteType.real;
    }
    throw StateError('No remote type for a column declared as "$declared".');
  }
}
