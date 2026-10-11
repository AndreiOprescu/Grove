// Planner paths through the screen that had no test (PLAN §5.1.4, §5.1.6,
// §5.1.7): the command key, "Schedule existing task", Shift-ripple, a
// selection of more than one block, auto-scroll, Space, Cmd+D, zoom, the
// question for a repeating event, the all-day strip and the day totals.
//
// The tests run as on Android, so Ctrl is the command key.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/calendar/event_editor.dart';
import 'package:grove/ui/planner/inline_title_field.dart';
import 'package:grove/ui/planner/planner_grid.dart';
import 'package:grove/ui/planner/workload.dart';

import 'planner_support.dart';

const command = LogicalKeyboardKey.controlLeft;
const shift = LogicalKeyboardKey.shiftLeft;

final monday = wednesday.adding(days: -2);

/// A block on Wednesday, not selected. Gives the block.
PlannerBlock addBlock(
  AppStore store,
  String title, {
  bool asEvent = true,
  required int start,
  int length = 60,
  DayKey? day,
}) {
  store.createFromDraft(
    title: title,
    day: day ?? wednesday,
    start: start,
    end: start + length,
    asEvent: asEvent,
  );
  // A new block is selected. These tests start with no selection.
  store.selection = {};
  return blockNamed(store, title);
}

/// "11:00 to 12:00" as a pair of minutes.
(int, int) time(AppStore store, String title) {
  final block = blockNamed(store, title);
  return (block.startMinute, block.endMinute);
}

/// A mouse drag. `atEnd` is held down just before the button goes up, and
/// let go right after it. `during` is held only in the middle of the drag.
Future<void> mouseDragWithKey(
  WidgetTester tester,
  Offset from,
  Offset offset, {
  LogicalKeyboardKey? atEnd,
  LogicalKeyboardKey? during,
}) async {
  const steps = 8;
  final gesture = await tester.startGesture(
    from,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  if (during != null) await tester.sendKeyDownEvent(during);
  for (var i = 1; i <= steps; i++) {
    await gesture.moveTo(from + offset * (i / steps));
    await tester.pump(const Duration(milliseconds: 16));
  }
  if (during != null) await tester.sendKeyUpEvent(during);
  if (atEnd != null) await tester.sendKeyDownEvent(atEnd);
  await gesture.up();
  if (atEnd != null) await tester.sendKeyUpEvent(atEnd);
  await tester.pumpAndSettle();
}

/// A mouse click with the command key held.
Future<void> commandClick(WidgetTester tester, Offset at) async {
  await tester.sendKeyDownEvent(command);
  await mouseTap(tester, at);
  await tester.sendKeyUpEvent(command);
  await endTapWindow(tester);
  await tester.pumpAndSettle();
}

/// A key with the command key held.
Future<void> commandKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(command);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(command);
  await tester.pumpAndSettle();
}

/// The part of the window where the grid scrolls.
Rect viewport(WidgetTester tester) => tester.getRect(
  find
      .descendant(
        of: find.byType(PlannerGrid),
        matching: find.byType(Scrollable),
      )
      .first,
);

Finder get titleField => find.descendant(
  of: find.byType(InlineTitleField),
  matching: find.byType(EditableText),
);

