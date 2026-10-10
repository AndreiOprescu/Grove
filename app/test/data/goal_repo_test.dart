import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/event.dart';
import 'package:grove/core/model/goal.dart';
import 'package:grove/core/model/ids.dart';
import 'package:grove/data/data.dart';

import 'helpers.dart';

// 2026-10-05 is a Monday. The Monday-first week runs to Sunday 2026-10-11.
const monday = DayKey('2026-10-05');
const sunday = DayKey('2026-10-11');

EventItem block(
  Repos r, {
  required String? goal,
  required DayKey day,
  int from = 600,
  int to = 660,
  bool done = false,
  String? id,
}) {
  final e = EventItem(
    id: id ?? newId(),
    title: 'Block',
    start: WallTime(day: day, minute: from),
    end: WallTime(day: day, minute: to),
    kind: EventKind.block,
    goalId: goal,
    doneAt: done ? '2026-10-05T12:00:00' : null,
    color: 'accent',
  );
  r.events.save(e);
  return e;
}

void main() {
  test('a goal is saved, loaded, changed and deleted', () {
    final r = makeRepos();
    var g = GoalItem(
      id: 'G1',
      title: 'Read',
      notes: 'Novels only',
      color: 'teal',
      targetMin: 360,
      sort: 2,
    );
    r.goals.upsert(g);
    final got = r.goals.get('G1')!;
    expect(got.title, 'Read');
    expect(got.notes, 'Novels only');
    expect(got.color, 'teal');
    expect(got.kind, GoalKind.hours);
    expect(got.targetMin, 360);
    expect(got.targetCount, 3);
    expect(got.sort, 2);
    expect(got.archived, isFalse);
    g = g.copyWith(
      title: 'Read more',
      targetMin: 420,
      kind: GoalKind.sessions,
      targetCount: 4,
      archived: true,
    );
    r.goals.upsert(g);
    final back = r.goals.get('G1')!;
    expect(back.title, 'Read more');
    expect(back.targetMin, 420);
    expect(back.kind, GoalKind.sessions);
    expect(back.targetCount, 4);
    expect(back.archived, isTrue);
    // An update, not a second row.
    expect(
      r.db.query('SELECT COUNT(*) FROM goals', const [], (x) => x.asInt(0)),
      [1],
    );
    r.goals.delete('G1');
    expect(r.goals.get('G1'), isNull);
  });

  test('saving a goal again refreshes its edit time and keeps the creation '
      'time', () {
    final r = makeRepos();
    r.goals.upsert(
      GoalItem(
        id: 'G1',
        title: 'Read',
        createdAt: '2026-01-01T08:00:00',
        updatedAt: '2026-01-01T08:00:00',
      ),
    );
    final got = r.goals.get('G1')!;
    expect(got.createdAt, '2026-01-01T08:00:00');
    expect(got.updatedAt, isNot('2026-01-01T08:00:00'));
  });

  test('all hides archived goals unless asked', () {
    final r = makeRepos();
    r.goals.upsert(GoalItem(id: 'A', title: 'A', sort: 2));
    r.goals.upsert(GoalItem(id: 'B', title: 'B', sort: 1));
    r.goals.upsert(GoalItem(id: 'C', title: 'C', sort: 3, archived: true));
    expect(r.goals.all().map((g) => g.id), ['B', 'A']);
    expect(r.goals.all(includeArchived: true).map((g) => g.id), [
      'B',
      'A',
      'C',
    ]);
  });

  test('an event keeps its goal and done time', () {
    final r = makeRepos();
    block(r, goal: 'G1', day: monday, done: true, id: 'E1');
    final got = r.events.get('E1')!;
    expect(got.goalId, 'G1');
    expect(got.doneAt, '2026-10-05T12:00:00');
    r.events.save(got.copyWith(goalId: null, doneAt: null));
    expect(r.events.get('E1')?.goalId, isNull);
    expect(r.events.get('E1')?.doneAt, isNull);
  });

  test('blocks for a goal come earliest first', () {
    final r = makeRepos();
    block(r, goal: 'G1', day: monday.adding(days: 1), id: 'late');
    block(r, goal: 'G1', day: monday, id: 'early');
    block(r, goal: 'G2', day: monday);
    expect(r.events.blocksForGoal('G1').map((e) => e.id), ['early', 'late']);
  });

  test('minutes add up every block of the goal in the range', () {
    final r = makeRepos();
    block(r, goal: 'G1', day: monday, from: 600, to: 660);
    block(
      r,
      goal: 'G1',
      day: monday.adding(days: 2),
      from: 540,
      to: 600,
      done: true,
    );
    block(r, goal: 'G1', day: monday.adding(days: 3), from: 540, to: 570);
    expect(r.goals.minutes('G1', from: monday, to: sunday), 150);
    expect(r.goals.minutes('G1', from: monday, to: sunday, doneOnly: true), 60);
  });

  test('doneOnly counts the done blocks', () {
    final r = makeRepos();
    block(r, goal: 'G1', day: monday, from: 600, to: 615);
    block(r, goal: 'G1', day: monday, from: 700, to: 940, done: true);
    block(r, goal: 'G1', day: sunday, from: 800, to: 845, done: true);
    expect(r.goals.sessions('G1', from: monday, to: sunday, doneOnly: true), 2);
    expect(
      r.goals.minutes('G1', from: monday, to: sunday, doneOnly: true),
      285,
    );
    expect(r.goals.minutes('G2', from: monday, to: sunday, doneOnly: true), 0);
  });

  test('sessions count the blocks whatever their length', () {
    final r = makeRepos();
    block(r, goal: 'G1', day: monday, from: 600, to: 615);
    block(r, goal: 'G1', day: monday, from: 700, to: 940);
    block(r, goal: 'G1', day: sunday, from: 800, to: 845, done: true);
    expect(r.goals.sessions('G1', from: monday, to: sunday), 3);
  });

  test('the first and last day of the range count', () {
    final r = makeRepos();
    block(r, goal: 'G1', day: monday);
    block(r, goal: 'G1', day: sunday);
    expect(r.goals.minutes('G1', from: monday, to: sunday), 120);
    expect(r.goals.sessions('G1', from: monday, to: sunday), 2);
  });

  test('the day before and the day after the range do not count', () {
    final r = makeRepos();
    block(r, goal: 'G1', day: monday.adding(days: -1), from: 1380, to: 1440);
    block(r, goal: 'G1', day: sunday.adding(days: 1), from: 0, to: 60);
    expect(r.goals.minutes('G1', from: monday, to: sunday), 0);
    expect(r.goals.sessions('G1', from: monday, to: sunday), 0);
  });

  test('a Sunday-first week holds the Sunday before but not the next one', () {
    final r = makeRepos();
    final firstSunday = monday.adding(days: -1);
    block(r, goal: 'G1', day: firstSunday);
    block(r, goal: 'G1', day: sunday);
    expect(
      r.goals.minutes('G1', from: firstSunday, to: firstSunday.adding(days: 6)),
      60,
    );
    expect(r.goals.minutes('G1', from: monday, to: sunday), 60);
  });

  test('other goals and plain blocks are not counted', () {
    final r = makeRepos();
    block(r, goal: 'G2', day: monday);
    block(r, goal: null, day: monday);
    block(r, goal: 'G1', day: monday, from: 600, to: 645);
    expect(r.goals.minutes('G1', from: monday, to: sunday), 45);
    expect(r.goals.minutes('G2', from: monday, to: sunday), 60);
    expect(r.goals.sessions('G1', from: monday, to: sunday), 1);
  });

  test('a longer block counts its whole length', () {
    final r = makeRepos();
    block(r, goal: 'G1', day: monday, from: 480, to: 720);
    expect(r.goals.minutes('G1', from: monday, to: monday), 240);
  });

  test('a block that runs past midnight counts on its start day with its '
      'whole length', () {
    final r = makeRepos();
    r.events.save(
      EventItem(
        id: 'N',
        title: 'Night',
        start: const WallTime(day: sunday, minute: 1380),
        end: WallTime(day: sunday.adding(days: 1), minute: 60),
        kind: EventKind.block,
        goalId: 'G1',
        color: 'accent',
      ),
    );
    expect(r.goals.minutes('G1', from: monday, to: sunday), 120);
    expect(
      r.goals.minutes(
        'G1',
        from: sunday.adding(days: 1),
        to: sunday.adding(days: 7),
      ),
      0,
    );
    expect(r.goals.sessions('G1', from: monday, to: sunday), 1);
  });

  test('deleting a goal keeps its blocks as plain blocks', () {
    final r = makeRepos();
    r.goals.upsert(GoalItem(id: 'G1', title: 'Read'));
    r.goals.upsert(GoalItem(id: 'G2', title: 'Run'));
    block(r, goal: 'G1', day: monday, done: true, id: 'E1');
    block(r, goal: 'G1', day: monday, id: 'E2');
    block(r, goal: 'G2', day: monday, done: true, id: 'E3');
    r.goals.delete('G1');
    expect(r.goals.get('G1'), isNull);
    for (final id in ['E1', 'E2']) {
      final e = r.events.get(id)!;
      expect(e.goalId, isNull);
      expect(e.doneAt, isNull);
      expect(e.kind, EventKind.block);
    }
    expect(r.events.get('E3')?.goalId, 'G2');
    expect(r.goals.minutes('G1', from: monday, to: sunday), 0);
    expect(r.goals.minutes('G2', from: monday, to: sunday), 60);
  });

  test('upgrading a version 4 database keeps its data', () {
    final dir = tempDir('grove-m5-');
    final path = oldDatabase(
      dir,
      4,
      'INSERT INTO tasks (id, title, notes, created_at, updated_at) VALUES '
      "('t1', 'Old task', 'body', '2026-10-01T09:00:00', "
      "'2026-10-01T09:00:00');"
      'INSERT INTO events (id, title, start, end, kind, task_id, '
      "created_at, updated_at) VALUES ('e1', 'Old block', "
      "'2026-10-01T09:00', '2026-10-01T10:00', 'block', 't1', "
      "'2026-10-01T09:00:00', '2026-10-01T09:00:00');",
    );
    final r = Repos(Database.open(path));
    expect(r.db.userVersion, Migrations.all.length);
    expect(r.tasks.get('t1')?.title, 'Old task');
    final old = r.events.get('e1')!;
    expect(old.title, 'Old block');
    expect(old.taskId, 't1');
    expect(old.goalId, isNull);
    expect(old.doneAt, isNull);
    expect(r.goals.all(), isEmpty);
    r.goals.upsert(GoalItem(id: 'g1', title: 'Read'));
    expect(r.goals.get('g1')?.title, 'Read');
    r.db.close();
  });

  test('upgrading a version 5 database makes the old goals hour goals', () {
    final dir = tempDir('grove-m6-');
    final path = oldDatabase(
      dir,
      5,
      'INSERT INTO goals (id, title, target_min, created_at, updated_at) '
      "VALUES ('g1', 'Read', 360, '2026-10-01T09:00:00', "
      "'2026-10-01T09:00:00');",
    );
    final r = Repos(Database.open(path));
    expect(r.db.userVersion, Migrations.all.length);
    final g = r.goals.get('g1')!;
    expect(g.title, 'Read');
    expect(g.kind, GoalKind.hours);
    expect(g.targetMin, 360);
    expect(g.targetCount, 3);
    r.db.close();
  });
}
