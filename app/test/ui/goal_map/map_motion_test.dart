import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/goals/goal_graph.dart';
import 'package:grove/core/goals/goal_map_layout.dart';
import 'package:grove/core/model/goal_square.dart';
import 'package:grove/ui/goal_map/map_motion.dart';

const goal = 'G';
final root = GoalSquare.rootIdOf(goal);

GoalGraph graph(List<String> ids, List<(String, String)> links) =>
    GoalGraph.build(
      goal,
      [
        GoalSquare(id: root, goalId: goal, title: 'R'),
        for (final id in ids) GoalSquare(id: id, goalId: goal, title: id),
      ],
      [for (final (c, p) in links) SquareLink(childId: c, parentId: p)],
    );

Offset place(GoalMapLayout l, String id) => Offset(l.at(id).x, l.at(id).y);

void main() {
  final two = graph(['a', 'b'], [('a', root), ('b', 'a')]);
  final three = graph(['a', 'b', 'c'], [('a', root), ('b', 'a'), ('c', 'b')]);
  final l2 = GoalMapLayout.of(two), l3 = GoalMapLayout.of(three);

  test('at the start of a move each square is where it was; at the end it is '
      'at its new place', () {
    final m = MapMotion()..jump(l2);
    m.moveTo(l3, two);
    expect(m.t, 0);
    expect(m.place('a'), place(l2, 'a'));
    m.t = 1;
    expect(m.place('a'), place(l3, 'a'));
  });

  test('a move that starts in a move goes on from where the square is', () {
    final m = MapMotion()..jump(l2);
    m.moveTo(l3, two);
    m.t = 0.5;
    final middle = m.place('a');
    expect(middle, isNot(place(l2, 'a')));
    m.moveTo(l2, three);
    expect(m.place('a'), middle);
  });

  test('a new square is clear at the start of the move and solid at the '
      'end', () {
    final m = MapMotion()..jump(l2);
    m.moveTo(l3, two);
    expect(m.alphaOf('c'), 0);
    m.t = 1;
    expect(m.alphaOf('c'), 1);
    expect(m.scaleOf('c'), 1);
  });

  test('a square that leaves shrinks into its parent and then is gone', () {
    final m = MapMotion()..jump(l3);
    m.moveTo(l2, three);
    final c = m.leaving.single;
    expect(c.id, 'c');
    expect(c.start, place(l3, 'c'));
    expect(c.end, place(l2, 'b'));
    m.t = 0.2;
    expect(m.leavingScale(), lessThan(1));
    m.t = 1;
    expect(m.leavingAlpha(), 0);
    m.settle();
    expect(m.leaving, isEmpty);
  });

  test('a line goes between its squares in every moment of a move', () {
    final m = MapMotion()..jump(l2);
    m.moveTo(l3, two);
    for (final t in [0.0, 0.3, 0.7, 1.0]) {
      m.t = t;
      for (final e in m.edges) {
        expect(m.pointsOf(e).length, greaterThanOrEqualTo(2));
      }
    }
  });

  test('a new map grows out of its root: the root first, far squares last', () {
    final m = MapMotion()..jump(l2);
    m.growInto(l3, three);
    expect(m.place('c'), place(l3, root));
    m.t = 0.4;
    expect(m.alphaOf(root), greaterThan(m.alphaOf('c')));
    m.t = 1;
    expect(m.place('c'), place(l3, 'c'));
    expect(m.alphaOf('c'), 1);
    m.settle();
    expect(m.isMoving, isFalse);
  });

  test('a jump has nothing to move', () {
    final m = MapMotion()..jump(l2);
    expect(m.isMoving, isFalse);
    expect(m.place('b'), place(l2, 'b'));
    expect(m.leaving, isEmpty);
  });
}
