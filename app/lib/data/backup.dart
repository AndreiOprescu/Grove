import 'dart:io';

import '../core/model/day_key.dart';
import 'database.dart';

/// Copies of the database file: one a day, and one before an import.
abstract final class Backup {
  static String _join(String dir, String name) =>
      '$dir${Platform.pathSeparator}$name';

  static String _baseName(String path) => path.split(RegExp(r'[/\\]')).last;

  static bool _isDaily(String name) =>
      name.startsWith('grove-') && name.endsWith('.sqlite');

  static void _vacuumInto(Database db, String target) =>
      db.execute("VACUUM INTO '${target.replaceAll("'", "''")}'");

  static List<String> _dailyNames(String directory) {
    final dir = Directory(directory);
    if (!dir.existsSync()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .map((f) => _baseName(f.path))
        .where(_isDaily)
        .toList()
      ..sort();
  }

  /// Writes `grove-YYYY-MM-DD.sqlite` into [directory] if today's copy does not
  /// exist yet, then keeps only the newest [keep] copies. Returns the new file,
  /// or null if one already existed.
  static String? runDaily(
    Database db, {
    required String directory,
    required DayKey today,
    int keep = 14,
  }) {
    Directory(directory).createSync(recursive: true);
    final target = _join(directory, 'grove-${today.string}.sqlite');
    String? created;
    if (!File(target).existsSync()) {
      _vacuumInto(db, target);
      created = target;
    }
    final files = _dailyNames(directory);
    if (files.length > keep) {
      for (final old in files.take(files.length - keep)) {
        try {
          File(_join(directory, old)).deleteSync();
        } on FileSystemException {
          // A copy we cannot remove now is removed next time.
        }
      }
    }
    return created;
  }

  /// The name of the copy made before the data of an account replaces the
  /// data of this device: `before-sync-YYYYMMDD-HHMMSS.sqlite`. Each copy
  /// has its own name, so a new one never takes the place of an old one.
  /// Grove never deletes these files.
  static String beforeSyncName(DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'before-sync-${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}${two(now.second)}.sqlite';
  }

  /// A copy of the data before an import replaces it. One file,
  /// `before-import.sqlite`; a new copy replaces the old one. It is not in
  /// [list] and the daily clean-up leaves it alone.
  ///
  /// The first login can replace the data too. It gives the copy a [name]
  /// of its own (see [beforeSyncName]).
  static String safetyCopy(
    Database db, {
    required String directory,
    String name = 'before-import.sqlite',
  }) {
    Directory(directory).createSync(recursive: true);
    final target = _join(directory, name);
    final file = File(target);
    if (file.existsSync()) file.deleteSync();
    _vacuumInto(db, target);
    return target;
  }

  /// The daily copies, newest first.
  static List<String> list(String directory) => [
    for (final name in _dailyNames(directory).reversed) _join(directory, name),
  ];
}
