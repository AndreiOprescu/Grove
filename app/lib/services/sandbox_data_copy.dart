import 'dart:io';

/// Grove for Mac left the sandbox for the agent (ADR 0004). Its data folder
/// moved from the sandbox container to `~/Library/Application Support`. On
/// the first start outside the sandbox the old folder is copied, never moved
/// or deleted: it stays as a backup.
abstract final class SandboxDataCopy {
  /// The database file in a data folder.
  static const dbName = 'grove.sqlite';

  /// The data folder of the sandboxed Grove of the Mac, in [home].
  static String oldFolder(String home) =>
      '$home/Library/Containers/local.grove.app/Data/Library/'
      'Application Support/local.grove.app';

  /// Copies everything in [from] into [to], when [to] has no database yet and
  /// [from] has one. True when it copied. A file that is already in [to] is
  /// kept. Never throws: a copy that fails leaves Grove with an empty (new)
  /// folder and the old one as it was.
  static bool copyOnce({required String from, required String to}) {
    final sep = Platform.pathSeparator;
    try {
      if (File('$to$sep$dbName').existsSync()) return false;
      if (!File('$from$sep$dbName').existsSync()) return false;
      Directory(to).createSync(recursive: true);
      _copyDir(Directory(from), Directory(to));
      return true;
    } on FileSystemException {
      return false;
    }
  }

  static void _copyDir(Directory from, Directory to) {
    final sep = Platform.pathSeparator;
    for (final e in from.listSync(followLinks: false)) {
      final name = e.path.split(sep).last;
      final target = '${to.path}$sep$name';
      if (e is Directory) {
        final dir = Directory(target)..createSync(recursive: true);
        _copyDir(e, dir);
      } else if (e is File) {
        if (!File(target).existsSync()) e.copySync(target);
      }
      // A link is left out: it can point anywhere.
    }
  }
}
