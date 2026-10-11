import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import '../data/helpers.dart';
import 'support.dart';

// The subtasks of a goal block (table `block_subtasks`, shared migration 7)
// sync like every other row: the outbox sees them, a second device gets them,
// and they go when their block goes.

EventItem goalBlock(Repos r, {String? id, int hour = 10}) {
  final e = EventItem(
    id: id,
    title: 'Read',
    start: at('2026-10-05T${hour.toString().padLeft(2, '0')}:00'),
    end: at('2026-10-05T${(hour + 1).toString().padLeft(2, '0')}:00'),
    kind: EventKind.block,
    goalId: 'G1',
  );
  r.events.save(e);
  return e;
}

List<String> titles(Device d, String eventId) => [
  for (final s in d.repos.blockSubtasks.forEvent(eventId)) s.title,
];

List<String> columns(Database db, String table) =>
    db.query('PRAGMA table_info($table)', const [], (r) => r.text(1));

void randomOp(Device d, Random rnd) {
  final r = d.repos;
  T? pick<T>(List<T> xs) => xs.isEmpty ? null : xs[rnd.nextInt(xs.length)];
  final events = r.events.all();
  final event = pick(events);
  final subs = [for (final e in events) ...r.blockSubtasks.forEvent(e.id)];
  final sub = pick(subs);
  switch (rnd.nextInt(8)) {
    case 0:
      goalBlock(r, hour: 6 + rnd.nextInt(12));
    case 1 || 2 || 3:
      if (event != null) {
        r.blockSubtasks.save(
          BlockSubtaskItem(
            eventId: event.id,
            title: 'S${rnd.nextInt(1000)}',
            sort: rnd.nextInt(5).toDouble(),
          ),
        );
      }
    case 4:
      if (sub != null) {
        r.blockSubtasks.save(
          sub.copyWith(doneAt: sub.isDone ? null : '2026-10-05T11:00:00'),
        );
      }
    case 5:
      if (sub != null) {
        r.blockSubtasks.save(sub.copyWith(title: 'R${rnd.nextInt(1000)}'));
      }
    case 6:
      if (sub != null) r.blockSubtasks.delete(sub.id);
    case 7:
      if (event != null && rnd.nextBool()) r.events.delete(event.id);
  }
}

