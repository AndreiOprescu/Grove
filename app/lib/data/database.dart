import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart' as sql;

import 'migrations.dart';

/// One result row. Column indexes start at 0.
/// Like the Mac app, a NULL reads as '' for text and 0 for numbers.
class Row {
  Row(this._values, this._names);

  final List<Object?> _values;
  final List<String> _names;

  int get length => _values.length;
  String name(int i) => _names[i];

  /// The value as SQLite gave it: int, double, String, Uint8List or null.
  Object? value(int i) => _values[i];

  String text(int i) => switch (_values[i]) {
    null => '',
    final String s => s,
    final Uint8List b => String.fromCharCodes(b),
    final Object o => o.toString(),
  };

  String? optText(int i) => _values[i] == null ? null : text(i);

  int asInt(int i) => switch (_values[i]) {
    final int n => n,
    final double d => d.toInt(),
    final String s => int.tryParse(s) ?? 0,
    _ => 0,
  };

  int? optInt(int i) => _values[i] == null ? null : asInt(i);

  double asDouble(int i) => switch (_values[i]) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s) ?? 0,
    _ => 0,
  };

  bool asBool(int i) => asInt(i) != 0;

  Uint8List blob(int i) => switch (_values[i]) {
    final Uint8List b => b,
    final String s => Uint8List.fromList(s.codeUnits),
    _ => Uint8List(0),
  };
}

/// Thin SQLite wrapper, the same shape as the Mac app's `Database`.
/// Use it from one isolate only; the data set is small.
class Database {
  Database._(this._db, this.path) {
    _db.execute('PRAGMA journal_mode=WAL');
    _db.execute('PRAGMA foreign_keys=ON');
    Migrations.run(this);
    SyncMigrations.run(this);
  }

  /// Opens (or creates) the file at [path] and brings its schema up to date.
  factory Database.open(String path) =>
      Database._(sql.sqlite3.open(path), path);

  factory Database.inMemory() =>
      Database._(sql.sqlite3.openInMemory(), ':memory:');

  final sql.Database _db;
  final String path;
  final _cache = <String, sql.PreparedStatement>{};
  var _savepoints = 0;

  sql.PreparedStatement _statement(String sqlText) =>
      _cache[sqlText] ??= _db.prepare(sqlText);

  static List<Object?> _bind(List<Object?> args) => [
    for (final a in args) a is bool ? (a ? 1 : 0) : a,
  ];

  /// Runs one statement. Any rows it returns are ignored.
  void execute(String sqlText, [List<Object?> args = const []]) =>
      _statement(sqlText).execute(_bind(args));

  /// Runs several statements separated by semicolons (no parameters).
  void executeScript(String sqlText) => _db.execute(sqlText);

  List<T> query<T>(
    String sqlText,
    List<Object?> args,
    T Function(Row row) map,
  ) {
    final result = _statement(sqlText).select(_bind(args));
    final names = result.columnNames;
    return [for (final values in result.rows) map(Row(values, names))];
  }

  T? queryOne<T>(String sqlText, List<Object?> args, T Function(Row row) map) {
    final rows = query(sqlText, args, map);
    return rows.isEmpty ? null : rows.first;
  }

  /// Number of rows changed by the last write.
  int get changes => _db.updatedRows;

  /// Nested-safe transaction (uses savepoints). Rolls back if [body] throws.
  T transaction<T>(T Function() body) {
    final name = 'sp${++_savepoints}';
    _db.execute('SAVEPOINT $name');
    try {
      final result = body();
      _db.execute('RELEASE $name');
      return result;
    } catch (_) {
      try {
        _db.execute('ROLLBACK TO $name');
        _db.execute('RELEASE $name');
      } on sql.SqliteException {
        // The savepoint is already gone. Nothing more to undo.
      }
      rethrow;
    }
  }

  /// The shared schema number. The Mac app reads and writes the same one.
  int get userVersion => _db.userVersion;
  set userVersion(int value) => _db.userVersion = value;

  /// The schema number of the sync-only changes (see [SyncMigrations]).
  int get syncVersion => SyncMigrations.version(this);

  void close() {
    for (final s in _cache.values) {
      s.close();
    }
    _cache.clear();
    _db.close();
  }
}
