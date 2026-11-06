import 'dart:math';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/goals/goal_graph.dart';
import 'package:grove/core/goals/goal_map_layout.dart';
import 'package:grove/core/model/goal_square.dart';
import 'package:grove/ui/goal_map/goal_map_view.dart';
import 'package:grove/ui/goal_map/square_tile.dart';

const goal = 'G';
final root = GoalSquare.rootIdOf(goal);

GoalSquare sq(String id, {String? doneAt, String? started, int? wait}) =>
    GoalSquare(
      id: id,
      goalId: goal,
      title: id,
      doneAt: doneAt,
      waitStartedAt: started,
      waitMinutes: wait,
    );

GoalGraph chain(
  List<String> ids, {
  Set<String> done = const {},
  String id = goal,
}) {
  final rootId = GoalSquare.rootIdOf(id);
  final all = [rootId, ...ids];
  return GoalGraph.build(
    id,
    [
      for (final s in all)
        GoalSquare(
          id: s,
          goalId: id,
          title: s,
          doneAt: done.contains(s) ? '2026-11-05T10:00:00' : null,
        ),
    ],
    [
      for (var i = 1; i < all.length; i++)
        SquareLink(childId: all[i], parentId: all[i - 1]),
    ],
  );
}

Widget host(
  GoalGraph graph, {
  String goalId = goal,
  bool motion = true,
  bool disable = false,
  String? selected,
  ValueChanged<String>? onTap,
  ValueChanged<String>? onTick,
  VoidCallback? onEmpty,
  GoalMapController? controller,
  void Function(String child, String parent)? onLink,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(1000, 700),
      disableAnimations: disable,
    ),
    child: Scaffold(
      body: GoalMapView(
        goalId: goalId,
        title: 'Delft',
        graph: graph,
        goalColor: Colors.teal,
        motion: motion,
        selectedId: selected,
        controller: controller,
        clock: () => DateTime(2026, 11, 5, 10),
        onTapSquare: onTap,
        onTickSquare: onTick,
        onTapEmpty: onEmpty,
        onLink: onLink,
      ),
    ),
  ),
);

Finder square(String id) => find.byKey(ValueKey('square-$id'));

/// Where a square shows now.
Offset where(WidgetTester tester, String id) => tester.getTopLeft(square(id));

