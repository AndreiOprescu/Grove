// Port of Tests/GroveCoreTests/RollOverTests.swift.
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/event.dart';
import 'package:grove/core/model/task.dart';
import 'package:grove/data/data.dart';

import 'helpers.dart';

const today = DayKey('2026-10-05');
final yesterday = today.adding(days: -1);

/// An open task planned for [day] with one block at [minute].
({TaskItem task, EventItem block}) plan(
  Repos r,
  String title, {
  required DayKey day,
  int minute = 540,
  int length = 60,
  TaskStatus status = TaskStatus.open,
}) {
  final t = TaskItem(
    title: title,
    status: status,
    bucket: TaskBucket.day,
    planDate: day,
  );
  r.tasks.save(t);
  final b = EventItem(
    title: title,
    start: WallTime(day: day, minute: minute),
    end: WallTime(day: day, minute: minute + length),
    kind: EventKind.block,
    taskId: t.id,
  );
  r.events.save(b);
  return (task: t, block: b);
}

void main() {
  test('an open task with a block yesterday is offered', () {
    final r = makeRepos();
    final p = plan(r, 'Write report', day: yesterday);
    final items = RollOver.items(r, today: today);
    expect(items.map((i) => i.task.id), [p.task.id]);
    expect(items.first.blocks.map((b) => b.id), [p.block.id]);
  });

  test('done and cancelled tasks are not offered', () {
    final r = makeRepos();
    plan(r, 'Done one', day: yesterday, status: TaskStatus.done);
    plan(r, 'Dropped one', day: yesterday, status: TaskStatus.cancelled);
    expect(RollOver.items(r, today: today), isEmpty);
  });

  test('a plain event is not offered', () {
    final r = makeRepos();
    r.events.save(
      EventItem(
        title: 'Dentist',
        start: WallTime(day: yesterday, minute: 600),
        end: WallTime(day: yesterday, minute: 660),
      ),
    );
    expect(RollOver.items(r, today: today), isEmpty);
  });

  test('only yesterday counts', () {
    final r = makeRepos();
    plan(r, 'Two days ago', day: today.adding(days: -2));
    plan(r, 'Today', day: today);
    plan(r, 'Tomorrow', day: today.adding(days: 1));
    expect(RollOver.items(r, today: today), isEmpty);
  });

  test('two blocks of one task make one item', () {
    final r = makeRepos();
    final p = plan(r, 'Big job', day: yesterday);
    final second = EventItem(
      title: 'Big job',
      start: WallTime(day: yesterday, minute: 840),
      end: WallTime(day: yesterday, minute: 900),
      kind: EventKind.block,
      taskId: p.task.id,
    );
    r.events.save(second);
    final items = RollOver.items(r, today: today);
    expect(items.length, 1);
    expect(items.first.blocks.map((b) => b.id), [p.block.id, second.id]);
  });

  test('items come in the order of their first block', () {
    final r = makeRepos();
    plan(r, 'Late', day: yesterday, minute: 900);
    plan(r, 'Early', day: yesterday, minute: 480);
    expect(RollOver.items(r, today: today).map((i) => i.task.title), [
      'Early',
      'Late',
    ]);
  });

  test('a block on the day before is found by its start day', () {
    final r = makeRepos();
    // Ends at midnight: it touches today's first minute but it started
    // yesterday.
    final t = TaskItem(
      title: 'Night owl',
      bucket: TaskBucket.day,
      planDate: yesterday,
    );
    r.tasks.save(t);
    r.events.save(
      EventItem(
        title: 'Night owl',
        start: WallTime(day: yesterday, minute: 1380),
        end: const WallTime(day: today, minute: 0),
        kind: EventKind.block,
        taskId: t.id,
      ),
    );
    expect(RollOver.items(r, today: today).map((i) => i.task.id), [t.id]);
    expect(RollOver.items(r, today: today.adding(days: 1)), isEmpty);
  });

  test('after an answer the card is handled for that day only', () {
    final r = makeRepos();
    expect(RollOver.isHandled(r, today: today), isFalse);
    RollOver.markHandled(r, today: today);
    expect(RollOver.isHandled(r, today: today), isTrue);
    expect(RollOver.isHandled(r, today: today.adding(days: 1)), isFalse);
  });
}