void main() {
  late MemoryRemote remote;
  late Device a, b;

  setUp(() {
    remote = MemoryRemote();
    a = Device(remote);
    b = Device(remote);
  });

  /// A goal block that both devices have.
  Future<EventItem> shared() async {
    final e = goalBlock(a.repos);
    await a.sync();
    await b.sync();
    return e;
  }

  group('The schema', () {
    test('the table is synced and exported, right after the events', () {
      const tables = SyncMigrations.syncedTables;
      expect(tables.indexOf('block_subtasks'), tables.indexOf('events') + 1);
      expect(DataExport.tables, tables);
    });

    test('it has the sync columns, and they are not data columns', () {
      final cols = columns(a.db, 'block_subtasks');
      expect(cols, containsAll(['deleted', 'user_id', 'updated_at']));
      expect(cols.where((c) => c == 'updated_at').length, 1);
      expect(SyncMigrations.addedColumns['block_subtasks'], {
        'deleted',
        'user_id',
      });
      expect(SyncTable.read(a.db, 'block_subtasks').columns, [
        'id',
        'event_id',
        'title',
        'done_at',
        'sort',
        'created_at',
        'updated_at',
      ]);
    });

    test('the engine knows that a subtask goes with its block', () {
      final fk = SyncTable.read(a.db, 'block_subtasks').foreignKeys.values;
      expect(fk.single.column, 'event_id');
      expect(fk.single.parent, 'events');
      expect(fk.single.setsNull, isFalse);
    });

    test('a database of an older build of this app gets the table, the '
        'sync columns and the triggers', () {
      final dir = tempDir('grove-m7-sync-');
      final path = join(dir, 'o.sqlite');
      var db = Database.open(path);
      final e = goalBlock(Repos(db));
      // Take the database back to shared schema 6 and sync schema 2.
      db.executeScript('''
        DROP TABLE block_subtasks;
        PRAGMA user_version = 6;
        UPDATE sync_meta SET value = '2' WHERE key = 'schema';
        DELETE FROM sync_meta WHERE key = 'triggers';
      ''');
      db.execute('DELETE FROM outbox');
      db.close();

      db = Database.open(path);
      expect(db.userVersion, Migrations.all.length);
      expect(db.syncVersion, SyncMigrations.all.length);
      expect(
        columns(db, 'block_subtasks'),
        containsAll(['deleted', 'user_id']),
      );
      expect(Repos(db).events.get(e.id)?.title, 'Read');
      expect(Outbox(db).count, 0);
      final s = BlockSubtaskItem(eventId: e.id, title: 'Chapter 3');
      Repos(db).blockSubtasks.save(s);
      final entry = Outbox(db).entries().single;
      expect(
        (entry.table, entry.key, entry.deleted),
        ('block_subtasks', s.id, false),
      );
      db.close();

      // A third open changes nothing.
      db = Database.open(path);
      expect(columns(db, 'block_subtasks').where((c) => c == 'deleted'), [
        'deleted',
      ]);
      expect(Outbox(db).count, 1);
      db.close();
    });

    test('a Mac database with subtasks, opened for the first time: the old '
        'rows wait in the outbox with the lowest rank', () {
      final dir = tempDir('grove-m7-mac-');
      final path = oldDatabase(
        dir,
        7,
        'INSERT INTO events (id, title, start, end, kind, goal_id, '
        "created_at, updated_at) VALUES ('e1', 'Read', '2026-10-01T09:00', "
        "'2026-10-01T10:00', 'block', 'g1', '2026-10-01T09:00:00', "
        "'2026-10-01T09:00:00');"
        'INSERT INTO block_subtasks (id, event_id, title, sort, created_at, '
        "updated_at) VALUES ('s1', 'e1', 'Chapter 3', 1, "
        "'2026-10-01T09:00:00', '2026-10-01T09:00:00');",
      );
      final db = Database.open(path);
      expect(
        columns(db, 'block_subtasks'),
        containsAll(['deleted', 'user_id']),
      );
      final entry = Outbox(db).entry('block_subtasks', 's1');
      expect(entry?.stamp, 0);
      expect(entry?.deleted, isFalse);
      expect(Repos(db).blockSubtasks.get('s1')?.title, 'Chapter 3');
      db.close();
    });
  });

  group('What the outbox writes down', () {
    test('a saved subtask is one waiting change', () {
      final e = goalBlock(a.repos);
      a.clearOutbox();
      final s = BlockSubtaskItem(eventId: e.id, title: 'Chapter 3');
      a.repos.blockSubtasks.save(s);
      expect(a.waiting, ['block_subtasks saved']);
      expect(a.outbox.entry('block_subtasks', s.id)?.stamp, greaterThan(0));
      a.repos.blockSubtasks.save(s.copyWith(doneAt: '2026-10-05T11:00:00'));
      expect(a.waiting, ['block_subtasks saved']);
    });

    test('a deleted subtask is one waiting change', () {
      final e = goalBlock(a.repos);
      final s = BlockSubtaskItem(eventId: e.id, title: 'Chapter 3');
      a.repos.blockSubtasks.save(s);
      a.clearOutbox();
      a.repos.blockSubtasks.delete(s.id);
      expect(a.waiting, ['block_subtasks gone']);
    });

    test('a deleted block takes its subtasks into the outbox', () {
      final e = goalBlock(a.repos);
      final s = BlockSubtaskItem(eventId: e.id, title: 'Chapter 3');
      a.repos.blockSubtasks.save(s);
      a.clearOutbox();
      a.repos.events.delete(e.id);
      expect(
        a.waiting,
        unorderedEquals(['events gone', 'block_subtasks gone']),
      );
      expect(a.outbox.entry('block_subtasks', s.id)?.deleted, isTrue);
    });
  });

  group('Two devices', () {
    test('a subtask goes to the other device, on its block only', () async {
      final e = await shared();
      final other = goalBlock(a.repos, hour: 14);
      a.repos.blockSubtasks.save(
        BlockSubtaskItem(eventId: e.id, title: 'Chapter 3', sort: 1),
      );
      a.repos.blockSubtasks.save(
        BlockSubtaskItem(eventId: e.id, title: 'Chapter 4', sort: 2),
      );
      await settle([a, b]);

      expect(titles(b, e.id), ['Chapter 3', 'Chapter 4']);
      expect(titles(b, other.id), isEmpty);
      expect(b.outbox.count, 0);
      expectSame([a, b]);
    });

    test('a block and its subtasks made offline arrive together', () async {
      final e = goalBlock(a.repos);
      a.repos.blockSubtasks.save(
        BlockSubtaskItem(eventId: e.id, title: 'Chapter 3'),
      );
      final report = await a.sync();
      expect(report.skipped, isEmpty);
      final pulled = await b.sync();
      expect(pulled.skipped, isEmpty);
      expect(titles(b, e.id), ['Chapter 3']);
    });

    test('a tick and a new name travel', () async {
      final e = await shared();
      final s = BlockSubtaskItem(eventId: e.id, title: 'Chapter 3');
      a.repos.blockSubtasks.save(s);
      await settle([a, b]);

      b.later();
      b.repos.blockSubtasks.save(
        b.repos.blockSubtasks
            .get(s.id)!
            .copyWith(title: 'Chapter 3 and 4', doneAt: '2026-10-05T11:00:00'),
      );
      await settle([b, a]);

      final back = a.repos.blockSubtasks.get(s.id)!;
      expect(back.title, 'Chapter 3 and 4');
      expect(back.isDone, isTrue);
      expectSame([a, b]);
    });

    test('a deleted subtask goes on the other device too', () async {
      final e = await shared();
      final s = BlockSubtaskItem(eventId: e.id, title: 'One', sort: 1);
      a.repos.blockSubtasks.save(s);
      a.repos.blockSubtasks.save(
        BlockSubtaskItem(eventId: e.id, title: 'Two', sort: 2),
      );
      await settle([a, b]);

      a.later();
      a.repos.blockSubtasks.delete(s.id);
      await settle([a, b]);

      expect(titles(b, e.id), ['Two']);
      expect(remoteRows(remote, 'block_subtasks'), contains('${s.id} gone'));
    });

    test('a deleted block takes its subtasks, on the remote too', () async {
      final e = await shared();
      final s = BlockSubtaskItem(eventId: e.id, title: 'One');
      a.repos.blockSubtasks.save(s);
      await settle([a, b]);

      b.later();
      b.repos.events.delete(e.id);
      await settle([b, a]);

      expect(a.repos.events.get(e.id), isNull);
      expect(a.repos.blockSubtasks.get(s.id), isNull);
      expect(remoteRows(remote, 'block_subtasks'), ['${s.id} gone']);
      expectSame([a, b]);
    });

    test('one device deletes a block, the other ticks its subtask: both '
        'rows go, on the remote too', () async {
      final e = await shared();
      final s = BlockSubtaskItem(eventId: e.id, title: 'One');
      a.repos.blockSubtasks.save(s);
      await settle([a, b]);

      a.later();
      a.repos.events.delete(e.id);
      b.later();
      b.repos.blockSubtasks.save(s.copyWith(doneAt: '2026-10-05T11:00:00'));
      await settle([b, a]);

      expect(a.repos.blockSubtasks.get(s.id), isNull);
      expect(b.repos.blockSubtasks.get(s.id), isNull);
      expect(b.repos.events.get(e.id), isNull);
      expect(remoteRows(remote, 'block_subtasks'), ['${s.id} gone']);
      expectSame([a, b]);
    });

    test('one device deletes a block, the other adds a subtask to it: the '
        'new subtask goes too', () async {
      final e = await shared();

      a.later();
      a.repos.events.delete(e.id);
      b.later();
      final s = BlockSubtaskItem(eventId: e.id, title: 'Late');
      b.repos.blockSubtasks.save(s);
      await settle([b, a]);
      await settle([a, b]);

      expect(a.repos.blockSubtasks.get(s.id), isNull);
      expect(b.repos.blockSubtasks.get(s.id), isNull);
      expect(a.repos.events.get(e.id), isNull);
      expect(b.repos.events.get(e.id), isNull);
      expectSame([a, b]);
    });

    test('two devices tick the same subtask: the later change stays', () async {
      final e = await shared();
      final s = BlockSubtaskItem(eventId: e.id, title: 'One');
      a.repos.blockSubtasks.save(s);
      await settle([a, b]);

      a.later();
      a.repos.blockSubtasks.save(s.copyWith(doneAt: '2026-10-05T11:00:00'));
      b.later();
      b.repos.blockSubtasks.save(s.copyWith(title: 'One, changed'));
      await settle([a, b]);

      for (final d in [a, b]) {
        final back = d.repos.blockSubtasks.get(s.id)!;
        expect(back.title, 'One, changed');
        expect(back.isDone, isFalse);
      }
    });

    test(
      'an import on one device replaces the subtasks on the other',
      () async {
        final e = await shared();
        a.repos.blockSubtasks.save(
          BlockSubtaskItem(eventId: e.id, title: 'Old'),
        );
        await settle([a, b]);

        final file = Device(MemoryRemote());
        final kept = goalBlock(file.repos, id: 'KEPT');
        file.repos.blockSubtasks.save(
          BlockSubtaskItem(eventId: kept.id, title: 'From the file'),
        );
        a.later();
        DataExport.importData(DataExport.export(file.db), a.repos);
        await settle([a, b]);

        expect(b.repos.events.get(e.id), isNull);
        expect(titles(b, 'KEPT'), ['From the file']);
        expectSame([a, b]);
      },
    );
  });

  group('Many devices', () {
    for (var seed = 1; seed <= 12; seed++) {
      test('random offline work on blocks and subtasks ends the same '
          '(seed $seed)', () async {
        final rnd = Random(seed);
        final devices = [a, b, Device(remote, pageSize: 3)];
        for (var step = 0; step < 80; step++) {
          final d = devices[rnd.nextInt(3)];
          if (rnd.nextInt(4) > 0) d.later();
          randomOp(d, rnd);
          if (rnd.nextInt(6) == 0) await devices[rnd.nextInt(3)].sync();
        }

        await settle(devices);
        expectSame(devices);

        final fresh = Device(remote);
        final report = await fresh.sync();
        expect(report.skipped, isEmpty);
        expect(fresh.outbox.count, 0);
        expectSame([a, fresh]);
      });
    }
  });
}
