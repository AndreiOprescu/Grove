import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/block_subtask.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/event.dart';
import 'package:grove/core/model/goal.dart';
import 'package:grove/data/data.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import 'helpers.dart';

// Subtasks of one goal block. They belong to that one block (one event), not
// to the goal. Another block of the same goal has its own list, which starts
// empty. Port of the Mac app's `BlockSubtaskTests`.

// 2026-10-05 is a Monday.
const monday = DayKey('2026-10-05');

EventItem goalBlock(
  Repos r, {
  String goal = 'G1',
  required DayKey day,
  required String id,
}) {
  final e = EventItem(
    id: id,
    title: 'Read',
    start: WallTime(day: day, minute: 600),
    end: WallTime(day: day, minute: 660),
    kind: EventKind.block,
    goalId: goal,
  );
  r.events.save(e);
  return e;
}

Repos twoBlocksOfOneGoal() {
  final r = makeRepos();
  r.goals.upsert(GoalItem(id: 'G1', title: 'Read'));
  goalBlock(r, day: monday, id: 'E1');
  goalBlock(r, day: monday.adding(days: 1), id: 'E2');
  return r;
}

BlockSubtaskItem sub(
  String id,
  String event,
  String title, {
  double sort = 0,
  String? doneAt,
}) => BlockSubtaskItem(
  id: id,
  eventId: event,
  title: title,
  sort: sort,
  doneAt: doneAt,
);

