import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/block_subtask.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/event.dart';
import 'package:grove/core/model/goal.dart';
import 'package:grove/core/model/goal_subtask.dart';
import 'package:grove/data/data.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import 'helpers.dart';

// Subtasks of a goal (table `goal_subtasks`, shared migration 8). The list
// belongs to the goal, so every block of the goal has the same one. It is
// another list than the subtasks of one block (`block_subtasks`).
//
// A subtask of a goal can be planned in one block of the goal (column
// `event_id`, shared migration 9). It stays one row of the goal.

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

/// Two goals. The first has a block on Monday and one on Tuesday.
Repos twoGoals() {
  final r = makeRepos();
  r.goals.upsert(GoalItem(id: 'G1', title: 'Read'));
  r.goals.upsert(GoalItem(id: 'G2', title: 'Gym'));
  goalBlock(r, day: monday, id: 'E1');
  goalBlock(r, day: monday.adding(days: 1), id: 'E2');
  return r;
}

GoalSubtaskItem sub(
  String id,
  String goal,
  String title, {
  double sort = 0,
  String? doneAt,
  String? eventId,
}) => GoalSubtaskItem(
  id: id,
  goalId: goal,
  title: title,
  sort: sort,
  doneAt: doneAt,
  eventId: eventId,
);

List<String> ids(Iterable<GoalSubtaskItem> subs) => [
  for (final s in subs) s.id,
];

