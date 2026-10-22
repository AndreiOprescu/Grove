import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import '../data/helpers.dart';
import 'support.dart';

// The subtasks of a goal (table `goal_subtasks`, shared migration 8) sync
// like every other row: the outbox sees them, a second device gets them, and
// they go when their goal goes.
//
// A subtask can be planned in a block of its goal (column `event_id`, shared
// migration 9). The plan syncs too. When the block goes, the subtask stays,
// in no block.

GoalItem goal(Repos r, {String? id, String title = 'Read'}) {
  final g = GoalItem(id: id, title: title);
  r.goals.upsert(g);
  return g;
}

/// A block of the goal, on Monday 2026-10-05.
EventItem block(Repos r, GoalItem g, {int hour = 10}) {
  final e = EventItem(
    title: g.title,
    start: at('2026-10-05T${hour.toString().padLeft(2, '0')}:00'),
    end: at('2026-10-05T${(hour + 1).toString().padLeft(2, '0')}:00'),
    kind: EventKind.block,
    goalId: g.id,
  );
  r.events.save(e);
  return e;
}

List<String> titles(Device d, String goalId) => [
  for (final s in d.repos.goalSubtasks.forGoal(goalId)) s.title,
];

List<String> columns(Database db, String table) =>
    db.query('PRAGMA table_info($table)', const [], (r) => r.text(1));

