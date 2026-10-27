// The wake-up line and the sleep line of a day in the planner: the day menu
// (a right click, or a long press, on the name of a day) adds them, a drag
// moves them in steps of 15 minutes, a menu takes them away.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/planner/planner_grid.dart';
import 'package:grove/ui/planner/planner_kind.dart';
import 'package:grove/ui/planner/planner_view.dart';

import '../tasks/tasks_support.dart' show pumpPane;
import 'planner_support.dart';

/// The "+" that was above the schedule. It is gone (owner, 2026-10-27).
final addButton = find.byKey(const ValueKey('day-marker-add'));

Finder chip(DayMarkerKind kind, [DayKey? day]) => find.byKey(
  ValueKey('day-marker-${kind.name}-${(day ?? wednesday).string}'),
);

Finder lineOf(DayMarkerKind kind, [DayKey? day]) => find.byKey(
  ValueKey('day-marker-line-${kind.name}-${(day ?? wednesday).string}'),
);

Finder menuLine(String label) =>
    find.widgetWithText(PopupMenuItem<VoidCallback>, label);

/// The name of [day] at the top of the planner week. On the Today screen
/// ([today]) it is the date above the timeline.
Finder dayName({DayKey? day, bool today = false}) => today
    ? find.byKey(const ValueKey('spread-date'))
    : find.byKey(ValueKey('day-header-${(day ?? wednesday).string}'));

/// The time that the chip of a line shows.
String shownTime(WidgetTester tester, DayMarkerKind kind, [DayKey? day]) {
  final texts = tester.widgetList<Text>(
    find.descendant(of: chip(kind, day), matching: find.byType(Text)),
  );
  return texts.map((t) => t.data).firstWhere((t) => t!.contains(':'))!;
}

/// Opens the day menu of a day name: a right click, or a long press with
/// [touch].
Future<void> openDayMenu(
  WidgetTester tester, {
  DayKey? day,
  bool today = false,
  bool touch = false,
}) async {
  final name = dayName(day: day, today: today);
  if (touch) {
    await tester.longPress(name);
    await tester.pumpAndSettle();
  } else {
    await rightClick(tester, tester.getCenter(name));
    await endTapWindow(tester);
  }
}

/// Opens the day menu and picks one line of it.
Future<void> pickFromDayMenu(
  WidgetTester tester,
  String label, {
  DayKey? day,
  bool today = false,
  bool touch = false,
}) async {
  await openDayMenu(tester, day: day, today: today, touch: touch);
  await tester.tap(menuLine(label));
  await tester.pumpAndSettle();
}

/// The top and the bottom of the part of the grid that is on the screen.
Rect viewport(WidgetTester tester) => tester.getRect(
  find
      .descendant(
        of: find.byType(PlannerGrid),
        matching: find.byType(Scrollable),
      )
      .first,
);

