// Port of Tests/GroveTests/PlannerStoreTests.swift.
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Never "today", so "now" does not change the slot math.
final day = DayKey.today().adding(days: 3);
final past = DayKey.today().adding(days: -2);

List<PlannerBlock> on(AppStore s, DayKey d) => s.blocks(DayRange.single(d));

Map<String, PlannerBlock> byTitle(AppStore s) => {
  for (final b in on(s, day)) b.title: b,
};

void draft(
  AppStore s,
  String title,
  int start,
  int end, {
  bool asEvent = true,
  DayKey? on,
}) => s.createFromDraft(
  title: title,
  day: on ?? day,
  start: start,
  end: end,
  asEvent: asEvent,
);

BlockEdit edit(String id, DayKey d, int start, int end) =>
    BlockEdit(id: id, day: d, start: start, end: end);

TaskItem saved(AppStore s, TaskItem t) {
  s.repos.tasks.save(t);
  return t;
}

/// An overdue task with its block on a past day.
({TaskItem task, EventItem block}) overdueTask(AppStore s, {int at = 600}) {
  final t = saved(
    s,
    TaskItem(
      title: 'Late',
      bucket: TaskBucket.day,
      planDate: past,
      estimateMin: 45,
    ),
  );
  final b = s.blockEvent(t, day: past, start: at, end: at + 45);
  s.repos.events.save(b);
  return (task: t, block: b);
}

void addEvent(AppStore s, int start, int end, {DayKey? on}) =>
    draft(s, 'E$start', start, end, on: on);

void nineHours(AppStore s, {DayKey? on}) {
  for (var h = 0; h < 9; h++) {
    addEvent(s, 480 + h * 60, 540 + h * 60, on: on);
  }
}

