import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../data/helpers.dart' show tempDir;
import 'support.dart';

AppStore openStore(String dir) {
  final s = AppStore.open(dataDir: dir, prefs: MemoryPrefs());
  addTearDown(() {
    s.dispose();
    s.repos.db.close();
  });
  return s;
}

List<String> names(AppStore s) => [
  for (final f in s.backupFiles()) f.path.split(Platform.pathSeparator).last,
];

void main() {
  final today = DayKey.today();

  test('the launch made the copy of today, so a new call makes none', () {
    final s = openStore(tempDir('grove-backup').path);
    expect(names(s), ['grove-${today.string}.sqlite']);
    expect(s.runDailyBackup(), isNull);
    expect(names(s).length, 1);
  });

  test('a new day gets its own copy, with the data of now', () {
    final s = openStore(tempDir('grove-backup').path);
    s.quickAdd('Made after the launch');
    final tomorrow = today.adding(days: 1);

    final path = s.runDailyBackup(today: tomorrow);

    expect(path, endsWith('grove-${tomorrow.string}.sqlite'));
    expect(names(s), [
      'grove-${tomorrow.string}.sqlite',
      'grove-${today.string}.sqlite',
    ]);
    final copy = Repos(Database.open(path!));
    addTearDown(copy.db.close);
    expect(
      copy.tasks.all().map((t) => t.title),
      contains('Made after the launch'),
    );
  });

  test('only the newest 14 copies stay', () {
    final s = openStore(tempDir('grove-backup').path);
    for (var i = 1; i <= 20; i++) {
      s.runDailyBackup(today: today.adding(days: i));
    }
    final list = names(s);
    expect(list.length, 14);
    expect(list.first, 'grove-${today.adding(days: 20).string}.sqlite');
  });

  test('a new copy also drops the old images that no text uses', () {
    final s = openStore(tempDir('grove-backup').path);
    final old = DateTime.now().subtract(const Duration(days: 3));
    s.repos.db.execute(
      'INSERT INTO attachments (id, data, mime, created_at) VALUES (?, ?, ?, ?)',
      [
        'A1',
        Uint8List.fromList([1, 2, 3]),
        'image/png',
        Stamp.fromDate(old),
      ],
    );
    expect(s.repos.attachments.count(), 1);

    // No new copy: the images stay.
    s.runDailyBackup();
    expect(s.repos.attachments.count(), 1);

    s.runDailyBackup(today: today.adding(days: 1));
    expect(s.repos.attachments.count(), 0);
  });

  test('a store in memory has no folder: nothing happens', () {
    expect(makeStore().runDailyBackup(), isNull);
  });

  test('a folder that cannot be written gives null, not an error', () {
    final dir = tempDir('grove-backup');
    final s = openStore(dir.path);
    final backups = Directory('${dir.path}${Platform.pathSeparator}Backups')
      ..deleteSync(recursive: true);
    // A file is in the way of the folder.
    File(backups.path).writeAsStringSync('in the way');
    expect(s.runDailyBackup(today: today.adding(days: 1)), isNull);
  });
}
