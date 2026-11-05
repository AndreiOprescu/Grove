import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/goals/goal_graph.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/event.dart';
import 'package:grove/core/model/goal.dart';
import 'package:grove/core/model/goal_square.dart';
import 'package:grove/core/model/goal_subtask.dart';
import 'package:grove/data/data.dart';

import 'helpers.dart';

// The squares of a project (shared migration 15), the links between them and
// the blocks that hold them.

GoalItem project(Repos r, {String id = 'G', String title = 'Delft'}) {
  final g = GoalItem(id: id, title: title, type: GoalType.project);
  r.goals.upsert(g);
  r.goalSquares.save(
    GoalSquare(id: GoalSquare.rootIdOf(id), goalId: id, title: title),
  );
  return g;
}

EventItem block(Repos r, String goalId, {int hour = 10}) {
  final e = EventItem(
    title: 'Block',
    start: WallTime.parse('2026-11-05T$hour:00')!,
    end: WallTime.parse('2026-11-05T${hour + 1}:00')!,
    kind: EventKind.block,
    goalId: goalId,
  );
  r.events.save(e);
  return e;
}

void main() {
  late Repos r;
  setUp(() => r = makeRepos());
  tearDown(() => r.db.close());

  group('goal fields', () {
    test('a project keeps its description', () {
      r.goals.upsert(
        GoalItem(
          id: 'G',
          title: 'Delft',
          notes: 'The AI hub work',
          type: GoalType.project,
          doneWhen: 'The report is in',
          workMinutes: 1200,
          dueDay: const DayKey('2026-12-01'),
          why: 'I want the job',
        ),
      );
      final g = r.goals.get('G')!;
      expect(g.isProject, isTrue);
      expect(g.notes, 'The AI hub work');
      expect(g.doneWhen, 'The report is in');
      expect(g.workMinutes, 1200);
      expect(g.dueDay, const DayKey('2026-12-01'));
      expect(g.why, 'I want the job');
    });

    test('a row with empty new columns reads as a plain habit', () {
      r.goals.upsert(GoalItem(id: 'G', title: 'Read'));
      r.db.execute(
        'UPDATE goals SET type = NULL, done_when = NULL, why = NULL '
        "WHERE id = 'G'",
      );
      final g = r.goals.get('G')!;
      expect(g.type, GoalType.habit);
      expect(g.doneWhen, '');
      expect(g.why, '');
      expect(g.workMinutes, isNull);
      expect(g.dueDay, isNull);
    });

    test('a type this build does not know reads as a habit', () {
      r.goals.upsert(GoalItem(id: 'G', title: 'Read'));
      r.db.execute("UPDATE goals SET type = 'odd' WHERE id = 'G'");
      expect(r.goals.get('G')!.type, GoalType.habit);
    });
  });

  group('squares', () {
    test('a save keeps the links and the block rows', () {
      project(r);
      final s = GoalSquare(id: 'a', goalId: 'G', title: 'Apply');
      r.goalSquares.save(s);
      r.goalSquares.addLink(
        SquareLink(childId: 'a', parentId: GoalSquare.rootIdOf('G')),
      );
      final e = block(r, 'G');
      r.goalSquares.addBlock('a', e.id);
      r.goalSquares.save(
        s.copyWith(waitMinutes: 4320, waitStartedAt: '2026-11-05T10:00:00'),
      );
      final got = r.goalSquares.get('a')!;
      expect(got.waitMinutes, 4320);
      expect(got.waitStartedAt, '2026-11-05T10:00:00');
      expect(r.goalSquares.linksForGoal('G'), hasLength(1));
      expect(r.goalSquares.blocksOf('a'), [e.id]);
    });

    test(
      'deleting a square takes its links and block rows; the block stays',
      () {
        project(r);
        r.goalSquares.save(GoalSquare(id: 'a', goalId: 'G', title: 'Apply'));
        r.goalSquares.addLink(
          SquareLink(childId: 'a', parentId: GoalSquare.rootIdOf('G')),
        );
        final e = block(r, 'G');
        r.goalSquares.addBlock('a', e.id);
        r.goalSquares.delete('a');
        expect(r.goalSquares.linksForGoal('G'), isEmpty);
        expect(r.goalSquares.forEvents([e.id]), isEmpty);
        expect(r.events.get(e.id), isNotNull);
      },
    );

    test('deleting a block takes the block row; the square stays', () {
      project(r);
      r.goalSquares.save(GoalSquare(id: 'a', goalId: 'G', title: 'Apply'));
      final e = block(r, 'G');
      r.goalSquares.addBlock('a', e.id);
      r.events.delete(e.id);
      expect(r.goalSquares.blocksOf('a'), isEmpty);
      expect(r.goalSquares.get('a'), isNotNull);
    });

    test('deleting a goal takes its squares; its blocks stay as plain '
        'blocks', () {
      project(r);
      r.goalSquares.save(GoalSquare(id: 'a', goalId: 'G', title: 'Apply'));
      final e = block(r, 'G');
      r.goalSquares.addBlock('a', e.id);
      r.goals.delete('G');
      expect(r.goalSquares.forGoal('G'), isEmpty);
      expect(r.events.get(e.id)!.goalId, isNull);
    });

    test('a block can hold many squares, and a square many blocks', () {
      project(r);
      r.goalSquares.save(GoalSquare(id: 'a', goalId: 'G', title: 'A', sort: 2));
      r.goalSquares.save(GoalSquare(id: 'b', goalId: 'G', title: 'B', sort: 1));
      final e1 = block(r, 'G', hour: 10);
      final e2 = block(r, 'G', hour: 12);
      r.goalSquares
        ..addBlock('a', e1.id)
        ..addBlock('b', e1.id)
        ..addBlock('a', e2.id)
        ..addBlock('a', e2.id);
      final held = r.goalSquares.forEvents([e1.id, e2.id]);
      expect([for (final s in held[e1.id]!) s.id], ['b', 'a']);
      expect([for (final s in held[e2.id]!) s.id], ['a']);
      expect(r.goalSquares.blocksOf('a'), unorderedEquals([e1.id, e2.id]));
    });

    test('roots finds the root of each project', () {
      project(r);
      r.goals.upsert(GoalItem(id: 'H', title: 'Read'));
      final roots = r.goalSquares.roots(['G', 'H']);
      expect(roots.keys, ['G']);
    });
  });

  group('make it a project', () {
    test('subtasks become squares under the root; ticks and plans stay', () {
      final g = GoalItem(id: 'G', title: 'Delft');
      r.goals.upsert(g);
      final e = block(r, 'G');
      r.goalSubtasks.save(
        GoalSubtaskItem(
          id: 's1',
          goalId: 'G',
          title: 'Read',
          sort: 1,
          doneAt: '2026-11-01T10:00:00',
        ),
      );
      r.goalSubtasks.save(
        GoalSubtaskItem(
          id: 's2',
          goalId: 'G',
          title: 'Write',
          sort: 2,
          eventId: e.id,
        ),
      );
      r.goalSquares.convert(g);

      expect(r.goals.get('G')!.isProject, isTrue);
      expect(r.goalSubtasks.forGoal('G'), isEmpty);
      final graph = GoalGraph.build(
        'G',
        r.goalSquares.forGoal('G'),
        r.goalSquares.linksForGoal('G'),
      );
      expect(graph.childrenOf(graph.rootId), ['sq:s1', 'sq:s2']);
      expect(graph.droppedLinks, isEmpty);
      expect(graph.addedLinks, isEmpty);
      expect(graph.square(graph.rootId).title, 'Delft');
      expect(graph.square('sq:s1').doneAt, '2026-11-01T10:00:00');
      expect(r.goalSquares.blocksOf('sq:s2'), [e.id]);
      // The block keeps its goal.
      expect(r.events.get(e.id)!.goalId, 'G');
    });

    test('a second run finds nothing to do', () {
      final g = GoalItem(id: 'G', title: 'Delft');
      r.goals.upsert(g);
      r.goalSubtasks.save(GoalSubtaskItem(id: 's', goalId: 'G', title: 'Read'));
      r.goalSquares.convert(g);
      final before = r.goalSquares.forGoal('G');
      r.goalSquares.convert(g);
      expect(r.goalSquares.forGoal('G'), before);
      expect(r.goalSquares.heal(), isFalse);
    });
  });

  group('heal', () {
    test('a goal with a root is a project', () {
      project(r);
      r.db.execute("UPDATE goals SET type = 'habit' WHERE id = 'G'");
      expect(r.goalSquares.heal(), isTrue);
      expect(r.goals.get('G')!.isProject, isTrue);
    });

    test('a project with no root gets one', () {
      r.goals.upsert(GoalItem(id: 'G', title: 'Delft', type: GoalType.project));
      expect(r.goalSquares.heal(), isTrue);
      expect(r.goalSquares.get(GoalSquare.rootIdOf('G'))!.title, 'Delft');
    });

    test('a late subtask of a project becomes a square', () {
      project(r);
      r.goalSubtasks.save(GoalSubtaskItem(id: 's', goalId: 'G', title: 'Read'));
      expect(r.goalSquares.heal(), isTrue);
      expect(r.goalSubtasks.forGoal('G'), isEmpty);
      expect(r.goalSquares.get('sq:s')!.title, 'Read');
      expect(r.goalSquares.linksForGoal('G'), [
        SquareLink(childId: 'sq:s', parentId: GoalSquare.rootIdOf('G')),
      ]);
    });

    test('a subtask of a habit stays; nothing changes', () {
      r.goals.upsert(GoalItem(id: 'G', title: 'Read'));
      r.goalSubtasks.save(GoalSubtaskItem(id: 's', goalId: 'G', title: 'Book'));
      expect(r.goalSquares.heal(), isFalse);
      expect(r.goalSubtasks.forGoal('G'), hasLength(1));
    });
  });
}
