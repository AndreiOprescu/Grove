// Port of Tests/GroveTests/TaskStoreTests.swift.
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final today = DayKey.today();

/// A Monday two weeks ahead, never today.
final monday = today.weekStart().adding(days: 14);

List<String> order(AppStore s, TaskPlacement placement) =>
    titles(s.openTasks(placement));

List<PlannerBlock> blocksOn(AppStore s, DayKey day) =>
    s.blocks(DayRange.single(day));

TaskItem repeatingTask(AppStore s) {
  final t = TaskItem(
    title: 'Gym',
    bucket: TaskBucket.day,
    planDate: monday,
    estimateMin: 60,
    recurrence: RecurrenceRule(freq: Freq.weekly, weekdays: [1]),
    notes: 'bring towel',
  );
  s.repos.tasks.save(t);
  s.repos.tasks.save(
    TaskItem(title: 'Pack bag', parentId: t.id, status: TaskStatus.done),
  );
  s.repos.tasks.save(TaskItem(title: 'Fill bottle', parentId: t.id));
  s.repos.events.save(
    EventItem(
      title: 'Gym',
      start: WallTime(day: monday, minute: 420),
      end: WallTime(day: monday, minute: 480),
      kind: EventKind.block,
      taskId: t.id,
    ),
  );
  return t;
}