void main() {
  group('The model', () {
    test('a new subtask is open and has an id and times', () {
      final s = GoalSubtaskItem(goalId: 'G1', title: 'Chapter 3');
      expect(s.id, isNotEmpty);
      expect(s.isDone, isFalse);
      expect(s.sort, 0);
      expect(s.createdAt, isNotEmpty);
      expect(s.updatedAt, isNotEmpty);
    });

    test('copyWith can set and clear the done time', () {
      final s = GoalSubtaskItem(goalId: 'G1', title: 'Chapter 3');
      final done = s.copyWith(doneAt: '2026-10-05T11:00:00');
      expect(done.isDone, isTrue);
      expect(done.copyWith(title: 'Other').doneAt, '2026-10-05T11:00:00');
      expect(done.copyWith(doneAt: null).isDone, isFalse);
      expect(s.copyWith(), s);
      expect(s.copyWith().hashCode, s.hashCode);
      expect(done, isNot(s));
    });

    test('a new subtask is in no block, and copyWith can set and clear the '
        'block', () {
      final s = GoalSubtaskItem(goalId: 'G1', title: 'Chapter 3');
      expect(s.eventId, isNull);
      final planned = s.copyWith(eventId: 'E1');
      expect(planned.eventId, 'E1');
      expect(planned.copyWith(title: 'Other').eventId, 'E1');
      expect(planned.copyWith(eventId: null).eventId, isNull);
      expect(planned, isNot(s));
      expect(planned.copyWith(eventId: null), s);
    });
  });

  group('The list of a goal', () {
    test('the subtasks of a goal come back in list order', () {
      final r = twoGoals();
      r.goalSubtasks.save(sub('S2', 'G1', 'Second', sort: 2));
      r.goalSubtasks.save(sub('S1', 'G1', 'First', sort: 1));
      expect(ids(r.goalSubtasks.forGoal('G1')), ['S1', 'S2']);
    });

    test('another goal has its own list', () {
      final r = twoGoals();
      r.goalSubtasks.save(sub('S1', 'G1', 'Chapter 3'));
      expect(r.goalSubtasks.forGoal('G2'), isEmpty);
      r.goalSubtasks.save(sub('S2', 'G2', 'Legs'));
      expect(ids(r.goalSubtasks.forGoal('G1')), ['S1']);
      expect(ids(r.goalSubtasks.forGoal('G2')), ['S2']);
    });

    test('many goals in one query', () {
      final r = twoGoals();
      r.goalSubtasks.save(sub('S2', 'G1', 'Second', sort: 2));
      r.goalSubtasks.save(sub('S1', 'G1', 'First', sort: 1));
      r.goalSubtasks.save(sub('S3', 'G2', 'Legs'));
      final all = r.goalSubtasks.forGoals(['G1', 'G2', 'nope']);
      expect(all.keys.toSet(), {'G1', 'G2'});
      expect(ids(all['G1']!), ['S1', 'S2']);
      expect(ids(all['G2']!), ['S3']);
      expect(r.goalSubtasks.forGoals(const []), isEmpty);
    });

    test('a tick is saved, and a save again changes the row', () {
      final r = twoGoals();
      final s = sub('S1', 'G1', 'Chapter 3');
      r.goalSubtasks.save(s);
      r.goalSubtasks.save(
        s.copyWith(title: 'Chapter 3 and 4', doneAt: '2026-10-05T11:00:00'),
      );
      final back = r.goalSubtasks.get('S1')!;
      expect(back.title, 'Chapter 3 and 4');
      expect(back.doneAt, '2026-10-05T11:00:00');
      expect(back.isDone, isTrue);
      expect(r.goalSubtasks.forGoal('G1').length, 1);
    });

    test('a deleted subtask leaves the other ones', () {
      final r = twoGoals();
      r.goalSubtasks.save(sub('S1', 'G1', 'A', sort: 1));
      r.goalSubtasks.save(sub('S2', 'G1', 'B', sort: 2));
      r.goalSubtasks.delete('S1');
      expect(ids(r.goalSubtasks.forGoal('G1')), ['S2']);
    });

    test('a subtask needs its goal', () {
      final r = twoGoals();
      expect(
        () => r.goalSubtasks.save(GoalSubtaskItem(goalId: 'nope', title: 'A')),
        throwsA(isA<SqliteException>()),
      );
    });

    test('a deleted goal takes its subtasks, and only its own', () {
      final r = twoGoals();
      r.goalSubtasks.save(sub('S1', 'G1', 'A'));
      r.goalSubtasks.save(sub('S2', 'G2', 'B'));
      r.goals.delete('G1');
      expect(r.goalSubtasks.get('S1'), isNull);
      expect(r.goalSubtasks.get('S2'), isNotNull);
    });

    test('an archived goal keeps its subtasks', () {
      final r = twoGoals();
      r.goalSubtasks.save(sub('S1', 'G1', 'A'));
      r.goals.upsert(r.goals.get('G1')!.copyWith(archived: true));
      expect(ids(r.goalSubtasks.forGoal('G1')), ['S1']);
    });
  });

  group('One list for every block of the goal', () {
    test(
      'a block has no goal subtask of its own: the list hangs on the goal',
      () {
        final r = twoGoals();
        r.goalSubtasks.save(sub('S1', 'G1', 'Chapter 3'));
        for (final block in ['E1', 'E2']) {
          final goal = r.events.get(block)!.goalId!;
          expect(ids(r.goalSubtasks.forGoal(goal)), ['S1'], reason: block);
        }
      },
    );

    test('a deleted block does not touch the list of the goal', () {
      final r = twoGoals();
      r.goalSubtasks.save(sub('S1', 'G1', 'Chapter 3'));
      r.events.delete('E1');
      expect(ids(r.goalSubtasks.forGoal('G1')), ['S1']);
    });

    test('a subtask can be planned in one block of the goal', () {
      final r = twoGoals();
      r.goalSubtasks.save(sub('S1', 'G1', 'Chapter 3', eventId: 'E1'));
      expect(r.goalSubtasks.get('S1')!.eventId, 'E1');
      // It is still one row of the goal.
      expect(ids(r.goalSubtasks.forGoal('G1')), ['S1']);
      expect(r.goalSubtasks.forGoal('G1').single.eventId, 'E1');
      r.goalSubtasks.save(r.goalSubtasks.get('S1')!.copyWith(eventId: 'E2'));
      expect(r.goalSubtasks.get('S1')!.eventId, 'E2');
      r.goalSubtasks.save(r.goalSubtasks.get('S1')!.copyWith(eventId: null));
      expect(r.goalSubtasks.get('S1')!.eventId, isNull);
    });

    test('the planned subtasks of many blocks in one query, in list order', () {
      final r = twoGoals();
      r.goalSubtasks.save(sub('S2', 'G1', 'Second', sort: 2, eventId: 'E1'));
      r.goalSubtasks.save(sub('S1', 'G1', 'First', sort: 1, eventId: 'E1'));
      r.goalSubtasks.save(sub('S3', 'G1', 'Third', sort: 3, eventId: 'E2'));
      r.goalSubtasks.save(sub('S4', 'G1', 'Free', sort: 4));
      final all = r.goalSubtasks.forEvents(['E1', 'E2', 'nope']);
      expect(all.keys.toSet(), {'E1', 'E2'});
      expect(ids(all['E1']!), ['S1', 'S2']);
      expect(ids(all['E2']!), ['S3']);
      expect(r.goalSubtasks.forEvents(const []), isEmpty);
    });

    test('a planned subtask needs its block', () {
      final r = twoGoals();
      expect(
        () => r.goalSubtasks.save(sub('S1', 'G1', 'A', eventId: 'nope')),
        throwsA(isA<SqliteException>()),
      );
    });

    test('a deleted block gives its planned subtask back to the goal', () {
      final r = twoGoals();
      r.goalSubtasks.save(
        sub('S1', 'G1', 'A', eventId: 'E1', doneAt: '2026-10-05T11:00:00'),
      );
      r.goalSubtasks.save(sub('S2', 'G1', 'B', sort: 1, eventId: 'E2'));
      r.events.delete('E1');
      final back = r.goalSubtasks.get('S1')!;
      expect(back.eventId, isNull);
      expect(back.isDone, isTrue);
      expect(r.goalSubtasks.get('S2')!.eventId, 'E2');
    });

    test('the subtasks of one block are another list', () {
      final r = twoGoals();
      r.goalSubtasks.save(sub('S1', 'G1', 'Of the goal'));
      r.blockSubtasks.save(BlockSubtaskItem(eventId: 'E1', title: 'Of E1'));
      expect(r.goalSubtasks.forGoal('G1').map((s) => s.title), ['Of the goal']);
      expect(r.blockSubtasks.forEvent('E1').map((s) => s.title), ['Of E1']);
      expect(r.blockSubtasks.forEvent('E2'), isEmpty);
    });
  });

  group('The database file', () {
    test('a tick is still there after the file is closed and opened again', () {
      final dir = tempDir('grove-goal-subtasks-');
      final path = join(dir, 'grove.sqlite');
      var r = Repos(Database.open(path));
      r.goals.upsert(GoalItem(id: 'G1', title: 'Read'));
      r.goalSubtasks.save(sub('S1', 'G1', 'Chapter 3', sort: 1));
      r.goalSubtasks.save(sub('S2', 'G1', 'Chapter 4', sort: 2));
      r.goalSubtasks.save(
        r.goalSubtasks.get('S1')!.copyWith(doneAt: '2026-10-05T11:00:00'),
      );
      r.db.close();

      r = Repos(Database.open(path));
      final back = r.goalSubtasks.forGoal('G1');
      expect(ids(back), ['S1', 'S2']);
      expect([for (final s in back) s.isDone], [true, false]);
      expect(back.first.doneAt, '2026-10-05T11:00:00');
      r.db.close();
    });

    test('the shared schema has the table and its index', () {
      final db = makeRepos().db;
      final names = db.query(
        "SELECT name FROM sqlite_master WHERE tbl_name = 'goal_subtasks' "
        "AND type IN ('table', 'index') ORDER BY name",
        const [],
        (r) => r.text(0),
      );
      expect(names, contains('goal_subtasks'));
      expect(names, contains('goal_subtasks_goal'));
      expect(names, contains('goal_subtasks_event'));
      expect(Migrations.all.length, 10);
      expect(db.userVersion, 10);
    });

    test('upgrading a version 8 database keeps its subtasks, in no block', () {
      final dir = tempDir('grove-m9-');
      final path = oldDatabase(
        dir,
        8,
        'INSERT INTO goals (id, title, target_min, kind, target_count, '
        "created_at, updated_at) VALUES ('g1', 'Read', 360, 'hours', 0, "
        "'2026-10-01T09:00:00', '2026-10-01T09:00:00');"
        'INSERT INTO events (id, title, start, end, kind, goal_id, '
        "created_at, updated_at) VALUES ('e1', 'Read', '2026-10-01T09:00', "
        "'2026-10-01T10:00', 'block', 'g1', "
        "'2026-10-01T09:00:00', '2026-10-01T09:00:00');"
        'INSERT INTO goal_subtasks (id, goal_id, title, done_at, sort, '
        "created_at, updated_at) VALUES ('s1', 'g1', 'Chapter 3', "
        "'2026-10-01T10:00:00', 1, '2026-10-01T09:00:00', "
        "'2026-10-01T09:00:00');",
      );
      final r = Repos(Database.open(path));
      expect(r.db.userVersion, Migrations.all.length);
      final s = r.goalSubtasks.get('s1')!;
      expect(s.title, 'Chapter 3');
      expect(s.doneAt, '2026-10-01T10:00:00');
      expect(s.eventId, isNull);
      r.goalSubtasks.save(s.copyWith(eventId: 'e1'));
      expect(ids(r.goalSubtasks.forEvents(['e1'])['e1']!), ['s1']);
      r.db.close();
    });

    test('upgrading a version 7 database keeps its data', () {
      final dir = tempDir('grove-m8-');
      final path = oldDatabase(
        dir,
        7,
        'INSERT INTO goals (id, title, target_min, kind, target_count, '
        "created_at, updated_at) VALUES ('g1', 'Read', 360, 'sessions', 4, "
        "'2026-10-01T09:00:00', '2026-10-01T09:00:00');"
        'INSERT INTO events (id, title, start, end, kind, goal_id, done_at, '
        "created_at, updated_at) VALUES ('e1', 'Read', '2026-10-01T09:00', "
        "'2026-10-01T10:00', 'block', 'g1', '2026-10-01T10:00:00', "
        "'2026-10-01T09:00:00', '2026-10-01T09:00:00');"
        'INSERT INTO block_subtasks (id, event_id, title, sort, created_at, '
        "updated_at) VALUES ('b1', 'e1', 'Of the block', 1, "
        "'2026-10-01T09:00:00', '2026-10-01T09:00:00');",
      );
      final r = Repos(Database.open(path));
      expect(r.db.userVersion, Migrations.all.length);
      final g = r.goals.get('g1')!;
      expect(g.title, 'Read');
      expect(g.kind, GoalKind.sessions);
      expect(g.targetCount, 4);
      expect(r.events.get('e1')!.goalId, 'g1');
      expect(r.blockSubtasks.forEvent('e1').map((s) => s.title), [
        'Of the block',
      ]);
      expect(r.goalSubtasks.forGoal('g1'), isEmpty);
      r.goalSubtasks.save(sub('s1', 'g1', 'Chapter 3'));
      expect(r.goalSubtasks.forGoal('g1').map((s) => s.title), ['Chapter 3']);
      r.db.close();
    });
  });

  group('Export and import', () {
    test('subtasks of a goal come back from an export file', () {
      final a = twoGoals();
      a.goalSubtasks.save(sub('S1', 'G1', 'A', sort: 1));
      a.goalSubtasks.save(
        sub('S2', 'G1', 'B', sort: 2, doneAt: '2026-10-05T11:00:00'),
      );
      expect(DataExport.tables, contains('goal_subtasks'));
      final b = makeRepos();
      DataExport.importData(DataExport.export(a.db), b);
      expect(b.goalSubtasks.forGoal('G1'), a.goalSubtasks.forGoal('G1'));
      expect(b.goalSubtasks.forGoal('G1').length, 2);
      expect(b.goalSubtasks.forGoal('G2'), isEmpty);
    });

    test('the block of a subtask comes back from an export file', () {
      final a = twoGoals();
      a.goalSubtasks.save(sub('S1', 'G1', 'A', sort: 1, eventId: 'E2'));
      a.goalSubtasks.save(sub('S2', 'G1', 'B', sort: 2));
      final b = makeRepos();
      DataExport.importData(DataExport.export(a.db), b);
      expect(b.goalSubtasks.get('S1')!.eventId, 'E2');
      expect(b.goalSubtasks.get('S2')!.eventId, isNull);
      expect(ids(b.goalSubtasks.forEvents(['E2'])['E2']!), ['S1']);
    });

    test('the table comes after the goals and after the blocks in the file '
        'order: it points at both', () {
      final at = DataExport.tables.indexOf('goal_subtasks');
      expect(at, greaterThan(DataExport.tables.indexOf('goals')));
      expect(at, greaterThan(DataExport.tables.indexOf('events')));
    });

    test('the file says schema 10 and has the data columns only', () {
      final a = twoGoals();
      a.goalSubtasks.save(sub('S1', 'G1', 'A', sort: 1));
      final obj = jsonDecode(DataExport.export(a.db)) as Map<String, Object?>;
      expect(obj['schema'], 10);
      final rows = (obj['tables'] as Map)['goal_subtasks'] as List;
      expect((rows.single as Map).keys.toSet(), {
        'id',
        'goal_id',
        'title',
        'done_at',
        'sort',
        'created_at',
        'updated_at',
        'event_id',
      });
    });

    test('an export file of schema 8 (no block column) still imports, and '
        'its subtasks are in no block', () {
      final a = twoGoals();
      a.goalSubtasks.save(
        sub('S1', 'G1', 'A', sort: 1, doneAt: '2026-10-05T11:00:00'),
      );
      final obj = jsonDecode(DataExport.export(a.db)) as Map<String, Object?>;
      for (final row in (obj['tables'] as Map)['goal_subtasks'] as List) {
        (row as Map).remove('event_id');
      }
      obj['schema'] = 8;
      final b = makeRepos();
      DataExport.importData(jsonEncode(obj), b);
      final back = b.goalSubtasks.get('S1')!;
      expect(back.title, 'A');
      expect(back.isDone, isTrue);
      expect(back.eventId, isNull);
    });

    test('a file with a subtask in a block that is not in the file is '
        'refused, and nothing changes', () {
      final a = twoGoals();
      a.goalSubtasks.save(sub('S1', 'G1', 'A', eventId: 'E1'));
      final obj = jsonDecode(DataExport.export(a.db)) as Map<String, Object?>;
      ((obj['tables'] as Map)['events'] as List).clear();
      final b = makeRepos();
      b.goals.upsert(GoalItem(id: 'OLD', title: 'Old goal'));
      expect(
        () => DataExport.importData(jsonEncode(obj), b),
        throwsA(anything),
      );
      expect(b.goals.get('OLD'), isNotNull);
    });

    for (final version in [7, 6]) {
      test('an older export file (schema $version) without the table still '
          'imports, and the old subtasks go like every old row', () {
        final a = twoGoals();
        final obj = jsonDecode(DataExport.export(a.db)) as Map<String, Object?>;
        final tables = obj['tables'] as Map;
        tables.remove('goal_subtasks');
        if (version == 6) tables.remove('block_subtasks');
        obj['schema'] = version;
        final b = makeRepos();
        b.goals.upsert(GoalItem(id: 'OLD', title: 'Old goal'));
        b.goalSubtasks.save(sub('X', 'OLD', 'Old'));
        DataExport.importData(jsonEncode(obj), b);
        expect(b.goals.get('G1')?.title, 'Read');
        expect(b.goals.get('OLD'), isNull);
        expect(b.goalSubtasks.get('X'), isNull);
        expect(b.goalSubtasks.forGoal('G1'), isEmpty);
      });
    }

    test('a file from a newer Grove is refused', () {
      final a = twoGoals();
      final obj = jsonDecode(DataExport.export(a.db)) as Map<String, Object?>;
      obj['schema'] = 11;
      final b = makeRepos();
      b.goals.upsert(GoalItem(id: 'OLD', title: 'Old goal'));
      expect(
        () => DataExport.importData(jsonEncode(obj), b),
        throwsA(anything),
      );
      expect(b.goals.get('OLD'), isNotNull);
    });
  });
}
