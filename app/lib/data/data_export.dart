import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart' as sql;

import '../core/model/day_key.dart';
import 'database.dart';
import 'migrations.dart';
import 'repos.dart';

enum ExportFailureKind { notAGroveFile, newerFile, newerSchema, badData }

/// Why an import was refused. The data is unchanged when this is thrown.
class ExportFailure implements Exception {
  const ExportFailure._(this.kind, [this.why = '']);

  const ExportFailure.badData(String why)
    : this._(ExportFailureKind.badData, why);

  static const notAGroveFile = ExportFailure._(ExportFailureKind.notAGroveFile);
  static const newerFile = ExportFailure._(ExportFailureKind.newerFile);
  static const newerSchema = ExportFailure._(ExportFailureKind.newerSchema);

  final ExportFailureKind kind;
  final String why;

  String get message => switch (kind) {
    ExportFailureKind.notAGroveFile => 'This is not a Grove export file.',
    ExportFailureKind.newerFile || ExportFailureKind.newerSchema =>
      'This file comes from a newer Grove. Update Grove first.',
    ExportFailureKind.badData => 'The file has a problem. $why',
  };

  @override
  bool operator ==(Object other) =>
      other is ExportFailure && other.kind == kind && other.why == why;

  @override
  int get hashCode => Object.hash(kind, why);

  @override
  String toString() => 'ExportFailure: $message';
}

/// What is in a file. The confirm dialog shows it before anything is replaced.
class ExportSummary {
  const ExportSummary({
    required this.tasks,
    required this.events,
    required this.notes,
    required this.lists,
    required this.images,
  });

  final int tasks, events, notes, lists, images;

  @override
  bool operator ==(Object other) =>
      other is ExportSummary &&
      other.tasks == tasks &&
      other.events == events &&
      other.notes == notes &&
      other.lists == lists &&
      other.images == images;

  @override
  int get hashCode => Object.hash(tasks, events, notes, lists, images);

  @override
  String toString() =>
      'ExportSummary(tasks: $tasks, events: $events, notes: $notes, '
      'lists: $lists, images: $images)';
}

class _Insert {
  const _Insert(this.sql, this.args);

  final String sql;
  final List<Object?> args;
}

/// All data in one JSON file, and back (PLAN §4.4). The same file as the Mac
/// app makes and reads. Import replaces everything. A bad file leaves the data
/// as it was.
abstract final class DataExport {
  static const format = 'grove-export';
  static const version = 1;

  /// The tables in the file. The import fills them in this order, so a table
  /// comes after the tables it points to. The search index is not in the file.
  /// The import builds it again.
  static const tables = SyncMigrations.syncedTables;

  /// "grove-export-2026-10-04.json"
  static String suggestedFileName(DayKey day) => 'grove-export-$day.json';

  // Export.

  static String export(Database db) {
    final out = <String, Object?>{};
    for (final table in tables) {
      final skip = SyncMigrations.addedColumns[table] ?? const {};
      out[table] = db.query('SELECT * FROM $table ORDER BY rowid', const [], (
        r,
      ) {
        final row = <String, Object?>{};
        for (var i = 0; i < r.length; i++) {
          final name = r.name(i);
          if (skip.contains(name)) continue;
          final value = r.value(i);
          row[name] = value is Uint8List ? base64Encode(value) : value;
        }
        return row;
      });
    }
    final root = <String, Object?>{
      'format': format,
      'version': version,
      'schema': db.userVersion,
      'exportedAt': Stamp.now(),
      'tables': out,
    };
    return const JsonEncoder.withIndent('  ').convert(_sorted(root));
  }

  /// The same value with every map's keys in A to Z order.
  static Object? _sorted(Object? value) => switch (value) {
    final Map<String, Object?> m => {
      for (final k in m.keys.toList()..sort()) k: _sorted(m[k]),
    },
    final List<Object?> l => [for (final v in l) _sorted(v)],
    _ => value,
  };

  // Look inside.

  /// Counts what a file holds. Throws when it is not a usable file. Changes nothing.
  static ExportSummary summary(String data) {
    final tables = _readRoot(data).tables;
    int count(String name) => switch (tables[name]) {
      final List<Object?> l => l.length,
      _ => 0,
    };
    return ExportSummary(
      tasks: count('tasks'),
      events: count('events'),
      notes: count('notes'),
      lists: count('lists'),
      images: count('attachments'),
    );
  }

