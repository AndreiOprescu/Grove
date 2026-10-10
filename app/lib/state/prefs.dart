import 'dart:convert';
import 'dart:io';

/// Small settings of this device (the Mac app keeps them in `UserDefaults`).
/// They are not in the database, so they do not sync.
abstract class Prefs {
  Object? get(String key);
  void set(String key, Object? value);

  bool? getBool(String key) {
    final v = get(key);
    return v is bool ? v : null;
  }

  int? getInt(String key) {
    final v = get(key);
    return v is int ? v : (v is double ? v.toInt() : null);
  }

  double? getDouble(String key) {
    final v = get(key);
    return v is num ? v.toDouble() : null;
  }

  String? getString(String key) {
    final v = get(key);
    return v is String ? v : null;
  }

  void remove(String key) => set(key, null);
}

/// Settings that live in memory only. For tests.
class MemoryPrefs extends Prefs {
  MemoryPrefs([Map<String, Object?>? values]) : _values = {...?values};

  final Map<String, Object?> _values;

  @override
  Object? get(String key) => _values[key];

  @override
  void set(String key, Object? value) {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }
}

/// Settings in one JSON file. A file that cannot be read counts as empty, and
/// a write that fails is dropped: a lost setting is better than a crash.
class FilePrefs extends Prefs {
  FilePrefs(this.path) {
    try {
      final decoded = jsonDecode(File(path).readAsStringSync());
      if (decoded is Map<String, dynamic>) _values.addAll(decoded);
    } on Object {
      // No file yet, or a damaged one. Start empty.
    }
  }

  final String path;
  final Map<String, Object?> _values = {};

  @override
  Object? get(String key) => _values[key];

  @override
  void set(String key, Object? value) {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      final temp = File('$path.tmp')..writeAsStringSync(jsonEncode(_values));
      temp.renameSync(path);
    } on Object {
      // Keep the value in memory.
    }
  }
}
