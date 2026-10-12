import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/goal_subtask.dart';
import 'package:grove/state/rules/block_subtask_row.dart';

import 'support.dart';

// Subtasks of a goal. The list belongs to the goal, not to one block: every
// block of the goal, on any day, has the same list. The Goals panel shows
// it. The subtasks of one block (`block_subtasks`) are another list.
//
// A subtask of the goal can be planned in one block of the goal. It is still
// one subtask of the goal. When it is ticked, the goal does not show it any
// more: the block keeps it.

// 2026-10-05 is a Monday.
final monday = d('2026-10-05');

List<String> names(Iterable<GoalSubtaskItem> subs) => [
  for (final x in subs) x.title,
];

List<String> rowNames(Iterable<BlockSubtask> subs) => [
  for (final x in subs) x.title,
];

List<bool> ticks(Iterable<GoalSubtaskItem> subs) => [
  for (final x in subs) x.isDone,
];

/// A goal "Read" with these subtasks. Gives the goal.
GoalItem goalWith(AppStore s, List<String> titles) {
  final g = s.addGoal(title: 'Read', target: 300)!;
  for (final t in titles) {
    expect(s.addGoalSubtask(to: g.id, title: t), isNotNull);
  }
  return g;
}

final mondayOnly = DayRange.single(monday);
final tuesday = monday.adding(days: 1);

/// A goal "Read" with these subtasks, a block on Monday 10:00 and a block on
/// Tuesday 14:00. Gives the goal and the ids of the two blocks.
(GoalItem, String, String) planned(AppStore s, List<String> titles) {
  final g = goalWith(s, titles);
  s.scheduleGoal(goalId: g.id, day: monday, start: 600);
  final a = s.selection.single;
  s.scheduleGoal(goalId: g.id, day: tuesday, start: 840);
  final b = s.selection.single;
  return (g, a, b);
}

/// The id of the subtask of the goal with this title.
String subId(AppStore s, GoalItem g, String title) =>
    s.goalSubtasks(g.id).firstWhere((x) => x.title == title).id;

/// The rows that the planner shows in a block.
List<BlockSubtask> rows(AppStore s, String blockId) => s
    .blocks(DayRange(monday, tuesday))
    .firstWhere((b) => b.id == blockId)
    .subtasks;

/// A subtask list of this many open and then this many done subtasks.
List<GoalSubtaskItem> list({int open = 0, int done = 0}) => [
  for (var i = 0; i < open; i++)
    GoalSubtaskItem(goalId: 'G', title: 'Open $i', sort: i + 1.0),
  for (var i = 0; i < done; i++)
    GoalSubtaskItem(
      goalId: 'G',
      title: 'Done $i',
      sort: open + i + 1.0,
      doneAt: '2026-10-05T11:00:00',
    ),
];