  // Import.

  /// Replaces all data with the data in [data]. All or nothing.
  static void importData(String data, Repos repos) {
    final db = repos.db;
    final root = _readRoot(data);
    if (root.schema > db.userVersion) throw ExportFailure.newerSchema;
    final inserts = _prepareInserts(root.tables, db);
    try {
      db.transaction(() {
        // Rows may come in any order inside a table (a subtask before its parent).
        // Check the links at the end.
        db.executeScript('PRAGMA defer_foreign_keys = ON');
        for (final table in tables.reversed) {
          db.execute('DELETE FROM $table');
        }
        db.execute('DELETE FROM search');
        for (final insert in inserts) {
          db.execute(insert.sql, insert.args);
        }
        repos.rebuildSearch();
      });
    } on sql.SqliteException catch (e) {
      // A row breaks a rule of the database (a missing value, a link to
      // nothing). The transaction is rolled back, so nothing changed.
      throw ExportFailure.badData('A row does not fit: ${e.message}.');
    }
  }

  // Reading the file.

  static ({int schema, Map<String, Object?> tables}) _readRoot(String data) {
    Object? root;
    try {
      root = jsonDecode(data);
    } on FormatException {
      throw ExportFailure.notAGroveFile;
    }
    if (root
        case {
          'format': format,
          'version': final int fileVersion,
          'schema': final int schema,
          'tables': final Map<String, Object?> tables,
        }
        when fileVersion >= 1) {
      if (fileVersion > version) throw ExportFailure.newerFile;
      return (schema: schema, tables: tables);
    }
    throw ExportFailure.notAGroveFile;
  }

  /// Turns every row into one INSERT. All checks happen here, before anything
  /// is deleted.
  static List<_Insert> _prepareInserts(
    Map<String, Object?> fileTables,
    Database db,
  ) {
    for (final name in fileTables.keys) {
      if (!tables.contains(name)) {
        throw ExportFailure.badData(
          'It has a table that Grove does not know: $name.',
        );
      }
    }
    final inserts = <_Insert>[];
    for (final table in tables) {
      final value = fileTables[table];
      if (value == null) continue; // A missing table is an empty table.
      if (value is! List<Object?> ||
          value.any((row) => row is! Map<String, Object?>)) {
        throw ExportFailure.badData('The table $table is not a list of rows.');
      }
      final known = _columns(table, db);
      for (final row in value.cast<Map<String, Object?>>()) {
        final names = <String>[], args = <Object?>[];
        for (final column in row.keys.toList()..sort()) {
          final isBlob = known[column];
          if (isBlob == null) {
            throw ExportFailure.badData(
              'The table $table has a column that Grove does not know: '
              '$column.',
            );
          }
          names.add('"$column"');
          args.add(_sqlValue(row[column], isBlob, '$table.$column'));
        }
        if (names.isEmpty) {
          throw ExportFailure.badData('The table $table has an empty row.');
        }
        final marks = List.filled(names.length, '?').join(', ');
        inserts.add(
          _Insert(
            'INSERT INTO $table (${names.join(', ')}) VALUES ($marks)',
            args,
          ),
        );
      }
    }
    return inserts;
  }

  /// Column name to "is it a BLOB column".
  static Map<String, bool> _columns(String table, Database db) => {
    for (final (name, isBlob) in db.query(
      'PRAGMA table_info($table)',
      const [],
      (r) => (r.text(1), r.text(2).toUpperCase() == 'BLOB'),
    ))
      name: isBlob,
  };

  static Object? _sqlValue(Object? raw, bool isBlob, String place) {
    switch (raw) {
      case null:
        return null;
      case final String text:
        if (!isBlob) return text;
        try {
          return base64Decode(text);
        } on FormatException {
          throw ExportFailure.badData('The picture data in $place is damaged.');
        }
      case final bool flag:
        return flag ? 1 : 0;
      case final num number:
        if (isBlob) {
          throw ExportFailure.badData('The picture data in $place is damaged.');
        }
        return number;
      default:
        throw ExportFailure.badData(
          'The value in $place is not text or a number.',
        );
    }
  }
}
