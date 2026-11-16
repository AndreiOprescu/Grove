import 'package:flutter_test/flutter_test.dart';

import '../data/helpers.dart';
import 'support.dart';

// Routines (shared schema 16, sync schema 10): the rule on `tasks` and the
// done days in `routine_done` sync like every other row.

List<String> columns(Database db, String table) =>
    db.query('PRAGMA table_info($table)', const [], (r) => r.text(1));

TaskItem gym(Device d) {
  final t = TaskItem(
    id: 'T',
    title: 'Gym',
    routine: RoutineRule(every: 2, unit: RoutineUnit.days),
    routineSince: DayKey('2026-11-10'),
  );
  d.repos.tasks.save(t);
  return t;
}

void main() {
  late MemoryRemote remote;
  late Device a, b;

  setUp(() {
    remote = MemoryRemote();
    a = Device(remote);
    b = Device(remote);
  });

  group('The schema', () {
    test('the done days are synced and exported, after the tasks', () {
      const tables = SyncMigrations.syncedTables;
      expect(
        tables.indexOf('routine_done'),
        greaterThan(tables.indexOf('tasks')),
      );
      expect(DataExport.tables, tables);
      expect(SyncMigrations.addedColumns['routine_done'], {
        'deleted',
        'user_id',
        'updated_at',
      });
    });

    test('the SQL for Supabase has the table and the task columns', () {
      final sql = supabaseSql(RemoteSchema.read(a.db));
      expect(
        sql,
        contains('create table if not exists public."routine_done" ('),
      );
      expect(sql, contains('"routine" text'));
      expect(sql, contains('"routine_since" text'));
    });
  });

  group('Upgrade', () {
    test('a database of the goal map build (schema 15, sync 9) gets the '
        'table, the columns and the triggers', () {
      final dir = tempDir('grove-m16-sync-');
      final path = join(dir, 'o.sqlite');
      var db = Database.open(path);
      Repos(db).tasks.save(TaskItem(id: 'T', title: 'Gym'));
      rewindRoutines(db);
      db.executeScript('''
        PRAGMA user_version = 15;
        UPDATE sync_meta SET value = '9' WHERE key = 'schema';
      ''');
      db.execute('DELETE FROM outbox');
      expect(columns(db, 'tasks'), isNot(contains('routine')));
      db.close();

      db = Database.open(path);
      addTearDown(db.close);
      expect(db.userVersion, Migrations.all.length);
      expect(columns(db, 'tasks'), containsAll(['routine', 'routine_since']));
      expect(columns(db, 'routine_done'), contains('updated_at'));
      final r = Repos(db);
      expect(r.tasks.get('T')!.routine, isNull);
      // The triggers were made again: they see the new column and the new
      // table.
      db.execute('DELETE FROM outbox');
      db.execute('UPDATE tasks SET routine = ? WHERE id = ?', [
        '{"every":1,"unit":"weeks"}',
        'T',
      ]);
      r.routineDones.save(
        RoutineDone(taskId: 'T', day: DayKey('2026-11-16'), doneAt: 'x'),
      );
      expect(
        {for (final e in Outbox(db).entries()) e.table},
        {'tasks', 'routine_done'},
      );
    });
  });

  group('Two devices', () {
    test('the rule and the done days reach the other device', () async {
      final t = gym(a);
      a.repos.routineDones.save(
        RoutineDone(
          taskId: t.id,
          day: DayKey('2026-11-12'),
          doneAt: '2026-11-12T08:00:00',
        ),
      );
      await settle([a, b]);
      expectSame([a, b]);
      final got = b.repos.tasks.get(t.id)!;
      expect(got.routine, RoutineRule(every: 2, unit: RoutineUnit.days));
      expect(got.routineSince, DayKey('2026-11-10'));
      expect(b.repos.routineDones.forTask(t.id).map((x) => x.day), [
        DayKey('2026-11-12'),
      ]);
    });

    test('a tick on each device, offline, keeps both days', () async {
      final t = gym(a);
      await settle([a, b]);
      a.repos.routineDones.save(
        RoutineDone(taskId: t.id, day: DayKey('2026-11-12'), doneAt: 'a'),
      );
      b.repos.routineDones.save(
        RoutineDone(taskId: t.id, day: DayKey('2026-11-14'), doneAt: 'b'),
      );
      await settle([a, b]);
      expectSame([a, b]);
      expect(b.repos.routineDones.forTask(t.id).length, 2);
    });

    test('an untick travels', () async {
      final t = gym(a);
      final x = RoutineDone(
        taskId: t.id,
        day: DayKey('2026-11-12'),
        doneAt: 'a',
      );
      a.repos.routineDones.save(x);
      await settle([a, b]);
      a.later();
      a.repos.routineDones.delete(x.id);
      await settle([a, b]);
      expect(b.repos.routineDones.forTask(t.id), isEmpty);
    });
  });
}
