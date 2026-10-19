import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grove/services/sandbox_data_copy.dart';

import '../data/helpers.dart' show tempDir, join;

void main() {
  late Directory old;
  late String fresh;

  setUp(() {
    old = tempDir('grove-old-');
    fresh = join(tempDir('grove-new-'), 'local.grove.app');
    File(join(old, 'grove.sqlite')).writeAsStringSync('db');
    File(join(old, 'grove.sqlite-wal')).writeAsStringSync('wal');
    File(join(old, 'prefs.json')).writeAsStringSync('{}');
    Directory(join(old, 'Backups')).createSync();
    File(join(Directory(join(old, 'Backups')), 'grove-2026-10-18.sqlite'))
        .writeAsStringSync('backup');
  });

  String read(String path) => File(path).readAsStringSync();
  String sub(String a, String b) => '$a${Platform.pathSeparator}$b';

  test('the old folder is in the sandbox container of the app', () {
    expect(
      SandboxDataCopy.oldFolder('/Users/x'),
      '/Users/x/Library/Containers/local.grove.app/Data/Library/'
      'Application Support/local.grove.app',
    );
  });

  test('copies every file and folder once, and never deletes the old', () {
    expect(SandboxDataCopy.copyOnce(from: old.path, to: fresh), isTrue);
    expect(read(sub(fresh, 'grove.sqlite')), 'db');
    expect(read(sub(fresh, 'grove.sqlite-wal')), 'wal');
    expect(read(sub(fresh, 'prefs.json')), '{}');
    expect(
      read(sub(sub(fresh, 'Backups'), 'grove-2026-10-18.sqlite')),
      'backup',
    );
    // The old folder is all still there.
    expect(read(join(old, 'grove.sqlite')), 'db');
    expect(File(join(old, 'prefs.json')).existsSync(), isTrue);
    expect(Directory(join(old, 'Backups')).existsSync(), isTrue);

    // A second start: the new folder has a database, nothing is copied.
    File(sub(fresh, 'grove.sqlite')).writeAsStringSync('changed');
    expect(SandboxDataCopy.copyOnce(from: old.path, to: fresh), isFalse);
    expect(read(sub(fresh, 'grove.sqlite')), 'changed');
  });

  test('does nothing when the new folder has a database already', () {
    Directory(fresh).createSync(recursive: true);
    File(sub(fresh, 'grove.sqlite')).writeAsStringSync('new');
    expect(SandboxDataCopy.copyOnce(from: old.path, to: fresh), isFalse);
    expect(read(sub(fresh, 'grove.sqlite')), 'new');
    expect(File(sub(fresh, 'prefs.json')).existsSync(), isFalse);
  });

  test('does nothing when the old folder is missing', () {
    final gone = join(old, 'nothing-here');
    expect(SandboxDataCopy.copyOnce(from: gone, to: fresh), isFalse);
    expect(Directory(fresh).existsSync(), isFalse);
  });
}
