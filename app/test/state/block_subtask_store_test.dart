// Port of Tests/GroveTests/GoalBlockSubtaskTests.swift and of the store part
// of Tests/GroveTests/PlannerSubtaskTests.swift.
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/state/rules/block_subtask_row.dart';

import 'support.dart';

// Subtasks inside planner blocks. A task block carries the subtasks of its
// task. A goal block has its own subtasks: they stay on that one block.

// 2026-10-05 is a Monday.
final monday = d('2026-10-05');
final mondayOnly = DayRange.single(monday);

/// A goal with two blocks on Monday: 10:00 and 14:00. Gives their event ids.
(String, String) twoBlocks(AppStore s) {
  final g = s.addGoal(title: 'Read', target: 300)!;
  s.scheduleGoal(goalId: g.id, day: monday, start: 600);
  s.scheduleGoal(goalId: g.id, day: monday, start: 840);
  final ids = [
    for (final b
        in s.blocks(mondayOnly).where((b) => b.goalId == g.id).toList()
          ..sort((x, y) => x.startMinute.compareTo(y.startMinute)))
      b.id,
  ];
  expect(ids.length, 2);
  return (ids[0], ids[1]);
}

PlannerBlock block(AppStore s, String id) =>
    s.blocks(mondayOnly).firstWhere((b) => b.id == id);

List<String> names(Iterable<BlockSubtask> subs) => [
  for (final x in subs) x.title,
];

List<bool> ticks(Iterable<BlockSubtask> subs) => [
  for (final x in subs) x.isDone,
];

