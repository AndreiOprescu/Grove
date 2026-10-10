// Port of Tests/GroveTests/RollOverStoreTests.swift.
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const today = DayKey('2026-10-05');
final yesterday = today.adding(days: -1);

AppStore store() => makeStore(
  notifier: FakeNotifier(),
  clock: const WallTime(day: today, minute: 8 * 60),
);

({TaskItem task, EventItem block}) plan(
  AppStore s,
  String title, {
  int minute = 540,
}) {
  final t = TaskItem(title: title, bucket: TaskBucket.day, planDate: yesterday);
  s.repos.tasks.save(t);
  final b = EventItem(
    title: title,
    start: WallTime(day: yesterday, minute: minute),
    end: WallTime(day: yesterday, minute: minute + 60),
    kind: EventKind.block,
    taskId: t.id,
  );
  s.repos.events.save(b);
  return (task: t, block: b);
}

void main() {
  test('the card lists open blocks from yesterday', () {
    final s = store();
    plan(s, 'Write report');
    expect([for (final i in s.rollOverItems()) i.task.title], ['Write report']);
  });

  test('no blocks yesterday means no card', () {
    final s = store();
    expect(s.rollOverItems(), isEmpty);
  });

  test('move sends the tasks to today and takes the blocks away', () {
    final s = store();
    final p = plan(s, 'Write report');
    s.moveRollOver();
    final t = s.task(p.task.id)!;
    expect(t.bucket, TaskBucket.day);
    expect(t.planDate, today);
    expect(s.blocksOfTask(p.task.id), isEmpty); // it is a sticky note now
    expect(s.rollOverItems(), isEmpty);
  });

  test('move leaves the task no block at all', () {
    final s = store();
    final p = plan(s, 'Write report');
    // A second block of the same task, on another day, goes too.
    s.repos.events.save(
      s.blockEvent(p.task, day: today.adding(days: 2), start: 600, end: 660),
    );
    s.moveRollOver();
    expect(s.blocksOfTask(p.task.id), isEmpty);
    expect(s.task(p.task.id)?.planDate, today);
    s.undo();
    expect(s.blocksOfTask(p.task.id).length, 2);
  });

  test('move is one undo step', () {
    final s = store();
    final p = plan(s, 'A');
    plan(s, 'B', minute: 700);
    s.moveRollOver();
    expect(s.undoName, 'Move to Today');
    s.undo();
    expect(s.task(p.task.id)?.planDate, yesterday);
    expect(s.blocksOfTask(p.task.id).length, 1);
    expect(s.repos.tasks.all().length, 2);
  });

  test('leave changes nothing and hides the card', () {
    final s = store();
    final p = plan(s, 'Write report');
    s.leaveRollOver();
    expect(s.task(p.task.id)?.planDate, yesterday);
    expect(s.blocksOfTask(p.task.id).length, 1);
    expect(s.rollOverItems(), isEmpty);
    expect(s.undoName, isNull);
  });

  test('the card stays hidden for the rest of the day', () {
    final s = store();
    plan(s, 'Write report');
    s.leaveRollOver();
    plan(s, 'Another one', minute: 800);
    expect(s.rollOverItems(), isEmpty);
  });

  test('the card comes back on the next day', () {
    final s = store();
    plan(s, 'Write report');
    s.leaveRollOver();
    s.clockOverride = WallTime(day: today.adding(days: 1), minute: 8 * 60);
    // Nothing was planned on the new "yesterday" (today), so there is still
    // nothing to offer.
    expect(s.rollOverItems(), isEmpty);
    s.repos.tasks.save(
      TaskItem(
        id: 'T9',
        title: 'Late',
        bucket: TaskBucket.day,
        planDate: today,
      ),
    );
    s.repos.events.save(
      EventItem(
        title: 'Late',
        start: const WallTime(day: today, minute: 600),
        end: const WallTime(day: today, minute: 660),
        kind: EventKind.block,
        taskId: 'T9',
      ),
    );
    expect([for (final i in s.rollOverItems()) i.task.id], ['T9']);
  });

  test('move skips a task finished since the card was shown', () {
    final s = store();
    final a = plan(s, 'A');
    final b = plan(s, 'B', minute: 700);
    s.toggleDone(taskId: a.task.id);
    s.moveRollOver();
    // Done: left where it was.
    expect(s.task(a.task.id)?.planDate, yesterday);
    expect(s.task(b.task.id)?.planDate, today);
  });
}
