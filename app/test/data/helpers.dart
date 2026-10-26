import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grove/data/data.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

Repos makeRepos() => Repos(Database.inMemory());

/// A fresh folder that is deleted after the test. Close every database in it first.
Directory tempDir(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

String join(Directory dir, String name) =>
    '${dir.path}${Platform.pathSeparator}$name';

/// Builds an old database the way an older Mac app left it: only the first
/// [version] migrations, then [seed].
String oldDatabase(Directory dir, int version, String seed) {
  final path = join(dir, 'old-$version.sqlite');
  final db = raw.sqlite3.open(path);
  db.execute(
    '${Migrations.all.take(version).join(';')};'
    'PRAGMA user_version = $version;$seed',
  );
  db.close();
  return path;
}

/// The columns that shared migration 14 put on `notes`.
const notebookNoteColumns = [
  'notebook_id',
  'section_id',
  'sort_order',
  'archived_at',
];

/// Takes a database of this app back to before shared migration 14 and sync
/// migration 8 (notebooks): no notebook tables, no new note columns, and the
/// update trigger of `notes` and the saved trigger list of before. A test
/// that takes a database back to an older build calls this first.
void rewindNotebooks(Database db) {
  final trigger = db.queryOne(
    "SELECT sql FROM sqlite_master WHERE name = 'sync_notes_update'",
    const [],
    (r) => r.text(0),
  );
  db.executeScript('''
    DROP TRIGGER IF EXISTS sync_notes_update;
    DROP INDEX IF EXISTS notes_notebook;
    ${[for (final c in notebookNoteColumns) 'ALTER TABLE notes DROP COLUMN $c;'].join('\n')}
    DROP TABLE notebook_sections;
    DROP TABLE notebooks;
  ''');
  if (trigger != null) {
    var old = trigger;
    for (final c in notebookNoteColumns) {
      old = old.replaceAll(' OR OLD.$c IS NOT NEW.$c', '');
    }
    db.executeScript('$old;');
  }
  final saved = db.queryOne(
    "SELECT value FROM sync_meta WHERE key = 'triggers'",
    const [],
    (r) => r.text(0),
  );
  if (saved != null) {
    final old = saved
        .replaceAll(RegExp(r';notebooks:[^;]*'), '')
        .replaceAll(RegExp(r';notebook_sections:[^;]*'), '')
        .replaceAll(',${notebookNoteColumns.join(',')}', '');
    db.execute("UPDATE sync_meta SET value = ? WHERE key = 'triggers'", [old]);
  }
  final hasOutbox = db.queryOne(
    "SELECT 1 FROM sqlite_master WHERE name = 'outbox'",
    const [],
    (r) => r.asInt(0),
  );
  if (hasOutbox != null) {
    db.execute(
      "DELETE FROM outbox WHERE tbl IN ('notebooks', 'notebook_sections')",
    );
  }
}