void main() {
  testWidgets('it shows each square; the root shows the name of the goal', (
    tester,
  ) async {
    await tester.pumpWidget(host(chain(['a', 'b'])));
    expect(square('a'), findsOneWidget);
    expect(square(root), findsOneWidget);
    expect(find.text('Delft'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Not ready'), findsOneWidget);
  });

  testWidgets('at rest nothing runs', (tester) async {
    await tester.pumpWidget(host(chain(['a', 'b'])));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a new square moves the others over a time, then all rests', (
    tester,
  ) async {
    await tester.pumpWidget(host(chain(['a'])));
    await tester.pumpAndSettle();
    final start = where(tester, 'a');
    await tester.pumpWidget(host(chain(['a', 'b'])));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(square('b'), findsOneWidget);
    expect(where(tester, 'b').dx, lessThan(where(tester, 'a').dx));
    expect(tester.binding.hasScheduledFrame, isFalse);
    // The camera followed: the square the user knew stays at its place.
    expect((where(tester, 'a') - start).distance, lessThan(320));
  });

  testWidgets('a deleted square shrinks, then it is gone', (tester) async {
    await tester.pumpWidget(host(chain(['a', 'b'])));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(chain(['a'])));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(square('b'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(square('b'), findsNothing);
  });

  testWidgets('a tick runs an effect, and the parent wakes at the end', (
    tester,
  ) async {
    await tester.pumpWidget(host(chain(['a', 'b'])));
    await tester.pumpAndSettle();
    final ready = find.text('Ready');
    expect(ready, findsOneWidget);
    await tester.pumpWidget(host(chain(['a', 'b'], done: {'b'})));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // The light has not reached "a" yet.
    expect(find.text('Not ready'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a tick of the root sends a wave, then all rests', (
    tester,
  ) async {
    await tester.pumpWidget(host(chain(['a'], done: {'a'})));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(chain(['a'], done: {'a', root})));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Finished'), findsOneWidget);
  });

  testWidgets('a new goal: the old map fades and the new one grows', (
    tester,
  ) async {
    await tester.pumpWidget(host(chain(['a', 'b'])));
    await tester.pumpAndSettle();
    final other = chain(['x', 'y', 'z'], id: 'H');
    await tester.pumpWidget(host(other, goalId: 'H'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(square('a'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(square('a'), findsNothing);
    expect(square('x'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  group('reduce motion', () {
    for (final (name, motion, disable) in [
      ('the setting', false, false),
      ('the system', true, true),
    ]) {
      testWidgets('$name: a change shows at once, with no frames', (
        tester,
      ) async {
        Widget one(GoalGraph g, {String id = goal}) =>
            host(g, goalId: id, motion: motion, disable: disable);
        await tester.pumpWidget(one(chain(['a', 'b'])));
        await tester.pump();
        await tester.pumpWidget(one(chain(['a', 'b'], done: {'b'})));
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(find.text('Ready'), findsOneWidget);
        await tester.pumpWidget(one(chain(['a'])));
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(square('b'), findsNothing);
        await tester.pumpWidget(one(chain(['x'], id: 'H'), id: 'H'));
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(square('x'), findsOneWidget);
      });
    }
  });

  testWidgets('a tap on a square, on its icon and on empty space each say so', (
    tester,
  ) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      host(
        chain(['a']),
        onTap: (id) => tapped.add('tap $id'),
        onTick: (id) => tapped.add('tick $id'),
        onEmpty: () => tapped.add('empty'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('a'));
    await tester.tap(find.byKey(const ValueKey('square-tick-a')));
    await tester.tapAt(const Offset(4, 4));
    expect(tapped, ['tap a', 'tick a', 'empty']);
  });

  testWidgets('a drag on a square moves the map and is not a tap', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(host(chain(['a']), onTap: (_) => taps++));
    await tester.pumpAndSettle();
    final before = where(tester, 'a');
    await tester.drag(find.text('a'), const Offset(60, 40));
    await tester.pumpAndSettle();
    expect(taps, 0);
    expect((where(tester, 'a') - before).distance, greaterThan(20));
  });

  testWidgets('fit brings a far map back in view', (tester) async {
    final c = GoalMapController();
    await tester.pumpWidget(host(chain(['a']), controller: c));
    await tester.pumpAndSettle();
    final at = where(tester, 'a');
    await tester.drag(find.text('a'), const Offset(300, 200));
    await tester.pumpAndSettle();
    expect(where(tester, 'a'), isNot(at));
    c.fit();
    await tester.pumpAndSettle();
    expect((where(tester, 'a') - at).distance, lessThan(1));
  });

  testWidgets('a waiting square says how long, and the clock is dropped '
      'with the view', (tester) async {
    final g = GoalGraph.build(
      goal,
      [
        GoalSquare(id: root, goalId: goal, title: 'R'),
        sq('a', started: '2026-11-05T10:00:00', wait: 3 * 24 * 60),
      ],
      [SquareLink(childId: 'a', parentId: root)],
    );
    await tester.pumpWidget(host(g));
    expect(find.text('Waiting, 3 days left'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a map of 50 squares and 70 lines draws and rests', (
    tester,
  ) async {
    final rnd = Random(3);
    final ids = [for (var i = 0; i < 49; i++) 's$i'];
    final all = [root, ...ids];
    final links = <SquareLink>[
      for (var i = 1; i < all.length; i++)
        SquareLink(childId: all[i], parentId: all[rnd.nextInt(i)]),
    ];
    while (links.length < 70) {
      final c = 1 + rnd.nextInt(all.length - 1);
      final link = SquareLink(childId: all[c], parentId: all[rnd.nextInt(c)]);
      if (!links.contains(link)) links.add(link);
    }
    final g = GoalGraph.build(goal, [
      for (final s in all) GoalSquare(id: s, goalId: goal, title: s),
    ], links);
    await tester.pumpWidget(host(g));
    await tester.pumpAndSettle();
    expect(find.byType(SquareTile), findsNWidgets(50));
    expect(GoalMapLayout.of(g).edges, hasLength(70));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  group('the handle that makes a link with a mouse', () {
    GoalGraph fork() => GoalGraph.build(
      goal,
      [GoalSquare(id: root, goalId: goal, title: root), sq('a'), sq('b')],
      [
        SquareLink(childId: 'a', parentId: root),
        SquareLink(childId: 'b', parentId: root),
      ],
    );
    final handle = find.byKey(const ValueKey('square-link-handle'));

    testWidgets('no onLink, no selection or the root: no handle', (
      tester,
    ) async {
      await tester.pumpWidget(host(fork(), selected: 'a'));
      await tester.pumpAndSettle();
      expect(handle, findsNothing);
      await tester.pumpWidget(host(fork(), onLink: (_, _) {}));
      await tester.pumpAndSettle();
      expect(handle, findsNothing);
      await tester.pumpWidget(host(fork(), selected: root, onLink: (_, _) {}));
      await tester.pumpAndSettle();
      expect(handle, findsNothing);
    });

    testWidgets('a drag onto a square links the selected one under it', (
      tester,
    ) async {
      final links = <(String, String)>[];
      await tester.pumpWidget(
        host(fork(), selected: 'a', onLink: (c, p) => links.add((c, p))),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(handle),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      final camera = where(tester, 'b');
      await gesture.moveTo(tester.getCenter(square('b')));
      await tester.pump();
      // The map stays where it is during the drag.
      expect(where(tester, 'b'), camera);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(links, [('a', 'b')]);
    });

    testWidgets(
      'a drop on empty space or on a square that loops does nothing',
      (tester) async {
        final links = <(String, String)>[];
        await tester.pumpWidget(
          host(
            chain(['a', 'b']),
            selected: 'a',
            onLink: (c, p) => links.add((c, p)),
          ),
        );
        await tester.pumpAndSettle();
        for (final to in [
          const Offset(990, 690),
          tester.getCenter(square('b')),
        ]) {
          final gesture = await tester.startGesture(
            tester.getCenter(handle),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pump();
          await gesture.moveTo(to);
          await gesture.up();
          await tester.pumpAndSettle();
        }
        expect(links, isEmpty);
      },
    );

    testWidgets('a finger on the handle does not start a link', (tester) async {
      final links = <(String, String)>[];
      await tester.pumpWidget(
        host(fork(), selected: 'a', onLink: (c, p) => links.add((c, p))),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(square('b')));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(links, isEmpty);
    });
  });

  group('the camera', () {
    Widget sized(
      GoalGraph graph,
      Size size, {
      String? selected,
      EdgeInsets safe = EdgeInsets.zero,
    }) => MaterialApp(
      home: Scaffold(
        body: SizedBox.fromSize(
          size: size,
          child: GoalMapView(
            goalId: goal,
            title: 'Delft',
            graph: graph,
            goalColor: Colors.teal,
            motion: false,
            selectedId: selected,
            safeArea: safe,
            clock: () => DateTime(2026, 11, 5, 10),
          ),
        ),
      ),
    );

    testWidgets('a map too big to read whole starts at the next thing to do', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final graph = chain(['a', 'b', 'c', 'd', 'e', 'f']);
      await tester.pumpWidget(sized(graph, const Size(390, 800)));
      await tester.pumpAndSettle();
      // "f" has no children, so it is the one that is ready.
      final box = tester.getRect(square('f'));
      expect(box.left, greaterThanOrEqualTo(0));
      expect(box.right, lessThanOrEqualTo(390));
      expect(box.width, closeTo(GoalMapLayout.squareWidth * 0.6, 1));
    });

    testWidgets('the fit button shows the whole big map', (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = GoalMapController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GoalMapView(
              goalId: goal,
              title: 'Delft',
              graph: chain(['a', 'b', 'c', 'd', 'e', 'f']),
              goalColor: Colors.teal,
              motion: false,
              controller: controller,
              clock: () => DateTime(2026, 11, 5, 10),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      controller.fit();
      await tester.pumpAndSettle();
      expect(tester.getRect(square('f')).left, greaterThanOrEqualTo(0));
      expect(tester.getRect(square(root)).right, lessThanOrEqualTo(390));
    });

    testWidgets('a selected square comes out from under a panel', (
      tester,
    ) async {
      const size = Size(1000, 700);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final graph = chain(['a', 'b']);
      await tester.pumpWidget(sized(graph, size));
      await tester.pumpAndSettle();
      // The panel takes the right half, and the root is at the right.
      const safe = EdgeInsets.only(right: 500);
      await tester.pumpWidget(sized(graph, size, selected: root, safe: safe));
      await tester.pumpAndSettle();
      expect(tester.getRect(square(root)).right, lessThanOrEqualTo(500));
    });
  });
}
