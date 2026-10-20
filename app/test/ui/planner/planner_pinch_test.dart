// Pinch zoom on the planner grid: two fingers on a trackpad, and two fingers
// on the glass of a phone. The height of one hour stays in 36...160.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/store_app.dart';

import 'planner_support.dart';

/// The height of one hour on the screen, from the height of a day column.
double hourOnScreen(WidgetTester tester) =>
    tester.getSize(columnFinder(wednesday)).height / 24;

/// A pinch on a trackpad at `at`, in steps up to `scale`. Gives the gesture
/// back before its end.
Future<TestGesture> trackpadPinch(
  WidgetTester tester,
  Offset at,
  double scale,
) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.trackpad);
  await gesture.panZoomStart(at);
  await tester.pump();
  for (var i = 1; i <= 4; i++) {
    await gesture.panZoomUpdate(at, scale: 1 + (scale - 1) * i / 4);
    await tester.pump(const Duration(milliseconds: 16));
  }
  return gesture;
}

/// Two fingers at `a` and `b`. Each moves away from the other by `apart`
/// points, up and down. A negative number moves them together.
Future<(TestGesture, TestGesture)> fingerPinch(
  WidgetTester tester,
  Offset a,
  Offset b,
  double apart,
) async {
  final first = await tester.startGesture(a, pointer: 1);
  await tester.pump(const Duration(milliseconds: 16));
  final second = await tester.startGesture(b, pointer: 2);
  await tester.pump(const Duration(milliseconds: 16));
  for (var i = 1; i <= 4; i++) {
    await first.moveTo(a - Offset(0, apart * i / 4));
    await second.moveTo(b + Offset(0, apart * i / 4));
    await tester.pump(const Duration(milliseconds: 16));
  }
  return (first, second);
}

