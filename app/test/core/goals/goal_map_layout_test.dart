import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/goals/goal_graph.dart';
import 'package:grove/core/goals/goal_map_layout.dart';
import 'package:grove/core/model/goal_square.dart';

const goal = 'G';
final root = GoalSquare.rootIdOf(goal);

GoalSquare sq(String id, {double sort = 0}) =>
    GoalSquare(id: id, goalId: goal, title: id, sort: sort);
SquareLink l(String child, String parent) =>
    SquareLink(childId: child, parentId: parent);

GoalMapLayout lay(List<GoalSquare> squares, List<SquareLink> links) =>
    GoalMapLayout.of(GoalGraph.build(goal, squares, links));

void main() {
  test('first steps are on the left, the root on the right', () {
    final m = lay([sq(root), sq('i'), sq('s')], [l('i', root), l('s', 'i')]);
    expect(m.at('s').x, lessThan(m.at('i').x));
    expect(m.at('i').x, lessThan(m.at(root).x));
    expect(m.at('s').y, m.at(root).y);
  });

  test('a parent sits in the middle of its children', () {
    final m = lay(
      [sq(root), sq('a'), sq('b'), sq('c'), sq('d')],
      [l('a', root), l('b', root), l('c', root), l('d', root)],
    );
    final ys = [for (final id in 'abcd'.split('')) m.at(id).y];
    expect(ys.reduce((a, b) => a + b) / 4, closeTo(m.at(root).y, 0.001));
  });

  test('a square sits at its longest path from the root', () {
    final m = lay(
      [sq(root), sq('a'), sq('b')],
      [l('a', root), l('b', 'a'), l('b', root)],
    );
    expect(m.at('b').x, lessThan(m.at('a').x));
  });

  test('a new loose square sits left of all linked squares', () {
    final m = lay(
      [sq(root), sq('a'), sq('b'), sq('x')],
      [l('a', root), l('b', 'a')],
    );
    expect(m.at('x').x, lessThan(m.at('b').x));
    expect(m.edges.where((e) => e.childId == 'x'), isEmpty);
  });

  test('a loose square stays right of its children', () {
    final m = lay(
      [sq(root), sq('a'), sq('b'), sq('x'), sq('y')],
      [l('a', root), l('b', 'a'), l('b', 'x'), l('y', 'x')],
    );
    expect(m.at('b').x, lessThan(m.at('x').x));
    expect(m.at('y').x, lessThan(m.at('x').x));
  });

  test('a long link gets a path that goes around the layers between', () {
    final m = lay(
      [sq(root), sq('a'), sq('b')],
      [l('a', root), l('b', 'a'), l('b', root)],
    );
    final long = m.edges.firstWhere(
      (e) => e.childId == 'b' && e.parentId == root,
    );
    expect(long.points.length, greaterThan(2));
    final short = m.edges.firstWhere(
      (e) => e.childId == 'b' && e.parentId == 'a',
    );
    expect(short.points.length, 2);
  });

  test('the order follows sort when nothing else decides', () {
    final m = lay(
      [sq(root), sq('a', sort: 2), sq('b', sort: 1)],
      [l('a', root), l('b', root)],
    );
    expect(m.at('b').y, lessThan(m.at('a').y));
  });

  test('crossings go away where they can', () {
    // p1 needs c1, p2 needs c2. The sort order alone would cross them.
    final m = lay(
      [
        sq(root),
        sq('p1', sort: 1),
        sq('p2', sort: 2),
        sq('c1', sort: 2),
        sq('c2', sort: 1),
      ],
      [l('p1', root), l('p2', root), l('c1', 'p1'), l('c2', 'p2')],
    );
    expect(m.at('c1').y, lessThan(m.at('c2').y));
  });

  test(
    'same input in any order gives the same places; squares never overlap',
    () {
      final rnd = Random(11);
      for (var run = 0; run < 150; run++) {
        final n = 1 + rnd.nextInt(40);
        final ids = [root, for (var i = 0; i < n; i++) 's$i'];
        final squares = [for (final id in ids) sq(id)];
        final links = [
          for (var i = 0; i < rnd.nextInt(70); i++)
            l(ids[rnd.nextInt(ids.length)], ids[rnd.nextInt(ids.length)]),
        ];
        final a = lay(squares, links);
        final b = lay([...squares]..shuffle(rnd), [...links]..shuffle(rnd));
        for (final id in ids) {
          expect(b.at(id).x, a.at(id).x);
          expect(b.at(id).y, a.at(id).y);
          expect(a.at(id).x, greaterThanOrEqualTo(0));
          expect(a.at(id).y, greaterThanOrEqualTo(0));
        }
        for (var i = 0; i < ids.length; i++) {
          for (var j = i + 1; j < ids.length; j++) {
            final p = a.at(ids[i]);
            final q = a.at(ids[j]);
            final apart =
                (p.x - q.x).abs() >= GoalMapLayout.squareWidth ||
                (p.y - q.y).abs() >= GoalMapLayout.squareHeight;
            expect(apart, isTrue, reason: '${ids[i]} and ${ids[j]} overlap');
          }
        }
        // A child is always left of its parent, loose or not.
        for (final e in a.edges) {
          expect(a.at(e.childId).x, lessThan(a.at(e.parentId).x));
        }
        expect(a.width, greaterThanOrEqualTo(GoalMapLayout.squareWidth));
        expect(a.height, greaterThanOrEqualTo(GoalMapLayout.squareHeight));
      }
    },
  );

  test('a map of 50 squares and 70 links takes little time', () {
    final rnd = Random(3);
    final ids = [root, for (var i = 0; i < 49; i++) 's$i'];
    final squares = [for (final id in ids) sq(id)];
    final links = [
      for (var i = 0; i < 70; i++)
        l(ids[rnd.nextInt(ids.length)], ids[rnd.nextInt(ids.length)]),
    ];
    final w = Stopwatch()..start();
    lay(squares, links);
    expect(w.elapsedMilliseconds, lessThan(100));
  });
}