void main() {
  group('A task block', () {
    test('carries its subtasks in panel order, without cancelled ones', () {
      final s = makeStore();
      final day = DayKey.today();
      final a = s.quickAdd('Plan trip today 10am for 1h')!;
      final one = s.addSubtask(to: a.id, title: 'Flights')!;
      expect(s.addSubtask(to: a.id, title: 'Hotel'), isNotNull);
      final gone = s.addSubtask(to: a.id, title: 'Old idea')!;
      s.toggleDone(taskId: one);
      s.repos.tasks.save(s.task(gone)!.copyWith(status: TaskStatus.cancelled));
      final b = s
          .blocks(DayRange.single(day))
          .firstWhere((b) => b.taskId == a.id);
      expect(names(b.subtasks), ['Flights', 'Hotel']);
      expect(ticks(b.subtasks), [true, false]);
      expect(b.subtasks.first.id, one);
    });

    test('with a task that has no subtasks has none', () {
      final s = makeStore();
      final a = s.quickAdd('Plan trip today 10am for 1h')!;
      final b = s
          .blocks(DayRange.single(DayKey.today()))
          .firstWhere((b) => b.taskId == a.id);
      expect(b.subtasks, isEmpty);
    });

    test('two blocks of one task show the same subtasks', () {
      final s = makeStore();
      final day = DayKey.today();
      final a = s.quickAdd('Plan trip today 10am for 1h')!;
      s.addSubtask(to: a.id, title: 'Flights');
      final first = s
          .blocks(DayRange.single(day))
          .firstWhere((b) => b.taskId == a.id);
      s.duplicate(blockIds: [first.id]);
      final both = s
          .blocks(DayRange.single(day))
          .where((b) => b.taskId == a.id)
          .toList();
      expect(both.length, 2);
      expect(
        [for (final b in both) names(b.subtasks)],
        [
          ['Flights'],
          ['Flights'],
        ],
      );
    });

    test('an event has no subtasks', () {
      final s = makeStore();
      s.repos.events.save(
        EventItem(
          title: 'Standup',
          start: WallTime(day: monday, minute: 540),
          end: WallTime(day: monday, minute: 570),
        ),
      );
      expect(s.blocks(mondayOnly).single.subtasks, isEmpty);
    });

    test('two blocks are the same only with the same subtasks', () {
      final s = makeStore();
      final (a, _) = twoBlocks(s);
      final before = block(s, a);
      expect(block(s, a), before);
      expect(block(s, a).hashCode, before.hashCode);
      final id = s.addBlockSubtask(to: a, title: 'Chapter 3')!;
      final withOne = block(s, a);
      expect(withOne, isNot(before));
      s.toggleBlockSubtask(id);
      expect(block(s, a), isNot(withOne));
    });
  });

  group('One instance only', () {
    test('a subtask shows only in its own block', () {
      final s = makeStore();
      final (a, b) = twoBlocks(s);
      expect(s.addBlockSubtask(to: a, title: 'Chapter 3'), isNotNull);
      expect(s.addBlockSubtask(to: a, title: 'Chapter 4'), isNotNull);
      expect(names(block(s, a).subtasks), ['Chapter 3', 'Chapter 4']);
      expect(ticks(block(s, a).subtasks), [false, false]);
      expect(block(s, b).subtasks, isEmpty);
      expect(s.undoName, 'New Subtask');
    });

    test('a new block of the same goal starts empty', () {
      final s = makeStore();
      final (a, _) = twoBlocks(s);
      expect(s.addBlockSubtask(to: a, title: 'Chapter 3'), isNotNull);
      final g = s.goals().first;
      final tuesday = monday.adding(days: 1);
      s.scheduleGoal(goalId: g.id, day: tuesday, start: 600);
      final next = s
          .blocks(DayRange.single(tuesday))
          .firstWhere((b) => b.goalId == g.id);
      expect(next.subtasks, isEmpty);
    });

    test('only a goal block takes a new subtask', () {
      final s = makeStore();
      final (a, _) = twoBlocks(s);
      expect(s.addBlockSubtask(to: a, title: '   '), isNull);
      expect(s.addBlockSubtask(to: 'missing', title: 'x'), isNull);
      final task = s.quickAdd('Write today 10am for 1h')!;
      final taskBlock = s
          .blocks(DayRange.single(DayKey.today()))
          .firstWhere((b) => b.taskId == task.id);
      expect(s.addBlockSubtask(to: taskBlock.id, title: 'x'), isNull);
      expect(s.blockSubtasks(a), isEmpty);
    });

    test('the title of a new subtask is trimmed', () {
      final s = makeStore();
      final (a, _) = twoBlocks(s);
      s.addBlockSubtask(to: a, title: '  Chapter 3 \n');
      expect(s.blockSubtasks(a).single.title, 'Chapter 3');
    });

    test('duplicating a block does not copy its subtasks', () {
      final s = makeStore();
      final (a, _) = twoBlocks(s);
      expect(s.addBlockSubtask(to: a, title: 'Chapter 3'), isNotNull);
      s.duplicate(blockIds: [a]);
      final copy = s.selection.first;
      expect(copy, isNot(a));
      expect(s.blockSubtasks(copy), isEmpty);
      expect(s.blockSubtasks(a).length, 1);
    });

    test('splitting a block keeps the subtasks on the first half', () {
      final s = makeStore();
      final (a, _) = twoBlocks(s);
      expect(s.addBlockSubtask(to: a, title: 'Chapter 3'), isNotNull);
      s.scheduleGoal(
        goalId: s.goals().first.id,
        day: monday,
        start: 300,
        length: 120,
      );
      final long = s
          .blocks(mondayOnly)
          .firstWhere((b) => b.startMinute == 300)
          .id;
      expect(s.addBlockSubtask(to: long, title: 'Part'), isNotNull);
      s.split(blockId: long);
      final halves = s
          .blocks(mondayOnly)
          .where((b) => b.startMinute >= 300 && b.startMinute < 420)
          .toList();
      expect(halves.length, 2);
      expect(names(halves.firstWhere((b) => b.id == long).subtasks), ['Part']);
      expect(halves.firstWhere((b) => b.id != long).subtasks, isEmpty);
    });
  });

  group('Tick, rename, delete, with undo', () {
    test('ticking a subtask strikes it and undo brings it back', () {
      final s = makeStore();
      final (a, _) = twoBlocks(s);
      final id = s.addBlockSubtask(to: a, title: 'Chapter 3')!;
      s.toggleBlockSubtask(id);
      expect(block(s, a).subtasks.first.isDone, isTrue);
      expect(s.undoName, 'Complete Subtask');
      s.undo();
      expect(block(s, a).subtasks.first.isDone, isFalse);
      s.redo();
      expect(block(s, a).subtasks.first.isDone, isTrue);
      s.toggleBlockSubtask(id);
      expect(s.undoName, 'Reopen Subtask');
      expect(block(s, a).subtasks.first.isDone, isFalse);
    });

    test('ticking a subtask does not tick the block', () {
      final s = makeStore();
      final (a, _) = twoBlocks(s);
      final id = s.addBlockSubtask(to: a, title: 'Chapter 3')!;
      s.toggleBlockSubtask(id);
      expect(block(s, a).isDone, isFalse);
    });

    test('a subtask that is gone cannot be ticked, renamed or deleted', () {
      final s = makeStore();
      final (a, _) = twoBlocks(s);
      s.addBlockSubtask(to: a, title: 'Chapter 3');
      s.toggleBlockSubtask('missing');
      s.renameBlockSubtask('missing', to: 'x');
      s.deleteBlockSubtask('missing');
      expect(s.undoName, 'New Subtask');
      expect(s.errorMessage, isNull);
    });

    test('renaming a subtask is one undo step', () {
      final s = makeStore();
      final (a, _) = twoBlocks(s);
      final id = s.addBlockSubtask(to: a, title: 'Chapter 3')!;
      s.renameBlockSubtask(id, to: '  Chapter 3 and 4 ');
      expect(s.blockSubtasks(a).first.title, 'Chapter 3 and 4');
      expect(s.undoName, 'Rename Subtask');
      s.undo();
      expect(s.blockSubtasks(a).first.title, 'Chapter 3');
    });

    test('an empty or same name changes nothing', () {
      final s = makeStore();
      final (a, _) = twoBlocks(s);
      final id = s.addBlockSubtask(to: a, title: 'Chapter 3')!;
      s.renameBlockSubtask(id, to: '   ');
      s.renameBlockSubtask(id, to: 'Chapter 3');
      expect(s.blockSubtasks(a).first.title, 'Chapter 3');
      expect(s.undoName, 'New Subtask');
    });

    test('deleting a subtask and undoing puts it back in its place', () {
      final s = makeStore();
      final (a, _) = twoBlocks(s);
      s.addBlockSubtask(to: a, title: 'One');
      final two = s.addBlockSubtask(to: a, title: 'Two')!;
      s.addBlockSubtask(to: a, title: 'Three');
      s.deleteBlockSubtask(two);
      expect([for (final x in s.blockSubtasks(a)) x.title], ['One', 'Three']);
      expect(s.undoName, 'Delete Subtask');
      s.undo();
      expect(
        [for (final x in s.blockSubtasks(a)) x.title],
        ['One', 'Two', 'Three'],
      );
    });

    test('undoing the add removes the subtask', () {
      final s = makeStore();
      final (a, _) = twoBlocks(s);
      s.addBlockSubtask(to: a, title: 'One');
      s.undo();
      expect(s.blockSubtasks(a), isEmpty);
      s.redo();
      expect(s.blockSubtasks(a).single.title, 'One');
    });

    test('each change is its own undo step, also close in time', () {
      final s = makeStore();
      final (a, _) = twoBlocks(s);
      final steps = s.undoStack.length;
      final id = s.addBlockSubtask(to: a, title: 'One')!;
      s.renameBlockSubtask(id, to: 'Two');
      s.renameBlockSubtask(id, to: 'Three');
      expect(s.undoStack.length, steps + 3);
    });

    test('deleting the block and undoing brings the subtasks back', () {
      final s = makeStore();
      final (a, b) = twoBlocks(s);
      final one = s.addBlockSubtask(to: a, title: 'One')!;
      s.addBlockSubtask(to: a, title: 'Two');
      s.toggleBlockSubtask(one);
      s.deleteBlocks([a], name: 'Delete Goal Block');
      expect(s.blockSubtasks(a), isEmpty);
      s.undo();
      expect(names(block(s, a).subtasks), ['One', 'Two']);
      expect(ticks(block(s, a).subtasks), [true, false]);
      expect(block(s, b).subtasks, isEmpty);
      s.redo();
      expect(s.blockSubtasks(a), isEmpty);
      s.undo();
      expect(names(block(s, a).subtasks), ['One', 'Two']);
    });

    test('deleting the goal keeps the subtasks on the plain block', () {
      final s = makeStore();
      final (a, _) = twoBlocks(s);
      s.addBlockSubtask(to: a, title: 'One');
      s.deleteGoal(s.goals().first.id);
      final plain = block(s, a);
      expect(plain.goalId, isNull);
      expect(names(plain.subtasks), ['One']);
      s.undo();
      expect(block(s, a).goalId, isNotNull);
      expect(block(s, a).subtasks.length, 1);
    });

    test('an old goal block keeps its subtasks: they can be ticked, renamed '
        'and deleted, and no new one can be added', () {
      final s = makeStore();
      final (a, _) = twoBlocks(s);
      final id = s.addBlockSubtask(to: a, title: 'One')!;
      s.deleteGoal(s.goals().first.id);
      expect(s.addBlockSubtask(to: a, title: 'Two'), isNull);
      s.toggleBlockSubtask(id);
      expect(ticks(block(s, a).subtasks), [true]);
      s.renameBlockSubtask(id, to: 'Uno');
      expect(names(block(s, a).subtasks), ['Uno']);
      s.deleteBlockSubtask(id);
      expect(block(s, a).subtasks, isEmpty);
    });
  });

  group('The editor', () {
    test('the subtask editor opens only for a goal block', () {
      final s = makeStore();
      final (a, _) = twoBlocks(s);
      var calls = 0;
      s.addListener(() => calls++);
      s.openBlockSubtasks(a);
      expect(s.editingBlockSubtasks, a);
      expect(calls, greaterThan(0));
      s.closeBlockSubtasks();
      expect(s.editingBlockSubtasks, isNull);
      s.openBlockSubtasks('missing');
      expect(s.editingBlockSubtasks, isNull);
    });

    test('it does not open for a task block or a plain block', () {
      final s = makeStore();
      final task = s.quickAdd('Write today 10am for 1h')!;
      final taskBlock = s
          .blocks(DayRange.single(DayKey.today()))
          .firstWhere((b) => b.taskId == task.id);
      s.openBlockSubtasks(taskBlock.id);
      expect(s.editingBlockSubtasks, isNull);
      final plain = EventItem(
        title: 'Lunch',
        start: WallTime(day: monday, minute: 720),
        end: WallTime(day: monday, minute: 780),
        kind: EventKind.block,
      );
      s.repos.events.save(plain);
      s.openBlockSubtasks(plain.id);
      expect(s.editingBlockSubtasks, isNull);
    });

    test('it opens for an old goal block that still has subtasks', () {
      final s = makeStore();
      final (a, b) = twoBlocks(s);
      s.addBlockSubtask(to: a, title: 'One');
      s.deleteGoal(s.goals().first.id);
      s.openBlockSubtasks(a);
      expect(s.editingBlockSubtasks, a);
      s.closeBlockSubtasks();
      s.openBlockSubtasks(b);
      expect(s.editingBlockSubtasks, isNull);
    });

    test('an import closes it', () {
      final s = makeStore();
      final (a, _) = twoBlocks(s);
      s.openBlockSubtasks(a);
      s.resetAfterReplace();
      expect(s.editingBlockSubtasks, isNull);
    });
  });

  group('The labels', () {
    test('labels for the more row and the badge', () {
      expect(
        SubtaskRules.moreLabel(hidden: 3, shown: 2, done: 1, total: 5),
        '+3 more',
      );
      expect(
        SubtaskRules.moreLabel(hidden: 4, shown: 0, done: 1, total: 4),
        '1/4 subtasks',
      );
      expect(SubtaskRules.badge(done: 1, total: 4), '1/4');
    });

    test('a goal block gives the numbers for the labels', () {
      final s = makeStore();
      final (a, _) = twoBlocks(s);
      for (final t in ['One', 'Two', 'Three', 'Four', 'Five']) {
        expect(s.addBlockSubtask(to: a, title: t), isNotNull);
      }
      s.toggleBlockSubtask(s.blockSubtasks(a).first.id);
      final b = block(s, a);
      expect(b.summary, isEmpty);
      final done = b.subtasks.where((x) => x.isDone).length;
      expect(
        SubtaskRules.moreLabel(hidden: 4, shown: 1, done: done, total: 5),
        '+4 more',
      );
      expect(SubtaskRules.badge(done: done, total: b.subtasks.length), '1/5');
    });
  });
}
