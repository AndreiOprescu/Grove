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