void randomOp(Device d, Random rnd) {
  final r = d.repos;
  T? pick<T>(List<T> xs) => xs.isEmpty ? null : xs[rnd.nextInt(xs.length)];
  final goals = r.goals.all();
  final g = pick(goals);
  final subs = [for (final g in goals) ...r.goalSubtasks.forGoal(g.id)];
  final sub = pick(subs);
  final blocks = [
    for (final e in r.events.all())
      if (e.goalId != null) e,
  ];
  switch (rnd.nextInt(11)) {
    case 0:
      goal(r, title: 'G${rnd.nextInt(1000)}');
    case 1 || 2 || 3:
      if (g != null) {
        r.goalSubtasks.save(
          GoalSubtaskItem(
            goalId: g.id,
            title: 'S${rnd.nextInt(1000)}',
            sort: rnd.nextInt(5).toDouble(),
          ),
        );
      }
    case 4:
      if (sub != null) {
        r.goalSubtasks.save(
          sub.copyWith(doneAt: sub.isDone ? null : '2026-10-05T11:00:00'),
        );
      }
    case 5:
      if (sub != null) {
        r.goalSubtasks.save(sub.copyWith(title: 'R${rnd.nextInt(1000)}'));
      }
    case 6:
      if (sub != null) r.goalSubtasks.delete(sub.id);
    case 7:
      if (g != null && rnd.nextBool()) r.goals.delete(g.id);
    case 8:
      if (g != null) block(r, g, hour: 6 + rnd.nextInt(12));
    case 9:
      // Plans the subtask in a block of its goal, or takes it out.
      if (sub != null) {
        final mine = [
          for (final e in blocks)
            if (e.goalId == sub.goalId) e,
        ];
        r.goalSubtasks.save(
          sub.copyWith(eventId: sub.isPlanned ? null : pick(mine)?.id),
        );
      }
    case 10:
      final e = pick(blocks);
      if (e != null) r.events.delete(e.id);
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

  /// A goal that both devices have.
  Future<GoalItem> shared() async {
    final g = goal(a.repos);
    await a.sync();
    await b.sync();
    return g;
  }

  group('The schema', () {
    test('the table is synced and exported, after the goals and after the '
        'blocks', () {
      const tables = SyncMigrations.syncedTables;
      final at = tables.indexOf('goal_subtasks');
      expect(at, greaterThan(tables.indexOf('goals')));
      expect(at, greaterThan(tables.indexOf('events')));
      expect(DataExport.tables, tables);
    });

    test('it has the sync columns, and they are not data columns', () {
      final cols = columns(a.db, 'goal_subtasks');
      expect(cols, containsAll(['deleted', 'user_id', 'updated_at']));
      expect(cols.where((c) => c == 'updated_at').length, 1);
      expect(SyncMigrations.addedColumns['goal_subtasks'], {
        'deleted',
        'user_id',
      });
      expect(SyncTable.read(a.db, 'goal_subtasks').columns, [
        'id',
        'goal_id',
        'title',
        'done_at',
        'sort',
        'created_at',
        'updated_at',
        'event_id',
      ]);
    });

    test('the engine knows that a subtask goes with its goal, and that it '
        'stays when its block goes', () {
      final fks = SyncTable.read(a.db, 'goal_subtasks').foreignKeys.values;
      expect(fks.length, 2);
      final toGoal = fks.singleWhere((fk) => fk.column == 'goal_id');
      expect(toGoal.parent, 'goals');
      expect(toGoal.setsNull, isFalse);
      final toBlock = fks.singleWhere((fk) => fk.column == 'event_id');
      expect(toBlock.parent, 'events');
      expect(toBlock.setsNull, isTrue);
    });

    test('a database with the sync on (shared schema 8) gets the column, '
        'and the plan of a subtask is a waiting change', () {
      final dir = tempDir('grove-m9-sync-');
      final path = join(dir, 'o.sqlite');
      var db = Database.open(path);
      final g = goal(Repos(db));
      final s = GoalSubtaskItem(goalId: g.id, title: 'Chapter 3');
      Repos(db).goalSubtasks.save(s);
      final e = block(Repos(db), g);
      // Take the database back to shared schema 8: no column, and the
      // update trigger and the saved trigger list of that schema. The sync
      // columns stay. The persona (shared schema 10, sync schema 5),
      // deadlines (shared schema 11) and the agent (shared schema 12, sync
      // schema 6) came later, so they go.
      const watch = ' OR OLD.event_id IS NOT NEW.event_id';
      final trigger = db.queryOne(
        "SELECT sql FROM sqlite_master WHERE name = 'sync_goal_subtasks_update'",
        const [],
        (r) => r.text(0),
      )!;
      expect(trigger, contains(watch));
      const deadlineWatch = ' OR OLD.is_deadline IS NOT NEW.is_deadline';
      final eventTrigger = db.queryOne(
        "SELECT sql FROM sqlite_master WHERE name = 'sync_events_update'",
        const [],
        (r) => r.text(0),
      )!;
      expect(eventTrigger, contains(deadlineWatch));
      db.executeScript('''
        DROP TRIGGER sync_events_update;
        ALTER TABLE events DROP COLUMN is_deadline;
        ${eventTrigger.replaceAll(deadlineWatch, '')};
        DROP TRIGGER sync_goal_subtasks_update;
        DROP INDEX goal_subtasks_event;
        ALTER TABLE goal_subtasks DROP COLUMN event_id;
        ${trigger.replaceAll(watch, '')};
        DROP TABLE earnings;
        DROP TABLE rewards;
        DROP TABLE skills;
        DROP TABLE agent_events;
        DROP TABLE agent_jobs;
        PRAGMA user_version = 8;
        UPDATE sync_meta SET value = '4' WHERE key = 'schema';
        UPDATE sync_meta SET value = replace(value, ',event_id', '')
          WHERE key = 'triggers';
        UPDATE sync_meta SET value = replace(value, ',is_deadline', '')
          WHERE key = 'triggers';
      ''');
      db.execute('DELETE FROM outbox');
      db.close();

      db = Database.open(path);
      expect(db.userVersion, Migrations.all.length);
      expect(columns(db, 'goal_subtasks'), contains('event_id'));
      // The data columns are the same as on a new database, in the same
      // order: the sync columns are not in the list.
      expect(
        SyncTable.read(db, 'goal_subtasks').columns,
        SyncTable.read(a.db, 'goal_subtasks').columns,
      );
      expect(Repos(db).goalSubtasks.get(s.id)?.eventId, isNull);
      expect(Outbox(db).count, 0);
      // A change of the new column only. The triggers were made again, so
      // they see it.
      db.execute('UPDATE goal_subtasks SET event_id = ? WHERE id = ?', [
        e.id,
        s.id,
      ]);
      final entry = Outbox(db).entries().single;
      expect(
        (entry.table, entry.key, entry.deleted),
        ('goal_subtasks', s.id, false),
      );
      db.close();
    });

    test('a database of an older build of this app gets the table, the '
        'sync columns and the triggers', () {
      final dir = tempDir('grove-m8-sync-');
      final path = join(dir, 'o.sqlite');
      var db = Database.open(path);
      final g = goal(Repos(db));
      // Take the database back to shared schema 7 and sync schema 3. The
      // persona and the agent came later, so they go too.
      db.executeScript('''
        DROP TRIGGER sync_events_update;
        ALTER TABLE events DROP COLUMN is_deadline;
        DROP TABLE goal_subtasks;
        DROP TABLE earnings;
        DROP TABLE rewards;
        DROP TABLE skills;
        DROP TABLE agent_events;
        DROP TABLE agent_jobs;
        PRAGMA user_version = 7;
        UPDATE sync_meta SET value = '3' WHERE key = 'schema';
        DELETE FROM sync_meta WHERE key = 'triggers';
      ''');
      db.execute('DELETE FROM outbox');
      db.close();

      db = Database.open(path);
      expect(db.userVersion, Migrations.all.length);
      expect(db.syncVersion, SyncMigrations.all.length);
      expect(db.syncVersion, 7);
      expect(columns(db, 'goal_subtasks'), containsAll(['deleted', 'user_id']));
      expect(Repos(db).goals.get(g.id)?.title, 'Read');
      expect(Outbox(db).count, 0);
      final s = GoalSubtaskItem(goalId: g.id, title: 'Chapter 3');
      Repos(db).goalSubtasks.save(s);
      final entry = Outbox(db).entries().single;
      expect(
        (entry.table, entry.key, entry.deleted),
        ('goal_subtasks', s.id, false),
      );
      db.close();

      // A third open changes nothing.
      db = Database.open(path);
      expect(columns(db, 'goal_subtasks').where((c) => c == 'deleted'), [
        'deleted',
      ]);
      expect(Outbox(db).count, 1);
      db.close();
    });

    test('a Mac database (shared schema 7), opened for the first time, gets '
        'the table with the sync columns', () {
      final dir = tempDir('grove-m8-mac-');
      final path = oldDatabase(
        dir,
        7,
        'INSERT INTO goals (id, title, created_at, updated_at) VALUES '
        "('g1', 'Read', '2026-10-01T09:00:00', '2026-10-01T09:00:00');",
      );
      final db = Database.open(path);
      expect(columns(db, 'goal_subtasks'), containsAll(['deleted', 'user_id']));
      expect(Outbox(db).entry('goals', 'g1')?.stamp, 0);
      final s = GoalSubtaskItem(goalId: 'g1', title: 'Chapter 3');
      Repos(db).goalSubtasks.save(s);
      expect(Outbox(db).entry('goal_subtasks', s.id)?.deleted, isFalse);
      db.close();
    });
  });

  group('What the outbox writes down', () {
    test('a saved subtask is one waiting change', () {
      final g = goal(a.repos);
      a.clearOutbox();
      final s = GoalSubtaskItem(goalId: g.id, title: 'Chapter 3');
      a.repos.goalSubtasks.save(s);
      expect(a.waiting, ['goal_subtasks saved']);
      expect(a.outbox.entry('goal_subtasks', s.id)?.stamp, greaterThan(0));
      a.repos.goalSubtasks.save(s.copyWith(doneAt: '2026-10-05T11:00:00'));
      expect(a.waiting, ['goal_subtasks saved']);
    });

    test('a deleted subtask is one waiting change', () {
      final g = goal(a.repos);
      final s = GoalSubtaskItem(goalId: g.id, title: 'Chapter 3');
      a.repos.goalSubtasks.save(s);
      a.clearOutbox();
      a.repos.goalSubtasks.delete(s.id);
      expect(a.waiting, ['goal_subtasks gone']);
    });

    test('a deleted goal takes its subtasks into the outbox', () {
      final g = goal(a.repos);
      final s = GoalSubtaskItem(goalId: g.id, title: 'Chapter 3');
      a.repos.goalSubtasks.save(s);
      a.clearOutbox();
      a.repos.goals.delete(g.id);
      expect(a.waiting, unorderedEquals(['goals gone', 'goal_subtasks gone']));
      expect(a.outbox.entry('goal_subtasks', s.id)?.deleted, isTrue);
    });

    test('a deleted block writes down its planned subtask as a saved row, '
        'in no block', () {
      final g = goal(a.repos);
      final e = block(a.repos, g);
      final s = GoalSubtaskItem(goalId: g.id, title: 'One', eventId: e.id);
      a.repos.goalSubtasks.save(s);
      a.clearOutbox();
      a.repos.events.delete(e.id);
      expect(
        a.waiting,
        unorderedEquals(['events gone', 'goal_subtasks saved']),
      );
      expect(a.repos.goalSubtasks.get(s.id)?.eventId, isNull);
    });
  });

  group('A subtask planned in a block, on two devices', () {
    /// A goal, a block of it and a subtask in the block, on both devices.
    Future<(GoalItem, EventItem, GoalSubtaskItem)> plannedOnBoth() async {
      final g = await shared();
      final e = block(a.repos, g);
      final s = GoalSubtaskItem(goalId: g.id, title: 'One', eventId: e.id);
      a.repos.goalSubtasks.save(s);
      await settle([a, b]);
      return (g, e, s);
    }

    test('the plan goes to the other device', () async {
      final (_, e, s) = await plannedOnBoth();
      expect(b.repos.goalSubtasks.get(s.id)?.eventId, e.id);
      expect(b.repos.goalSubtasks.forEvents([e.id])[e.id]?.single.id, s.id);
      expect(b.outbox.count, 0);
      expectSame([a, b]);
    });

    test('a goal, a block and a planned subtask made offline arrive '
        'together', () async {
      final g = goal(a.repos);
      final e = block(a.repos, g);
      final s = GoalSubtaskItem(goalId: g.id, title: 'One', eventId: e.id);
      a.repos.goalSubtasks.save(s);
      final report = await a.sync();
      expect(report.skipped, isEmpty);
      final pulled = await b.sync();
      expect(pulled.skipped, isEmpty);
      expect(b.repos.goalSubtasks.get(s.id)?.eventId, e.id);
      expect(b.outbox.count, 0);
    });

    test('a push that stops half way does not lose the plan: the block '
        'goes to the remote before the subtask', () async {
      final g = goal(a.repos);
      final e = block(a.repos, g);
      final s = GoalSubtaskItem(goalId: g.id, title: 'One', eventId: e.id);
      a.repos.goalSubtasks.save(s);
      // The remote keeps two rows, then the push stops.
      remote.failPushAfter = 2;
      await expectLater(a.sync(), throwsA(isA<RemoteUnavailable>()));
      expect(remoteRows(remote, 'goals'), ['${g.id} saved']);
      expect(remoteRows(remote, 'events'), ['${e.id} saved']);
      expect(remoteRows(remote, 'goal_subtasks'), isEmpty);

      // The other device pulls now. It has nothing to repair.
      await b.sync();
      expect(b.repos.events.get(e.id), isNotNull);
      expect(b.outbox.count, 0);

      await settle([a, b]);
      expect(a.repos.goalSubtasks.get(s.id)?.eventId, e.id);
      expect(b.repos.goalSubtasks.get(s.id)?.eventId, e.id);
      expectSame([a, b]);
    });

    test('a subtask taken out of its block is out on the other device '
        'too', () async {
      final (_, e, s) = await plannedOnBoth();
      b.later();
      b.repos.goalSubtasks.save(
        b.repos.goalSubtasks.get(s.id)!.copyWith(eventId: null),
      );
      await settle([b, a]);
      expect(a.repos.goalSubtasks.get(s.id)?.eventId, isNull);
      expect(a.repos.events.get(e.id), isNotNull);
      expectSame([a, b]);
    });

    test('a subtask moved to another block is moved on the other device '
        'too', () async {
      final (g, _, s) = await plannedOnBoth();
      a.later();
      final other = block(a.repos, g, hour: 14);
      a.repos.goalSubtasks.save(s.copyWith(eventId: other.id));
      await settle([a, b]);
      expect(b.repos.goalSubtasks.get(s.id)?.eventId, other.id);
      expectSame([a, b]);
    });

    test('a deleted block gives the subtask back to the goal, on the '
        'other device and on the remote', () async {
      final (g, e, s) = await plannedOnBoth();
      a.later();
      a.repos.events.delete(e.id);
      await settle([a, b]);

      expect(b.repos.events.get(e.id), isNull);
      expect(titles(b, g.id), ['One']);
      expect(b.repos.goalSubtasks.get(s.id)?.eventId, isNull);
      expect(remoteRows(remote, 'goal_subtasks'), ['${s.id} saved']);
      final row = remote.rows.singleWhere((c) => c.table == 'goal_subtasks');
      expect(row.data['event_id'], isNull);
      expect(remoteRows(remote, 'events'), ['${e.id} gone']);
      expectSame([a, b]);
    });

    test('one device deletes a block, the other plans a subtask in it: the '
        'subtask stays, in no block', () async {
      final g = await shared();
      final e = block(a.repos, g);
      final s = GoalSubtaskItem(goalId: g.id, title: 'One');
      a.repos.goalSubtasks.save(s);
      await settle([a, b]);

      a.later();
      a.repos.events.delete(e.id);
      b.later();
      b.repos.goalSubtasks.save(s.copyWith(eventId: e.id));
      await settle([b, a]);
      await settle([a, b]);

      for (final d in [a, b]) {
        expect(d.repos.events.get(e.id), isNull);
        expect(d.repos.goalSubtasks.get(s.id)?.title, 'One');
        expect(d.repos.goalSubtasks.get(s.id)?.eventId, isNull);
      }
      expectSame([a, b]);
    });

    test('one device ticks a planned subtask, the other deletes its block: '
        'the later change stays, and no device points at a missing '
        'block', () async {
      final (_, e, s) = await plannedOnBoth();
      a.later();
      a.repos.goalSubtasks.save(s.copyWith(doneAt: '2026-10-05T11:00:00'));
      b.later();
      b.repos.events.delete(e.id);
      await settle([a, b]);
      await settle([b, a]);

      for (final d in [a, b]) {
        expect(d.repos.events.get(e.id), isNull);
        expect(d.repos.goalSubtasks.get(s.id)?.eventId, isNull);
      }
      expectSame([a, b]);
    });

    test('a deleted goal takes its planned subtask; the block stays as the '
        'schema says', () async {
      final (g, e, s) = await plannedOnBoth();
      b.later();
      b.repos.goals.delete(g.id);
      await settle([b, a]);

      expect(a.repos.goalSubtasks.get(s.id), isNull);
      expect(remoteRows(remote, 'goal_subtasks'), ['${s.id} gone']);
      expect(
        a.repos.events.get(e.id)?.goalId,
        b.repos.events.get(e.id)?.goalId,
      );
      expectSame([a, b]);
    });
  });

  group('Two devices', () {
    test('a subtask goes to the other device, on its goal only', () async {
      final g = await shared();
      final other = goal(a.repos, title: 'Gym');
      a.repos.goalSubtasks.save(
        GoalSubtaskItem(goalId: g.id, title: 'Chapter 3', sort: 1),
      );
      a.repos.goalSubtasks.save(
        GoalSubtaskItem(goalId: g.id, title: 'Chapter 4', sort: 2),
      );
      await settle([a, b]);

      expect(titles(b, g.id), ['Chapter 3', 'Chapter 4']);
      expect(titles(b, other.id), isEmpty);
      expect(b.outbox.count, 0);
      expectSame([a, b]);
    });

    test('a goal and its subtasks made offline arrive together', () async {
      final g = goal(a.repos);
      a.repos.goalSubtasks.save(
        GoalSubtaskItem(goalId: g.id, title: 'Chapter 3'),
      );
      final report = await a.sync();
      expect(report.skipped, isEmpty);
      final pulled = await b.sync();
      expect(pulled.skipped, isEmpty);
      expect(titles(b, g.id), ['Chapter 3']);
    });

    test('a tick and a new name travel', () async {
      final g = await shared();
      final s = GoalSubtaskItem(goalId: g.id, title: 'Chapter 3');
      a.repos.goalSubtasks.save(s);
      await settle([a, b]);

      b.later();
      b.repos.goalSubtasks.save(
        b.repos.goalSubtasks
            .get(s.id)!
            .copyWith(title: 'Chapter 3 and 4', doneAt: '2026-10-05T11:00:00'),
      );
      await settle([b, a]);

      final back = a.repos.goalSubtasks.get(s.id)!;
      expect(back.title, 'Chapter 3 and 4');
      expect(back.isDone, isTrue);
      expectSame([a, b]);
    });

    test('a deleted subtask goes on the other device too', () async {
      final g = await shared();
      final s = GoalSubtaskItem(goalId: g.id, title: 'One', sort: 1);
      a.repos.goalSubtasks.save(s);
      a.repos.goalSubtasks.save(
        GoalSubtaskItem(goalId: g.id, title: 'Two', sort: 2),
      );
      await settle([a, b]);

      a.later();
      a.repos.goalSubtasks.delete(s.id);
      await settle([a, b]);

      expect(titles(b, g.id), ['Two']);
      expect(remoteRows(remote, 'goal_subtasks'), contains('${s.id} gone'));
    });

    test('a deleted goal takes its subtasks, on the remote too', () async {
      final g = await shared();
      final s = GoalSubtaskItem(goalId: g.id, title: 'One');
      a.repos.goalSubtasks.save(s);
      await settle([a, b]);

      b.later();
      b.repos.goals.delete(g.id);
      await settle([b, a]);

      expect(a.repos.goals.get(g.id), isNull);
      expect(a.repos.goalSubtasks.get(s.id), isNull);
      expect(remoteRows(remote, 'goal_subtasks'), ['${s.id} gone']);
      expectSame([a, b]);
    });

    test('one device deletes a goal, the other ticks its subtask: both '
        'rows go, on the remote too', () async {
      final g = await shared();
      final s = GoalSubtaskItem(goalId: g.id, title: 'One');
      a.repos.goalSubtasks.save(s);
      await settle([a, b]);

      a.later();
      a.repos.goals.delete(g.id);
      b.later();
      b.repos.goalSubtasks.save(s.copyWith(doneAt: '2026-10-05T11:00:00'));
      await settle([b, a]);

      expect(a.repos.goalSubtasks.get(s.id), isNull);
      expect(b.repos.goalSubtasks.get(s.id), isNull);
      expect(b.repos.goals.get(g.id), isNull);
      expect(remoteRows(remote, 'goal_subtasks'), ['${s.id} gone']);
      expectSame([a, b]);
    });

    test('one device deletes a goal, the other adds a subtask to it: the '
        'new subtask goes too', () async {
      final g = await shared();

      a.later();
      a.repos.goals.delete(g.id);
      b.later();
      final s = GoalSubtaskItem(goalId: g.id, title: 'Late');
      b.repos.goalSubtasks.save(s);
      await settle([b, a]);
      await settle([a, b]);

      expect(a.repos.goalSubtasks.get(s.id), isNull);
      expect(b.repos.goalSubtasks.get(s.id), isNull);
      expect(a.repos.goals.get(g.id), isNull);
      expect(b.repos.goals.get(g.id), isNull);
      expectSame([a, b]);
    });

    test(
      'two devices change the same subtask: the later change stays',
      () async {
        final g = await shared();
        final s = GoalSubtaskItem(goalId: g.id, title: 'One');
        a.repos.goalSubtasks.save(s);
        await settle([a, b]);

        a.later();
        a.repos.goalSubtasks.save(s.copyWith(doneAt: '2026-10-05T11:00:00'));
        b.later();
        b.repos.goalSubtasks.save(s.copyWith(title: 'One, changed'));
        await settle([a, b]);

        for (final d in [a, b]) {
          final back = d.repos.goalSubtasks.get(s.id)!;
          expect(back.title, 'One, changed');
          expect(back.isDone, isFalse);
        }
      },
    );

    test(
      'an import on one device replaces the subtasks on the other',
      () async {
        final g = await shared();
        a.repos.goalSubtasks.save(GoalSubtaskItem(goalId: g.id, title: 'Old'));
        await settle([a, b]);

        final file = Device(MemoryRemote());
        final kept = goal(file.repos, id: 'KEPT');
        file.repos.goalSubtasks.save(
          GoalSubtaskItem(goalId: kept.id, title: 'From the file'),
        );
        a.later();
        DataExport.importData(DataExport.export(file.db), a.repos);
        await settle([a, b]);

        expect(b.repos.goals.get(g.id), isNull);
        expect(titles(b, 'KEPT'), ['From the file']);
        expectSame([a, b]);
      },
    );
  });

  group('Many devices', () {
    for (var seed = 1; seed <= 12; seed++) {
      test('random offline work on goals and subtasks ends the same '
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