void main() {
  group('The model', () {
    test('a new subtask is open and has stamps', () {
      final s = BlockSubtaskItem(eventId: 'E1', title: 'Chapter 3');
      expect(s.eventId, 'E1');
      expect(s.title, 'Chapter 3');
      expect(s.doneAt, isNull);
      expect(s.isDone, isFalse);
      expect(s.createdAt, isNotEmpty);
      expect(s.createdAt, s.updatedAt);
      expect(s.id, isNotEmpty);
    });

    test('copyWith can tick it done and open it again', () {
      final s = BlockSubtaskItem(eventId: 'E1', title: 'Chapter 3');
      final done = s.copyWith(doneAt: '2026-10-05T11:00:00');
      expect(done.isDone, isTrue);
      expect(done.id, s.id);
      expect(done.copyWith(title: 'x').doneAt, '2026-10-05T11:00:00');
      expect(done.copyWith(doneAt: null).isDone, isFalse);
      expect(done, isNot(s));
      expect(done.copyWith(doneAt: null), s);
    });
  });

  group('One instance only', () {
    test('subtasks stay on the one goal block', () {
      final r = twoBlocksOfOneGoal();
      r.blockSubtasks.save(sub('S1', 'E1', 'Chapter 3', sort: 1));
      r.blockSubtasks.save(sub('S2', 'E1', 'Chapter 4', sort: 2));
      expect(r.blockSubtasks.forEvent('E1').map((s) => s.title), [
        'Chapter 3',
        'Chapter 4',
      ]);
    });

    test('another block of the same goal has none', () {
      final r = twoBlocksOfOneGoal();
      r.blockSubtasks.save(sub('S1', 'E1', 'Chapter 3'));
      expect(r.blockSubtasks.forEvent('E2'), isEmpty);
      r.blockSubtasks.save(sub('S2', 'E2', 'Notes'));
      expect(r.blockSubtasks.forEvent('E1').map((s) => s.id), ['S1']);
      expect(r.blockSubtasks.forEvent('E2').map((s) => s.id), ['S2']);
    });

    test('the goal itself is not changed', () {
      final r = twoBlocksOfOneGoal();
      final before = r.goals.get('G1')!;
      r.blockSubtasks.save(sub('S1', 'E1', 'Chapter 3'));
      expect(r.goals.get('G1'), before);
    });

    test('saving twice updates the row and ticks it done', () {
      final r = twoBlocksOfOneGoal();
      final s = sub('S1', 'E1', 'Chapter 3');
      r.blockSubtasks.save(s);
      r.blockSubtasks.save(
        s.copyWith(title: 'Chapter 3 and 4', doneAt: '2026-10-05T11:00:00'),
      );
      final back = r.blockSubtasks.get('S1')!;
      expect(back.title, 'Chapter 3 and 4');
      expect(back.isDone, isTrue);
      expect(back.doneAt, '2026-10-05T11:00:00');
      expect(r.blockSubtasks.forEvent('E1').length, 1);
    });

    test('the list comes in sort order', () {
      final r = twoBlocksOfOneGoal();
      r.blockSubtasks.save(sub('S2', 'E1', 'Second', sort: 2));
      r.blockSubtasks.save(sub('S1', 'E1', 'First', sort: 1));
      expect(r.blockSubtasks.forEvent('E1').map((s) => s.id), ['S1', 'S2']);
      final both = r.blockSubtasks.forEvents(['E1', 'E2']);
      expect(both['E1']?.map((s) => s.id), ['S1', 'S2']);
      expect(both['E2'], isNull);
    });

    test('no blocks asked gives an empty map', () {
      final r = twoBlocksOfOneGoal();
      r.blockSubtasks.save(sub('S1', 'E1', 'A'));
      expect(r.blockSubtasks.forEvents(const []), isEmpty);
    });

    test('very many blocks can be asked at one time', () {
      final r = twoBlocksOfOneGoal();
      r.blockSubtasks.save(sub('S1', 'E1', 'A'));
      final ids = [for (var i = 0; i < 2500; i++) 'none-$i', 'E1'];
      expect(r.blockSubtasks.forEvents(ids).keys, ['E1']);
    });

    test('deleting a subtask removes only it', () {
      final r = twoBlocksOfOneGoal();
      r.blockSubtasks.save(sub('S1', 'E1', 'A'));
      r.blockSubtasks.save(sub('S2', 'E1', 'B'));
      r.blockSubtasks.delete('S1');
      expect(r.blockSubtasks.forEvent('E1').map((s) => s.id), ['S2']);
    });

    test('deleting the block deletes its subtasks', () {
      final r = twoBlocksOfOneGoal();
      r.blockSubtasks.save(sub('S1', 'E1', 'A'));
      r.blockSubtasks.save(sub('S2', 'E2', 'B'));
      r.events.delete('E1');
      expect(r.blockSubtasks.get('S1'), isNull);
      expect(r.blockSubtasks.get('S2'), isNotNull);
    });

    test('a subtask needs a block that exists', () {
      final r = makeRepos();
      expect(
        () =>
            r.blockSubtasks.save(BlockSubtaskItem(eventId: 'nope', title: 'A')),
        throwsA(isA<SqliteException>()),
      );
    });

    test('deleting the goal keeps the block and its subtasks', () {
      final r = twoBlocksOfOneGoal();
      r.blockSubtasks.save(sub('S1', 'E1', 'A'));
      r.goals.delete('G1');
      expect(r.events.get('E1'), isNotNull);
      expect(r.events.get('E1')?.goalId, isNull);
      expect(r.blockSubtasks.forEvent('E1').map((s) => s.id), ['S1']);
    });

    test('moving the block keeps its subtasks', () {
      final r = twoBlocksOfOneGoal();
      r.blockSubtasks.save(sub('S1', 'E1', 'A'));
      final e = r.events.get('E1')!;
      // An upsert, not a replace, so the cascade does not fire.
      r.events.save(
        e.copyWith(
          start: const WallTime(day: monday, minute: 720),
          end: const WallTime(day: monday, minute: 780),
        ),
      );
      expect(r.blockSubtasks.forEvent('E1').map((s) => s.id), ['S1']);
    });
  });

  group('The database upgrade', () {
    test('the shared schema has the table and its index', () {
      final db = makeRepos().db;
      final names = db.query(
        "SELECT name FROM sqlite_master WHERE tbl_name = 'block_subtasks' "
        "AND type IN ('table', 'index') ORDER BY name",
        const [],
        (r) => r.text(0),
      );
      expect(names, contains('block_subtasks'));
      expect(names, contains('block_subtasks_event'));
    });

    test('upgrading a version 6 database keeps its data', () {
      final dir = tempDir('grove-m7-');
      final path = oldDatabase(
        dir,
        6,
        'INSERT INTO goals (id, title, target_min, kind, target_count, '
        "created_at, updated_at) VALUES ('g1', 'Read', 360, 'sessions', 4, "
        "'2026-10-01T09:00:00', '2026-10-01T09:00:00');"
        'INSERT INTO tasks (id, title, notes, created_at, updated_at) VALUES '
        "('t1', 'Old task', 'body', '2026-10-01T09:00:00', "
        "'2026-10-01T09:00:00');"
        'INSERT INTO events (id, title, start, end, kind, goal_id, done_at, '
        "created_at, updated_at) VALUES ('e1', 'Read', '2026-10-01T09:00', "
        "'2026-10-01T10:00', 'block', 'g1', '2026-10-01T10:00:00', "
        "'2026-10-01T09:00:00', '2026-10-01T09:00:00');",
      );
      expect(Migrations.all.length, greaterThanOrEqualTo(7));
      final r = Repos(Database.open(path));
      expect(r.db.userVersion, Migrations.all.length);
      final g = r.goals.get('g1')!;
      expect(g.title, 'Read');
      expect(g.kind, GoalKind.sessions);
      expect(g.targetCount, 4);
      expect(g.targetMin, 360);
      expect(r.tasks.get('t1')?.notes, 'body');
      final e = r.events.get('e1')!;
      expect(e.goalId, 'g1');
      expect(e.doneAt, '2026-10-01T10:00:00');
      expect(e.title, 'Read');
      expect(r.blockSubtasks.forEvent('e1'), isEmpty);
      r.blockSubtasks.save(sub('s1', 'e1', 'Chapter 3'));
      expect(r.blockSubtasks.forEvent('e1').map((s) => s.title), ['Chapter 3']);
      r.db.close();
    });
  });

  group('Export and import', () {
    test('subtasks of a block come back from an export file', () {
      final a = twoBlocksOfOneGoal();
      a.blockSubtasks.save(sub('S1', 'E1', 'A', sort: 1));
      a.blockSubtasks.save(
        sub('S2', 'E1', 'B', sort: 2, doneAt: '2026-10-05T11:00:00'),
      );
      expect(DataExport.tables, contains('block_subtasks'));
      final b = makeRepos();
      DataExport.importData(DataExport.export(a.db), b);
      expect(b.blockSubtasks.forEvent('E1'), a.blockSubtasks.forEvent('E1'));
      expect(b.blockSubtasks.forEvent('E1').length, 2);
      expect(b.blockSubtasks.forEvent('E2'), isEmpty);
    });

    test('the table comes right after the events in the file order', () {
      final at = DataExport.tables.indexOf('block_subtasks');
      expect(at, DataExport.tables.indexOf('events') + 1);
    });

    test('the file has the Mac columns only', () {
      final a = twoBlocksOfOneGoal();
      a.blockSubtasks.save(sub('S1', 'E1', 'A', sort: 1));
      final obj = jsonDecode(DataExport.export(a.db)) as Map<String, Object?>;
      expect(obj['schema'], 7);
      final rows = (obj['tables'] as Map)['block_subtasks'] as List;
      expect((rows.single as Map).keys.toSet(), {
        'id',
        'event_id',
        'title',
        'done_at',
        'sort',
        'created_at',
        'updated_at',
      });
    });

    test('an older export file without the table still imports', () {
      final a = twoBlocksOfOneGoal();
      final obj = jsonDecode(DataExport.export(a.db)) as Map<String, Object?>;
      (obj['tables'] as Map).remove('block_subtasks');
      obj['schema'] = 6;
      final b = makeRepos();
      b.goals.upsert(GoalItem(id: 'G1', title: 'Read'));
      goalBlock(b, day: monday, id: 'OLD');
      b.blockSubtasks.save(sub('X', 'OLD', 'Old'));
      DataExport.importData(jsonEncode(obj), b);
      expect(b.events.get('E1'), isNotNull);
      expect(b.blockSubtasks.get('X'), isNull);
    });
  });
}