void main() {
  group('quick add', () {
    test('quick add makes task and block, and undo removes all', () {
      final s = makeStore();
      s.repos.lists.save(ListItem(name: 'Home'));
      final t = s.quickAdd('Call mum tomorrow 6pm for 20m #home /home !2')!;
      final tomorrow = today.adding(days: 1);
      final task = s.task(t.id)!;
      expect(task.title, 'Call mum');
      expect(task.bucket, TaskBucket.day);
      expect(task.planDate, tomorrow);
      expect(task.priority, 2);
      expect(task.estimateMin, 20);
      expect(
        task.listId,
        s.repos.lists.all().firstWhere((l) => l.name == 'Home').id,
      );
      expect(s.repos.tags.tagsForTask(t.id), ['home']);
      final block = blocksOn(s, tomorrow).first;
      expect(block.taskId, t.id);
      expect(block.startMinute, 18 * 60);
      expect(block.endMinute, 18 * 60 + 20);

      s.undo();
      expect(s.repos.tasks.all(), isEmpty);
      expect(blocksOn(s, tomorrow), isEmpty);
      expect(s.repos.tags.tagsForTask(t.id), isEmpty);
      s.redo();
      expect(s.repos.tags.tagsForTask(t.id), ['home']);
      expect(blocksOn(s, tomorrow).length, 1);
    });

    test('quick add without a date uses the default placement', () {
      final s = makeStore();
      final a = s.quickAdd('Buy milk', placement: TaskPlacement.day(monday))!;
      expect(s.task(a.id)?.bucket, TaskBucket.day);
      expect(s.task(a.id)?.planDate, monday);
      final b = s.quickAdd('Learn piano', placement: TaskPlacement.someday)!;
      expect(s.task(b.id)?.bucket, TaskBucket.someday);
      final c = s.quickAdd('Plan trip', placement: TaskPlacement.week(monday))!;
      expect(s.task(c.id)?.bucket, TaskBucket.week);
      expect(s.task(c.id)?.planWeek, monday);
      final e = s.quickAdd('Sort mail')!;
      expect(s.task(e.id)?.bucket, TaskBucket.inbox);
    });

    test('a date in the text beats the default placement', () {
      final s = makeStore();
      final t = s.quickAdd(
        'Read ch 5 next week',
        placement: TaskPlacement.someday,
      )!;
      expect(s.task(t.id)?.bucket, TaskBucket.week);
      expect(s.task(t.id)?.planWeek, today.weekStart().adding(days: 7));
    });

    test('empty text makes nothing', () {
      final s = makeStore();
      expect(s.quickAdd('   '), isNull);
      expect(s.repos.tasks.all(), isEmpty);
      expect(s.undoName, isNull);
    });

    test('new tasks go to the end of the list', () {
      final s = makeStore();
      s.quickAdd('One');
      s.quickAdd('Two');
      s.quickAdd('Three');
      expect(order(s, TaskPlacement.inbox), ['One', 'Two', 'Three']);
    });
  });

  group('completing and repeating', () {
    test('completing a repeating task makes the next one', () {
      final s = makeStore();
      final t = repeatingTask(s);
      s.toggleDone(taskId: t.id);
      expect(s.task(t.id)?.isDone, isTrue);

      final nextDay = monday.adding(days: 7);
      final nexts = s.repos.tasks.forDay(nextDay);
      expect(nexts.length, 1);
      final next = nexts.first;
      expect(next.id, isNot(t.id));
      expect(next.title, 'Gym');
      expect(next.status, TaskStatus.open);
      expect(next.notes, 'bring towel');
      expect(next.recurrence, t.recurrence);
      final subs = s.repos.tasks.subtasks(next.id);
      expect(titles(subs)..sort(), ['Fill bottle', 'Pack bag']);
      expect(subs.every((x) => x.status == TaskStatus.open), isTrue);
      final block = blocksOn(s, nextDay).first;
      expect(block.taskId, next.id);
      expect(block.startMinute, 420);
      expect(block.endMinute, 480);
      // The finished one keeps its own block.
      expect(blocksOn(s, monday).length, 1);

      s.undo();
      expect(s.task(t.id)?.isDone, isFalse);
      expect(s.repos.tasks.forDay(nextDay), isEmpty);
      expect(blocksOn(s, nextDay), isEmpty);
    });

    test('a late repeating task never gets a date in the past', () {
      final s = makeStore();
      final t = TaskItem(
        title: 'Water plants',
        bucket: TaskBucket.day,
        planDate: today.adding(days: -10),
        recurrence: RecurrenceRule(freq: Freq.daily),
      );
      s.repos.tasks.save(t);
      s.toggleDone(taskId: t.id);
      final next = s.repos.tasks.all().firstWhere((x) => x.id != t.id);
      expect(next.planDate, today.adding(days: 1));
    });

    test('a plain task makes no copy', () {
      final s = makeStore();
      final t = s.quickAdd('One-off')!;
      s.toggleDone(taskId: t.id);
      expect(s.repos.tasks.all().length, 1);
      s.toggleDone(taskId: t.id);
      expect(s.task(t.id)?.isDone, isFalse);
      expect(s.task(t.id)?.completedAt, isNull);
    });

    test('reopening a repeating task does not make another copy', () {
      final s = makeStore();
      final t = repeatingTask(s);
      s.toggleDone(taskId: t.id);
      final after = s.repos.tasks.all().length;
      s.toggleDone(taskId: t.id); // reopen
      expect(s.repos.tasks.all().length, after);
    });
  });

  group('subtasks, edit, tags', () {
    test('add subtask', () {
      final s = makeStore();
      final t = s.quickAdd('Trip')!;
      s.addSubtask(to: t.id, title: '  Book hotel ');
      s.addSubtask(to: t.id, title: '   ');
      expect(titles(s.repos.tasks.subtasks(t.id)), ['Book hotel']);
      s.undo();
      expect(s.repos.tasks.subtasks(t.id), isEmpty);
    });

    test('edit task is undoable', () {
      final s = makeStore();
      final t = s.quickAdd('Draft')!;
      s.editTask(
        t.id,
        (x) => x.copyWith(title: 'Final', priority: 3),
        name: 'Edit Task',
      );
      expect(s.task(t.id)?.title, 'Final');
      expect(s.task(t.id)?.priority, 3);
      expect(s.undoName, 'Edit Task');
      s.undo();
      expect(s.task(t.id)?.title, 'Draft');
      expect(s.task(t.id)?.priority, 0);
    });

    test('set tags is undoable', () {
      final s = makeStore();
      final t = s.quickAdd('Tagged #a')!;
      s.setTags(taskId: t.id, to: ['b', 'c']);
      expect(s.repos.tags.tagsForTask(t.id), ['b', 'c']);
      s.undo();
      expect(s.repos.tags.tagsForTask(t.id), ['a']);
    });
  });

  group('moving and reordering', () {
    test('moving to another day shifts its blocks; undo puts them back', () {
      final s = makeStore();
      final t = s.quickAdd('Write', placement: TaskPlacement.day(monday))!;
      s.schedule(taskId: t.id, day: monday, start: 600, length: 60);
      final other = monday.adding(days: 1);
      s.moveTask(t.id, to: TaskPlacement.day(other));
      expect(s.task(t.id)?.planDate, other);
      final b = blocksOn(s, other).first;
      expect(b.startMinute, 600);
      expect(b.endMinute, 660);
      expect(blocksOn(s, monday), isEmpty);
      s.undo();
      expect(s.task(t.id)?.planDate, monday);
      expect(blocksOn(s, monday).length, 1);
      expect(blocksOn(s, other), isEmpty);
    });

    test('moving off the calendar removes blocks', () {
      final s = makeStore();
      final t = s.quickAdd('Write', placement: TaskPlacement.day(monday))!;
      s.schedule(taskId: t.id, day: monday, start: 600, length: 60);
      s.moveTask(t.id, to: TaskPlacement.someday);
      expect(s.task(t.id)?.bucket, TaskBucket.someday);
      expect(s.task(t.id)?.planDate, isNull);
      expect(blocksOn(s, monday), isEmpty);
      s.undo();
      expect(blocksOn(s, monday).length, 1);
      expect(s.task(t.id)?.bucket, TaskBucket.day);
    });

    test('moving to a week sets the Monday', () {
      final s = makeStore();
      final t = s.quickAdd('Plan')!;
      s.moveTask(t.id, to: TaskPlacement.week(monday.adding(days: 3)));
      expect(s.task(t.id)?.bucket, TaskBucket.week);
      expect(s.task(t.id)?.planWeek, monday);
      expect(s.task(t.id)?.planDate, isNull);
    });

    test('reorder puts a task before another', () {
      final s = makeStore();
      s.quickAdd('A');
      s.quickAdd('B');
      final c = s.quickAdd('C')!;
      final a = s.openTasks(TaskPlacement.inbox).first;
      s.moveTask(c.id, to: TaskPlacement.inbox, before: a.id);
      expect(order(s, TaskPlacement.inbox), ['C', 'A', 'B']);
      s.moveTask(c.id, to: TaskPlacement.inbox); // to the end
      expect(order(s, TaskPlacement.inbox), ['A', 'B', 'C']);
      s.undo();
      expect(order(s, TaskPlacement.inbox), ['C', 'A', 'B']);
    });

    test('reorder works when all sort values are equal', () {
      final s = makeStore();
      for (final name in ['A', 'B', 'C']) {
        s.repos.tasks.save(TaskItem(title: name));
      }
      final first = s.openTasks(TaskPlacement.inbox).first;
      final last = s.openTasks(TaskPlacement.inbox).last;
      s.moveTask(last.id, to: TaskPlacement.inbox, before: first.id);
      expect(order(s, TaskPlacement.inbox), ['C', 'A', 'B']);
    });

    test('a drop between two tasks keeps the others untouched', () {
      final s = makeStore();
      s.quickAdd('A');
      s.quickAdd('B');
      s.quickAdd('C');
      final dd = s.quickAdd('D')!;
      final b = s
          .openTasks(TaskPlacement.inbox)
          .firstWhere((t) => t.title == 'B');
      final before = {
        for (final t in s.openTasks(TaskPlacement.inbox)) t.id: t.sort,
      };
      s.moveTask(dd.id, to: TaskPlacement.inbox, before: b.id);
      expect(order(s, TaskPlacement.inbox), ['A', 'D', 'B', 'C']);
      for (final t in s.openTasks(TaskPlacement.inbox)) {
        if (t.id != dd.id) expect(before[t.id], t.sort);
      }
    });

    test('moving from another list lands at the drop position', () {
      final s = makeStore();
      final x = s.quickAdd('X', placement: TaskPlacement.someday)!;
      s.quickAdd('A');
      s.quickAdd('B');
      final b = s
          .openTasks(TaskPlacement.inbox)
          .firstWhere((t) => t.title == 'B');
      s.moveTask(x.id, to: TaskPlacement.inbox, before: b.id);
      expect(order(s, TaskPlacement.inbox), ['A', 'X', 'B']);
      expect(order(s, TaskPlacement.someday), isEmpty);
    });
  });

  group('deleting', () {
    test('deleting a task takes its subtasks and blocks; undo brings them '
        'all back', () {
      final s = makeStore();
      final t = s.quickAdd(
        'Trip #travel',
        placement: TaskPlacement.day(monday),
      )!;
      s.addSubtask(to: t.id, title: 'Book hotel');
      s.schedule(taskId: t.id, day: monday, start: 540, length: 30);
      s.deleteTask(t.id);
      expect(s.repos.tasks.all(), isEmpty);
      expect(blocksOn(s, monday), isEmpty);
      s.undo();
      expect(s.repos.tasks.all().length, 2);
      expect(titles(s.repos.tasks.subtasks(t.id)), ['Book hotel']);
      expect(blocksOn(s, monday).length, 1);
      expect(s.repos.tags.tagsForTask(t.id), ['travel']);
      s.redo();
      expect(s.repos.tasks.all(), isEmpty);
    });

    test('deleting the open task closes its panel', () {
      final s = makeStore();
      final t = s.quickAdd('Trip', placement: TaskPlacement.day(monday))!;
      final other = s.quickAdd('Other', placement: TaskPlacement.day(monday))!;
      s.selectedTaskId = t.id;
      s.deleteTask(other.id);
      expect(s.selectedTaskId, t.id);
      s.deleteTask(t.id);
      expect(s.selectedTaskId, isNull);
    });

    test('deleting a parent closes the open subtask and drops its selected '
        'blocks', () {
      final s = makeStore();
      final t = s.quickAdd('Trip', placement: TaskPlacement.day(monday))!;
      s.addSubtask(to: t.id, title: 'Book hotel');
      final sub = s.repos.tasks.subtasks(t.id).first;
      s.schedule(taskId: t.id, day: monday, start: 540, length: 30);
      final block = blocksOn(s, monday).first;
      s.selectedTaskId = sub.id;
      s.selection = {block.id};
      s.deleteTask(t.id);
      expect(s.selectedTaskId, isNull);
      expect(s.selection, isEmpty);
    });
  });

  group('mentions', () {
    test('body mentions become links and renames follow', () {
      final s = makeStore();
      final target = s.quickAdd('Old title')!;
      final host = s.quickAdd('Host')!;
      s.editTask(
        host.id,
        (x) => x.copyWith(notes: 'needs [[old TITLE]]'),
        name: 'Edit Notes',
      );
      expect(s.task(host.id)?.notes, 'needs [[Old title|${target.id}]]');
      expect(s.repos.links.backlinks(ItemRef(ItemType.task, target.id)), [
        ItemRef(ItemType.task, host.id),
      ]);

      s.editTask(
        target.id,
        (x) => x.copyWith(title: 'Fresh title'),
        name: 'Rename Task',
      );
      expect(s.task(host.id)?.notes, 'needs [[Fresh title|${target.id}]]');
      s.undo();
      expect(s.task(host.id)?.notes, 'needs [[Old title|${target.id}]]');
      s.redo();
      expect(s.task(host.id)?.notes, 'needs [[Fresh title|${target.id}]]');
    });

    test('undoing a delete brings incoming links back', () {
      final s = makeStore();
      final target = s.quickAdd('Target')!;
      final host = s.quickAdd('Host')!;
      s.editTask(
        host.id,
        (x) => x.copyWith(notes: 'see [[Target]]'),
        name: 'Edit Notes',
      );
      s.deleteTask(target.id);
      expect(
        s.repos.links.backlinks(ItemRef(ItemType.task, target.id)),
        isEmpty,
      );
      s.undo();
      expect(s.repos.links.backlinks(ItemRef(ItemType.task, target.id)), [
        ItemRef(ItemType.task, host.id),
      ]);
    });
  });
}
