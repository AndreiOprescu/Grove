import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/goals/goal_graph.dart';
import 'package:grove/core/model/goal_square.dart';

const goal = 'G';
final root = GoalSquare.rootIdOf(goal);

GoalSquare sq(
  String id, {
  String? done,
  int? wait,
  String? waitStart,
  double sort = 0,
}) => GoalSquare(
  id: id,
  goalId: goal,
  title: id,
  doneAt: done,
  waitMinutes: wait,
  waitStartedAt: waitStart,
  sort: sort,
);

SquareLink l(String child, String parent) =>
    SquareLink(childId: child, parentId: parent);

GoalGraph graph(List<GoalSquare> squares, List<SquareLink> links) =>
    GoalGraph.build(goal, squares, links);

void main() {
  group('effective graph', () {
    test('a child is what must be done before its parent', () {
      final g = graph([sq(root), sq('a')], [l('a', root)]);
      expect(g.childrenOf(root), ['a']);
      expect(g.parentsOf('a'), [root]);
      expect(g.droppedLinks, isEmpty);
      expect(g.addedLinks, isEmpty);
    });

    test('one square can have many parents', () {
      final g = graph(
        [sq(root), sq('a'), sq('b'), sq('c')],
        [l('a', root), l('b', root), l('c', 'a'), l('c', 'b')],
      );
      expect(g.parentsOf('c'), ['a', 'b']);
    });

    test('a missing root gets a stand-in, so the map still draws', () {
      final g = graph([sq('a')], [l('a', root)]);
      expect(g.rootId, root);
      expect(g.square(root).title, '');
      expect(g.childrenOf(root), ['a']);
    });

    test('ignores self links, unknown squares and squares of other goals', () {
      final other = GoalSquare(id: 'x', goalId: 'OTHER', title: 'x');
      final g = graph(
        [sq(root), sq('a'), other],
        [
          l('a', 'a'),
          l('a', 'nope'),
          l('nope', 'a'),
          l('a', 'x'),
          l('a', root),
        ],
      );
      expect(g.ids, unorderedEquals([root, 'a']));
      expect(g.parentsOf('a'), [root]);
      expect(g.droppedLinks.length, 4);
    });

    test('the root can never be a child', () {
      final g = graph([sq(root), sq('a')], [l('a', root), l(root, 'a')]);
      expect(g.parentsOf(root), isEmpty);
      expect(g.droppedLinks, [l(root, 'a')]);
    });

    test('a loop from a sync merge loses one link and does not crash', () {
      final g = graph(
        [sq(root), sq('a'), sq('b')],
        [l('a', root), l('b', 'a'), l('a', 'b')],
      );
      expect(g.parentsOf('a'), [root]);
      expect(g.parentsOf('b'), ['a']);
      expect(g.droppedLinks, [l('a', 'b')]);
    });

    test('a square with no parent left joins the root', () {
      final g = graph([sq(root), sq('a'), sq('b')], [l('a', 'b')]);
      expect(g.parentsOf('b'), [root]);
      expect(g.parentsOf('a'), ['b']);
      expect(g.addedLinks, [l('b', root)]);
    });

    test('a loop cut off from the root joins it at one place', () {
      final g = graph([sq(root), sq('a'), sq('b')], [l('a', 'b'), l('b', 'a')]);
      expect(g.addedLinks.length, 1);
      expect(g.droppedLinks.length, 1);
      for (final id in ['a', 'b']) {
        expect(g.parentsOf(id), hasLength(1));
      }
    });

    test('any input gives every square a path to the root, with no loop', () {
      final rnd = Random(7);
      for (var run = 0; run < 300; run++) {
        final n = 2 + rnd.nextInt(25);
        final ids = [root, for (var i = 0; i < n; i++) 's$i'];
        final squares = [for (final id in ids) sq(id)]..shuffle(rnd);
        final links = [
          for (var i = 0; i < rnd.nextInt(60); i++)
            l(ids[rnd.nextInt(ids.length)], ids[rnd.nextInt(ids.length)]),
        ];
        final g = graph(squares, links);
        final shuffled = graph(
          [...squares]..shuffle(rnd),
          [...links]..shuffle(rnd),
        );
        for (final id in ids) {
          expect(
            shuffled.parentsOf(id),
            g.parentsOf(id),
            reason: 'same result',
          );
          if (id != root) expect(g.parentsOf(id), isNotEmpty);
          expect(g.reachesRoot(id), isTrue);
        }
        // Every square has a rank, which is only possible with no loop.
        expect(g.ranks.length, ids.length);
      }
    });
  });

  group('state', () {
    test('no children, or all done, is ready; otherwise not ready', () {
      final g = graph(
        [sq(root), sq('a'), sq('b', done: '2026-11-05T10:00:00'), sq('c')],
        [l('a', root), l('b', 'a'), l('c', 'b')],
      );
      expect(g.stateOf('c'), SquareState.ready);
      expect(g.stateOf('b'), SquareState.done);
      expect(g.stateOf('a'), SquareState.ready);
      expect(g.stateOf(root), SquareState.notReady);
    });

    test('a waiting square stays waiting, even with open children', () {
      final g = graph(
        [
          sq(root),
          sq('a', wait: 60, waitStart: '2026-11-05T10:00:00'),
          sq('b'),
        ],
        [l('a', root), l('b', 'a')],
      );
      expect(g.stateOf('a'), SquareState.waiting);
    });

    test('the lists for the panel: ready, waiting and later', () {
      final g = graph(
        [
          sq(root),
          sq('a', sort: 2),
          sq('b', sort: 1),
          sq('w', wait: 60, waitStart: '2026-11-05T10:00:00'),
          sq('later'),
          sq('d', done: '2026-11-05T10:00:00'),
        ],
        [
          l('a', root),
          l('b', root),
          l('w', root),
          l('d', root),
          l('later', root),
          l('a', 'later'),
        ],
      );
      expect(g.readyIds, ['b', 'a']);
      expect(g.waitingIds, ['w']);
      expect(g.laterIds, ['later', root]);
      expect(g.openCount, 4);
      expect(g.stepCount, 5);
    });
  });

  group('wait', () {
    final start = DateTime(2026, 11, 5, 10);
    final s = sq('a', wait: 3 * 24 * 60, waitStart: '2026-11-05T10:00:00');

    test('none until "Start waiting"', () {
      final w = sq('a', wait: 60).waitAt(start);
      expect(w.phase, WaitPhase.none);
    });

    test('counts down, then stays over until the tick', () {
      expect(
        s.waitAt(start.add(const Duration(hours: 1))).phase,
        WaitPhase.running,
      );
      expect(
        s.waitAt(start.add(const Duration(hours: 1))).label,
        '3 days left',
      );
      expect(s.waitAt(start.add(const Duration(days: 2))).label, '1 day left');
      expect(
        s.waitAt(start.add(const Duration(days: 2, hours: 20))).label,
        '4 h left',
      );
      final over = s.waitAt(start.add(const Duration(days: 4, hours: 1)));
      expect(over.phase, WaitPhase.over);
      expect(over.label, '1 day over');
      expect(
        s.waitAt(start.add(const Duration(days: 3, minutes: 1))).label,
        'Wait is over',
      );
      expect(s.waitAt(start.add(const Duration(days: 6))).label, '3 days over');
    });

    test('a bad time or a missing length does not throw', () {
      expect(sq('a', waitStart: 'junk').waitAt(start).phase, WaitPhase.over);
      expect(
        sq('a', waitStart: '2026-11-05T10:00:00').waitAt(start).phase,
        WaitPhase.over,
      );
    });
  });

  group('edits', () {
    test('canLink refuses a loop, a repeat, the root as child and itself', () {
      final g = graph(
        [sq(root), sq('a'), sq('b'), sq('c')],
        [l('a', root), l('b', 'a'), l('c', root)],
      );
      expect(g.canLink(child: 'b', parent: 'c'), isTrue);
      expect(
        g.canLink(child: 'a', parent: 'b'),
        isFalse,
        reason: 'a loop',
      );
      expect(
        g.canLink(child: 'b', parent: 'a'),
        isFalse,
        reason: 'a repeat',
      );
      expect(g.canLink(child: root, parent: 'a'), isFalse);
      expect(g.canLink(child: 'a', parent: 'a'), isFalse);
      expect(g.canLink(child: 'nope', parent: 'a'), isFalse);
    });

    test('deleting a square joins its children to its parents', () {
      final g = graph(
        [sq(root), sq('i'), sq('s')],
        [l('i', root), l('s', 'i')],
      );
      final e = g.deleteEdit('i')!;
      expect(e.add, [l('s', root)]);
      expect(e.remove, unorderedEquals([l('i', root), l('s', 'i')]));
    });

    test('deleting does not repeat a link that is there', () {
      final g = graph(
        [sq(root), sq('i'), sq('s')],
        [l('i', root), l('s', 'i'), l('s', root)],
      );
      expect(g.deleteEdit('i')!.add, isEmpty);
    });

    test('deleting with many parents and children joins them all', () {
      final g = graph(
        [sq(root), sq('p1'), sq('p2'), sq('m'), sq('c1'), sq('c2')],
        [
          l('p1', root),
          l('p2', root),
          l('m', 'p1'),
          l('m', 'p2'),
          l('c1', 'm'),
          l('c2', 'm'),
        ],
      );
      expect(
        g.deleteEdit('m')!.add,
        unorderedEquals([
          l('c1', 'p1'),
          l('c1', 'p2'),
          l('c2', 'p1'),
          l('c2', 'p2'),
        ]),
      );
    });

    test('the root cannot be deleted', () {
      final g = graph([sq(root), sq('a')], [l('a', root)]);
      expect(g.deleteEdit(root), isNull);
    });

    test('removing the last parent joins the root', () {
      final g = graph(
        [sq(root), sq('a'), sq('b')],
        [l('a', root), l('b', 'a')],
      );
      final e = g.unlinkEdit(child: 'b', parent: 'a')!;
      expect(e.remove, [l('b', 'a')]);
      expect(e.add, [l('b', root)]);
    });

    test('removing one of two parents adds nothing', () {
      final g = graph(
        [sq(root), sq('a'), sq('b')],
        [l('a', root), l('b', 'a'), l('b', root)],
      );
      expect(g.unlinkEdit(child: 'b', parent: 'a')!.add, isEmpty);
    });

    test('the last link to the root cannot be removed', () {
      final g = graph([sq(root), sq('a')], [l('a', root)]);
      expect(g.unlinkEdit(child: 'a', parent: root), isNull);
    });

    test('repairs write what the effective graph worked out', () {
      final g = graph([sq(root), sq('a'), sq('b')], [l('a', 'a'), l('b', 'a')]);
      final r = g.repairEdit;
      expect(r.add, [l('a', root)]);
      expect(r.remove, [l('a', 'a')]);
    });
  });
}
