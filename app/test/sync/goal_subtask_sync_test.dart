import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import '../data/helpers.dart';
import 'support.dart';

// The subtasks of a goal (table `goal_subtasks`, shared migration 8) sync
// like every other row: the outbox sees them, a second device gets them, and
// they go when their goal goes.

GoalItem goal(Repos r, {String? id, String title = 'Read'}) {
  final g = GoalItem(id: id, title: title);
  r.goals.upsert(g);
  return g;
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
  switch (rnd.nextInt(8)) {
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
    test('the table is synced and exported, right after the goals', () {
      const tables = SyncMigrations.syncedTables;
      expect(tables.indexOf('goal_subtasks'), tables.indexOf('goals') + 1);
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
      ]);
    });

    test('the engine knows that a subtask goes with its goal', () {
      final fk = SyncTable.read(a.db, 'goal_subtasks').foreignKeys.values;
      expect(fk.single.column, 'goal_id');
      expect(fk.single.parent, 'goals');
      expect(fk.single.setsNull, isFalse);
    });

    test('a database of an older build of this app gets the table, the '
        'sync columns and the triggers', () {
      final dir = tempDir('grove-m8-sync-');
      final path = join(dir, 'o.sqlite');
      var db = Database.open(path);
      final g = goal(Repos(db));
      // Take the database back to shared schema 7 and sync schema 3.
      db.executeScript('''
        DROP TABLE goal_subtasks;
        PRAGMA user_version = 7;
        UPDATE sync_meta SET value = '3' WHERE key = 'schema';
        DELETE FROM sync_meta WHERE key = 'triggers';
      ''');
      db.execute('DELETE FROM outbox');
      db.close();

      db = Database.open(path);
      expect(db.userVersion, Migrations.all.length);
      expect(db.syncVersion, SyncMigrations.all.length);
      expect(db.syncVersion, 4);
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
