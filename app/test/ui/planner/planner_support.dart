import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/planner/focus_card.dart';
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
AppStore plannerStore({int now = 10 * 60, bool motion = false}) {
  final store = makeStore(
    prefs: MemoryPrefs()..set('appearance.motion', motion),
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

/// A goal "Read" with one more block, on Wednesday when no day is given.
/// Gives the id of the block.
String goalBlock(
  AppStore store, {
  DayKey? day,
  int start = 11 * 60,
  int length = 90,
}) {
  final on = DayRange.single(day ?? wednesday);
  final goal =
      store.goals().where((g) => g.title == 'Read').firstOrNull ??
      store.addGoal(title: 'Read', target: 300)!;
  final before = {for (final b in store.blocks(on)) b.id};
  store.scheduleGoal(
    goalId: goal.id,
    day: on.first,
    start: start,
    length: length,
  );
  return store.blocks(on).firstWhere((b) => !before.contains(b.id)).id;
}

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

/// One click with the right button: the menu of a block.
Future<void> rightClick(WidgetTester tester, Offset at) async {
  await tester.tapAt(
    at,
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await tester.pumpAndSettle();
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

/// How far the grid of the planner is scrolled, in points.
double gridScroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(PlannerGrid),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position
    .pixels;

// Focus mode

/// The store starts a session only for a block that ends after the real
/// "now". The day of these tests is far away, so that is always true.
final focusDay = d('2099-03-04');

/// A store for the tests of focus mode. Motion is off. "Now" is 10:00 on
/// `focusDay`.
AppStore focusStore({bool motion = false}) {
  final store = makeStore(
    prefs: MemoryPrefs()..set('appearance.motion', motion),
    clock: WallTime(day: focusDay, minute: 10 * 60),
  );
  store
    ..selectedDay = focusDay
    ..screen = Screen.planner;
  return store;
}

/// A block from 10:00 to 11:00 on `focusDay`. Gives its id.
String hourBlock(AppStore store, String title, {bool asEvent = false}) {
  store.createFromDraft(
    title: title,
    day: focusDay,
    start: 10 * 60,
    end: 11 * 60,
    asEvent: asEvent,
  );
  return store
      .blocks(DayRange.single(focusDay))
      .firstWhere((b) => b.title == title)
      .id;
}

/// Sets the clock of the card: it shows this time on `focusDay` when the card
/// reads it first. From there it runs with the time of the test.
void setFocusClock(
  WidgetTester tester,
  int hour,
  int minute, [
  int second = 0,
]) {
  final at = DateTime(
    focusDay.year,
    focusDay.month,
    focusDay.day,
    hour,
    minute,
  ).add(Duration(seconds: second));
  DateTime? begun;
  FocusCard.clock = () {
    final now = tester.binding.clock.now();
    return at.add(now.difference(begun ??= now));
  };
  addTearDown(() => FocusCard.clock = null);
}
