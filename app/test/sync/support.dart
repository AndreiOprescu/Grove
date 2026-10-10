import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/data/data.dart';
import 'package:grove/sync/sync.dart';

export 'package:grove/core/model/day_key.dart';
export 'package:grove/core/model/event.dart';
export 'package:grove/core/model/goal.dart';
export 'package:grove/core/model/link.dart';
export 'package:grove/core/model/note.dart';
export 'package:grove/core/model/task.dart';
export 'package:grove/data/data.dart';
export 'package:grove/sync/sync.dart';

/// One phone or computer: its own database and its own sync engine.
class Device {
  Device(SyncRemote remote, {int pageSize = 500})
    : repos = Repos(Database.inMemory()) {
    engine = SyncEngine(repos: repos, remote: remote, pageSize: pageSize);
    addTearDown(repos.db.close);
  }

  final Repos repos;
  late final SyncEngine engine;

  Database get db => repos.db;
  Outbox get outbox => engine.outbox;

  Future<SyncReport> sync() => engine.sync();

  static int _time = DateTime.now().millisecondsSinceEpoch;

  /// A minute passes. The next change on this device is newer than every
  /// change made before, on any device.
  void later() {
    _time += 60000;
    outbox.seeClock(_time);
  }

  /// The waiting changes, as "table deleted" lines in the order they were made.
  List<String> get waiting => [
    for (final e in outbox.entries())
      '${e.table} ${e.deleted ? 'gone' : 'saved'}',
  ];

  void clearOutbox() => db.execute('DELETE FROM outbox');
}

/// Every synced row of a database as text, in a fixed order. Two databases
/// with the same data give the same result.
Map<String, List<String>> dump(Database db) => {
  for (final table in SyncMigrations.syncedTables)
    table: db.query('SELECT * FROM $table', const [], (r) {
      final skip = SyncMigrations.addedColumns[table] ?? const <String>{};
      return [
        for (var i = 0; i < r.length; i++)
          if (!skip.contains(r.name(i)))
            '${r.name(i)}=${switch (r.value(i)) {
              final Uint8List b => base64Encode(b),
              final Object? v => '$v',
            }}',
      ].join(' | ');
    })..sort(),
};

void expectSame(List<Device> devices) {
  final first = dump(devices.first.db);
  for (final d in devices.skip(1)) {
    expect(dump(d.db), first);
  }
}

/// Syncs every device again and again, until a full round moves nothing.
Future<void> settle(List<Device> devices, {int rounds = 10}) async {
  for (var i = 0; i < rounds; i++) {
    var quiet = true;
    for (final d in devices) {
      final report = await d.sync();
      if (report.pushed > 0 || report.pulled > 0) quiet = false;
    }
    if (quiet) return;
  }
  fail('The devices did not settle in $rounds rounds.');
}

/// The rows the remote holds, as "table key stamp state" lines.
List<String> remoteRows(MemoryRemote remote, String table) => [
  for (final c in remote.rows)
    if (c.table == table) '${c.key} ${c.deleted ? 'gone' : 'saved'}',
];

WallTime at(String text) => WallTime.parse(text)!;