void main() {
  group('the day menu', () {
    testWidgets('the planner has no "+" for the lines', (tester) async {
      for (final screen in [Screen.planner, Screen.today, Screen.calendar]) {
        for (final size in [desktopSize, phoneSize]) {
          final store = plannerStore()..screen = screen;
          await pumpPlanner(tester, store, size: size);
          expect(addButton, findsNothing, reason: '$screen $size');
          expect(
            find.bySemanticsLabel('Add a wake-up or sleep line'),
            findsNothing,
          );
        }
      }
    });

    testWidgets('adds the wake-up line: a line with its time, in view', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);
      expect(chip(DayMarkerKind.wake), findsNothing);

      await openDayMenu(tester);
      expect(menuLine('Add wake-up line'), findsOneWidget);
      expect(menuLine('Add sleep line'), findsOneWidget);
      await tester.tap(menuLine('Add wake-up line'));
      await tester.pumpAndSettle();

      expect(store.dayMarker(DayMarkerKind.wake, wednesday), 7 * 60);
      expect(chip(DayMarkerKind.wake), findsOneWidget);
      expect(lineOf(DayMarkerKind.wake), findsOneWidget);
      expect(shownTime(tester, DayMarkerKind.wake), '07:00');
      expect(chip(DayMarkerKind.sleep), findsNothing);

      // The line lies at 07:00 of Wednesday, across its column.
      final line = tester.getRect(lineOf(DayMarkerKind.wake));
      final column = tester.getRect(columnFinder(wednesday));
      expect(line.center.dy, pointAt(tester, wednesday, 7 * 60).dy);
      expect(line.left, column.left);
      expect(line.right, column.right);

      // "Now" is 10:00, so 07:00 was above the screen. The grid went there.
      final seen = viewport(tester);
      expect(line.center.dy, greaterThan(seen.top));
      expect(line.center.dy, lessThan(seen.bottom));
      expect(tester.takeException(), isNull);
    });

    testWidgets('adds the sleep line the same way', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);

      await pickFromDayMenu(tester, 'Add sleep line');

      expect(store.dayMarker(DayMarkerKind.sleep, wednesday), 23 * 60);
      expect(shownTime(tester, DayMarkerKind.sleep), '23:00');
      final line = tester.getRect(lineOf(DayMarkerKind.sleep));
      final seen = viewport(tester);
      expect(line.center.dy, pointAt(tester, wednesday, 23 * 60).dy);
      expect(line.center.dy, greaterThan(seen.top));
      expect(line.center.dy, lessThan(seen.bottom));
    });

    testWidgets('a line that is in view does not move the grid', (
      tester,
    ) async {
      final store = plannerStore();
      store.addDayMarker(DayMarkerKind.wake, wednesday.adding(days: -1));
      store.moveDayMarker(
        DayMarkerKind.wake,
        wednesday.adding(days: -1),
        11 * 60,
      );
      await pumpPlanner(tester, store);
      final before = gridScroll(tester);

      // The new line takes the time of the day before: 11:00, on the screen.
      await pickFromDayMenu(tester, 'Add wake-up line');

      expect(store.dayMarker(DayMarkerKind.wake, wednesday), 11 * 60);
      expect(gridScroll(tester), before);
    });

    testWidgets('names the line that is there as one to remove', (
      tester,
    ) async {
      final store = plannerStore();
      store.addDayMarker(DayMarkerKind.wake, wednesday);
      await pumpPlanner(tester, store);

      await openDayMenu(tester);
      expect(menuLine('Add wake-up line'), findsNothing);
      expect(menuLine('Add sleep line'), findsOneWidget);

      await tester.tap(menuLine('Remove wake-up line'));
      await tester.pumpAndSettle();
      expect(store.dayMarker(DayMarkerKind.wake, wednesday), isNull);
      expect(chip(DayMarkerKind.wake), findsNothing);
      expect(lineOf(DayMarkerKind.wake), findsNothing);
      expect(store.undoName, 'Remove Wake-up Line');
    });

    testWidgets('in the week it acts on the day that was clicked', (
      tester,
    ) async {
      final store = plannerStore();
      final friday = wednesday.adding(days: 2);
      await pumpPlanner(tester, store);

      await openDayMenu(tester, day: friday);
      expect(find.text('Friday 9 October'), findsOneWidget);
      await tester.tap(menuLine('Add wake-up line'));
      await tester.pumpAndSettle();

      expect(store.dayMarker(DayMarkerKind.wake, friday), 7 * 60);
      expect(store.dayMarker(DayMarkerKind.wake, wednesday), isNull);
      expect(chip(DayMarkerKind.wake, friday), findsOneWidget);
      // The line is in the column of Friday only.
      final line = tester.getRect(lineOf(DayMarkerKind.wake, friday));
      final column = tester.getRect(columnFinder(friday));
      expect(line.left, column.left);
      expect(line.right, column.right);
    });

    testWidgets('the Calendar day menu has the lines too', (tester) async {
      final store = plannerStore()..screen = Screen.calendar;
      final friday = wednesday.adding(days: 2);
      await pumpPlanner(tester, store);
      await rightClick(
        tester,
        tester.getCenter(find.byKey(ValueKey('month-day-${friday.string}'))),
      );
      await endTapWindow(tester);
      await tester.tap(menuLine('Add sleep line'));
      await tester.pumpAndSettle();

      expect(store.dayMarker(DayMarkerKind.sleep, friday), 23 * 60);
      expect(store.screen, Screen.calendar);
    });

    testWidgets('the Today screen has it on its date: the line is on today', (
      tester,
    ) async {
      final store = plannerStore()..screen = Screen.today;
      // Another day is selected in the planner. Today shows today.
      store.selectedDay = wednesday.adding(days: 3);
      await pumpPlanner(tester, store);

      await openDayMenu(tester, today: true);
      expect(find.text('Wednesday 7 October'), findsWidgets);
      await tester.tap(menuLine('Add wake-up line'));
      await tester.pumpAndSettle();
      await pickFromDayMenu(tester, 'Add sleep line', today: true);

      expect(store.dayMarker(DayMarkerKind.wake, wednesday), 7 * 60);
      expect(store.dayMarker(DayMarkerKind.sleep, wednesday), 23 * 60);
      expect(chip(DayMarkerKind.sleep), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // The header of the Today screen has a switch "Today | Tomorrow".
    for (final (name, size, touch) in [
      ('', desktopSize, false),
      (' on a phone', phoneSize, true),
    ]) {
      testWidgets('the Today screen on "Tomorrow"$name: the menu and the '
          'lines are those of tomorrow', (tester) async {
        final store = plannerStore()..screen = Screen.today;
        final tomorrow = wednesday.adding(days: 1);
        store.addDayMarker(DayMarkerKind.sleep, wednesday);
        store.showsTomorrow = true;
        await pumpPlanner(tester, store, size: size);
        // The sleep line of today is not a line of tomorrow.
        expect(chip(DayMarkerKind.sleep), findsNothing);
        expect(chip(DayMarkerKind.sleep, tomorrow), findsNothing);

        await pickFromDayMenu(
          tester,
          'Add wake-up line',
          today: true,
          touch: touch,
        );

        expect(store.dayMarker(DayMarkerKind.wake, tomorrow), 7 * 60);
        expect(store.dayMarker(DayMarkerKind.wake, wednesday), isNull);
        expect(chip(DayMarkerKind.wake, tomorrow), findsOneWidget);
        expect(shownTime(tester, DayMarkerKind.wake, tomorrow), '07:00');

        // Back on today: its own line, and not the one of tomorrow.
        store.showsTomorrow = false;
        await tester.pumpAndSettle();
        expect(chip(DayMarkerKind.wake, tomorrow), findsNothing);
        expect(chip(DayMarkerKind.wake), findsNothing);
        expect(chip(DayMarkerKind.sleep), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('a drag of a line', () {
    Future<AppStore> withWake(
      WidgetTester tester, {
      int at = 9 * 60 + 30,
      Size size = desktopSize,
    }) async {
      final store = plannerStore();
      store.addDayMarker(DayMarkerKind.wake, wednesday);
      store.moveDayMarker(DayMarkerKind.wake, wednesday, at);
      await pumpPlanner(tester, store, size: size);
      return store;
    }

    testWidgets('with the mouse moves it in steps of 15 minutes, and the '
        'time on the label follows', (tester) async {
      final store = await withWake(tester);
      final from = tester.getCenter(chip(DayMarkerKind.wake));

      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      // 40 points are 37.5 minutes. The line goes to the next step: 10:15.
      await gesture.moveTo(from + const Offset(0, 20));
      await tester.pump();
      await gesture.moveTo(from + const Offset(0, 40));
      await tester.pump();
      expect(shownTime(tester, DayMarkerKind.wake), '10:15');
      expect(
        tester.getRect(lineOf(DayMarkerKind.wake)).center.dy,
        pointAt(tester, wednesday, 10 * 60 + 15).dy,
      );
      // Nothing is saved before the mouse button is up.
      expect(store.dayMarker(DayMarkerKind.wake, wednesday), 9 * 60 + 30);

      await gesture.moveTo(from + const Offset(0, -60));
      await tester.pump();
      expect(shownTime(tester, DayMarkerKind.wake), '08:30');

      await gesture.up();
      await tester.pumpAndSettle();
      expect(store.dayMarker(DayMarkerKind.wake, wednesday), 8 * 60 + 30);
      expect(shownTime(tester, DayMarkerKind.wake), '08:30');
      expect(store.blocks(DayRange.single(wednesday)), isEmpty);
      expect(gridState(tester).draft, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('on the line itself works too, away from the label', (
      tester,
    ) async {
      final store = await withWake(tester);
      final line = tester.getRect(lineOf(DayMarkerKind.wake));

      await mouseDrag(
        tester,
        Offset(line.left + 12, line.center.dy),
        const Offset(0, 64),
      );

      expect(store.dayMarker(DayMarkerKind.wake, wednesday), 10 * 60 + 30);
      expect(store.blocks(DayRange.single(wednesday)), isEmpty);
      expect(gridState(tester).draft, isNull);
    });

    testWidgets('with a finger moves it at once: the grid does not scroll '
        'and no block is made', (tester) async {
      final store = await withWake(tester);
      final scrolled = gridScroll(tester);
      final from = tester.getCenter(chip(DayMarkerKind.wake));

      final gesture = await tester.startGesture(from);
      await tester.pump();
      for (var i = 1; i <= 8; i++) {
        await gesture.moveTo(from + Offset(0, 12.0 * i));
        await tester.pump(const Duration(milliseconds: 16));
        expect(gridScroll(tester), scrolled);
      }
      expect(shownTime(tester, DayMarkerKind.wake), '11:00');
      await gesture.up();
      await tester.pumpAndSettle();

      expect(store.dayMarker(DayMarkerKind.wake, wednesday), 11 * 60);
      expect(gridScroll(tester), scrolled);
      expect(store.blocks(DayRange.single(wednesday)), isEmpty);
      expect(gridState(tester).draft, isNull);
    });

    testWidgets('with a finger that holds first moves it too, and makes no '
        'block', (tester) async {
      final store = await withWake(tester, at: 12 * 60);
      final scrolled = gridScroll(tester);

      await touchDrag(
        tester,
        tester.getCenter(chip(DayMarkerKind.wake)),
        const Offset(0, -64),
      );

      expect(store.dayMarker(DayMarkerKind.wake, wednesday), 11 * 60);
      expect(gridScroll(tester), scrolled);
      expect(store.blocks(DayRange.single(wednesday)), isEmpty);
      expect(gridState(tester).draft, isNull);
    });

    testWidgets('over a block does not move the block', (tester) async {
      final store = plannerStore();
      store.createFromDraft(
        title: 'Deep work',
        day: wednesday,
        start: 9 * 60,
        end: 11 * 60,
        asEvent: true,
      );
      store.addDayMarker(DayMarkerKind.wake, wednesday);
      store.moveDayMarker(DayMarkerKind.wake, wednesday, 10 * 60);
      await pumpPlanner(tester, store);
      final line = tester.getRect(lineOf(DayMarkerKind.wake));
      final selected = store.selection;

      // The line lies on the block. The drag starts on the line, over it.
      await mouseDrag(
        tester,
        Offset(line.left + 20, line.center.dy),
        const Offset(0, 32),
      );
      await touchDrag(
        tester,
        tester.getCenter(chip(DayMarkerKind.wake)),
        const Offset(0, 32),
      );

      expect(store.dayMarker(DayMarkerKind.wake, wednesday), 11 * 60);
      final block = blockNamed(store, 'Deep work');
      expect(block.startMinute, 9 * 60);
      expect(block.endMinute, 11 * 60);
      expect(store.blocks(DayRange.single(wednesday)), hasLength(1));
      expect(store.selection, selected);
    });

    testWidgets('stops at the top and at the bottom of the day', (
      tester,
    ) async {
      final store = await withWake(tester, at: 9 * 60);
      await mouseDrag(
        tester,
        tester.getCenter(chip(DayMarkerKind.wake)),
        const Offset(0, -900),
        steps: 30,
      );
      expect(store.dayMarker(DayMarkerKind.wake, wednesday), 0);
      expect(shownTime(tester, DayMarkerKind.wake), '00:00');
      expect(tester.takeException(), isNull);
    });

    testWidgets('near the edge of the screen scrolls the grid, and the line '
        'goes on', (tester) async {
      final store = await withWake(tester, at: 13 * 60);
      final scrolled = gridScroll(tester);
      final from = tester.getCenter(chip(DayMarkerKind.wake));
      final seen = viewport(tester);

      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(Offset(from.dx, seen.bottom - 6));
      await tester.pump();
      // The mouse stays there. The grid scrolls under it.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(gridScroll(tester), greaterThan(scrolled + 100));
      await gesture.up();
      await tester.pumpAndSettle();

      final after = store.dayMarker(DayMarkerKind.wake, wednesday)!;
      // Farther than the mouse went on the screen.
      final moved = ((seen.bottom - 6 - from.dy) / hour * 60).round();
      expect(after, greaterThan(13 * 60 + moved + 60));
      // The scroll stops with the drag.
      final rest = gridScroll(tester);
      await tester.pump(const Duration(milliseconds: 200));
      expect(gridScroll(tester), rest);
    });

    testWidgets('is one undo step', (tester) async {
      final store = await withWake(tester);
      await mouseDrag(
        tester,
        tester.getCenter(chip(DayMarkerKind.wake)),
        const Offset(0, 64),
      );
      expect(store.dayMarker(DayMarkerKind.wake, wednesday), 10 * 60 + 30);
      expect(store.undoName, 'Move Wake-up Line');

      store.undo();
      await tester.pumpAndSettle();
      expect(store.dayMarker(DayMarkerKind.wake, wednesday), 9 * 60 + 30);
      expect(shownTime(tester, DayMarkerKind.wake), '09:30');
      await endToast(tester);
    });

    testWidgets('two fingers on a trackpad over a line scroll the grid and '
        'leave the line', (tester) async {
      final store = await withWake(tester, at: 12 * 60);
      final scrolled = gridScroll(tester);
      final at = tester.getCenter(chip(DayMarkerKind.wake));

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      await gesture.panZoomStart(at);
      await tester.pump();
      for (var i = 1; i <= 6; i++) {
        await gesture.panZoomUpdate(at, pan: Offset(0, -20.0 * i));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.panZoomEnd();
      await tester.pumpAndSettle();

      expect(gridScroll(tester), greaterThan(scrolled + 60));
      expect(store.dayMarker(DayMarkerKind.wake, wednesday), 12 * 60);
      expect(store.undoName, 'Move Wake-up Line');
    });

    testWidgets('the wheel of a mouse over a line scrolls the grid', (
      tester,
    ) async {
      final store = await withWake(tester, at: 12 * 60);
      final scrolled = gridScroll(tester);
      final at = tester.getCenter(chip(DayMarkerKind.wake));

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(at));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 80)));
      await tester.pumpAndSettle();

      expect(gridScroll(tester), scrolled + 80);
      expect(store.dayMarker(DayMarkerKind.wake, wednesday), 12 * 60);
    });

    testWidgets('a line that goes away under the pointer frees the grid', (
      tester,
    ) async {
      final store = await withWake(tester, at: 12 * 60);
      final from = tester.getCenter(chip(DayMarkerKind.wake));

      final gesture = await tester.startGesture(from);
      await tester.pump();
      await gesture.moveTo(from + const Offset(0, 40));
      await tester.pump();
      expect(shownTime(tester, DayMarkerKind.wake), '12:45');
      // Another device takes the line off in the middle of the drag.
      store.removeDayMarker(DayMarkerKind.wake, wednesday);
      await tester.pump();
      await gesture.moveTo(from + const Offset(0, 80));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(chip(DayMarkerKind.wake), findsNothing);
      expect(store.dayMarker(DayMarkerKind.wake, wednesday), isNull);

      // The grid scrolls again, and a drag on it makes a block again.
      final scrolled = gridScroll(tester);
      await tester.dragFrom(from, const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(gridScroll(tester), greaterThan(scrolled + 60));
      // No clock of the drag is left.
      expect(await framesAsked(tester), 0);
    });

    testWidgets('a block drag that runs does not start a line drag', (
      tester,
    ) async {
      final store = await withWake(tester, at: 12 * 60);
      store.createFromDraft(
        title: 'Deep work',
        day: wednesday,
        start: 10 * 60,
        end: 11 * 60,
        asEvent: true,
      );
      await tester.pumpAndSettle();
      final block = tester.getCenter(
        blockFinder(blockNamed(store, 'Deep work').id),
      );
      final at = tester.getCenter(chip(DayMarkerKind.wake));

      final mouse = await tester.startGesture(
        block,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await mouse.moveTo(block + const Offset(0, 20));
      await tester.pump();
      // A finger on the line while the mouse holds the block.
      final finger = await tester.startGesture(at, pointer: 7);
      await tester.pump();
      await finger.moveTo(at + const Offset(0, 64));
      await tester.pump();
      await finger.up();
      await mouse.up();
      await tester.pumpAndSettle();

      expect(store.dayMarker(DayMarkerKind.wake, wednesday), 12 * 60);
    });

    testWidgets('the sleep line may go above the wake-up line', (tester) async {
      final store = await withWake(tester, at: 13 * 60);
      store.addDayMarker(DayMarkerKind.sleep, wednesday);
      store.moveDayMarker(DayMarkerKind.sleep, wednesday, 14 * 60);
      await tester.pumpAndSettle();

      await mouseDrag(
        tester,
        tester.getCenter(chip(DayMarkerKind.sleep)),
        const Offset(0, -128),
      );

      expect(store.dayMarker(DayMarkerKind.sleep, wednesday), 12 * 60);
      expect(store.dayMarker(DayMarkerKind.wake, wednesday), 13 * 60);
    });
  });

  group('a line goes away', () {
    Future<AppStore> withBoth(WidgetTester tester) async {
      final store = plannerStore();
      store.addDayMarker(DayMarkerKind.wake, wednesday);
      store.moveDayMarker(DayMarkerKind.wake, wednesday, 9 * 60 + 30);
      store.addDayMarker(DayMarkerKind.sleep, wednesday);
      store.moveDayMarker(DayMarkerKind.sleep, wednesday, 12 * 60);
      await pumpPlanner(tester, store);
      return store;
    }

    testWidgets('with a tap on its label and "Remove"', (tester) async {
      final store = await withBoth(tester);

      await tester.tap(chip(DayMarkerKind.wake));
      await tester.pumpAndSettle();
      expect(menuLine('Remove sleep line'), findsNothing);
      await tester.tap(menuLine('Remove wake-up line'));
      await tester.pumpAndSettle();

      expect(store.dayMarker(DayMarkerKind.wake, wednesday), isNull);
      expect(chip(DayMarkerKind.wake), findsNothing);
      expect(lineOf(DayMarkerKind.wake), findsNothing);
      // The other line stays.
      expect(store.dayMarker(DayMarkerKind.sleep, wednesday), 12 * 60);
      expect(chip(DayMarkerKind.sleep), findsOneWidget);
      expect(store.undoName, 'Remove Wake-up Line');
    });

    testWidgets('with a right click on the line', (tester) async {
      final store = await withBoth(tester);
      final line = tester.getRect(lineOf(DayMarkerKind.sleep));

      await rightClick(tester, Offset(line.left + 10, line.center.dy));
      await tester.tap(menuLine('Remove sleep line'));
      await tester.pumpAndSettle();

      expect(store.dayMarker(DayMarkerKind.sleep, wednesday), isNull);
      expect(store.dayMarker(DayMarkerKind.wake, wednesday), 9 * 60 + 30);
      // No menu of the grid came up, and no block.
      expect(store.blocks(DayRange.single(wednesday)), isEmpty);
      expect(gridState(tester).draft, isNull);
    });

    testWidgets('a click that slips by a point opens the menu and moves '
        'nothing', (tester) async {
      final store = await withBoth(tester);
      final from = tester.getCenter(chip(DayMarkerKind.wake));

      await mouseDrag(tester, from, const Offset(1, 2), steps: 2);

      expect(store.dayMarker(DayMarkerKind.wake, wednesday), 9 * 60 + 30);
      expect(menuLine('Remove wake-up line'), findsOneWidget);
    });

    testWidgets('a tap away from the menu keeps the line', (tester) async {
      final store = await withBoth(tester);
      await tester.tap(chip(DayMarkerKind.wake));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(store.dayMarker(DayMarkerKind.wake, wednesday), 9 * 60 + 30);
      expect(chip(DayMarkerKind.wake), findsOneWidget);
    });
  });

  group('the lines on the screen', () {
    testWidgets('follow the store: another device, or undo', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);
      expect(chip(DayMarkerKind.wake), findsNothing);

      store.addDayMarker(DayMarkerKind.wake, wednesday);
      store.moveDayMarker(DayMarkerKind.wake, wednesday, 9 * 60 + 15);
      await tester.pumpAndSettle();
      expect(shownTime(tester, DayMarkerKind.wake), '09:15');

      store.undo();
      await tester.pumpAndSettle();
      expect(shownTime(tester, DayMarkerKind.wake), '07:00');
      store.undo();
      await tester.pumpAndSettle();
      expect(chip(DayMarkerKind.wake), findsNothing);
      await endToast(tester);
    });

    testWidgets('are there again when the screen comes back', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);
      await pickFromAdd(tester, 'Add wake-up line');
      await mouseDrag(
        tester,
        tester.getCenter(chip(DayMarkerKind.wake)),
        const Offset(0, 32),
      );
      expect(shownTime(tester, DayMarkerKind.wake), '07:30');

      store.screen = Screen.notes;
      await tester.pumpAndSettle();
      expect(chip(DayMarkerKind.wake), findsNothing);
      store.screen = Screen.planner;
      await tester.pumpAndSettle();

      expect(shownTime(tester, DayMarkerKind.wake), '07:30');
      // Today shows the same line of the same day.
      store.screen = Screen.today;
      await tester.pumpAndSettle();
      expect(shownTime(tester, DayMarkerKind.wake), '07:30');
    });

    testWidgets('each day of the week shows its own lines', (tester) async {
      final store = plannerStore();
      final monday = wednesday.adding(days: -2);
      store.addDayMarker(DayMarkerKind.wake, monday);
      store.moveDayMarker(DayMarkerKind.wake, monday, 9 * 60);
      store.addDayMarker(DayMarkerKind.wake, wednesday);
      store.moveDayMarker(DayMarkerKind.wake, wednesday, 10 * 60 + 30);
      await pumpPlanner(tester, store);

      expect(shownTime(tester, DayMarkerKind.wake, monday), '09:00');
      expect(shownTime(tester, DayMarkerKind.wake), '10:30');
      expect(chip(DayMarkerKind.wake, wednesday.adding(days: 1)), findsNothing);
      expect(
        tester.getRect(lineOf(DayMarkerKind.wake, monday)).left,
        tester.getRect(columnFinder(monday)).left,
      );
      // The day after has no line of its own. The week goes on: the lines
      // of this week are not on the next one.
      store.selectedDay = wednesday.adding(days: 7);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('day-marker-layer')), findsOneWidget);
      expect(chip(DayMarkerKind.wake, monday), findsNothing);
      expect(chip(DayMarkerKind.wake), findsNothing);
    });

    testWidgets('ask for no frame when nothing moves', (tester) async {
      final store = plannerStore();
      store.addDayMarker(DayMarkerKind.wake, wednesday);
      store.moveDayMarker(DayMarkerKind.wake, wednesday, 9 * 60 + 30);
      store.addDayMarker(DayMarkerKind.sleep, wednesday);
      // The planner alone: the shell has a background of its own.
      await pumpPane(
        tester,
        PlannerView(store: store, kind: PlannerKind.week),
        size: desktopSize,
      );
      await tester.pumpAndSettle();
      expect(chip(DayMarkerKind.wake), findsOneWidget);

      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 7));
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.hasRunningAnimations, isFalse);
      }
      expect(await framesAsked(tester), 0);

      // After a drag too: its clock for the edge of the screen has stopped.
      await mouseDrag(
        tester,
        tester.getCenter(chip(DayMarkerKind.wake)),
        const Offset(0, 64),
      );
      expect(store.dayMarker(DayMarkerKind.wake, wednesday), 10 * 60 + 30);
      expect(await framesAsked(tester), 0);
    });

    testWidgets('a screen reader says the line and its time, and can move '
        'it', (tester) async {
      final handle = tester.ensureSemantics();
      final store = plannerStore();
      store.addDayMarker(DayMarkerKind.wake, wednesday);
      store.moveDayMarker(DayMarkerKind.wake, wednesday, 9 * 60 + 30);
      await pumpPlanner(tester, store);

      final node = tester.getSemantics(find.bySemanticsLabel('Wake up line'));
      expect(node.value, '09:30');
      void act(SemanticsAction action) => tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          type: action,
          nodeId: tester.getSemantics(find.bySemanticsLabel('Wake up line')).id,
          viewId: tester.view.viewId,
        ),
      );
      act(SemanticsAction.increase);
      await tester.pumpAndSettle();
      expect(store.dayMarker(DayMarkerKind.wake, wednesday), 9 * 60 + 45);
      act(SemanticsAction.decrease);
      await tester.pumpAndSettle();
      expect(store.dayMarker(DayMarkerKind.wake, wednesday), 9 * 60 + 30);
      handle.dispose();
    });
  });

  group('with motion on', () {
    testWidgets('the grid glides to a new line and then rests', (tester) async {
      final store = plannerStore(motion: true);
      await pumpPane(
        tester,
        PlannerView(store: store, kind: PlannerKind.week),
        size: desktopSize,
      );
      await tester.pump();
      final scrolled = gridScroll(tester);

      await rightClick(tester, tester.getCenter(dayName()));
      await tester.pumpAndSettle();
      await tester.tap(menuLine('Add wake-up line'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(gridScroll(tester), lessThan(scrolled));
      await tester.pump(const Duration(milliseconds: 600));
      // 07:00, one hour below the top of the grid.
      expect(gridScroll(tester), 6 * hour);
      expect(shownTime(tester, DayMarkerKind.wake), '07:00');

      // Only the pulse of the now line asks for frames: 20 a second at
      // most. The lines ask for none.
      await tester.pump(const Duration(seconds: 1));
      expect(await framesAsked(tester), lessThanOrEqualTo(20));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('on a phone', () {
    testWidgets('a long press on the day name adds both lines, a finger '
        'moves one, a tap removes it', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store, size: phoneSize);
      expect(addButton, findsNothing);

      await pickFromDayMenu(tester, 'Add wake-up line', touch: true);
      await pickFromDayMenu(tester, 'Add sleep line', touch: true);
      expect(shownTime(tester, DayMarkerKind.sleep), '23:00');
      expect(store.dayMarker(DayMarkerKind.wake, wednesday), 7 * 60);

      final scrolled = gridScroll(tester);
      final from = tester.getCenter(chip(DayMarkerKind.sleep));
      final gesture = await tester.startGesture(from);
      await tester.pump();
      for (var i = 1; i <= 8; i++) {
        await gesture.moveTo(from + Offset(0, -8.0 * i));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(shownTime(tester, DayMarkerKind.sleep), '22:00');
      await gesture.up();
      await tester.pumpAndSettle();
      expect(store.dayMarker(DayMarkerKind.sleep, wednesday), 22 * 60);
      expect(gridScroll(tester), scrolled);
      expect(store.blocks(DayRange.single(wednesday)), isEmpty);
      expect(gridState(tester).draft, isNull);

      await tester.tap(chip(DayMarkerKind.sleep));
      await tester.pumpAndSettle();
      await tester.tap(menuLine('Remove sleep line'));
      await tester.pumpAndSettle();
      expect(store.dayMarker(DayMarkerKind.sleep, wednesday), isNull);
      expect(chip(DayMarkerKind.sleep), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Today screen: a long press on the date', (tester) async {
      final store = plannerStore()..screen = Screen.today;
      await pumpPlanner(tester, store, size: phoneSize);
      await pickFromDayMenu(
        tester,
        'Add wake-up line',
        today: true,
        touch: true,
      );
      expect(store.dayMarker(DayMarkerKind.wake, wednesday), 7 * 60);
      expect(chip(DayMarkerKind.wake), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('a right click on empty time', () {
    testWidgets('adds the wake-up line at the time of the click', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);

      await rightClick(tester, pointAt(tester, wednesday, 11 * 60 + 38));
      expect(menuLine('Add wake-up line at 11:45'), findsOneWidget);
      expect(menuLine('Add sleep line at 11:45'), findsOneWidget);
      await tester.tap(menuLine('Add wake-up line at 11:45'));
      await tester.pumpAndSettle();

      expect(store.dayMarker(DayMarkerKind.wake, wednesday), 11 * 60 + 45);
      expect(store.dayMarker(DayMarkerKind.sleep, wednesday), isNull);
      expect(store.undoName, 'Add Wake-up Line');
      expect(shownTime(tester, DayMarkerKind.wake), '11:45');
      // No new block, no block that waits for its title.
      expect(store.blocks(DayRange.single(wednesday)), isEmpty);
      expect(gridState(tester).draft, isNull);
    });

    testWidgets('acts on the day of the column that was clicked', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);
      final thursday = wednesday.adding(days: 1);

      await rightClick(tester, pointAt(tester, thursday, 10 * 60));
      await tester.tap(menuLine('Add sleep line at 10:00'));
      await tester.pumpAndSettle();

      expect(store.dayMarker(DayMarkerKind.sleep, thursday), 10 * 60);
      expect(store.dayMarker(DayMarkerKind.sleep, wednesday), isNull);
    });

    testWidgets('moves a line that is there to the time of the click', (
      tester,
    ) async {
      final store = plannerStore();
      store.addDayMarker(DayMarkerKind.wake, wednesday);
      await pumpPlanner(tester, store);

      await rightClick(tester, pointAt(tester, wednesday, 12 * 60));
      expect(menuLine('Add wake-up line at 12:00'), findsNothing);
      await tester.tap(menuLine('Move wake-up line to 12:00'));
      await tester.pumpAndSettle();

      expect(store.dayMarker(DayMarkerKind.wake, wednesday), 12 * 60);
      expect(store.undoName, 'Move Wake-up Line');
    });

    testWidgets('on a block opens the menu of the block', (tester) async {
      final store = plannerStore();
      store
        ..createFromDraft(
          title: 'Deep work',
          day: wednesday,
          start: 11 * 60,
          end: 12 * 60,
          asEvent: true,
        )
        ..selection = {};
      await pumpPlanner(tester, store);

      await rightClick(tester, pointAt(tester, wednesday, 11 * 60 + 30));

      expect(menuLine('Duration'), findsOneWidget);
      expect(find.textContaining('wake-up line at'), findsNothing);
    });
  });

  // The header of the week with the real fonts: day_marker_header_test.dart.
  group('the header of the timeline', () {
    testWidgets('fits at each width', (tester) async {
      final store = plannerStore()..screen = Screen.today;
      for (var width = 240.0; width <= 520; width += 10) {
        await pumpPane(
          tester,
          PlannerView(store: store, kind: PlannerKind.today),
          size: Size(width, 620),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'the timeline at a width of $width',
        );
      }
    });
  });
}
