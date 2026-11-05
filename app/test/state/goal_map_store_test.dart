import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

import 'package:grove/core/model/goal_subtask.dart';

final monday = d('2026-10-05');

GoalGraph graphOf(AppStore s, String id) => s.goalGraph(id)!;

String rootOf(GoalItem g) => GoalSquare.rootIdOf(g.id);

void main() {
  group('a project', () {
    test('needs no field, and it has its root at once', () {
      final s = makeStore();
      final g = s.addProject()!;
      expect(s.goal(g.id)!.isProject, isTrue);
      expect(s.goal(g.id)!.title, '');
      expect(graphOf(s, g.id).ids, [rootOf(g)]);
    });

    test('saves all fields, and a field can be emptied', () {
      final s = makeStore();
      final g = s.addProject(
        title: 'Delft',
        notes: 'AI hub',
        doneWhen: 'They reply',
        workMinutes: 600,
        dueDay: monday,
        why: 'Work',
      )!;
      final read = s.goal(g.id)!;
      expect(read.doneWhen, 'They reply');
      expect(read.workMinutes, 600);
      expect(read.dueDay, monday);
      expect(read.why, 'Work');
      s.updateProject(g.id, title: 'Delft hub', workMinutes: null);
      expect(s.goal(g.id)!.workMinutes, isNull);
      expect(s.goal(g.id)!.dueDay, monday);
      expect(s.goalSquare(rootOf(g))!.title, 'Delft hub');
    });

    test('undo takes the project and its root away', () {
      final s = makeStore();
      final g = s.addProject(title: 'A')!;
      s.undo();
      expect(s.goal(g.id), isNull);
      expect(s.goalGraph(g.id), isNull);
      s.redo();
      expect(graphOf(s, g.id).ids, [rootOf(g)]);
    });

    test('deleting it takes the map; undo brings all back', () {
      final s = makeStore();
      final g = s.addProject(title: 'A')!;
      final a = s.addSquare(parentId: rootOf(g), title: 'a')!;
      s.scheduleSquare(squareId: a.id, day: monday, start: 600);
      final block = s.selection.single;
      s.deleteGoal(g.id);
      expect(s.goalSquare(a.id), isNull);
      s.undo();
      expect(graphOf(s, g.id).parentsOf(a.id), [rootOf(g)]);
      expect(s.squaresOfBlock(block).map((x) => x.id), [a.id]);
      expect(s.event(block)!.goalId, g.id);
    });
  });

  group('the map', () {
    test('a new square is a child of the square it came from', () {
      final s = makeStore();
      final g = s.addProject(title: 'A')!;
      final a = s.addSquare(parentId: rootOf(g), title: ' a ')!;
      final b = s.addSquare(parentId: a.id, title: 'b')!;
      final graph = graphOf(s, g.id);
      expect(graph.square(a.id).title, 'a');
      expect(graph.childrenOf(a.id), [b.id]);
      expect(graph.square(b.id).sort, greaterThan(graph.square(a.id).sort));
      s.undo();
      expect(s.goalSquare(b.id), isNull);
      expect(graphOf(s, g.id).childrenOf(a.id), isEmpty);
    });

    test('a deleted square gives its children to its parents; undo puts all '
        'back', () {
      final s = makeStore();
      final g = s.addProject(title: 'A')!;
      final a = s.addSquare(parentId: rootOf(g), title: 'a')!;
      final b = s.addSquare(parentId: a.id, title: 'b')!;
      expect(s.deleteSquare(a.id), isTrue);
      expect(s.goalSquare(a.id), isNull);
      expect(graphOf(s, g.id).parentsOf(b.id), [rootOf(g)]);
      expect(s.repos.goalSquares.linksForGoal(g.id), [
        SquareLink(childId: b.id, parentId: rootOf(g)),
      ]);
      s.undo();
      final back = graphOf(s, g.id);
      expect(back.parentsOf(a.id), [rootOf(g)]);
      expect(back.parentsOf(b.id), [a.id]);
      expect(back.parentsOf(b.id), isNot(contains(rootOf(g))));
    });

    test('the root cannot be deleted', () {
      final s = makeStore();
      final g = s.addProject(title: 'A')!;
      expect(s.deleteSquare(rootOf(g)), isFalse);
      expect(s.goalSquare(rootOf(g)), isNotNull);
    });

    test('a link that makes a loop is refused', () {
      final s = makeStore();
      final g = s.addProject(title: 'A')!;
      final a = s.addSquare(parentId: rootOf(g), title: 'a')!;
      final b = s.addSquare(parentId: a.id, title: 'b')!;
      final other = s.addSquare(parentId: rootOf(g), title: 'c')!;
      expect(s.linkSquares(child: a.id, parent: b.id), isFalse);
      expect(s.linkSquares(child: rootOf(g), parent: a.id), isFalse);
      expect(s.linkSquares(child: b.id, parent: other.id), isTrue);
      expect(graphOf(s, g.id).parentsOf(b.id), containsAll([a.id, other.id]));
      s.undo();
      expect(graphOf(s, g.id).parentsOf(b.id), [a.id]);
    });

    test('removing the last link leaves the square on the root', () {
      final s = makeStore();
      final g = s.addProject(title: 'A')!;
      final a = s.addSquare(parentId: rootOf(g), title: 'a')!;
      final b = s.addSquare(parentId: a.id, title: 'b')!;
      s.unlinkSquares(child: b.id, parent: a.id);
      expect(graphOf(s, g.id).parentsOf(b.id), [rootOf(g)]);
      s.undo();
      expect(graphOf(s, g.id).parentsOf(b.id), [a.id]);
    });

    test('the next edit writes a repair of the rows, and undo is exact', () {
      final s = makeStore();
      final g = s.addProject(title: 'A')!;
      final a = s.addSquare(parentId: rootOf(g), title: 'a')!;
      final b = s.addSquare(parentId: a.id, title: 'b')!;
      // A merge of two devices made a loop.
      s.repos.goalSquares.addLink(SquareLink(childId: a.id, parentId: b.id));
      final graph = graphOf(s, g.id);
      expect(graph.droppedLinks, isNotEmpty);
      s.addSquare(parentId: a.id, title: 'c');
      expect(graphOf(s, g.id).droppedLinks, isEmpty);
    });

    test('a tick of a square, and of the root, can be taken back', () {
      final s = makeStore();
      final g = s.addProject(title: 'A')!;
      final a = s.addSquare(parentId: rootOf(g), title: 'a')!;
      s.toggleSquareDone(a.id);
      expect(s.goalSquare(a.id)!.isDone, isTrue);
      expect(s.isProjectFinished(g.id), isFalse);
      s.toggleSquareDone(rootOf(g));
      expect(s.isProjectFinished(g.id), isTrue);
      s.toggleSquareDone(rootOf(g));
      expect(s.isProjectFinished(g.id), isFalse);
      s.undo();
      expect(s.isProjectFinished(g.id), isTrue);
    });
  });

  group('a wait', () {
    test('starts with a length and shows in the state; it ends by a tick', () {
      final s = makeStore();
      final g = s.addProject(title: 'A')!;
      final a = s.addSquare(parentId: rootOf(g), title: 'a')!;
      s.startWaiting(a.id, minutes: 3 * 24 * 60);
      final w = s.goalSquare(a.id)!;
      expect(w.waitMinutes, 3 * 24 * 60);
      expect(w.isWaiting, isTrue);
      expect(graphOf(s, g.id).stateOf(a.id), SquareState.waiting);
      s.toggleSquareDone(a.id);
      expect(graphOf(s, g.id).stateOf(a.id), SquareState.done);
    });

    test('with no length it takes 3 days, and it can stop', () {
      final s = makeStore();
      final g = s.addProject(title: 'A')!;
      final a = s.addSquare(parentId: rootOf(g), title: 'a')!;
      s.startWaiting(a.id);
      expect(s.goalSquare(a.id)!.waitMinutes, 3 * 24 * 60);
      s.stopWaiting(a.id);
      expect(s.goalSquare(a.id)!.isWaiting, isFalse);
      expect(graphOf(s, g.id).stateOf(a.id), SquareState.ready);
    });

    test('the root has no wait', () {
      final s = makeStore();
      final g = s.addProject(title: 'A')!;
      s.startWaiting(rootOf(g));
      expect(s.goalSquare(rootOf(g))!.isWaiting, isFalse);
    });
  });

  group('blocks', () {
    test('a dragged square makes a block that holds it, with its name', () {
      final s = makeStore();
      final g = s.addProject(title: 'A')!;
      final a = s.addSquare(parentId: rootOf(g), title: 'Write')!;
      expect(
        s.dropSquareOnPlanner(
          raw: DragPayload.square(a.id),
          day: monday,
          minute: 600,
        ),
        isTrue,
      );
      final block = s.event(s.selection.single)!;
      expect(block.title, 'Write');
      expect(block.goalId, g.id);
      expect(s.squaresOfBlock(block.id).single.id, a.id);
      s.undo();
      expect(s.event(block.id), isNull);
      expect(s.repos.goalSquares.blocksOf(a.id), isEmpty);
    });

    test('a drag text that is not a square does nothing', () {
      final s = makeStore();
      final g = s.addProject(title: 'A')!;
      expect(
        s.dropSquareOnPlanner(
          raw: DragPayload.goal(g.id),
          day: monday,
          minute: 600,
        ),
        isFalse,
      );
    });

    test('deleting a block keeps the square; undo brings the row back', () {
      final s = makeStore();
      final g = s.addProject(title: 'A')!;
      final a = s.addSquare(parentId: rootOf(g), title: 'a')!;
      s.scheduleSquare(squareId: a.id, day: monday, start: 600);
      final block = s.selection.single;
      final e = s.event(block)!;
      s.commit(Mutation('Delete')..events.add((before: e, after: null)));
      expect(s.goalSquare(a.id), isNotNull);
      expect(s.repos.goalSquares.blocksOf(a.id), isEmpty);
      s.undo();
      expect(s.repos.goalSquares.blocksOf(a.id), [block]);
    });

    test('a square from another goal cannot go in a block', () {
      final s = makeStore();
      final g = s.addProject(title: 'A')!;
      final h = s.addProject(title: 'B')!;
      final a = s.addSquare(parentId: rootOf(g), title: 'a')!;
      final b = s.addSquare(parentId: rootOf(h), title: 'b')!;
      s.scheduleSquare(squareId: a.id, day: monday, start: 600);
      final block = s.selection.single;
      s.addSquareToBlock(squareId: b.id, eventId: block);
      expect(s.squaresOfBlock(block).map((x) => x.id), [a.id]);
      s.removeSquareFromBlock(squareId: a.id, eventId: block);
      expect(s.squaresOfBlock(block), isEmpty);
    });

    test('the answers of a block tick are one undo step', () {
      final s = makeStore();
      final g = s.addProject(title: 'A')!;
      final a = s.addSquare(parentId: rootOf(g), title: 'a')!;
      final b = s.addSquare(parentId: rootOf(g), title: 'b')!;
      final c = s.addSquare(parentId: rootOf(g), title: 'c')!;
      s.scheduleSquare(squareId: a.id, day: monday, start: 600);
      final block = s.selection.single;
      s.addSquareToBlock(squareId: b.id, eventId: block);
      s.addSquareToBlock(squareId: c.id, eventId: block);
      expect(s.openSquaresOfBlock(block), hasLength(3));
      s.answerBlockTick(
        eventId: block,
        answers: {
          a.id: SquareAnswer.done,
          b.id: const SquareAnswer(
            SquareAnswerKind.startWaiting,
            waitMinutes: 1440,
          ),
          c.id: SquareAnswer.notYet,
        },
      );
      expect(s.event(block)!.doneAt, isNotNull);
      expect(s.goalSquare(a.id)!.isDone, isTrue);
      expect(s.goalSquare(b.id)!.isWaiting, isTrue);
      expect(s.goalSquare(b.id)!.waitMinutes, 1440);
      expect(s.goalSquare(c.id)!.isDone, isFalse);
      expect(s.goalSquare(c.id)!.isWaiting, isFalse);
      expect(s.openSquaresOfBlock(block).map((x) => x.id), [b.id, c.id]);
      s.undo();
      expect(s.event(block)!.doneAt, isNull);
      expect(s.goalSquare(a.id)!.isDone, isFalse);
      expect(s.goalSquare(b.id)!.isWaiting, isFalse);
    });
  });

  group('make it a project', () {
    test('subtasks become squares; blocks stay; undo gives the habit back', () {
      final s = makeStore();
      final g = s.addGoal(title: 'Read')!;
      s.scheduleGoal(goalId: g.id, day: monday, start: 600);
      final block = s.selection.single;
      final subId = s.addGoalSubtask(to: g.id, title: 'Chapter 1')!;
      s.repos.goalSubtasks.save(
        s.repos.goalSubtasks.get(subId)!.copyWith(eventId: block),
      );
      s.makeProject(g.id);
      expect(s.goal(g.id)!.isProject, isTrue);
      expect(s.event(block)!.goalId, g.id);
      expect(s.goalSubtasks(g.id), isEmpty);
      final id = GoalSquare.idFromSubtask(subId);
      final graph = graphOf(s, g.id);
      expect(graph.square(id).title, 'Chapter 1');
      expect(graph.parentsOf(id), [rootOf(g)]);
      expect(s.squaresOfBlock(block).map((x) => x.id), [id]);
      s.undo();
      expect(s.goal(g.id)!.isProject, isFalse);
      expect(s.goalGraph(g.id), isNull);
      expect(s.goalSubtasks(g.id).single.eventId, block);
    });

    test('a project stays as it is', () {
      final s = makeStore();
      final g = s.addProject(title: 'A')!;
      final name = s.undoName;
      s.makeProject(g.id);
      expect(s.undoName, name);
    });
  });

  test('project hours count every block, on any day', () {
    final s = makeStore();
    final g = s.addProject(title: 'A')!;
    final a = s.addSquare(parentId: rootOf(g), title: 'a')!;
    s.scheduleSquare(squareId: a.id, day: monday, start: 600, length: 60);
    final first = s.selection.single;
    s.scheduleSquare(
      squareId: a.id,
      day: monday.adding(days: 40),
      start: 600,
      length: 30,
    );
    expect(s.projectMinutes(g.id), 90);
    expect(s.projectMinutes(g.id, doneOnly: true), 0);
    s.toggleGoalBlockDone(eventId: first);
    expect(s.projectMinutes(g.id, doneOnly: true), 60);
  });

  test('a replan gives the open squares to the rest of the work', () {
    final s = makeStore(clock: WallTime(day: monday, minute: 630));
    final g = s.addProject(title: 'A')!;
    final a = s.addSquare(parentId: rootOf(g), title: 'a')!;
    final b = s.addSquare(parentId: rootOf(g), title: 'b')!;
    s.scheduleSquare(squareId: a.id, day: monday, start: 600, length: 120);
    final block = s.selection.single;
    s.addSquareToBlock(squareId: b.id, eventId: block);
    s.toggleSquareDone(b.id);
    final steps = s.undoStack.length;
    s.applyReplan({block: 50});
    expect(s.undoStack.length, steps + 1);
    final rest = s.repos.events
        .blocksForGoal(g.id)
        .firstWhere((e) => e.id != block);
    expect(s.repos.goalSquares.blocksOf(a.id), [rest.id]);
    expect(s.repos.goalSquares.blocksOf(b.id), [block]);
    s.undo();
    expect(s.repos.goalSquares.blocksOf(a.id), [block]);
  });

  test('a pull that leaves a late subtask on a project makes a square', () {
    final repos = Repos(Database.inMemory());
    final s = makeStore(repos: repos);
    final g = s.addProject(title: 'A')!;
    repos.goalSubtasks.save(
      GoalSubtaskItem(id: 'late', goalId: g.id, title: 'Late', sort: 1),
    );
    s.resetAfterReplace();
    expect(graphOf(s, g.id).contains(GoalSquare.idFromSubtask('late')), isTrue);
    expect(s.goalSubtasks(g.id), isEmpty);
  });
}
