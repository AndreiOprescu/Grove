import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/task.dart';
import 'package:grove/data/data.dart';
import 'package:grove/services/sandbox_data_copy.dart';

import '../data/helpers.dart' show tempDir, join;

void main() {
  late Directory old;
  late String fresh;

  String sub(String a, String b) => '$a${Platform.pathSeparator}$b';
  String read(String path) => File(path).readAsStringSync();
  String marker() => sub(fresh, SandboxDataCopy.markerName);

  /// The titles of the tasks in the database at [path].
  List<String> titles(String path) {
    final db = Database.open(path);
    try {
      return [for (final t in Repos(db).tasks.all()) t.title];
    } finally {
      db.close();
    }
  }

  /// A database of Grove at [path] with one task per title.
  void makeDb(String path, List<String> tasks) {
    final db = Database.open(path);
    final repos = Repos(db);
    for (final t in tasks) {
      repos.tasks.save(TaskItem(title: t));
    }
    db.close();
  }

  /// Every file under [dir] with its bytes, to see that nothing changed.
  Map<String, List<int>> snapshot(Directory dir) => {
    for (final e in dir.listSync(recursive: true))
      if (e is File) e.path: e.readAsBytesSync(),
  };

  /// The old folder is as it was. SQLite may add the empty WAL and shared
  /// memory files of a read-only reader, nothing else.
  void sameOld(Map<String, List<int>> before) {
    final now = snapshot(old);
    for (final MapEntry(:key, :value) in before.entries) {
      expect(now[key], value, reason: key);
    }
    for (final path in now.keys.where((k) => !before.containsKey(k))) {
      expect(path, anyOf(endsWith('grove.sqlite-wal'), endsWith('-shm')));
      if (path.endsWith('-wal')) expect(now[path], isEmpty);
    }
  }

  setUp(() {
    old = tempDir('grove-old-');
    fresh = join(tempDir('grove-new-'), 'local.grove.app');
    makeDb(join(old, 'grove.sqlite'), ['Old task']);
    File(join(old, 'prefs.json')).writeAsStringSync('{}');
    Directory(join(old, 'Backups')).createSync();
    File(join(Directory(join(old, 'Backups')), 'grove-2026-10-18.sqlite'))
        .writeAsStringSync('backup');
  });

  test('the old folder is in the sandbox container of the app', () {
    expect(
      SandboxDataCopy.oldFolder('/Users/x'),
      '/Users/x/Library/Containers/local.grove.app/Data/Library/'
      'Application Support/local.grove.app',
    );
  });

  test('copies the database and every other file, and never changes the '
      'old folder', () {
    final before = snapshot(old);
    expect(
      SandboxDataCopy.copyOnce(from: old.path, to: fresh),
      SandboxCopyResult.copied,
    );
    expect(titles(sub(fresh, 'grove.sqlite')), ['Old task']);
    expect(read(sub(fresh, 'prefs.json')), '{}');
    expect(
      read(sub(sub(fresh, 'Backups'), 'grove-2026-10-18.sqlite')),
      'backup',
    );
    expect(File(marker()).existsSync(), isTrue);
    expect(File(sub(fresh, 'grove.sqlite.part')).existsSync(), isFalse);
    sameOld(before);
  });

  test('rows still in the WAL of the old database are copied', () {
    // The old Grove is still running: its last rows are only in the WAL.
    final db = Database.open(join(old, 'grove.sqlite'));
    addTearDown(db.close);
    Repos(db).tasks.save(TaskItem(title: 'Only in the WAL'));
    expect(File(join(old, 'grove.sqlite-wal')).lengthSync(), greaterThan(0));

    expect(
      SandboxDataCopy.copyOnce(from: old.path, to: fresh),
      SandboxCopyResult.copied,
    );
    expect(File(sub(fresh, 'grove.sqlite-wal')).existsSync(), isFalse);
    expect(
      titles(sub(fresh, 'grove.sqlite')),
      unorderedEquals(['Old task', 'Only in the WAL']),
    );
  });

  test('a copy cut off half way (a .part left) is done on the next start', () {
    Directory(fresh).createSync(recursive: true);
    File(sub(fresh, 'grove.sqlite.part')).writeAsStringSync('half');
    File(sub(fresh, 'prefs.json')).writeAsStringSync('{"copied":1}');

    expect(
      SandboxDataCopy.copyOnce(from: old.path, to: fresh),
      SandboxCopyResult.copied,
    );
    expect(titles(sub(fresh, 'grove.sqlite')), ['Old task']);
    expect(File(sub(fresh, 'grove.sqlite.part')).existsSync(), isFalse);
    // A file that is there already is kept.
    expect(read(sub(fresh, 'prefs.json')), '{"copied":1}');
    expect(File(marker()).existsSync(), isTrue);
  });

  test('a copy that fails makes no database, keeps the old folder, and is '
      'tried again', () {
    // Not a database: SQLite cannot read it.
    File(join(old, 'grove.sqlite')).writeAsStringSync('not a database');
    final before = snapshot(old);

    expect(
      SandboxDataCopy.copyOnce(from: old.path, to: fresh),
      SandboxCopyResult.failed,
    );
    expect(File(sub(fresh, 'grove.sqlite')).existsSync(), isFalse);
    expect(File(sub(fresh, 'grove.sqlite.part')).existsSync(), isFalse);
    expect(File(marker()).existsSync(), isFalse);
    sameOld(before);
    expect(
      SandboxDataCopy.failedMessage,
      'Grove could not copy your old data. It is safe in '
      '~/Library/Containers/local.grove.app. Quit the old Grove and start '
      'again.',
    );

    // The next start tries again.
    for (final e in old.listSync().whereType<File>()) {
      if (e.path.contains('grove.sqlite')) e.deleteSync();
    }
    makeDb(join(old, 'grove.sqlite'), ['Fixed']);
    expect(
      SandboxDataCopy.copyOnce(from: old.path, to: fresh),
      SandboxCopyResult.copied,
    );
    expect(titles(sub(fresh, 'grove.sqlite')), ['Fixed']);
  });

  test('a new database with the data of the person is never replaced', () {
    Directory(fresh).createSync(recursive: true);
    makeDb(sub(fresh, 'grove.sqlite'), ['New task']);

    expect(
      SandboxDataCopy.copyOnce(from: old.path, to: fresh),
      SandboxCopyResult.skipped,
    );
    expect(titles(sub(fresh, 'grove.sqlite')), ['New task']);
    expect(File(sub(fresh, 'prefs.json')).existsSync(), isFalse);
    expect(File(marker()).existsSync(), isTrue);
  });

  test('a new database with only the sample data is replaced, and kept '
      'aside', () {
    Directory(fresh).createSync(recursive: true);
    final db = Database.open(sub(fresh, 'grove.sqlite'));
    FirstRun.seedIfNew(Repos(db), today: DayKey.today());
    db.close();

    expect(
      SandboxDataCopy.copyOnce(from: old.path, to: fresh),
      SandboxCopyResult.copied,
    );
    expect(titles(sub(fresh, 'grove.sqlite')), ['Old task']);
    final aside = Directory(fresh)
        .listSync()
        .map((e) => e.path.split(Platform.pathSeparator).last)
        .where((n) => n.startsWith('grove.sqlite.empty-'))
        // Its WAL and shared memory files go aside with it.
        .where((n) => !n.endsWith('-wal') && !n.endsWith('-shm'))
        .toList();
    expect(aside, hasLength(1));
    expect(
      aside.single,
      matches(RegExp(r'^grove\.sqlite\.empty-\d{8}-\d{6}$')),
    );
    expect(
      titles(sub(fresh, aside.single)),
      unorderedEquals(FirstRun.sampleTitles),
    );
  });

  test('the empty database is checked with its open WAL too', () {
    // Grove opened the new empty database and the person added a task that
    // is only in its WAL so far.
    Directory(fresh).createSync(recursive: true);
    final db = Database.open(sub(fresh, 'grove.sqlite'));
    addTearDown(db.close);
    Repos(db).tasks.save(TaskItem(title: 'In the new WAL'));

    expect(
      SandboxDataCopy.copyOnce(from: old.path, to: fresh),
      SandboxCopyResult.skipped,
    );
    expect(File(marker()).existsSync(), isTrue);
  });

  test('a second start does nothing', () {
    expect(
      SandboxDataCopy.copyOnce(from: old.path, to: fresh),
      SandboxCopyResult.copied,
    );
    final before = snapshot(Directory(fresh));
    // Even an empty folder again: the marker says the copy was made.
    expect(
      SandboxDataCopy.copyOnce(from: old.path, to: fresh),
      SandboxCopyResult.skipped,
    );
    expect(snapshot(Directory(fresh)), before);
  });

  test('does nothing when the old folder is missing', () {
    final gone = join(old, 'nothing-here');
    expect(
      SandboxDataCopy.copyOnce(from: gone, to: fresh),
      SandboxCopyResult.skipped,
    );
    expect(Directory(fresh).existsSync(), isFalse);
  });
}