void main() {
  group('The list of a goal', () {
    test('a new goal has no subtasks', () {
      final s = makeStore();
      final g = s.addGoal(title: 'Read')!;
      expect(s.goalSubtasks(g.id), isEmpty);
    });

    test('new subtasks go to the end of the list', () {
      final s = makeStore();
      final g = goalWith(s, ['Chapter 3', 'Chapter 4', 'Notes']);
      expect(names(s.goalSubtasks(g.id)), ['Chapter 3', 'Chapter 4', 'Notes']);
      expect(ticks(s.goalSubtasks(g.id)), [false, false, false]);
      expect(s.undoName, 'New Subtask');
    });

    test('the title of a new subtask is trimmed, and an empty one adds '
        'nothing', () {
      final s = makeStore();
      final g = s.addGoal(title: 'Read')!;
      expect(s.addGoalSubtask(to: g.id, title: '   '), isNull);
      expect(s.addGoalSubtask(to: g.id, title: ''), isNull);
      expect(s.undoName, 'New Goal');
      s.addGoalSubtask(to: g.id, title: '  Chapter 3 \n');
      expect(s.goalSubtasks(g.id).single.title, 'Chapter 3');
    });

    test('a goal that does not exist takes no subtask', () {
      final s = makeStore();
      expect(s.addGoalSubtask(to: 'missing', title: 'x'), isNull);
      expect(s.errorMessage, isNull);
    });

    test('another goal has its own list', () {
      final s = makeStore();
      final read = goalWith(s, ['Chapter 3']);
      final gym = s.addGoal(title: 'Gym')!;
      expect(s.goalSubtasks(gym.id), isEmpty);
      s.addGoalSubtask(to: gym.id, title: 'Legs');
      expect(names(s.goalSubtasks(read.id)), ['Chapter 3']);
      expect(names(s.goalSubtasks(gym.id)), ['Legs']);
    });

    test('the lists of many goals in one call', () {
      final s = makeStore();
      final read = goalWith(s, ['Chapter 3', 'Chapter 4']);
      final gym = s.addGoal(title: 'Gym')!;
      final all = s.goalSubtasksOf([read.id, gym.id]);
      expect(names(all[read.id]!), ['Chapter 3', 'Chapter 4']);
      expect(all[gym.id], isNull);
    });
  });

  group('One list for every block of the goal', () {
    test('two blocks of the goal on two days have the same list', () {
      final s = makeStore();
      final g = goalWith(s, ['Chapter 3']);
      s.scheduleGoal(goalId: g.id, day: monday, start: 600);
      s.scheduleGoal(goalId: g.id, day: monday.adding(days: 1), start: 840);
      final blocks = s.repos.events.all().where((e) => e.goalId == g.id);
      expect(blocks.map((e) => e.start.day).toSet(), {
        monday,
        monday.adding(days: 1),
      });
      // A subtask added after the blocks were made is in the one list too.
      s.addGoalSubtask(to: g.id, title: 'Chapter 4');
      for (final block in blocks) {
        expect(names(s.goalSubtasks(block.goalId!)), [
          'Chapter 3',
          'Chapter 4',
        ], reason: '${block.start.day}');
      }
    });

    test('a tick shows for every block of the goal', () {
      final s = makeStore();
      final g = goalWith(s, ['Chapter 3', 'Chapter 4']);
      s.scheduleGoal(goalId: g.id, day: monday, start: 600);
      s.scheduleGoal(goalId: g.id, day: monday.adding(days: 3), start: 600);
      s.toggleGoalSubtask(s.goalSubtasks(g.id).first.id);
      for (final block in s.repos.events.all()) {
        expect(ticks(s.goalSubtasks(block.goalId!)), [true, false]);
      }
    });

    test('a deleted block leaves the list of the goal', () {
      final s = makeStore();
      final g = goalWith(s, ['Chapter 3']);
      s.scheduleGoal(goalId: g.id, day: monday, start: 600);
      s.deleteBlocks([s.repos.events.all().single.id], name: 'Delete Block');
      expect(names(s.goalSubtasks(g.id)), ['Chapter 3']);
    });

    test('a tick of a subtask does not tick a block, and a done block does '
        'not tick a subtask', () {
      final s = makeStore();
      final g = goalWith(s, ['Chapter 3']);
      s.scheduleGoal(goalId: g.id, day: monday, start: 600);
      final block = s.repos.events.all().single;
      s.toggleGoalSubtask(s.goalSubtasks(g.id).single.id);
      expect(s.repos.events.get(block.id)!.doneAt, isNull);
      s.toggleGoalSubtask(s.goalSubtasks(g.id).single.id);
      s.toggleGoalBlockDone(eventId: block.id);
      expect(s.goalSubtasks(g.id).single.isDone, isFalse);
    });

    test('the subtasks of one block stay on that block, apart from the list '
        'of the goal', () {
      final s = makeStore();
      final g = goalWith(s, ['Of the goal']);
      s.scheduleGoal(goalId: g.id, day: monday, start: 600);
      s.scheduleGoal(goalId: g.id, day: monday.adding(days: 1), start: 600);
      final blocks = s.repos.events.all();
      s.addBlockSubtask(to: blocks.first.id, title: 'Of one block');
      expect(names(s.goalSubtasks(g.id)), ['Of the goal']);
      expect(s.blockSubtasks(blocks.first.id).single.title, 'Of one block');
      expect(s.blockSubtasks(blocks.last.id), isEmpty);
    });
  });

  group('Tick, rename, delete, with undo', () {
    test('a tick is one undo step', () {
      final s = makeStore();
      final g = goalWith(s, ['Chapter 3']);
      final id = s.goalSubtasks(g.id).single.id;
      s.toggleGoalSubtask(id);
      expect(s.goalSubtasks(g.id).single.isDone, isTrue);
      expect(s.undoName, 'Complete Subtask');
      s.undo();
      expect(s.goalSubtasks(g.id).single.isDone, isFalse);
      s.redo();
      expect(s.goalSubtasks(g.id).single.isDone, isTrue);
      s.toggleGoalSubtask(id);
      expect(s.undoName, 'Reopen Subtask');
      expect(s.goalSubtasks(g.id).single.isDone, isFalse);
    });

    test('a subtask that is gone cannot be ticked, renamed or deleted', () {
      final s = makeStore();
      goalWith(s, ['Chapter 3']);
      s.toggleGoalSubtask('missing');
      s.renameGoalSubtask('missing', to: 'x');
      s.deleteGoalSubtask('missing');
      expect(s.undoName, 'New Subtask');
      expect(s.errorMessage, isNull);
    });

    test('a new name is one undo step', () {
      final s = makeStore();
      final g = goalWith(s, ['Chapter 3']);
      final id = s.goalSubtasks(g.id).single.id;
      s.renameGoalSubtask(id, to: '  Chapter 3 and 4 ');
      expect(s.goalSubtasks(g.id).single.title, 'Chapter 3 and 4');
      expect(s.undoName, 'Rename Subtask');
      s.undo();
      expect(s.goalSubtasks(g.id).single.title, 'Chapter 3');
    });

    test('an empty or same name changes nothing', () {
      final s = makeStore();
      final g = goalWith(s, ['Chapter 3']);
      final id = s.goalSubtasks(g.id).single.id;
      s.renameGoalSubtask(id, to: '   ');
      s.renameGoalSubtask(id, to: 'Chapter 3');
      expect(s.goalSubtasks(g.id).single.title, 'Chapter 3');
      expect(s.undoName, 'New Subtask');
    });

    test('a deleted subtask comes back in its place with undo', () {
      final s = makeStore();
      final g = goalWith(s, ['One', 'Two', 'Three']);
      s.deleteGoalSubtask(s.goalSubtasks(g.id)[1].id);
      expect(names(s.goalSubtasks(g.id)), ['One', 'Three']);
      expect(s.undoName, 'Delete Subtask');
      s.undo();
      expect(names(s.goalSubtasks(g.id)), ['One', 'Two', 'Three']);
    });

    test('undo of the add takes the subtask away', () {
      final s = makeStore();
      final g = goalWith(s, ['One']);
      s.undo();
      expect(s.goalSubtasks(g.id), isEmpty);
      s.redo();
      expect(s.goalSubtasks(g.id).single.title, 'One');
    });

    test('each change is its own undo step, also close in time', () {
      final s = makeStore();
      final g = s.addGoal(title: 'Read')!;
      final steps = s.undoStack.length;
      final id = s.addGoalSubtask(to: g.id, title: 'One')!;
      s.renameGoalSubtask(id, to: 'Two');
      s.renameGoalSubtask(id, to: 'Three');
      s.toggleGoalSubtask(id);
      expect(s.undoStack.length, steps + 4);
    });
  });

  group('The goal goes or changes', () {
    test('a deleted goal takes its subtasks, and undo brings them back with '
        'their ticks', () {
      final s = makeStore();
      final g = goalWith(s, ['One', 'Two']);
      final gym = s.addGoal(title: 'Gym')!;
      s.addGoalSubtask(to: gym.id, title: 'Legs');
      s.scheduleGoal(goalId: g.id, day: monday, start: 600);
      s.toggleGoalSubtask(s.goalSubtasks(g.id).first.id);

      s.deleteGoal(g.id);
      expect(s.goal(g.id), isNull);
      expect(s.goalSubtasks(g.id), isEmpty);
      expect(s.repos.goalSubtasks.forGoals([g.id]), isEmpty);
      expect(names(s.goalSubtasks(gym.id)), ['Legs']);
      expect(s.undoName, 'Delete Goal');

      s.undo();
      expect(names(s.goalSubtasks(g.id)), ['One', 'Two']);
      expect(ticks(s.goalSubtasks(g.id)), [true, false]);
      expect(s.repos.events.all().single.goalId, g.id);

      s.redo();
      expect(s.goalSubtasks(g.id), isEmpty);
      s.undo();
      expect(names(s.goalSubtasks(g.id)), ['One', 'Two']);
    });

    test('undo of a new goal with subtasks made after it leaves no row', () {
      final s = makeStore();
      final g = goalWith(s, ['One']);
      s.undo();
      s.undo();
      expect(s.goals(), isEmpty);
      expect(s.repos.goalSubtasks.forGoals([g.id]), isEmpty);
      s.redo();
      s.redo();
      expect(names(s.goalSubtasks(g.id)), ['One']);
    });

    test('an archived goal keeps its subtasks', () {
      final s = makeStore();
      final g = goalWith(s, ['One']);
      s.updateGoal(g.id, archived: true);
      expect(names(s.goalSubtasks(g.id)), ['One']);
    });

    test('a new name or kind of the goal keeps its subtasks', () {
      final s = makeStore();
      final g = goalWith(s, ['One']);
      s.updateGoal(g.id, title: 'Read books', kind: GoalKind.sessions);
      expect(names(s.goalSubtasks(g.id)), ['One']);
    });
  });

  group('The app starts again', () {
    test('subtasks and their ticks are in the database file', () {
      final dir = Directory.systemTemp.createTempSync('grove-goal-subs-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}${Platform.pathSeparator}grove.sqlite';

      var db = Database.open(path);
      var s = AppStore(repos: Repos(db));
      final g = goalWith(s, ['Chapter 3', 'Chapter 4']);
      s.toggleGoalSubtask(s.goalSubtasks(g.id).first.id);
      s.dispose();
      db.close();

      db = Database.open(path);
      s = AppStore(repos: Repos(db));
      expect(names(s.goalSubtasks(g.id)), ['Chapter 3', 'Chapter 4']);
      expect(ticks(s.goalSubtasks(g.id)), [true, false]);
      s.dispose();
      db.close();
    });

    test('an import replaces the subtasks with the ones of the file', () {
      final from = makeStore();
      final g = goalWith(from, ['From the file']);
      final file = DataExport.export(from.repos.db);

      final s = makeStore();
      final old = goalWith(s, ['Old']);
      DataExport.importData(file, s.repos);
      s.resetAfterReplace();
      expect(s.goalSubtasks(old.id), isEmpty);
      expect(names(s.goalSubtasks(g.id)), ['From the file']);
    });
  });

  group('A subtask planned in a block of the goal', () {
    test('a planned subtask shows in its block, and only there', () {
      final s = makeStore();
      final (g, a, b) = planned(s, ['Chapter 3', 'Chapter 4']);
      final id = subId(s, g, 'Chapter 3');
      expect(s.assignGoalSubtask(id, to: a), isTrue);
      expect(s.undoName, 'Plan Subtask');
      expect(s.goalSubtasks(g.id).first.eventId, a);
      expect(names(s.plannedGoalSubtasks(a)), ['Chapter 3']);
      expect(s.plannedGoalSubtasks(b), isEmpty);
      final row = rows(s, a).single;
      expect(
        (row.id, row.title, row.isDone, row.fromGoal),
        (id, 'Chapter 3', false, true),
      );
      expect(rows(s, b), isEmpty);
    });

    test('it is still one subtask of the goal: the goal shows it until it '
        'is ticked', () {
      final s = makeStore();
      final (g, a, _) = planned(s, ['Chapter 3', 'Chapter 4']);
      s.assignGoalSubtask(subId(s, g, 'Chapter 3'), to: a);
      expect(names(s.goalSubtasks(g.id)), ['Chapter 3', 'Chapter 4']);
      expect(names(GoalSubtaskRules.inGoal(s.goalSubtasks(g.id))), [
        'Chapter 3',
        'Chapter 4',
      ]);
    });

    test('a tick takes it out of the list of the goal, and the block keeps '
        'it', () {
      final s = makeStore();
      final (g, a, _) = planned(s, ['Chapter 3', 'Chapter 4']);
      final id = subId(s, g, 'Chapter 3');
      s.assignGoalSubtask(id, to: a);
      s.toggleGoalSubtask(id);
      final all = s.goalSubtasks(g.id);
      expect(names(GoalSubtaskRules.inGoal(all)), ['Chapter 4']);
      expect(names(GoalSubtaskRules.closed(all)), ['Chapter 4']);
      // Not in the "done" count of the goal: it is gone from the goal.
      expect(GoalSubtaskRules.moreLine(all), isNull);
      expect(rowNames(rows(s, a)), ['Chapter 3']);
      expect(rows(s, a).single.isDone, isTrue);
      // Open it again in the block: the goal shows it again.
      s.toggleGoalSubtask(id);
      expect(names(GoalSubtaskRules.inGoal(s.goalSubtasks(g.id))), [
        'Chapter 3',
        'Chapter 4',
      ]);
      expect(rows(s, a).single.isDone, isFalse);
    });

    test('a done subtask that is in no block stays in the goal', () {
      final s = makeStore();
      final (g, _, _) = planned(s, ['Chapter 3']);
      s.toggleGoalSubtask(subId(s, g, 'Chapter 3'));
      final all = s.goalSubtasks(g.id);
      expect(names(GoalSubtaskRules.inGoal(all)), ['Chapter 3']);
      expect(GoalSubtaskRules.moreLine(all), '1 done');
    });

    test('a subtask is in one block at most: a second block takes it from '
        'the first', () {
      final s = makeStore();
      final (g, a, b) = planned(s, ['Chapter 3']);
      final id = subId(s, g, 'Chapter 3');
      s.assignGoalSubtask(id, to: a);
      expect(s.assignGoalSubtask(id, to: b), isTrue);
      expect(rows(s, a), isEmpty);
      expect(rowNames(rows(s, b)), ['Chapter 3']);
      expect(s.goalSubtasks(g.id).length, 1);
      s.undo();
      expect(rowNames(rows(s, a)), ['Chapter 3']);
      expect(rows(s, b), isEmpty);
    });

    test('the same block again changes nothing and is no undo step', () {
      final s = makeStore();
      final (g, a, _) = planned(s, ['Chapter 3']);
      final id = subId(s, g, 'Chapter 3');
      s.assignGoalSubtask(id, to: a);
      final steps = s.undoStack.length;
      expect(s.assignGoalSubtask(id, to: a), isFalse);
      expect(s.undoStack.length, steps);
    });

    test('a block of another goal, a task block, an event and a missing '
        'block take no subtask', () {
      final s = makeStore();
      final (g, _, _) = planned(s, ['Chapter 3']);
      final id = subId(s, g, 'Chapter 3');
      final gym = s.addGoal(title: 'Gym')!;
      s.scheduleGoal(goalId: gym.id, day: monday, start: 900);
      final other = s.selection.single;
      final task = s.quickAdd('Mail')!;
      s.schedule(taskId: task.id, day: monday, start: 1000);
      final taskBlock = s
          .blocks(mondayOnly)
          .firstWhere((b) => b.taskId == task.id)
          .id;
      final steps = s.undoStack.length;
      for (final block in [other, taskBlock, 'missing']) {
        expect(s.assignGoalSubtask(id, to: block), isFalse, reason: block);
      }
      expect(s.assignGoalSubtask('missing', to: other), isFalse);
      expect(s.goalSubtasks(g.id).single.eventId, isNull);
      expect(s.undoStack.length, steps);
      expect(s.errorMessage, isNull);
    });

    test('"back to the goal" takes it out of the block, with undo', () {
      final s = makeStore();
      final (g, a, _) = planned(s, ['Chapter 3']);
      final id = subId(s, g, 'Chapter 3');
      s.assignGoalSubtask(id, to: a);
      s.unassignGoalSubtask(id);
      expect(s.undoName, 'Unplan Subtask');
      expect(rows(s, a), isEmpty);
      expect(s.goalSubtasks(g.id).single.eventId, isNull);
      s.undo();
      expect(rowNames(rows(s, a)), ['Chapter 3']);
      // A subtask in no block: nothing to do.
      s.undo();
      final steps = s.undoStack.length;
      s.unassignGoalSubtask(id);
      s.unassignGoalSubtask('missing');
      expect(s.undoStack.length, steps);
    });

    test('a done subtask that goes back to the goal shows there as done', () {
      final s = makeStore();
      final (g, a, _) = planned(s, ['Chapter 3']);
      final id = subId(s, g, 'Chapter 3');
      s.assignGoalSubtask(id, to: a);
      s.toggleGoalSubtask(id);
      s.unassignGoalSubtask(id);
      final all = s.goalSubtasks(g.id);
      expect(names(GoalSubtaskRules.inGoal(all)), ['Chapter 3']);
      expect(GoalSubtaskRules.moreLine(all), '1 done');
    });

    test('the block shows the planned subtasks first, in the order of the '
        'goal, then its own subtasks', () {
      final s = makeStore();
      final (g, a, _) = planned(s, ['One', 'Two', 'Three']);
      s.addBlockSubtask(to: a, title: 'Own');
      s.assignGoalSubtask(subId(s, g, 'Three'), to: a);
      s.assignGoalSubtask(subId(s, g, 'One'), to: a);
      expect(rowNames(rows(s, a)), ['One', 'Three', 'Own']);
      expect([for (final r in rows(s, a)) r.fromGoal], [true, true, false]);
      expect(names(s.plannedGoalSubtasks(a)), ['One', 'Three']);
      expect(s.blockSubtasks(a).single.title, 'Own');
    });

    test('a new name or a delete of a planned subtask shows in the block', () {
      final s = makeStore();
      final (g, a, _) = planned(s, ['Chapter 3']);
      final id = subId(s, g, 'Chapter 3');
      s.assignGoalSubtask(id, to: a);
      s.renameGoalSubtask(id, to: 'Chapter 5');
      expect(rowNames(rows(s, a)), ['Chapter 5']);
      expect(s.goalSubtasks(g.id).single.eventId, a);
      s.deleteGoalSubtask(id);
      expect(rows(s, a), isEmpty);
      expect(s.goalSubtasks(g.id), isEmpty);
      s.undo();
      expect(rowNames(rows(s, a)), ['Chapter 5']);
    });

    test('the subtasks of the goal that a block can take: open, and in no '
        'block', () {
      final s = makeStore();
      final (g, a, b) = planned(s, ['One', 'Two', 'Three', 'Four']);
      s.assignGoalSubtask(subId(s, g, 'One'), to: a);
      s.assignGoalSubtask(subId(s, g, 'Two'), to: b);
      s.toggleGoalSubtask(subId(s, g, 'Three'));
      expect(names(s.freeGoalSubtasks(a)), ['Four']);
      expect(names(s.freeGoalSubtasks(b)), ['Four']);
      expect(s.freeGoalSubtasks('missing'), isEmpty);
      // A block with no goal has no list to take from.
      final lunch = EventItem(
        title: 'Lunch',
        start: WallTime(day: monday, minute: 720),
        end: WallTime(day: monday, minute: 780),
      );
      s.repos.events.save(lunch);
      expect(s.freeGoalSubtasks(lunch.id), isEmpty);
    });
  });

  group('The block of a planned subtask goes', () {
    test('a deleted block gives the subtask back to the goal, and undo puts '
        'it in the block again', () {
      final s = makeStore();
      final (g, a, b) = planned(s, ['Chapter 3', 'Chapter 4']);
      final three = subId(s, g, 'Chapter 3');
      s.assignGoalSubtask(three, to: a);
      s.assignGoalSubtask(subId(s, g, 'Chapter 4'), to: b);
      s.toggleGoalSubtask(three);
      s.deleteBlocks([a], name: 'Delete Goal Block');
      var all = s.goalSubtasks(g.id);
      expect([for (final x in all) x.eventId], [null, b]);
      // It was done in the block. Now it is a done subtask of the goal.
      expect(names(GoalSubtaskRules.inGoal(all)), ['Chapter 3', 'Chapter 4']);
      expect(GoalSubtaskRules.moreLine(all), '1 done');
      s.undo();
      all = s.goalSubtasks(g.id);
      expect([for (final x in all) x.eventId], [a, b]);
      expect(rowNames(rows(s, a)), ['Chapter 3']);
      expect(rows(s, a).single.isDone, isTrue);
      s.redo();
      expect(s.goalSubtasks(g.id).first.eventId, isNull);
      s.undo();
      expect(rowNames(rows(s, a)), ['Chapter 3']);
    });

    test('the delete of the block is one undo step, with the subtask in '
        'it', () {
      final s = makeStore();
      final (g, a, _) = planned(s, ['Chapter 3']);
      s.assignGoalSubtask(subId(s, g, 'Chapter 3'), to: a);
      final steps = s.undoStack.length;
      s.deleteBlocks([a], name: 'Delete Goal Block');
      expect(s.undoStack.length, steps + 1);
      final change = s.undoStack.last.goalSubtasks.single;
      expect(change.before?.eventId, a);
      expect(change.after?.eventId, isNull);
    });

    test('a deleted goal takes its planned subtasks too. The plain block '
        'that stays has none. Undo brings all back', () {
      final s = makeStore();
      final (g, a, _) = planned(s, ['Chapter 3']);
      s.assignGoalSubtask(subId(s, g, 'Chapter 3'), to: a);
      s.addBlockSubtask(to: a, title: 'Own');
      s.deleteGoal(g.id);
      expect(s.goalSubtasks(g.id), isEmpty);
      expect(rowNames(rows(s, a)), ['Own']);
      s.undo();
      expect(rowNames(rows(s, a)), ['Chapter 3', 'Own']);
      expect(s.goalSubtasks(g.id).single.eventId, a);
    });

    test('a copy of the block does not take the planned subtask', () {
      final s = makeStore();
      final (g, a, _) = planned(s, ['Chapter 3']);
      s.assignGoalSubtask(subId(s, g, 'Chapter 3'), to: a);
      s.duplicate(blockIds: [a]);
      final copies = s
          .blocks(DayRange(monday, tuesday))
          .where((b) => b.goalId == g.id && b.day == monday)
          .toList();
      expect(copies.length, 2);
      expect(rowNames(copies.firstWhere((b) => b.id == a).subtasks), [
        'Chapter 3',
      ]);
      expect(copies.firstWhere((b) => b.id != a).subtasks, isEmpty);
    });

    test('a block that is cut in two keeps the planned subtask on its first '
        'half', () {
      final s = makeStore();
      final (g, a, _) = planned(s, ['Chapter 3']);
      s.assignGoalSubtask(subId(s, g, 'Chapter 3'), to: a);
      s.split(blockId: a);
      final halves =
          s
              .blocks(DayRange(monday, tuesday))
              .where((b) => b.goalId == g.id && b.day == monday)
              .toList()
            ..sort((x, y) => x.startMinute.compareTo(y.startMinute));
      expect(halves.length, 2);
      expect(halves.first.id, a);
      expect(rowNames(halves.first.subtasks), ['Chapter 3']);
      expect(halves.last.subtasks, isEmpty);
    });

    test('the plan is in the database file', () {
      final dir = Directory.systemTemp.createTempSync('grove-plan-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}${Platform.pathSeparator}grove.sqlite';

      var db = Database.open(path);
      var s = AppStore(repos: Repos(db));
      final (g, a, _) = planned(s, ['Chapter 3']);
      s.assignGoalSubtask(subId(s, g, 'Chapter 3'), to: a);
      s.dispose();
      db.close();

      db = Database.open(path);
      s = AppStore(repos: Repos(db));
      expect(s.goalSubtasks(g.id).single.eventId, a);
      expect(rowNames(rows(s, a)), ['Chapter 3']);
      s.dispose();
      db.close();
    });
  });

  group('A subtask dragged out of the Goals panel', () {
    test('a subtask payload is parsed back to its id', () {
      expect(DragPayload.goalSubtaskPrefix, 'grove-goal-subtask:');
      expect(DragPayload.goalSubtask('ABC'), 'grove-goal-subtask:ABC');
      expect(DragPayload.goalSubtaskId(DragPayload.goalSubtask('ABC')), 'ABC');
    });

    test('other payloads and text are not subtasks of a goal', () {
      expect(DragPayload.goalSubtaskId(DragPayload.goal('ABC')), isNull);
      expect(DragPayload.goalSubtaskId(DragPayload.task('ABC')), isNull);
      expect(DragPayload.goalSubtaskId(DragPayload.note('ABC')), isNull);
      expect(DragPayload.goalSubtaskId('plain text'), isNull);
      expect(DragPayload.goalSubtaskId('grove-goal-subtask:'), isNull);
    });

    test('goals, tasks and notes ignore a subtask payload', () {
      final raw = DragPayload.goalSubtask('ABC');
      expect(DragPayload.goalId(raw), isNull);
      expect(DragPayload.noteId(raw), isNull);
      expect(raw.startsWith(DragPayload.taskPrefix), isFalse);
    });

    test('a drop on a block of the same goal plans it there', () {
      final s = makeStore();
      final (g, a, b) = planned(s, ['Chapter 3']);
      final raw = DragPayload.goalSubtask(subId(s, g, 'Chapter 3'));
      expect(s.canDropGoalSubtask(raw: raw, blockId: a), isTrue);
      expect(s.dropGoalSubtaskOnBlock(raw: raw, blockId: a), isTrue);
      expect(rowNames(rows(s, a)), ['Chapter 3']);
      // It is in this block now. The other block can take it.
      expect(s.canDropGoalSubtask(raw: raw, blockId: a), isFalse);
      expect(s.canDropGoalSubtask(raw: raw, blockId: b), isTrue);
    });

    test('a drop on another block, or of another thing, does nothing', () {
      final s = makeStore();
      final (g, a, _) = planned(s, ['Chapter 3']);
      final gym = s.addGoal(title: 'Gym')!;
      s.scheduleGoal(goalId: gym.id, day: monday, start: 900);
      final other = s.selection.single;
      final raw = DragPayload.goalSubtask(subId(s, g, 'Chapter 3'));
      final steps = s.undoStack.length;
      expect(s.canDropGoalSubtask(raw: raw, blockId: other), isFalse);
      expect(s.dropGoalSubtaskOnBlock(raw: raw, blockId: other), isFalse);
      for (final bad in [
        DragPayload.goal(g.id),
        DragPayload.task('x'),
        DragPayload.goalSubtask('missing'),
        'plain text',
      ]) {
        expect(s.canDropGoalSubtask(raw: bad, blockId: a), isFalse);
        expect(s.dropGoalSubtaskOnBlock(raw: bad, blockId: a), isFalse);
      }
      expect(s.undoStack.length, steps);
      expect(rows(s, a), isEmpty);
      expect(rows(s, other), isEmpty);
    });

    test('a done subtask cannot be dragged into a block', () {
      final s = makeStore();
      final (g, a, _) = planned(s, ['Chapter 3']);
      final id = subId(s, g, 'Chapter 3');
      s.toggleGoalSubtask(id);
      final raw = DragPayload.goalSubtask(id);
      expect(s.canDropGoalSubtask(raw: raw, blockId: a), isFalse);
      expect(s.dropGoalSubtaskOnBlock(raw: raw, blockId: a), isFalse);
      expect(rows(s, a), isEmpty);
    });
  });

  group('The mark of the block on a planned subtask', () {
    test('it says the day and the start of the block', () {
      String mark(DayKey day, int minute, {DayKey? today}) =>
          GoalSubtaskRules.planMark(
            WallTime(day: day, minute: minute),
            today: today ?? monday,
          );
      expect(mark(monday, 600), 'Today 10:00');
      expect(mark(tuesday, 840), 'Tue 14:00');
      expect(mark(monday.adding(days: 6), 545), 'Sun 09:05');
      // A week or more away, or a day that is over: the date.
      expect(mark(monday.adding(days: 7), 600), '12 Oct 10:00');
      expect(mark(monday.adding(days: -1), 600), '4 Oct 10:00');
    });

    test('the store gives the mark of each planned subtask', () {
      final s = makeStore();
      s.clockOverride = WallTime(day: monday, minute: 480);
      final (g, a, b) = planned(s, ['One', 'Two', 'Three']);
      s.assignGoalSubtask(subId(s, g, 'One'), to: a);
      s.assignGoalSubtask(subId(s, g, 'Two'), to: b);
      expect(s.goalSubtaskMarks(s.goalSubtasks(g.id)), {
        subId(s, g, 'One'): 'Today 10:00',
        subId(s, g, 'Two'): 'Tue 14:00',
      });
      // The block moves: the mark moves with it.
      s.applyEdits(
        [BlockEdit(id: b, day: tuesday, start: 900, end: 960)],
        ripple: false,
        name: 'Move',
      );
      expect(
        s.goalSubtaskMarks(s.goalSubtasks(g.id))[subId(s, g, 'Two')],
        'Tue 15:00',
      );
      expect(s.goalSubtaskMarks(const []), isEmpty);
    });
  });

  group('What a closed goal shows', () {
    test('up to three subtasks show, in list order', () {
      expect(GoalSubtaskRules.closedCount, 3);
      expect(GoalSubtaskRules.closed(const []), isEmpty);
      expect(names(GoalSubtaskRules.closed(list(open: 2))), [
        'Open 0',
        'Open 1',
      ]);
      expect(names(GoalSubtaskRules.closed(list(open: 5))), [
        'Open 0',
        'Open 1',
        'Open 2',
      ]);
    });

    test('done subtasks do not take a place', () {
      final subs = [
        ...list(done: 2),
        ...list(open: 4).map((s) => s.copyWith(sort: s.sort + 10)),
      ];
      expect(names(GoalSubtaskRules.closed(subs)), [
        'Open 0',
        'Open 1',
        'Open 2',
      ]);
      expect(GoalSubtaskRules.closed(list(done: 3)), isEmpty);
    });

    test('the line under them says what is not shown', () {
      String? line({int open = 0, int done = 0}) =>
          GoalSubtaskRules.moreLine(list(open: open, done: done));
      expect(line(), isNull);
      expect(line(open: 3), isNull);
      expect(line(open: 5), '+2 more');
      expect(line(open: 4), '+1 more');
      expect(line(open: 5, done: 2), '+2 more · 2 done');
      expect(line(open: 2, done: 1), '1 done');
      expect(line(done: 4), '4 done');
    });
  });
}