void main() {
  test('a draft creates a task and a block, and undo removes both', () {
    final s = makeStore();
    draft(s, 'Write report', 600, 660, asEvent: false);
    final blocks = on(s, day);
    expect(blocks.length, 1);
    expect(blocks[0].isTaskBlock, isTrue);
    expect(blocks[0].title, 'Write report');
    expect(blocks[0].startMinute, 600);
    expect(blocks[0].endMinute, 660);
    final task = s.task(blocks[0].taskId!)!;
    expect(task.bucket, TaskBucket.day);
    expect(task.planDate, day);
    expect(task.estimateMin, 60);
    s.undo();
    expect(on(s, day), isEmpty);
    expect(s.repos.tasks.all(), isEmpty);
    s.redo();
    expect(on(s, day).length, 1);
    expect(s.repos.tasks.all().length, 1);
  });

  test('a draft as event makes a plain event', () {
    final s = makeStore();
    draft(s, 'Dentist', 840, 900);
    final b = on(s, day).first;
    expect(b.isTaskBlock, isFalse);
    expect(b.kind, EventKind.event);
    expect(s.repos.tasks.all(), isEmpty);
  });

  test('move and resize are undoable', () {
    final s = makeStore();
    draft(s, 'A', 600, 660);
    final id = on(s, day).first.id;
    s.applyEdits([edit(id, day, 615, 735)], ripple: false, name: 'Move Block');
    expect(on(s, day).first.startMinute, 615);
    expect(on(s, day).first.endMinute, 735);
    s.undo();
    expect(on(s, day).first.startMinute, 600);
    expect(s.undoName, 'New Block');
  });

  test('moving a task block to another day updates the task plan date', () {
    final s = makeStore();
    draft(s, 'T', 600, 630, asEvent: false);
    final b = on(s, day).first;
    final next = day.adding(days: 1);
    s.applyEdits(
      [edit(b.id, next, 600, 630)],
      ripple: false,
      name: 'Move Block',
    );
    expect(on(s, day), isEmpty);
    expect(on(s, next).length, 1);
    final tid = b.taskId!;
    expect(s.task(tid)?.planDate, next);
    s.undo();
    expect(s.task(tid)?.planDate, day);
  });

  test('overlap is allowed', () {
    final s = makeStore();
    draft(s, 'A', 600, 660);
    draft(s, 'B', 630, 690);
    expect(on(s, day).length, 2);
  });

  test('ripple pushes later blocks', () {
    final s = makeStore();
    draft(s, 'A', 600, 660);
    draft(s, 'B', 660, 720);
    draft(s, 'C', 720, 780);
    final a = byTitle(s)['A']!;
    final pushed = s.applyEdits(
      [edit(a.id, day, 600, 690)],
      ripple: true,
      name: 'Resize Block',
    );
    expect(pushed, 2);
    final now = byTitle(s);
    expect(now['B']?.startMinute, 690);
    expect(now['B']?.endMinute, 750);
    expect(now['C']?.startMinute, 750);
    expect(now['C']?.endMinute, 810);
    s.undo(); // One undo step reverts the resize and the push together.
    final after = byTitle(s);
    expect(after['A']?.endMinute, 660);
    expect(after['B']?.startMinute, 660);
    expect(after['C']?.startMinute, 720);
  });

  test('unschedule keeps the task and returns it to the tray', () {
    final s = makeStore();
    draft(s, 'Read', 600, 630, asEvent: false);
    expect(s.unscheduled(day), isEmpty);
    final b = on(s, day).first;
    s.deleteBlocks([b.id], name: 'Unschedule');
    expect(on(s, day), isEmpty);
    expect(titles(s.unscheduled(day)), ['Read']);
  });

  test('a task dropped from the tray uses its estimate', () {
    final s = makeStore();
    final t = saved(s, TaskItem(title: 'Email', estimateMin: 45));
    s.schedule(taskId: t.id, day: day, start: 540);
    final b = on(s, day).first;
    expect(b.startMinute, 540);
    expect(b.length, 45);
    final task = s.task(t.id)!;
    expect(task.bucket, TaskBucket.day);
    expect(task.planDate, day);
  });

  group('one block per task', () {
    test('scheduling twice leaves one block at the new time', () {
      final s = makeStore();
      final t = saved(s, TaskItem(title: 'Email', estimateMin: 45));
      final next = day.adding(days: 1);
      s.schedule(taskId: t.id, day: day, start: 540);
      s.schedule(taskId: t.id, day: next, start: 780);
      final blocks = s.blocksOfTask(t.id);
      expect(blocks.length, 1);
      expect(blocks[0].start, WallTime(day: next, minute: 780));
      expect(blocks[0].end, WallTime(day: next, minute: 825));
      expect(on(s, day), isEmpty);
      expect(s.task(t.id)?.planDate, next);
    });

    test('scheduling again on the same day moves the block', () {
      final s = makeStore();
      final t = saved(s, TaskItem(title: 'Email', estimateMin: 45));
      s.schedule(taskId: t.id, day: day, start: 540);
      s.schedule(taskId: t.id, day: day, start: 900);
      expect([for (final b in s.blocksOfTask(t.id)) b.start.minute], [900]);
    });

    test('dropping an overdue task sets the new day and removes its old '
        'block', () {
      final s = makeStore();
      final (task: t, block: old) = overdueTask(s);
      expect(ids(s.unscheduledTasks().overdue), [t.id]);
      s.schedule(taskId: t.id, day: day, start: 540);
      final task = s.task(t.id)!;
      expect(task.bucket, TaskBucket.day);
      expect(task.planDate, day);
      final blocks = s.blocksOfTask(t.id);
      expect(blocks.length, 1);
      expect(blocks[0].start, WallTime(day: day, minute: 540));
      expect(blocks[0].id, isNot(old.id));
      expect(on(s, past), isEmpty);
      expect(s.unscheduledTasks().overdue, isEmpty);
    });

    test('one undo brings back the old block and the old plan date', () {
      final s = makeStore();
      final (task: t, block: old) = overdueTask(s);
      s.schedule(taskId: t.id, day: day, start: 540);
      expect(s.undoName, 'Schedule Task');
      s.undo();
      expect(s.task(t.id)?.planDate, past);
      expect(s.blocksOfTask(t.id), [old]);
      expect(on(s, day), isEmpty);
      s.redo();
      expect(s.task(t.id)?.planDate, day);
      expect(
        [for (final b in s.blocksOfTask(t.id)) b.start],
        [WallTime(day: day, minute: 540)],
      );
    });

    test('a drop on the day strip plans the day with no time and removes '
        'the old block', () {
      final s = makeStore();
      final t = overdueTask(s).task;
      s.dropTask(t.id, on: day);
      final task = s.task(t.id)!;
      expect(task.bucket, TaskBucket.day);
      expect(task.planDate, day);
      expect(s.blocksOfTask(t.id), isEmpty);
      expect(ids(s.timeless([day])[day]!), [t.id]);
    });

    test('a drop on the strip of the same day still removes the block', () {
      final s = makeStore();
      final t = saved(s, TaskItem(title: 'Email', estimateMin: 45));
      s.schedule(taskId: t.id, day: day, start: 540);
      s.dropTask(t.id, on: day);
      expect(s.blocksOfTask(t.id), isEmpty);
      expect(s.task(t.id)?.planDate, day);
    });

    test('a strip drop is one undo step that brings back the block', () {
      final s = makeStore();
      final (task: t, block: old) = overdueTask(s);
      s.dropTask(t.id, on: day);
      s.undo();
      expect(s.task(t.id)?.planDate, past);
      expect(s.blocksOfTask(t.id), [old]);
    });

    test('moving a task from a menu still carries its block along', () {
      final s = makeStore();
      final t = overdueTask(s).task;
      s.moveTask(t.id, to: TaskPlacement.day(day));
      final blocks = s.blocksOfTask(t.id);
      expect(blocks.length, 1);
      expect(blocks[0].start, WallTime(day: day, minute: 600));
    });

    test('fit replaces the old block', () {
      final s = makeStore();
      final t = overdueTask(s).task;
      s.fit(taskId: t.id, day: day, workStart: 540, workEnd: 1020, step: 15);
      final blocks = s.blocksOfTask(t.id);
      expect(blocks.length, 1);
      expect(blocks[0].start, WallTime(day: day, minute: 540));
      expect(on(s, past), isEmpty);
      expect(s.task(t.id)?.planDate, day);
    });

    test("fit does not count the task's own block on that day as busy", () {
      final s = makeStore();
      final t = saved(s, TaskItem(title: 'Email', estimateMin: 45));
      s.schedule(taskId: t.id, day: day, start: 540);
      s.fit(taskId: t.id, day: day, workStart: 540, workEnd: 1020, step: 15);
      expect([for (final b in s.blocksOfTask(t.id)) b.start.minute], [540]);
    });

    test('plan my day replaces the old blocks of its tasks', () {
      final s = makeStore();
      final a = overdueTask(s).task;
      final b = saved(s, TaskItem(title: 'Fresh', estimateMin: 30));
      s.applyPlan([(task: a, start: 540), (task: b, start: 600)], day: day);
      expect(
        [for (final x in s.blocksOfTask(a.id)) x.start],
        [WallTime(day: day, minute: 540)],
      );
      expect(
        [for (final x in s.blocksOfTask(b.id)) x.start],
        [WallTime(day: day, minute: 600)],
      );
      expect(on(s, past), isEmpty);
      s.undo();
      expect([for (final x in s.blocksOfTask(a.id)) x.start.day], [past]);
      expect(s.blocksOfTask(b.id), isEmpty);
    });
  });

  test('a short estimate makes a block of at least fifteen minutes', () {
    final s = makeStore();
    final short = saved(s, TaskItem(title: 'Call', estimateMin: 10));
    final odd = saved(s, TaskItem(title: 'Tidy', estimateMin: 20));
    s.schedule(taskId: short.id, day: day, start: 540);
    s.schedule(taskId: odd.id, day: day, start: 600);
    expect(byTitle(s)['Call']?.length, 15);
    expect(byTitle(s)['Tidy']?.length, 30);
  });

  test('timeless tasks are the day tasks with no block', () {
    final s = makeStore();
    final next = day.adding(days: 1);
    TaskItem dayTask(
      String title, {
      int priority = 0,
      TaskStatus status = TaskStatus.open,
      String? parentId,
      DayKey? on,
    }) => TaskItem(
      title: title,
      priority: priority,
      status: status,
      parentId: parentId,
      bucket: TaskBucket.day,
      planDate: on ?? day,
    );
    final free = dayTask('Free');
    final blocked = dayTask('Blocked');
    for (final t in [
      free,
      dayTask('Urgent', priority: 3),
      blocked,
      dayTask('Done', status: TaskStatus.done),
      dayTask('Sub', parentId: free.id),
      dayTask('Tomorrow', on: next),
      TaskItem(
        title: 'Week',
        bucket: TaskBucket.week,
        planWeek: day.weekStart(),
      ),
      TaskItem(title: 'Inbox'),
    ]) {
      s.repos.tasks.save(t);
    }
    s.schedule(taskId: blocked.id, day: day, start: 600);

    final map = s.timeless([day, next]);
    expect(titles(map[day]!), ['Urgent', 'Free']);
    expect(titles(map[next]!), ['Tomorrow']);

    // A block on another day does not give the task a time today.
    s.schedule(taskId: free.id, day: next, start: 600);
    expect(titles(s.timeless([day])[day]!), ['Urgent']);
  });

  test('a block shorter than half an hour cannot split', () {
    final s = makeStore();
    draft(s, 'Short', 600, 615);
    s.split(blockId: on(s, day).first.id);
    expect(on(s, day).length, 1);
    draft(s, 'Half', 700, 730);
    s.split(blockId: byTitle(s)['Half']!.id);
    final parts = [
      for (final b in on(s, day))
        if (b.title == 'Half') [b.startMinute, b.endMinute],
    ]..sort((a, b) => a[0].compareTo(b[0]));
    expect(parts, [
      [700, 715],
      [715, 730],
    ]);
  });

  test('fit uses the first free gap', () {
    final s = makeStore();
    draft(s, 'Busy', 540, 600);
    final t = saved(s, TaskItem(title: 'Fit me', estimateMin: 30));
    s.fit(taskId: t.id, day: day, workStart: 540, workEnd: 1080, step: 5);
    final placed = on(s, day).firstWhere((b) => b.taskId == t.id);
    expect(placed.startMinute, 600);
  });

  test('plan my day orders by priority', () {
    final s = makeStore();
    TaskItem dayTask(String title, int priority, int estimate) => TaskItem(
      title: title,
      priority: priority,
      bucket: TaskBucket.day,
      planDate: day,
      estimateMin: estimate,
    );
    saved(s, dayTask('low', 1, 60));
    saved(s, dayTask('high', 3, 30));
    final plan = s.planMyDayPreview(
      day: day,
      workStart: 540,
      workEnd: 1080,
      step: 5,
    );
    expect([for (final p in plan) p.task.title], ['high', 'low']);
    expect([for (final p in plan) p.start], [540, 570]);
    s.applyPlan(plan, day: day);
    expect(on(s, day).length, 2);
    s.undo();
    expect(on(s, day), isEmpty);
  });

  test('duplicate, split and duration', () {
    final s = makeStore();
    draft(s, 'A', 600, 660);
    final a = on(s, day).first;
    s.duplicate(blockIds: [a.id]);
    expect([for (final b in on(s, day)) b.startMinute]..sort(), [600, 660]);
    s.split(blockId: a.id);
    expect(on(s, day).length, 3);
    s.setDuration(blockIds: [a.id], minutes: 15);
    expect(on(s, day).firstWhere((b) => b.id == a.id).length, 15);
  });

  test('completing a task marks its block done', () {
    final s = makeStore();
    draft(s, 'Do it', 600, 630, asEvent: false);
    final tid = on(s, day).first.taskId!;
    s.toggleDone(taskId: tid);
    expect(on(s, day).first.isDone, isTrue);
    s.undo();
    expect(on(s, day).first.isDone, isFalse);
  });

  test('a block that ends at midnight round trips', () {
    final s = makeStore();
    draft(s, 'Late', 1380, 1440);
    expect(on(s, day).first.endMinute, 1440);
  });

  group('busy-day alert', () {
    test('planned minutes count overlaps once', () {
      final s = makeStore();
      addEvent(s, 600, 720);
      addEvent(s, 660, 780); // overlaps 60 min
      expect(s.plannedMinutes(day), 180);
    });

    test('no alert at exactly nine hours', () {
      final s = makeStore();
      nineHours(s);
      expect(s.plannedMinutes(day), 540);
      expect(s.overloadWarning, isNull);
    });

    test('alert when the day passes nine hours', () {
      final s = makeStore();
      nineHours(s);
      addEvent(s, 1020, 1050); // 9h30m
      expect(s.overloadWarning, contains('9h 30m'));
    });

    test('alert only when crossing, not while already over', () {
      final s = makeStore();
      nineHours(s);
      addEvent(s, 1020, 1050);
      s.overloadWarning = null; // The person dismissed it.
      addEvent(s, 1100, 1130); // Still over: no new alert.
      expect(s.overloadWarning, isNull);
    });

    test('moving a block to another day can trigger the alert', () {
      final s = makeStore();
      final next = day.adding(days: 1);
      nineHours(s, on: next);
      addEvent(s, 1200, 1230);
      final b = on(s, day).first;
      s.applyEdits(
        [edit(b.id, next, 1200, 1230)],
        ripple: false,
        name: 'Move Block',
      );
      expect(s.overloadWarning, isNotNull);
    });

    test('undo does not alert', () {
      final s = makeStore();
      nineHours(s);
      addEvent(s, 1020, 1050);
      s.overloadWarning = null;
      s.undo();
      s.redo();
      expect(s.overloadWarning, isNull);
    });
  });
}
