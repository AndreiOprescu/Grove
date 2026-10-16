// Where the database file is (PLAN §4): in the data folder of the app, under
// the name `grove.sqlite`. `main.dart` gives the folder of the system for the
// files of the app; `AppStore.open` makes the path.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../state/support.dart';
import 'helpers.dart' show join, tempDir;

AppStore openStore(String dir) {
  final s = AppStore.open(dataDir: dir, prefs: MemoryPrefs());
  addTearDown(() {
    s.dispose();
    s.repos.db.close();
  });
  return s;
}

void main() {
  test('the database file is grove.sqlite in the data folder', () {
    final dir = tempDir('grove-place');
    final s = openStore(dir.path);

    expect(s.dataDir, dir.path);
    expect(s.repos.db.path, join(dir, 'grove.sqlite'));
    expect(File(join(dir, 'grove.sqlite')).existsSync(), isTrue);
  });

  test('a data folder that is not there yet is made', () {
    final dir = Directory(
      join(Directory(join(tempDir('grove-place'), 'a')), 'Grove'),
    );
    expect(dir.existsSync(), isFalse);
    final s = openStore(dir.path);

    expect(s.repos.db.path, join(dir, 'grove.sqlite'));
    expect(File(join(dir, 'grove.sqlite')).existsSync(), isTrue);
  });

  test('what is saved is in that file: a second launch reads it', () {
    final dir = tempDir('grove-place');
    final first = AppStore.open(dataDir: dir.path, prefs: MemoryPrefs());
    first.quickAdd('Kept on disk');
    first.dispose();
    first.repos.db.close();

    final again = Database.open(join(dir, 'grove.sqlite'));
    addTearDown(again.close);
    expect(
      Repos(again).tasks.all().map((t) => t.title),
      contains('Kept on disk'),
    );
  });

  test('the backups and the settings are in the same folder', () {
    final dir = tempDir('grove-place');
    final s = AppStore.open(dataDir: dir.path);
    addTearDown(() {
      s.dispose();
      s.repos.db.close();
    });
    s.setMotion(!s.motionSetting);

    expect(Directory(join(dir, 'Backups')).existsSync(), isTrue);
    expect(s.backupFiles(), isNotEmpty);
    expect(
      s.backupFiles().map((f) => f.path),
      everyElement(startsWith(join(Directory(join(dir, 'Backups')), 'grove-'))),
    );
    expect(File(join(dir, 'prefs.json')).existsSync(), isTrue);
  });
}