void main() {
  group('a pinch on a trackpad', () {
    testWidgets('fingers apart make the hours taller', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);
      expect(hourOnScreen(tester), hour);

      final gesture = await trackpadPinch(
        tester,
        pointAt(tester, wednesday, 11 * 60),
        1.5,
      );
      // The grid follows the fingers before they lift.
      expect(hourOnScreen(tester), closeTo(96, 0.01));

      await gesture.panZoomEnd();
      await tester.pumpAndSettle();
      expect(store.plannerHourHeight, closeTo(96, 0.01));
      expect(hourOnScreen(tester), closeTo(96, 0.01));
      expect(tester.takeException(), isNull);
    });

    testWidgets('fingers together make the hours shorter', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);

      final gesture = await trackpadPinch(
        tester,
        pointAt(tester, wednesday, 11 * 60),
        0.75,
      );
      await gesture.panZoomEnd();
      await tester.pumpAndSettle();

      expect(store.plannerHourHeight, closeTo(48, 0.01));
      expect(hourOnScreen(tester), closeTo(48, 0.01));
    });

    testWidgets('the zoom stops at 36 and at 160', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);
      final at = pointAt(tester, wednesday, 11 * 60);

      var gesture = await trackpadPinch(tester, at, 0.2);
      expect(hourOnScreen(tester), 36);
      await gesture.panZoomEnd();
      await tester.pumpAndSettle();
      expect(store.plannerHourHeight, 36);

      gesture = await trackpadPinch(tester, at, 9);
      expect(hourOnScreen(tester), 160);
      await gesture.panZoomEnd();
      await tester.pumpAndSettle();
      expect(store.plannerHourHeight, 160);
    });

    testWidgets('a second pinch starts from the height of the first', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);
      final at = pointAt(tester, wednesday, 11 * 60);

      var gesture = await trackpadPinch(tester, at, 1.5);
      await gesture.panZoomEnd();
      await tester.pumpAndSettle();
      gesture = await trackpadPinch(tester, at, 0.5);
      await gesture.panZoomEnd();
      await tester.pumpAndSettle();

      expect(store.plannerHourHeight, closeTo(48, 0.01));
    });

    testWidgets('two fingers that only slide scroll the grid, with no zoom', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);
      final at = pointAt(tester, wednesday, 11 * 60);
      final before = gridScroll(tester);

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      await gesture.panZoomStart(at);
      await tester.pump();
      for (var i = 1; i <= 4; i++) {
        await gesture.panZoomUpdate(at, pan: Offset(0, -30.0 * i));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.panZoomEnd();
      await tester.pumpAndSettle();

      expect(store.plannerHourHeight, hour);
      expect(hourOnScreen(tester), hour);
      expect(gridScroll(tester), greaterThan(before));
    });

    testWidgets('the blocks keep their times and are drawn at the new size', (
      tester,
    ) async {
      final store = plannerStore();
      store
        ..createFromDraft(
          title: 'Lunch',
          day: wednesday,
          start: 12 * 60,
          end: 13 * 60,
          asEvent: true,
        )
        ..selection = {};
      final id = blockNamed(store, 'Lunch').id;
      await pumpPlanner(tester, store);
      final small = tester.getSize(blockFinder(id)).height;

      final gesture = await trackpadPinch(
        tester,
        pointAt(tester, wednesday, 12 * 60 + 30),
        1.5,
      );
      await gesture.panZoomEnd();
      await tester.pumpAndSettle();

      final block = blockNamed(store, 'Lunch');
      expect((block.startMinute, block.endMinute), (12 * 60, 13 * 60));
      expect(tester.getSize(blockFinder(id)).height, closeTo(small + 32, 1.5));
      expect(store.selection, isEmpty);
      expect(store.undoName, isNot(contains('Move')));
    });
  });

  testWidgets('with motion on, a block follows the pinch with no delay', (
    tester,
  ) async {
    final store = plannerStore(motion: true);
    store
      ..createFromDraft(
        title: 'Lunch',
        day: wednesday,
        start: 12 * 60,
        end: 13 * 60,
        asEvent: true,
      )
      ..selection = {};
    final id = blockNamed(store, 'Lunch').id;
    tester.view.physicalSize = desktopSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(StoreApp(key: UniqueKey(), store: store));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    // The now line moves all the time, so the screen never comes to rest.
    await tester.pump(const Duration(milliseconds: 500));
    final at = pointAt(tester, wednesday, 12 * 60 + 30);

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    await gesture.panZoomStart(at);
    await tester.pump();
    await gesture.panZoomUpdate(at, scale: 1.5);
    await tester.pump();

    double top() =>
        tester.getRect(blockFinder(id)).top -
        tester.getRect(columnFinder(wednesday)).top;
    expect(top(), closeTo(12 * 96, 0.5));
    expect(tester.getSize(blockFinder(id)).height, closeTo(95, 0.5));

    await gesture.panZoomEnd();
    await tester.pump();
    expect(top(), closeTo(12 * 96, 0.5));
    expect(store.plannerHourHeight, closeTo(96, 0.01));
    await tester.pump(const Duration(milliseconds: 300));
    expect(top(), closeTo(12 * 96, 0.5));
  });

  group('a pinch with two fingers on a phone', () {
    testWidgets('fingers apart make the hours taller', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store, size: phoneSize);
      final a = pointAt(tester, wednesday, 11 * 60, dx: 0.3);
      final b = pointAt(tester, wednesday, 12 * 60, dx: 0.7);
      final span = (b - a).distance;
      final scroll = gridScroll(tester);

      final (first, second) = await fingerPinch(tester, a, b, 40);
      final wide =
          (b + const Offset(0, 40) - (a - const Offset(0, 40))).distance;
      final wanted = hour * wide / span;
      expect(hourOnScreen(tester), closeTo(wanted, 0.01));
      // The grid does not scroll under the two fingers.
      expect(gridScroll(tester), scroll);

      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(store.plannerHourHeight, closeTo(wanted, 0.01));
      expect(hourOnScreen(tester), closeTo(wanted, 0.01));
      // No block, no new block that waits for its title, no menu.
      expect(store.blocks(DayRange.single(wednesday)), isEmpty);
      expect(gridState(tester).draft, isNull);
      expect(find.byType(PopupMenuItem<VoidCallback>), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fingers together make the hours shorter, down to 36', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpPlanner(tester, store, size: phoneSize);
      final a = pointAt(tester, wednesday, 10 * 60, dx: 0.3);
      final b = pointAt(tester, wednesday, 14 * 60, dx: 0.7);

      final (first, second) = await fingerPinch(tester, a, b, -110);
      expect(hourOnScreen(tester), 36);
      await first.up();
      await second.up();
      await tester.pumpAndSettle();

      expect(store.plannerHourHeight, 36);
    });

    testWidgets('a pinch that starts on a block does not move the block', (
      tester,
    ) async {
      final store = plannerStore();
      store
        ..createFromDraft(
          title: 'Lunch',
          day: wednesday,
          start: 11 * 60,
          end: 12 * 60,
          asEvent: true,
        )
        ..selection = {};
      await pumpPlanner(tester, store, size: phoneSize);
      final a = pointAt(tester, wednesday, 11 * 60 + 30, dx: 0.3);
      final b = pointAt(tester, wednesday, 13 * 60, dx: 0.7);

      // The fingers rest for longer than a long press, then move.
      final first = await tester.startGesture(a, pointer: 1);
      final second = await tester.startGesture(b, pointer: 2);
      await tester.pump(const Duration(milliseconds: 700));
      for (var i = 1; i <= 4; i++) {
        await first.moveTo(a - Offset(0, 10.0 * i));
        await second.moveTo(b + Offset(0, 10.0 * i));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await first.up();
      await second.up();
      await tester.pumpAndSettle();

      final block = blockNamed(store, 'Lunch');
      expect((block.startMinute, block.endMinute), (11 * 60, 12 * 60));
      expect(store.plannerHourHeight, greaterThan(hour));
      expect(find.byType(PopupMenuItem<VoidCallback>), findsNothing);
      expect(gridState(tester).draft, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('one finger still scrolls the grid after a pinch', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpPlanner(tester, store, size: phoneSize);
      final a = pointAt(tester, wednesday, 11 * 60, dx: 0.3);
      final b = pointAt(tester, wednesday, 12 * 60, dx: 0.7);
      final (first, second) = await fingerPinch(tester, a, b, 20);
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      final zoomed = store.plannerHourHeight;
      final before = gridScroll(tester);

      await tester.dragFrom(a, const Offset(0, -120));
      await tester.pumpAndSettle();

      expect(gridScroll(tester), greaterThan(before));
      expect(store.plannerHourHeight, zoomed);
    });

    testWidgets('a hold and drag after a pinch makes a block at the place of '
        'the finger', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store, size: phoneSize);
      final a = pointAt(tester, wednesday, 11 * 60, dx: 0.3);
      final b = pointAt(tester, wednesday, 12 * 60, dx: 0.7);
      final (first, second) = await fingerPinch(tester, a, b, 16);
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      final tall = store.plannerHourHeight;
      expect(tall, greaterThan(hour));

      // 11:00 is at a new place now.
      final column = tester.getRect(columnFinder(wednesday));
      final from = Offset(column.center.dx, column.top + 11 * tall);
      await touchDrag(tester, from, Offset(0, tall));

      final draft = gridState(tester).draft!;
      expect((draft.start, draft.end), (11 * 60, 12 * 60));
    });
  });
}
