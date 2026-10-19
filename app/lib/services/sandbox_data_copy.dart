import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart' as sql;

import '../data/first_run.dart';

/// How [SandboxDataCopy.copyOnce] ended.
enum SandboxCopyResult {
  /// The old data is in the new folder now.
  copied,

  /// Nothing to do: no old data, the copy was made before, or the new
  /// database has the data of the person.
  skipped,

  /// The copy did not work. The new folder has no database from it, the old
  /// folder is as it was, and the next start tries again.
  failed,
}

/// Grove for Mac left the sandbox for the agent (ADR 0004). Its data folder
/// moved from the sandbox container to `~/Library/Application Support`. On
/// the first start outside the sandbox the old folder is copied, never moved
/// or changed: it stays as a backup.
///
/// The steps, so that a crash or an error never loses data:
/// 1. Every file but the database is copied. A file that is there is kept.
/// 2. SQLite writes the old database into `grove.sqlite.part`
///    (`VACUUM INTO`). That takes in the rows that are still in the WAL, and
///    it works while the old Grove is still open.
/// 3. An empty new database is put aside as `grove.sqlite.empty-<time>`.
/// 4. `grove.sqlite.part` becomes `grove.sqlite`, the last step.
/// 5. The marker file says the copy is done.
abstract final class SandboxDataCopy {
  /// The database file in a data folder.
  static const dbName = 'grove.sqlite';

  /// The file that says the copy is done. Written after the last step only.
  static const markerName = '.sandbox-copied';

  /// The line Grove shows when the copy failed.
  static const failedMessage =
      'Grove could not copy your old data. It is safe in '
      '~/Library/Containers/local.grove.app. Quit the old Grove and start '
      'again.';

  /// The files that belong to the database. They are never copied as files.
  static const _dbFiles = {
    dbName,
    '$dbName-wal',
    '$dbName-shm',
    '$dbName-journal',
  };

  /// The tables that hold what a person made. A list alone is not counted:
  /// a new Grove makes three.
  static const _dataTables = ['notes', 'events'];

  /// The data folder of the sandboxed Grove of the Mac, in [home].
  static String oldFolder(String home) =>
      '$home/Library/Containers/local.grove.app/Data/Library/'
      'Application Support/local.grove.app';

  /// Copies the old folder [from] into [to] when the copy was not made yet
  /// and [to] has no database with data. Never throws.
  static SandboxCopyResult copyOnce({
    required String from,
    required String to,
    DateTime? now,
  }) {
    final sep = Platform.pathSeparator;
    final oldDb = '$from$sep$dbName';
    final newDb = '$to$sep$dbName';
    final part = '$newDb.part';
    final marker = '$to$sep$markerName';
    try {
      if (File(marker).existsSync()) return SandboxCopyResult.skipped;
      if (!File(oldDb).existsSync()) return SandboxCopyResult.skipped;
      final hasNew = File(newDb).existsSync();
      if (hasNew && _hasUserData(newDb)) {
        // Never over the data of the person.
        _writeMarker(marker, now);
        return SandboxCopyResult.skipped;
      }
      Directory(to).createSync(recursive: true);
      _deleteIfThere(part);
      _copyDir(Directory(from), Directory(to), top: true);
      _vacuumInto(oldDb, part);
      _putAside(to, now ?? DateTime.now());
      File(part).renameSync(newDb);
      _writeMarker(marker, now);
      return SandboxCopyResult.copied;
    } on Exception {
      // A SQLite or a file error. No half database is left.
      try {
        _deleteIfThere(part);
      } on Exception {
        // The next start deletes it.
      }
      return SandboxCopyResult.failed;
    }
  }

  /// True when the database at [path] has a task, a note or an event that
  /// the person made. The sample tasks of a new Grove do not count.
  static bool _hasUserData(String path) {
    final db = sql.sqlite3.open(path, mode: sql.OpenMode.readOnly);
    try {
      db.execute('PRAGMA busy_timeout = 5000');
      bool has(String table) => db.select(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
        [table],
      ).isNotEmpty;
      for (final t in _dataTables) {
        if (has(t) && db.select('SELECT 1 FROM $t LIMIT 1').isNotEmpty) {
          return true;
        }
      }
      if (!has('tasks')) return false;
      final samples = <String>{};
      if (has('settings')) {
        final rows = db.select('SELECT value FROM settings WHERE key = ?', [
          FirstRun.samplesKey,
        ]);
        if (rows.isNotEmpty) {
          try {
            final ids = jsonDecode('${rows.first.values.first}');
            if (ids is List) samples.addAll(ids.whereType<String>());
          } on FormatException {
            // No sample ids: every task counts.
          }
        }
      }
      return db
          .select('SELECT id FROM tasks')
          .any((r) => !samples.contains('${r.values.first}'));
    } finally {
      db.close();
    }
  }

  /// SQLite writes the database at [from], with its WAL, into one new file
  /// [to]. [from] is opened read-only: nothing in the old folder changes.
  static void _vacuumInto(String from, String to) {
    final db = sql.sqlite3.open(from, mode: sql.OpenMode.readOnly);
    try {
      db.execute('PRAGMA busy_timeout = 5000');
      db.execute('VACUUM INTO ?', [to]);
    } finally {
      db.close();
    }
    // SQLite does not flush the new file to the disk.
    final f = File(to).openSync(mode: FileMode.append);
    try {
      f.flushSync();
    } finally {
      f.closeSync();
    }
  }

  /// Puts the database files of [dir] aside, so the copy takes their place
  /// and a WAL of the empty database is never read with the copy.
  static void _putAside(String dir, DateTime now) {
    final sep = Platform.pathSeparator;
    final aside = '$dir$sep$dbName.empty-${_stamp(now)}';
    for (final end in const ['', '-wal', '-shm', '-journal']) {
      final f = File('$dir$sep$dbName$end');
      if (f.existsSync()) f.renameSync('$aside$end');
    }
  }

  static String _stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  static void _writeMarker(String path, DateTime? now) =>
      File(path).writeAsStringSync('${(now ?? DateTime.now()).toUtc()}\n');

  static void _deleteIfThere(String path) {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  }

  static void _copyDir(Directory from, Directory to, {bool top = false}) {
    final sep = Platform.pathSeparator;
    for (final e in from.listSync(followLinks: false)) {
      final name = e.path.split(sep).last;
      if (top && _dbFiles.contains(name)) continue;
      final target = '${to.path}$sep$name';
      if (e is Directory) {
        final dir = Directory(target)..createSync(recursive: true);
        _copyDir(e, dir);
      } else if (e is File) {
        if (File(target).existsSync()) continue;
        // Under another name first: a copy cut off half way is never kept.
        final temp = '$target.copying';
        e.copySync(temp);
        File(temp).renameSync(target);
      }
      // A link is left out: it can point anywhere.
    }
  }
}
