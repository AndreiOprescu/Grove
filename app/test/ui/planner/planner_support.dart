import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/planner/planner_grid.dart';
import 'package:grove/ui/store_app.dart';

import '../../state/support.dart';
import '../support.dart';

export '../../state/support.dart';
export '../support.dart';

/// A Wednesday. The week of the tests is Monday 5 to Sunday 11 October 2026.
final wednesday = d('2026-10-07');

/// One hour on the grid, in points. The default of the planner.
const hour = 64.0;

/// A store for the planner. Motion is off, so the screen comes to rest.
/// "Now" is Wednesday at 10:00.
AppStore plannerStore({int now = 10 * 60}) {
  final store = makeStore(
    prefs: MemoryPrefs()..set('appearance.motion', false),
    clock: WallTime(day: wednesday, minute: now),
  );
  store
    ..selectedDay = wednesday
    ..screen = Screen.planner;
  return store;
}

/// Shows the app on `store` in a window of `size` points.
Future<void> pumpPlanner(
  WidgetTester tester,
  AppStore store, {
  Size size = desktopSize,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(StoreApp(key: UniqueKey(), store: store));
  // Take the tree down at the end, before the store is closed.
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pumpAndSettle();
}

/// The block of the planner with this title.
PlannerBlock blockNamed(AppStore store, String title) => store
    .blocks(DayRange(wednesday.adding(days: -7), wednesday.adding(days: 7)))
    .firstWhere((b) => b.title == title);

Finder blockFinder(String id) => find.byKey(ValueKey('block-$id'));

Finder columnFinder(DayKey day) =>
    find.byKey(ValueKey('day-column-${day.string}'));

/// The point of the day column at `minute`, in window points.
Offset pointAt(WidgetTester tester, DayKey day, int minute, {double dx = 0.5}) {
  final column = tester.getRect(columnFinder(day));
  return Offset(
    column.left + column.width * dx,
    column.top + minute / 60 * hour,
  );
}

/// A mouse drag from `from` by `offset`, in small steps.
Future<void> mouseDrag(
  WidgetTester tester,
  Offset from,
  Offset offset, {
  int steps = 8,
}) async {
  final gesture = await tester.startGesture(
    from,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  for (var i = 1; i <= steps; i++) {
    await gesture.moveTo(from + offset * (i / steps));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

/// A finger drag: press, hold, move, lift.
Future<void> touchDrag(
  WidgetTester tester,
  Offset from,
  Offset offset, {
  int steps = 8,
}) async {
  final gesture = await tester.startGesture(from);
  await tester.pump(const Duration(milliseconds: 600));
  for (var i = 1; i <= steps; i++) {
    await gesture.moveTo(from + offset * (i / steps));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

/// One mouse click.
Future<void> mouseTap(WidgetTester tester, Offset at) async {
  await tester.tapAt(at, kind: PointerDeviceKind.mouse);
  await tester.pump();
}

/// Lets the double-tap window of the grid end.
Future<void> endTapWindow(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
}

/// Lets the short message at the bottom of the window go away.
Future<void> endToast(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 2500));
  await tester.pumpAndSettle();
}

PlannerGridState gridState(WidgetTester tester) =>
    tester.state<PlannerGridState>(find.byType(PlannerGrid));
