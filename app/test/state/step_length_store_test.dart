import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final monday = d('2026-10-05');

String rootOf(GoalItem g) => GoalSquare.rootIdOf(g.id);

/// A project with one square [a] on a block of [length] minutes at 10:00.
(GoalItem, GoalSquare, String) plannedSquare(AppStore s, {int length = 60}) {
  final g = s.addProject(title: 'Delft')!;
  final a = s.addSquare(parentId: rootOf(g), title: 'a')!;
  s.scheduleSquare(squareId: a.id, day: monday, start: 600, length: length);
  return (g, a, s.selection.single);
}

void main() {
  group('a square and its block have the same length', () {
    test('a square with no length takes the length of its block', () {
      final s = makeStore();
      final (_, a, block) = plannedSquare(s, length: 90);
      expect(s.event(block)!.durationMinutes, 90);
      expect(s.goalSquare(a.id)!.lengthMinutes, 90);
    });

    test('a square with a length makes a block as long', () {
      final s = makeStore();
      final g = s.addProject(title: 'Delft')!;
      final a = s.addSquare(parentId: rootOf(g), title: 'a')!;
      s.setSquareLength(a.id, 45);
      s.scheduleSquare(squareId: a.id, day: monday, start: 600);
      expect(s.event(s.selection.single)!.durationMinutes, 45);
    });

    test('a longer block makes the square longer, in one undo step', () {
      final s = makeStore();
      final (_, a, block) = plannedSquare(s);
      final steps = s.undoStack.length;
      s.setDuration(blockIds: [block], minutes: 90);
      expect(s.goalSquare(a.id)!.lengthMinutes, 90);
      expect(s.undoStack.length, steps + 1);
      s.undo();
      expect(s.goalSquare(a.id)!.lengthMinutes, 60);
      expect(s.event(block)!.durationMinutes, 60);
    });

    test('a resize on the grid makes the square longer', () {
      final s = makeStore();
      final (_, a, block) = plannedSquare(s);
      s.applyEdits(
        [BlockEdit(id: block, day: monday, start: 600, end: 720)],
        ripple: false,
        name: 'Resize Block',
      );
      expect(s.goalSquare(a.id)!.lengthMinutes, 120);
    });

    test('a new length on the Goals screen moves the end of the block', () {
      final s = makeStore();
      final (_, a, block) = plannedSquare(s);
      s.setSquareLength(a.id, 30);
      expect(s.event(block)!.start, WallTime(day: monday, minute: 600));
      expect(s.event(block)!.durationMinutes, 30);
      s.undo();
      expect(s.event(block)!.durationMinutes, 60);
      expect(s.goalSquare(a.id)!.lengthMinutes, 60);
    });

    test('a length stays in 5 minutes to one day; the root has none', () {
      final s = makeStore();
      final g = s.addProject(title: 'Delft')!;
      final a = s.addSquare(parentId: rootOf(g), title: 'a')!;
      s.setSquareLength(a.id, 2);
      expect(s.goalSquare(a.id)!.lengthMinutes, 5);
      s.setSquareLength(a.id, 5000);
      expect(s.goalSquare(a.id)!.lengthMinutes, 1440);
      s.setSquareLength(a.id, null);
      expect(s.goalSquare(a.id)!.lengthMinutes, isNull);
      s.setSquareLength(rootOf(g), 30);
      expect(s.goalSquare(rootOf(g))!.lengthMinutes, isNull);
    });

    test('an old block with many steps keeps the length of each', () {
      final s = makeStore();
      final (g, a, block) = plannedSquare(s);
      final b = s.addSquare(parentId: rootOf(g), title: 'b')!;
      // An old block, from before one step per block, holds two.
      s.repos.goalSquares.addBlock(b.id, block);
      s.setDuration(blockIds: [block], minutes: 120);
      expect(s.goalSquare(a.id)!.lengthMinutes, 60);
      expect(s.goalSquare(b.id)!.lengthMinutes, isNull);
      s.setSquareLength(a.id, 15);
      expect(s.event(block)!.durationMinutes, 120);
    });
  });

  group('a block holds one step', () {
    test('a second square is refused, and says why', () {
      final s = makeStore();
      final (g, a, block) = plannedSquare(s);
      final b = s.addSquare(parentId: rootOf(g), title: 'b')!;
      s.addSquareToBlock(squareId: b.id, eventId: block);
      expect(s.squaresOfBlock(block).map((x) => x.id), [a.id]);
      expect(s.toast, 'A block holds one step.');
      expect(s.addSquareInBlock(block, title: 'c'), isNull);
      expect(s.freeSquares(block), isEmpty);
    });

    test('a planned square dragged again takes its block with it', () {
      final s = makeStore();
      final (_, a, block) = plannedSquare(s, length: 45);
      final tuesday = monday.adding(days: 1);
      s.scheduleSquare(squareId: a.id, day: tuesday, start: 840);
      expect(s.repos.goalSquares.blocksOf(a.id), [block]);
      expect(s.event(block)!.start, WallTime(day: tuesday, minute: 840));
      expect(s.event(block)!.durationMinutes, 45);
      expect(s.selection, {block});
    });

    test('a square in an old block with others gets its own block', () {
      final s = makeStore();
      final (g, a, block) = plannedSquare(s);
      final b = s.addSquare(parentId: rootOf(g), title: 'b')!;
      s.repos.goalSquares.addBlock(b.id, block);
      s.scheduleSquare(squareId: b.id, day: monday, start: 900);
      final made = s.selection.single;
      expect(made, isNot(block));
      expect(s.repos.goalSquares.blocksOf(b.id), [made]);
      expect(s.squaresOfBlock(block).map((x) => x.id), [a.id]);
    });
  });

  group('the time done of a goal', () {
    test('a ticked square with no block adds its length', () {
      final s = makeStore();
      final g = s.addProject(title: 'Delft')!;
      final a = s.addSquare(parentId: rootOf(g), title: 'a')!;
      s.setSquareLength(a.id, 45);
      expect(s.projectMinutes(g.id, doneOnly: true), 0);
      s.toggleSquareDone(a.id);
      expect(s.projectMinutes(g.id, doneOnly: true), 45);
      expect(s.projectMinutes(g.id), 45);
    });

    test('a ticked square on a ticked block counts once', () {
      final s = makeStore();
      final (g, a, block) = plannedSquare(s);
      s.toggleGoalBlockDone(eventId: block);
      s.toggleSquareDone(a.id);
      expect(s.goalSquare(a.id)!.isDone, isTrue);
      expect(s.projectMinutes(g.id, doneOnly: true), 60);
    });

    test('a ticked square on an open block adds its length', () {
      final s = makeStore();
      final (g, a, _) = plannedSquare(s);
      s.toggleSquareDone(a.id);
      expect(s.projectMinutes(g.id, doneOnly: true), 60);
    });

    test('a ticked subtask of an hours habit adds its length to the week', () {
      final s = makeStore();
      final g = s.addGoal(title: 'Read', target: 300)!;
      final id = s.addGoalSubtask(to: g.id, title: 'Chapter 1')!;
      s.setGoalSubtaskLength(id, 30);
      s.toggleGoalSubtask(id);
      // A tick is stamped with the real clock.
      final day = d(s.repos.goalSubtasks.get(id)!.doneAt!.substring(0, 10));
      expect(s.goalProgress(g.id, weekOf: day).done, 30);
      // A week later it is not in that week.
      expect(s.goalProgress(g.id, weekOf: day.adding(days: 7)).done, 0);
    });
  });

  group('a subtask of a habit and its block have the same length', () {
    test('a planned subtask follows its block, and the block follows it', () {
      final s = makeStore();
      final g = s.addGoal(title: 'Read')!;
      s.scheduleGoal(goalId: g.id, day: monday, start: 600);
      final block = s.selection.single;
      final id = s.addGoalSubtaskToBlock(block, title: 'Chapter 1')!;
      expect(s.repos.goalSubtasks.get(id)!.lengthMinutes, 60);
      s.setDuration(blockIds: [block], minutes: 75);
      expect(s.repos.goalSubtasks.get(id)!.lengthMinutes, 75);
      s.setGoalSubtaskLength(id, 40);
      expect(s.event(block)!.durationMinutes, 40);
    });

    test('a block with a subtask takes no second one', () {
      final s = makeStore();
      final g = s.addGoal(title: 'Read')!;
      s.scheduleGoal(goalId: g.id, day: monday, start: 600);
      final block = s.selection.single;
      s.addGoalSubtaskToBlock(block, title: 'Chapter 1');
      expect(s.addGoalSubtaskToBlock(block, title: 'Chapter 2'), isNull);
      expect(s.plannedGoalSubtasks(block), hasLength(1));
    });
  });
}