void main() {
  group('the command key', () {
    testWidgets('held at the end of a drag on empty time, it makes an event', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);

      await mouseDragWithKey(
        tester,
        pointAt(tester, wednesday, 11 * 60),
        const Offset(0, hour),
        atEnd: command,
      );
      expect(gridState(tester).draft!.asEvent, isTrue);
      expect(find.text('New event'), findsOneWidget);

      // The key is up again when the title is typed.
      await tester.enterText(titleField, 'Dentist');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final block = blockNamed(store, 'Dentist');
      expect(block.isTaskBlock, isFalse);
      expect(block.kind, EventKind.event);
      expect((block.startMinute, block.endMinute), (660, 720));
      expect(store.openTasks(TaskPlacement.day(wednesday)), isEmpty);
    });

    testWidgets('let go before the end of the drag, it makes a task', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);

      await mouseDragWithKey(
        tester,
        pointAt(tester, wednesday, 11 * 60),
        const Offset(0, hour),
        during: command,
      );
      expect(gridState(tester).draft!.asEvent, isFalse);
      expect(find.text('New task'), findsOneWidget);

      await tester.enterText(titleField, 'Write report');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(blockNamed(store, 'Write report').isTaskBlock, isTrue);
    });

    testWidgets('held at Return in the title, it makes an event', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);
      await mouseDrag(
        tester,
        pointAt(tester, wednesday, 11 * 60),
        const Offset(0, hour),
      );
      expect(find.text('New task'), findsOneWidget);

      await tester.enterText(titleField, 'Dentist');
      await tester.sendKeyDownEvent(command);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.sendKeyUpEvent(command);
      await tester.pumpAndSettle();

      final block = blockNamed(store, 'Dentist');
      expect(block.isTaskBlock, isFalse);
      expect(block.kind, EventKind.event);
    });
  });

  group('"Schedule existing task"', () {
    Future<AppStore> withTasks(WidgetTester tester) async {
      final store = plannerStore();
      for (final title in [
        'Call the bank',
        'Call mum',
        'Call the vet',
        'Call the school',
        'Buy milk',
      ]) {
        store.quickAdd(title, placement: TaskPlacement.day(wednesday));
      }
      await pumpPlanner(tester, store);
      await mouseDrag(
        tester,
        pointAt(tester, wednesday, 10 * 60),
        const Offset(0, hour),
      );
      expect(gridState(tester).draft, isNotNull);
      return store;
    }

    Finder suggestions() => find.byWidgetPredicate((w) {
      final key = w.key;
      return key is ValueKey<String> && key.value.startsWith('suggest-');
    });

    testWidgets('two letters show the open tasks with that name, three at '
        'most', (tester) async {
      final store = await withTasks(tester);
      expect(find.text('Schedule existing task'), findsNothing);

      await tester.enterText(titleField, 'c');
      await tester.pumpAndSettle();
      expect(find.text('Schedule existing task'), findsNothing);
      expect(suggestions(), findsNothing);

      await tester.enterText(titleField, 'ca');
      await tester.pumpAndSettle();
      expect(find.text('Schedule existing task'), findsOneWidget);
      expect(suggestions(), findsNWidgets(3));
      for (final task in store.matchingTasks('ca', on: wednesday)) {
        expect(find.byKey(ValueKey('suggest-${task.id}')), findsOneWidget);
        expect(task.title, startsWith('Call'));
      }

      // A name that only one task has.
      await tester.enterText(titleField, 'vet');
      await tester.pumpAndSettle();
      expect(suggestions(), findsOneWidget);

      // No task has this name.
      await tester.enterText(titleField, 'zz');
      await tester.pumpAndSettle();
      expect(find.text('Schedule existing task'), findsNothing);
    });

    testWidgets('a click on a task gives it the time of the draft and makes '
        'no new task', (tester) async {
      final store = await withTasks(tester);
      final before = store.openTasks(TaskPlacement.day(wednesday)).length;
      await tester.enterText(titleField, 'vet');
      await tester.pumpAndSettle();
      final task = store.matchingTasks('vet', on: wednesday).single;

      await tester.tap(find.byKey(ValueKey('suggest-${task.id}')));
      await tester.pumpAndSettle();

      final block = store.blocks(DayRange.single(wednesday)).single;
      expect(block.taskId, task.id);
      expect(block.title, 'Call the vet');
      expect((block.startMinute, block.endMinute), (10 * 60, 11 * 60));
      expect(store.openTasks(TaskPlacement.day(wednesday)), hasLength(before));
      expect(gridState(tester).draft, isNull);
      expect(find.byKey(const ValueKey('planner-draft')), findsNothing);
      // The task is not a note with no time any more.
      expect(find.byKey(ValueKey('sticky-${task.id}')), findsNothing);
      expect(blockFinder(block.id), findsOneWidget);
    });

    testWidgets('Return with the same letters makes a new task', (
      tester,
    ) async {
      final store = await withTasks(tester);
      final before = store.openTasks(TaskPlacement.day(wednesday)).length;

      await tester.enterText(titleField, 'Call the vet again');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        store.openTasks(TaskPlacement.day(wednesday)),
        hasLength(before + 1),
      );
      expect(blockNamed(store, 'Call the vet again').isTaskBlock, isTrue);
    });

    testWidgets('a task that has a time on this day is not in the list', (
      tester,
    ) async {
      final store = plannerStore();
      addBlock(store, 'Call the bank', asEvent: false, start: 10 * 60);
      store.quickAdd('Call mum', placement: TaskPlacement.day(wednesday));
      await pumpPlanner(tester, store);
      await mouseDrag(
        tester,
        pointAt(tester, wednesday, 13 * 60),
        const Offset(0, hour),
      );

      await tester.enterText(titleField, 'call');
      await tester.pumpAndSettle();

      expect(suggestions(), findsOneWidget);
      expect(
        find.descendant(of: suggestions(), matching: find.text('Call mum')),
        findsOneWidget,
      );
    });
  });

  group('Shift at the end of a drag', () {
    Future<AppStore> withThree(WidgetTester tester) async {
      final store = plannerStore();
      addBlock(store, 'Alpha', start: 10 * 60);
      addBlock(store, 'Beta', start: 11 * 60);
      addBlock(store, 'Gamma', start: 12 * 60);
      await pumpPlanner(tester, store);
      return store;
    }

    testWidgets('a move pushes the blocks under it and says how many', (
      tester,
    ) async {
      final store = await withThree(tester);

      await mouseDragWithKey(
        tester,
        pointAt(tester, wednesday, 10 * 60 + 30),
        const Offset(0, hour / 2),
        atEnd: shift,
      );

      expect(time(store, 'Alpha'), (630, 690));
      expect(time(store, 'Beta'), (690, 750));
      expect(time(store, 'Gamma'), (750, 810));
      expect(find.text('Pushed 2 blocks'), findsOneWidget);
      await endToast(tester);
      expect(find.text('Pushed 2 blocks'), findsNothing);

      // One undo step puts all three back.
      store.undo();
      await tester.pumpAndSettle();
      expect(time(store, 'Alpha'), (600, 660));
      expect(time(store, 'Beta'), (660, 720));
      expect(time(store, 'Gamma'), (720, 780));
      await endToast(tester);
    });

    testWidgets('one pushed block: the message has no "s"', (tester) async {
      final store = plannerStore();
      addBlock(store, 'Alpha', start: 10 * 60);
      addBlock(store, 'Beta', start: 11 * 60);
      await pumpPlanner(tester, store);

      await mouseDragWithKey(
        tester,
        pointAt(tester, wednesday, 10 * 60 + 30),
        const Offset(0, hour / 4),
        atEnd: shift,
      );

      expect(time(store, 'Alpha'), (615, 675));
      expect(time(store, 'Beta'), (675, 735));
      expect(find.text('Pushed 1 block'), findsOneWidget);
      await endToast(tester);
    });

    testWidgets('a longer block pushes the blocks under it too', (
      tester,
    ) async {
      final store = await withThree(tester);
      final id = blockNamed(store, 'Alpha').id;

      await mouseDragWithKey(
        tester,
        tester.getCenter(find.byKey(ValueKey('resizeBottom-$id'))),
        const Offset(0, hour / 2),
        atEnd: shift,
      );

      expect(time(store, 'Alpha'), (600, 690));
      expect(time(store, 'Beta'), (690, 750));
      expect(time(store, 'Gamma'), (750, 810));
      expect(find.text('Pushed 2 blocks'), findsOneWidget);
      expect(store.undoName, 'Resize Block');
      await endToast(tester);
    });

    testWidgets('with no Shift nothing is pushed and nothing is said', (
      tester,
    ) async {
      final store = await withThree(tester);

      await mouseDrag(
        tester,
        pointAt(tester, wednesday, 10 * 60 + 30),
        const Offset(0, hour / 2),
      );

      expect(time(store, 'Alpha'), (630, 690));
      expect(time(store, 'Beta'), (660, 720));
      expect(time(store, 'Gamma'), (720, 780));
      expect(store.toast, isNull);
      expect(find.textContaining('Pushed'), findsNothing);
    });

    testWidgets('Shift let go before the end of the drag pushes nothing', (
      tester,
    ) async {
      final store = await withThree(tester);

      await mouseDragWithKey(
        tester,
        pointAt(tester, wednesday, 10 * 60 + 30),
        const Offset(0, hour / 2),
        during: shift,
      );

      expect(time(store, 'Alpha'), (630, 690));
      expect(time(store, 'Beta'), (660, 720));
      expect(store.toast, isNull);
    });

    testWidgets('a block above the moved block stays', (tester) async {
      final store = await withThree(tester);

      // Beta goes up by 30 minutes, over the end of Alpha.
      await mouseDragWithKey(
        tester,
        pointAt(tester, wednesday, 11 * 60 + 30),
        const Offset(0, -hour / 2),
        atEnd: shift,
      );

      expect(time(store, 'Alpha'), (600, 660));
      expect(time(store, 'Beta'), (630, 690));
      expect(time(store, 'Gamma'), (720, 780));
      expect(store.toast, isNull);
    });
  });

  group('more than one block', () {
    Future<AppStore> withThree(WidgetTester tester) async {
      final store = plannerStore();
      addBlock(store, 'Alpha', start: 10 * 60);
      addBlock(store, 'Beta', start: 12 * 60);
      addBlock(store, 'Gamma', start: 14 * 60, length: 30);
      await pumpPlanner(tester, store);
      return store;
    }

    String idOf(AppStore store, String title) => blockNamed(store, title).id;

    testWidgets('a click with the command key adds a block to the '
        'selection and takes it out again', (tester) async {
      final store = await withThree(tester);
      final alpha = idOf(store, 'Alpha');
      final beta = idOf(store, 'Beta');

      await commandClick(tester, pointAt(tester, wednesday, 10 * 60 + 30));
      expect(store.selection, {alpha});
      await commandClick(tester, pointAt(tester, wednesday, 12 * 60 + 30));
      expect(store.selection, {alpha, beta});
      // No card opens for a click that only selects.
      expect(store.editingEvent, isNull);
      expect(find.byType(EventEditor), findsNothing);

      await commandClick(tester, pointAt(tester, wednesday, 10 * 60 + 30));
      expect(store.selection, {beta});
    });

    testWidgets('a drag of one selected block moves all of them the same '
        'way', (tester) async {
      final store = await withThree(tester);
      await commandClick(tester, pointAt(tester, wednesday, 10 * 60 + 30));
      await commandClick(tester, pointAt(tester, wednesday, 12 * 60 + 30));
      final column = tester.getSize(columnFinder(wednesday)).width;

      // 45 minutes down and one day to the right.
      await mouseDrag(
        tester,
        pointAt(tester, wednesday, 12 * 60 + 30),
        Offset(column, hour * 0.75),
      );

      final thursday = wednesday.adding(days: 1);
      expect(blockNamed(store, 'Alpha').day, thursday);
      expect(blockNamed(store, 'Beta').day, thursday);
      expect(time(store, 'Alpha'), (645, 705));
      expect(time(store, 'Beta'), (765, 825));
      expect(blockNamed(store, 'Gamma').day, wednesday);
      expect(time(store, 'Gamma'), (840, 870));
      expect(store.selection, hasLength(2));

      // One undo step for the two blocks.
      expect(store.undoName, 'Move Block');
      store.undo();
      await tester.pumpAndSettle();
      expect(blockNamed(store, 'Alpha').day, wednesday);
      expect(time(store, 'Alpha'), (600, 660));
      expect(time(store, 'Beta'), (720, 780));
      await endToast(tester);
    });

    testWidgets('the selected blocks stop together at the end of the day', (
      tester,
    ) async {
      final store = plannerStore(now: 21 * 60);
      addBlock(store, 'Alpha', start: 21 * 60);
      addBlock(store, 'Beta', start: 22 * 60 + 30);
      await pumpPlanner(tester, store);
      await commandClick(tester, pointAt(tester, wednesday, 21 * 60 + 30));
      await commandClick(tester, pointAt(tester, wednesday, 23 * 60));

      await mouseDrag(
        tester,
        pointAt(tester, wednesday, 21 * 60 + 30),
        const Offset(0, hour * 1.5),
      );

      // Beta can go 30 minutes down. Alpha keeps its distance to it.
      expect(time(store, 'Alpha'), (21 * 60 + 30, 22 * 60 + 30));
      expect(time(store, 'Beta'), (23 * 60, 24 * 60));
    });

    testWidgets('a drag of a block that is not selected moves only that '
        'block', (tester) async {
      final store = await withThree(tester);
      await commandClick(tester, pointAt(tester, wednesday, 10 * 60 + 30));
      await commandClick(tester, pointAt(tester, wednesday, 12 * 60 + 30));

      await mouseDrag(
        tester,
        pointAt(tester, wednesday, 14 * 60 + 15),
        const Offset(0, -hour / 2),
      );

      expect(time(store, 'Gamma'), (810, 840));
      expect(time(store, 'Alpha'), (600, 660));
      expect(time(store, 'Beta'), (720, 780));
      expect(store.selection, {idOf(store, 'Gamma')});
    });

    testWidgets('Delete removes all selected blocks in one step', (
      tester,
    ) async {
      final store = await withThree(tester);
      await commandClick(tester, pointAt(tester, wednesday, 10 * 60 + 30));
      await commandClick(tester, pointAt(tester, wednesday, 12 * 60 + 30));

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      expect(store.blocks(DayRange.single(wednesday)).single.title, 'Gamma');
      expect(store.selection, isEmpty);
      store.undo();
      await tester.pumpAndSettle();
      expect(store.blocks(DayRange.single(wednesday)), hasLength(3));
      await endToast(tester);
    });

    testWidgets('the arrows move all selected blocks', (tester) async {
      final store = await withThree(tester);
      await commandClick(tester, pointAt(tester, wednesday, 10 * 60 + 30));
      await commandClick(tester, pointAt(tester, wednesday, 12 * 60 + 30));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(time(store, 'Alpha'), (615, 675));
      expect(time(store, 'Beta'), (735, 795));
      expect(time(store, 'Gamma'), (840, 870));
    });
  });

  group('auto-scroll', () {
    testWidgets('a block held near the bottom edge scrolls the grid and '
        'goes with it', (tester) async {
      final store = plannerStore();
      addBlock(store, 'Lunch', start: 11 * 60);
      await pumpPlanner(tester, store);
      final view = viewport(tester);
      final from = pointAt(tester, wednesday, 11 * 60 + 30);
      final scrollBefore = gridScroll(tester);

      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      // In the middle of the grid nothing scrolls.
      await gesture.moveTo(Offset(from.dx, view.center.dy));
      await tester.pump(const Duration(milliseconds: 160));
      expect(gridScroll(tester), scrollBefore);

      // 10 points from the bottom edge: the pointer is still, the grid goes.
      final hold = Offset(from.dx, view.bottom - 10);
      await gesture.moveTo(hold);
      await tester.pump(const Duration(milliseconds: 16));
      final first = gridScroll(tester);
      expect(first, greaterThan(scrollBefore));
      await tester.pump(const Duration(milliseconds: 160));
      final scrolled = gridScroll(tester);
      expect(scrolled, greaterThan(first + 100));
      // The label of the drag shows a time that is in view.
      expect(find.byKey(const ValueKey('live-label')), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();

      // The block is where the pointer is: its move on the screen and the
      // way the grid went under it.
      final moved = (hold.dy - from.dy) + (scrolled - scrollBefore);
      final start = PlannerMath.snap(
        11 * 60 + (moved / hour * 60).round(),
        step: PlannerMath.step,
      );
      expect(time(store, 'Lunch'), (start, start + 60));
      expect(start, greaterThan(14 * 60));

      // The scroll ends with the drag.
      await tester.pump(const Duration(milliseconds: 160));
      expect(gridScroll(tester), scrolled);
    });

    testWidgets('the scroll is faster nearer to the edge', (tester) async {
      final store = plannerStore();
      addBlock(store, 'Lunch', start: 11 * 60);
      await pumpPlanner(tester, store);
      final view = viewport(tester);
      final from = pointAt(tester, wednesday, 11 * 60 + 30);

      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(Offset(from.dx, view.bottom - 30));
      await tester.pump(const Duration(milliseconds: 16));
      final a = gridScroll(tester);
      await tester.pump(const Duration(milliseconds: 16));
      final slow = gridScroll(tester) - a;
      await gesture.moveTo(Offset(from.dx, view.bottom - 5));
      await tester.pump(const Duration(milliseconds: 16));
      final b = gridScroll(tester);
      await tester.pump(const Duration(milliseconds: 16));
      final fast = gridScroll(tester) - b;

      expect(slow, greaterThan(0));
      expect(fast, greaterThan(slow * 2));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a block held near the top edge scrolls the grid up', (
      tester,
    ) async {
      final store = plannerStore();
      addBlock(store, 'Lunch', start: 12 * 60);
      await pumpPlanner(tester, store);
      final view = viewport(tester);
      final from = pointAt(tester, wednesday, 12 * 60 + 30);
      final scrollBefore = gridScroll(tester);

      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      final hold = Offset(from.dx, view.top + 10);
      await gesture.moveTo(hold);
      await tester.pump(const Duration(milliseconds: 176));
      final scrolled = gridScroll(tester);
      expect(scrolled, lessThan(scrollBefore - 100));
      await gesture.up();
      await tester.pumpAndSettle();

      final moved = (hold.dy - from.dy) + (scrolled - scrollBefore);
      final start = PlannerMath.snap(
        12 * 60 + (moved / hour * 60).round(),
        step: PlannerMath.step,
      );
      expect(time(store, 'Lunch'), (start, start + 60));
      expect(start, lessThan(9 * 60));
    });

    testWidgets('the grid stops at the end of the day', (tester) async {
      final store = plannerStore();
      addBlock(store, 'Lunch', start: 11 * 60);
      await pumpPlanner(tester, store);
      final view = viewport(tester);
      final from = pointAt(tester, wednesday, 11 * 60 + 30);

      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(Offset(from.dx, view.bottom - 2));
      await tester.pump(const Duration(seconds: 2));
      final end = gridScroll(tester);
      expect(end, 24 * hour - view.height);
      await tester.pump(const Duration(milliseconds: 160));
      expect(gridScroll(tester), end);
      await gesture.up();
      await tester.pumpAndSettle();

      // The block cannot go over midnight.
      expect(time(store, 'Lunch').$2, lessThanOrEqualTo(24 * 60));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a drag on empty time scrolls too, and the new block grows', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);
      final view = viewport(tester);
      final from = pointAt(tester, wednesday, 13 * 60);
      final scrollBefore = gridScroll(tester);

      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      final hold = Offset(from.dx, view.bottom - 10);
      await gesture.moveTo(hold);
      await tester.pump(const Duration(milliseconds: 16));
      final rect = find.byKey(const ValueKey('create-rect'));
      final small = tester.getSize(rect).height;
      await tester.pump(const Duration(milliseconds: 160));
      final scrolled = gridScroll(tester);
      expect(scrolled, greaterThan(scrollBefore + 100));
      expect(tester.getSize(rect).height, greaterThan(small + 100));

      await gesture.up();
      await tester.pumpAndSettle();
      final moved = (hold.dy - from.dy) + (scrolled - scrollBefore);
      final draft = gridState(tester).draft!;
      expect(draft.start, 13 * 60);
      expect(
        draft.end,
        PlannerMath.snap(
          13 * 60 + (moved / hour * 60).round(),
          step: PlannerMath.step,
        ),
      );
    });

    testWidgets('a finger that holds a block near the bottom edge scrolls '
        'the grid', (tester) async {
      final store = plannerStore();
      addBlock(store, 'Lunch', start: 11 * 60);
      await pumpPlanner(tester, store, size: phoneSize);
      final view = viewport(tester);
      final from = pointAt(tester, wednesday, 11 * 60 + 30);
      final scrollBefore = gridScroll(tester);

      final gesture = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 600));
      for (var i = 1; i <= 8; i++) {
        await gesture.moveTo(
          Offset.lerp(from, Offset(from.dx, view.bottom - 10), i / 8)!,
        );
        await tester.pump(const Duration(milliseconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 160));
      final scrolled = gridScroll(tester);
      expect(scrolled, greaterThan(scrollBefore + 100));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(time(store, 'Lunch').$1, greaterThan(13 * 60));
      expect(tester.takeException(), isNull);
    });
  });

  group('keys', () {
    testWidgets('Space marks the selected task block done and open again', (
      tester,
    ) async {
      final store = plannerStore();
      final block = addBlock(store, 'Write', asEvent: false, start: 11 * 60);
      await pumpPlanner(tester, store);
      await mouseTap(tester, pointAt(tester, wednesday, 11 * 60 + 30));
      await endTapWindow(tester);
      await tester.pumpAndSettle();
      expect(store.selection, {block.id});

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(store.task(block.taskId!)!.status, TaskStatus.done);
      expect(blockNamed(store, 'Write').isDone, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(store.task(block.taskId!)!.status, TaskStatus.open);
    });

    testWidgets('Space marks the selected goal block done', (tester) async {
      final store = plannerStore();
      final id = goalBlock(store);
      await pumpPlanner(tester, store);
      await mouseTap(tester, pointAt(tester, wednesday, 11 * 60 + 30));
      await endTapWindow(tester);
      await tester.pumpAndSettle();
      expect(store.selection, {id});

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(store.blocks(DayRange.single(wednesday)).single.isDone, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(store.blocks(DayRange.single(wednesday)).single.isDone, isFalse);
    });

    testWidgets('Space marks all selected task blocks', (tester) async {
      final store = plannerStore();
      final a = addBlock(store, 'Write', asEvent: false, start: 10 * 60);
      final b = addBlock(store, 'Read', asEvent: false, start: 12 * 60);
      await pumpPlanner(tester, store);
      await commandClick(tester, pointAt(tester, wednesday, 10 * 60 + 30));
      await commandClick(tester, pointAt(tester, wednesday, 12 * 60 + 30));
      expect(store.selection, {a.id, b.id});

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      expect(blockNamed(store, 'Write').isDone, isTrue);
      expect(blockNamed(store, 'Read').isDone, isTrue);
    });

    testWidgets('the command key with D puts a copy after the block', (
      tester,
    ) async {
      final store = plannerStore();
      final block = addBlock(store, 'Lunch', start: 11 * 60);
      await pumpPlanner(tester, store);
      await commandClick(tester, pointAt(tester, wednesday, 11 * 60 + 30));
      expect(store.selection, {block.id});

      await commandKey(tester, LogicalKeyboardKey.keyD);

      final blocks = store.blocks(DayRange.single(wednesday));
      expect(blocks, hasLength(2));
      final copy = blocks.firstWhere((b) => b.id != block.id);
      expect(copy.title, 'Lunch');
      expect((copy.startMinute, copy.endMinute), (720, 780));
      expect(store.selection, {copy.id});
      expect(blockFinder(copy.id), findsOneWidget);
      expect(store.undoName, 'Duplicate');
    });

    testWidgets('D with no command key copies nothing', (tester) async {
      final store = plannerStore();
      addBlock(store, 'Lunch', start: 11 * 60);
      await pumpPlanner(tester, store);
      await commandClick(tester, pointAt(tester, wednesday, 11 * 60 + 30));

      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.pumpAndSettle();

      expect(store.blocks(DayRange.single(wednesday)), hasLength(1));
    });
  });

  group('zoom', () {
    testWidgets('the command key with + and - changes the height of an '
        'hour', (tester) async {
      final store = plannerStore();
      final block = addBlock(store, 'Lunch', start: 11 * 60);
      await pumpPlanner(tester, store);
      // A click on the grid gives it the keys.
      await mouseTap(tester, pointAt(tester, wednesday, 14 * 60));
      await endTapWindow(tester);
      final before = tester.getSize(blockFinder(block.id)).height;
      expect(store.plannerHourHeight, 64);

      await commandKey(tester, LogicalKeyboardKey.equal);
      expect(store.plannerHourHeight, closeTo(76.8, 0.001));
      expect(
        tester.getSize(blockFinder(block.id)).height,
        greaterThan(before + 10),
      );
      expect(
        tester.getSize(columnFinder(wednesday)).height,
        closeTo(24 * 76.8, 1),
      );

      await commandKey(tester, LogicalKeyboardKey.minus);
      expect(store.plannerHourHeight, closeTo(64, 0.001));
      expect(tester.getSize(blockFinder(block.id)).height, closeTo(before, 1));

      await commandKey(tester, LogicalKeyboardKey.minus);
      expect(store.plannerHourHeight, closeTo(64 / 1.2, 0.001));
      expect(
        tester.getSize(blockFinder(block.id)).height,
        lessThan(before - 5),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the keys of the number pad zoom too', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);
      await mouseTap(tester, pointAt(tester, wednesday, 14 * 60));
      await endTapWindow(tester);

      await commandKey(tester, LogicalKeyboardKey.numpadAdd);
      expect(store.plannerHourHeight, closeTo(76.8, 0.001));
      await commandKey(tester, LogicalKeyboardKey.numpadSubtract);
      expect(store.plannerHourHeight, closeTo(64, 0.001));
    });

    testWidgets('an hour is never lower than 36 or higher than 160', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);
      await mouseTap(tester, pointAt(tester, wednesday, 14 * 60));
      await endTapWindow(tester);

      for (var i = 0; i < 8; i++) {
        await commandKey(tester, LogicalKeyboardKey.equal);
      }
      expect(store.plannerHourHeight, 160);
      expect(tester.getSize(columnFinder(wednesday)).height, 24 * 160);

      for (var i = 0; i < 12; i++) {
        await commandKey(tester, LogicalKeyboardKey.minus);
      }
      expect(store.plannerHourHeight, 36);
      expect(tester.getSize(columnFinder(wednesday)).height, 24 * 36);
      expect(tester.takeException(), isNull);
    });

    testWidgets('+ with no command key does not zoom', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);
      await mouseTap(tester, pointAt(tester, wednesday, 14 * 60));
      await endTapWindow(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.sendKeyEvent(LogicalKeyboardKey.minus);
      await tester.pumpAndSettle();

      expect(store.plannerHourHeight, 64);
    });

    testWidgets('the buttons "Zoom in" and "Zoom out" change the height of '
        'an hour', (tester) async {
      final store = plannerStore();
      final block = addBlock(store, 'Lunch', start: 11 * 60);
      await pumpPlanner(tester, store);
      final before = tester.getSize(blockFinder(block.id)).height;

      await tester.tap(find.bySemanticsLabel('Zoom in'));
      await tester.pumpAndSettle();
      expect(store.plannerHourHeight, closeTo(76.8, 0.001));
      expect(
        tester.getSize(blockFinder(block.id)).height,
        greaterThan(before + 10),
      );

      await tester.tap(find.bySemanticsLabel('Zoom out'));
      await tester.tap(find.bySemanticsLabel('Zoom out'));
      await tester.pumpAndSettle();
      expect(store.plannerHourHeight, closeTo(64 / 1.2, 0.001));
      expect(
        tester.getSize(blockFinder(block.id)).height,
        lessThan(before - 5),
      );

      for (var i = 0; i < 10; i++) {
        await tester.tap(find.bySemanticsLabel('Zoom in'));
      }
      await tester.pumpAndSettle();
      expect(store.plannerHourHeight, 160);
      for (var i = 0; i < 12; i++) {
        await tester.tap(find.bySemanticsLabel('Zoom out'));
      }
      await tester.pumpAndSettle();
      expect(store.plannerHourHeight, 36);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a drag after a zoom still follows the pointer', (
      tester,
    ) async {
      final store = plannerStore();
      addBlock(store, 'Lunch', start: 15 * 60);
      await pumpPlanner(tester, store);
      for (var i = 0; i < 12; i++) {
        await tester.tap(find.bySemanticsLabel('Zoom out'));
      }
      await tester.pumpAndSettle();
      expect(store.plannerHourHeight, 36);

      // One hour is 36 points now. The block is in the middle of the grid,
      // far from the edges that scroll.
      final column = tester.getRect(columnFinder(wednesday));
      final view = viewport(tester);
      final from = Offset(column.center.dx, column.top + 15.5 * 36);
      expect(from.dy, greaterThan(view.top + 40));
      expect(from.dy + 36, lessThan(view.bottom - 40));
      await mouseDrag(tester, from, const Offset(0, 36));

      expect(time(store, 'Lunch'), (16 * 60, 17 * 60));
    });
  });

  group('a repeating event', () {
    /// "Standup", each Monday from 11:00 to 12:00.
    Future<AppStore> withStandup(WidgetTester tester) async {
      final store = plannerStore();
      store.saveEvent(
        EventItem(
          title: 'Standup',
          start: WallTime(day: monday, minute: 11 * 60),
          end: WallTime(day: monday, minute: 12 * 60),
          recurrence: RecurrenceRule(freq: Freq.weekly),
        ),
        from: null,
      );
      await pumpPlanner(tester, store);
      return store;
    }

    final nextMonday = monday.adding(days: 7);

    (int, int) standup(AppStore store, DayKey day) {
      final block = store.blocks(DayRange.single(day)).single;
      expect(block.title, 'Standup');
      return (block.startMinute, block.endMinute);
    }

    Future<void> answer(WidgetTester tester, String button) async {
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
    }

    testWidgets('a drag asks: this day only, or all days', (tester) async {
      final store = await withStandup(tester);

      await mouseDrag(
        tester,
        pointAt(tester, monday, 11 * 60 + 30),
        const Offset(0, hour),
      );

      expect(find.text('Move a repeating event'), findsOneWidget);
      expect(
        find.text('Change this day only, or every day of the event?'),
        findsOneWidget,
      );
      for (final button in ['Cancel', 'All events', 'This event only']) {
        expect(find.text(button), findsOneWidget, reason: button);
      }
      // Nothing is saved before the answer.
      expect(standup(store, monday), (660, 720));
    });

    testWidgets('"This event only" moves that day and keeps the others', (
      tester,
    ) async {
      final store = await withStandup(tester);
      await mouseDrag(
        tester,
        pointAt(tester, monday, 11 * 60 + 30),
        const Offset(0, hour),
      );

      await answer(tester, 'This event only');

      expect(find.text('Move a repeating event'), findsNothing);
      expect(standup(store, monday), (720, 780));
      expect(standup(store, nextMonday), (660, 720));
      expect(store.undoName, 'Move Block');

      store.undo();
      await tester.pumpAndSettle();
      expect(standup(store, monday), (660, 720));
      await endToast(tester);
    });

    testWidgets('"All events" moves every day of the event', (tester) async {
      final store = await withStandup(tester);
      await mouseDrag(
        tester,
        pointAt(tester, monday, 11 * 60 + 30),
        const Offset(0, hour),
      );

      await answer(tester, 'All events');

      expect(standup(store, monday), (720, 780));
      expect(standup(store, nextMonday), (720, 780));
    });

    testWidgets('"Cancel" puts the block back', (tester) async {
      final store = await withStandup(tester);
      final before = tester.getRect(
        blockFinder(store.blocks(DayRange.single(monday)).single.id),
      );
      await mouseDrag(
        tester,
        pointAt(tester, monday, 11 * 60 + 30),
        const Offset(0, hour),
      );

      await answer(tester, 'Cancel');

      expect(find.text('Move a repeating event'), findsNothing);
      expect(store.recurringPrompt, isNull);
      expect(standup(store, monday), (660, 720));
      expect(standup(store, nextMonday), (660, 720));
      expect(
        tester.getRect(
          blockFinder(store.blocks(DayRange.single(monday)).single.id),
        ),
        before,
      );
    });

    testWidgets('a drag to another day asks too', (tester) async {
      final store = await withStandup(tester);
      final column = tester.getSize(columnFinder(monday)).width;
      await mouseDrag(
        tester,
        pointAt(tester, monday, 11 * 60 + 30),
        Offset(column, 0),
      );
      expect(find.text('Move a repeating event'), findsOneWidget);

      await answer(tester, 'This event only');

      final tuesday = monday.adding(days: 1);
      expect(store.blocks(DayRange.single(monday)), isEmpty);
      expect(standup(store, tuesday), (660, 720));
      expect(standup(store, nextMonday), (660, 720));
    });

    testWidgets('a new length asks with the word "Resize"', (tester) async {
      final store = await withStandup(tester);
      final id = store.blocks(DayRange.single(monday)).single.id;

      await mouseDrag(
        tester,
        tester.getCenter(find.byKey(ValueKey('resizeBottom-$id'))),
        const Offset(0, hour / 2),
      );
      expect(find.text('Resize a repeating event'), findsOneWidget);

      await answer(tester, 'All events');
      expect(standup(store, monday), (660, 750));
      expect(standup(store, nextMonday), (660, 750));
    });

    testWidgets('"Delete Event" in the menu asks with the word "Delete"', (
      tester,
    ) async {
      final store = await withStandup(tester);

      await rightClick(tester, pointAt(tester, monday, 11 * 60 + 30));
      await tester.tap(find.text('Delete Event'));
      await tester.pumpAndSettle();
      expect(find.text('Delete a repeating event'), findsOneWidget);

      await answer(tester, 'This event only');
      expect(store.blocks(DayRange.single(monday)), isEmpty);
      expect(standup(store, nextMonday), (660, 720));
    });

    testWidgets('"Duration" in the menu asks with the word "Change"', (
      tester,
    ) async {
      final store = await withStandup(tester);

      await rightClick(tester, pointAt(tester, monday, 11 * 60 + 30));
      await tester.tap(find.text('Duration'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2h'));
      await tester.pumpAndSettle();
      expect(find.text('Change a repeating event'), findsOneWidget);

      await answer(tester, 'This event only');
      expect(standup(store, monday), (660, 780));
      expect(standup(store, nextMonday), (660, 720));
    });

    testWidgets('a copy or a split says that it cannot be done', (
      tester,
    ) async {
      final store = await withStandup(tester);

      await rightClick(tester, pointAt(tester, monday, 11 * 60 + 30));
      await tester.tap(find.text('Duplicate'));
      await tester.pumpAndSettle();
      expect(
        find.text('A repeating event cannot be copied here yet.'),
        findsOneWidget,
      );
      await endToast(tester);

      await rightClick(tester, pointAt(tester, monday, 11 * 60 + 30));
      await tester.tap(find.text('Split in Two'));
      await tester.pumpAndSettle();
      expect(find.text('A repeating event cannot be split.'), findsOneWidget);
      await endToast(tester);

      expect(standup(store, monday), (660, 720));
      expect(store.recurringPrompt, isNull);
    });
  });

  group('the all-day strip', () {
    EventItem allDay(AppStore store, String title, DayKey day) {
      store.saveEvent(
        EventItem(
          title: title,
          start: WallTime(day: day, minute: 0),
          end: WallTime(day: day, minute: 0),
          allDay: true,
        ),
        from: null,
      );
      return store
          .allDayEvents(DayRange.single(day))
          .firstWhere((e) => e.title == title);
    }

    testWidgets('an all-day event is in the strip, not on the grid', (
      tester,
    ) async {
      final store = plannerStore();
      final birthday = allDay(store, 'Birthday', monday);
      final fair = allDay(store, 'Book fair', wednesday.adding(days: 2));
      await pumpPlanner(tester, store);

      expect(find.text('All day'), findsOneWidget);
      for (final e in [birthday, fair]) {
        final chip = find.byKey(ValueKey('all-day-${e.id}'));
        expect(chip, findsOneWidget);
        expect(
          find.descendant(of: chip, matching: find.text(e.title)),
          findsOneWidget,
        );
        expect(blockFinder(e.id), findsNothing);
      }
      expect(find.text('Birthday'), findsOneWidget);
      // The strip is over the grid.
      expect(
        tester.getRect(find.text('All day')).bottom,
        lessThanOrEqualTo(viewport(tester).top),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('with no all-day event in the week there is no strip', (
      tester,
    ) async {
      final store = plannerStore();
      addBlock(store, 'Lunch', start: 11 * 60);
      // An all-day event of the next week.
      allDay(store, 'Trip', wednesday.adding(days: 7));
      await pumpPlanner(tester, store);

      expect(find.text('All day'), findsNothing);

      // The next week has it.
      await tester.tap(find.bySemanticsLabel('Next'));
      await tester.pumpAndSettle();
      expect(find.text('All day'), findsOneWidget);
      expect(find.text('Trip'), findsOneWidget);
    });

    testWidgets('a click on the event opens its card', (tester) async {
      final store = plannerStore();
      final birthday = allDay(store, 'Birthday', monday);
      await pumpPlanner(tester, store);

      await tester.tap(find.byKey(ValueKey('all-day-${birthday.id}')));
      await tester.pumpAndSettle();

      expect(store.editingEvent?.item.id, birthday.id);
      expect(find.byType(EventEditor), findsOneWidget);
    });

    testWidgets('a phone shows the all-day events of its one day', (
      tester,
    ) async {
      final store = plannerStore();
      allDay(store, 'Birthday', monday);
      final fair = allDay(store, 'Book fair', wednesday);
      await pumpPlanner(tester, store, size: phoneSize);

      expect(find.text('All day'), findsOneWidget);
      expect(find.byKey(ValueKey('all-day-${fair.id}')), findsOneWidget);
      expect(find.text('Birthday'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('the day totals', () {
    WorkloadBar bar(WidgetTester tester) =>
        tester.widget<WorkloadBar>(find.byType(WorkloadBar));

    testWidgets('the header shows planned time against the daily limit', (
      tester,
    ) async {
      final store = plannerStore();
      final done = addBlock(store, 'Write', asEvent: false, start: 10 * 60);
      addBlock(store, 'Read', asEvent: false, start: 14 * 60, length: 30);
      addBlock(store, 'Lunch', start: 12 * 60, length: 90);
      // Before the working hours: planned time, but not less free time.
      addBlock(store, 'Run', start: 7 * 60, length: 30);
      store.toggleDone(taskId: done.taskId!);
      await pumpPlanner(tester, store);

      expect(bar(tester).planned, 210);
      expect(bar(tester).limit, 9 * 60);
      expect(
        bar(tester).detail,
        '3h 30m planned · 6h free in working hours · 1/2 done',
      );
      expect(
        find.descendant(
          of: find.byType(WorkloadBar),
          matching: find.text('3h 30m/9h'),
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Planned 3h 30m/9h'), findsOneWidget);
    });

    testWidgets('the pointer over the bar shows the numbers of the day', (
      tester,
    ) async {
      final store = plannerStore();
      addBlock(store, 'Write', asEvent: false, start: 10 * 60);
      await pumpPlanner(tester, store);
      const detail = '1h planned · 8h free in working hours · 0/1 done';
      expect(find.text(detail), findsNothing);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byType(WorkloadBar)));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text(detail), findsOneWidget);
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
    });

    testWidgets('the totals follow a change on the grid', (tester) async {
      final store = plannerStore();
      final block = addBlock(store, 'Lunch', start: 11 * 60);
      await pumpPlanner(tester, store);
      expect(bar(tester).planned, 60);

      await mouseDrag(
        tester,
        tester.getCenter(find.byKey(ValueKey('resizeBottom-${block.id}'))),
        const Offset(0, hour),
      );

      expect(bar(tester).planned, 120);
      expect(
        bar(tester).detail,
        '2h planned · 7h free in working hours · 0/0 done',
      );
      expect(find.text('2h/9h'), findsOneWidget);
    });

    testWidgets('two blocks at the same time count once', (tester) async {
      final store = plannerStore();
      addBlock(store, 'Lunch', start: 11 * 60);
      addBlock(store, 'Call', start: 11 * 60 + 30);
      await pumpPlanner(tester, store);

      expect(bar(tester).planned, 90);
    });

    testWidgets('the totals are of the selected day', (tester) async {
      final store = plannerStore();
      final thursday = wednesday.adding(days: 1);
      addBlock(store, 'Lunch', start: 11 * 60);
      addBlock(store, 'Workshop', start: 10 * 60, length: 180, day: thursday);
      await pumpPlanner(tester, store);
      expect(bar(tester).planned, 60);

      await tester.tap(find.byKey(ValueKey('day-header-${thursday.string}')));
      await tester.pumpAndSettle();

      expect(store.selectedDay, thursday);
      expect(bar(tester).planned, 180);
    });

    testWidgets('a day over the limit says so', (tester) async {
      final store = plannerStore();
      addBlock(store, 'Night shift', start: 0, length: 8 * 60);
      addBlock(store, 'Workshop', start: 10 * 60, length: 120);
      await pumpPlanner(tester, store);

      expect(bar(tester).planned, 600);
      expect(
        find.bySemanticsLabel('Planned 10h/9h. Over the daily limit.'),
        findsOneWidget,
      );
      expect(find.text('10h/9h'), findsOneWidget);
    });

    testWidgets('a change that takes the day over the limit opens "Busy '
        'day"', (tester) async {
      final store = plannerStore();
      addBlock(store, 'Night shift', start: 0, length: 8 * 60);
      addBlock(store, 'Lunch', start: 11 * 60);
      await pumpPlanner(tester, store);
      expect(find.text('Busy day'), findsNothing);

      await rightClick(tester, pointAt(tester, wednesday, 11 * 60 + 30));
      await tester.tap(find.text('Duration'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2h'));
      await tester.pumpAndSettle();

      expect(find.text('Busy day'), findsOneWidget);
      expect(find.textContaining('has 10h planned'), findsOneWidget);
      expect(find.textContaining('That is more than 9h.'), findsOneWidget);
      // The change is saved. The window only tells.
      expect(time(store, 'Lunch'), (660, 780));

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Busy day'), findsNothing);
      expect(store.overloadWarning, isNull);

      // One more change on a day that is over the limit does not ask again.
      await rightClick(tester, pointAt(tester, wednesday, 11 * 60 + 30));
      await tester.tap(find.text('Duration'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3h'));
      await tester.pumpAndSettle();
      expect(find.text('Busy day'), findsNothing);
    });
  });
}
