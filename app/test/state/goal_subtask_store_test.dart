import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/goal_subtask.dart';

import 'support.dart';

// Subtasks of a goal. The list belongs to the goal, not to one block: every
// block of the goal, on any day, has the same list. The Goals panel shows
// it. The subtasks of one block (`block_subtasks`) are another list.

// 2026-10-05 is a Monday.
final monday = d('2026-10-05');

List<String> names(Iterable<GoalSubtaskItem> subs) => [
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
