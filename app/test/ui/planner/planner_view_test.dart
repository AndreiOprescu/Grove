import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/planner/inline_title_field.dart';
import 'package:grove/ui/planner/planner_grid.dart';
import 'package:grove/ui/planner/sticky_strip.dart';

import 'planner_support.dart';

void main() {
  group('the planner screen', () {
    testWidgets('shows the week, the hours and the now line', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);

      expect(find.byType(PlannerGrid), findsOneWidget);
      expect(find.text('5 Oct – 11 Oct 2026'), findsOneWidget);
      for (final name in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('09:00'), findsOneWidget);
      expect(find.byKey(const ValueKey('now-line')), findsOneWidget);
      expect(
        find.text('Drag a task here, or drag on the grid to plan time.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the day columns of the header, the strip and the grid start '
        'on the same whole points', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);

      for (var i = 0; i < 7; i++) {
        final day = wednesday.adding(days: i - 2);
        final column = tester.getRect(columnFinder(day));
        final header = tester.getRect(
          find.byKey(ValueKey('day-header-${day.string}')),
        );
        final cell = tester.getRect(
          find.byKey(ValueKey('sticky-cell-${day.string}')),
        );
        expect(column.left, column.left.roundToDouble(), reason: day.string);
        expect(header.left, column.left, reason: day.string);
        expect(cell.left, column.left, reason: day.string);
        expect(header.width, column.width, reason: day.string);
        expect(cell.width, column.width, reason: day.string);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a phone shows one day column', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store, size: phoneSize);

      expect(columnFinder(wednesday), findsOneWidget);
      expect(columnFinder(wednesday.adding(days: 1)), findsNothing);
      expect(find.text('Wednesday 7 October'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Next'));
      await tester.pumpAndSettle();
      expect(store.selectedDay, wednesday.adding(days: 1));
      expect(columnFinder(wednesday.adding(days: 1)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Previous and Next move one week', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);

      await tester.tap(find.bySemanticsLabel('Next'));
      await tester.pumpAndSettle();
      expect(store.selectedDay, wednesday.adding(days: 7));
      expect(find.text('12 Oct – 18 Oct 2026'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('planner-today')));
      await tester.pumpAndSettle();
      expect(store.selectedDay, wednesday);
    });
  });

  group('create', () {
    testWidgets('a mouse drag on empty time makes a block', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);

      await mouseDrag(
        tester,
        pointAt(tester, wednesday, 11 * 60),
        const Offset(0, hour),
      );
      expect(find.byKey(const ValueKey('planner-draft')), findsOneWidget);
      // Nothing is saved before the title.
      expect(store.blocks(DayRange.single(wednesday)), isEmpty);

      await tester.enterText(find.byType(EditableText), 'Write report');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final block = blockNamed(store, 'Write report');
      expect(block.day, wednesday);
      expect(block.startMinute, 11 * 60);
      expect(block.endMinute, 12 * 60);
      expect(block.isTaskBlock, isTrue);
      expect(find.byKey(const ValueKey('planner-draft')), findsNothing);
      expect(blockFinder(block.id), findsOneWidget);
    });

    testWidgets('a short drag makes 30 minutes; the start snaps to 15', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);

      // 11:03 snaps to 11:00. 4 points is less than 15 minutes.
      await mouseDrag(
        tester,
        pointAt(tester, wednesday, 11 * 60 + 3),
        const Offset(0, 4),
      );
      final draft = gridState(tester).draft!;
      expect(draft.start, 11 * 60);
      expect(draft.end, 11 * 60 + 30);
    });

    testWidgets('a finger makes a block with press, hold and drag', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);

      await touchDrag(
        tester,
        pointAt(tester, wednesday, 13 * 60),
        const Offset(0, hour * 1.5),
      );
      final draft = gridState(tester).draft!;
      expect(draft.day, wednesday);
      expect(draft.start, 13 * 60);
      expect(draft.end, 14 * 60 + 30);
    });

    testWidgets('Escape closes the draft and saves nothing', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);

      await mouseDrag(
        tester,
        pointAt(tester, wednesday, 11 * 60),
        const Offset(0, hour),
      );
      await tester.enterText(find.byType(EditableText), 'No');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('planner-draft')), findsNothing);
      expect(store.blocks(DayRange.single(wednesday)), isEmpty);
    });

    testWidgets('a press on a block does not start a new block', (
      tester,
    ) async {
      final store = plannerStore();
      store.createFromDraft(
        title: 'Busy',
        day: wednesday,
        start: 11 * 60,
        end: 12 * 60,
        asEvent: true,
      );
      await pumpPlanner(tester, store);

      await mouseTap(tester, pointAt(tester, wednesday, 11 * 60 + 30));
      await endTapWindow(tester);
      expect(gridState(tester).draft, isNull);
      expect(find.byKey(const ValueKey('create-rect')), findsNothing);
      expect(store.selection, {blockNamed(store, 'Busy').id});
    });
  });

  group('move and resize', () {
    testWidgets('a mouse drag moves a block and snaps to 15 minutes', (
      tester,
    ) async {
      final store = plannerStore();
      store.createFromDraft(
        title: 'Lunch',
        day: wednesday,
        start: 11 * 60,
        end: 12 * 60,
        asEvent: true,
      );
      final id = blockNamed(store, 'Lunch').id;
      await pumpPlanner(tester, store);

      // 70 points is about 66 minutes. The block snaps to +60.
      await mouseDrag(
        tester,
        pointAt(tester, wednesday, 11 * 60 + 30),
        const Offset(0, 70),
      );
      final block = store.blocks(DayRange.single(wednesday)).single;
      expect(block.id, id);
      expect(block.startMinute, 12 * 60);
      expect(block.endMinute, 13 * 60);
      expect(store.undoName, 'Move Block');
    });

    testWidgets('the label shows the new time during the drag', (tester) async {
      final store = plannerStore();
      store.createFromDraft(
        title: 'Lunch',
        day: wednesday,
        start: 11 * 60,
        end: 12 * 60,
        asEvent: true,
      );
      await pumpPlanner(tester, store);

      final from = pointAt(tester, wednesday, 11 * 60 + 30);
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(from + const Offset(0, hour / 2));
      await tester.pump();
      await gesture.moveTo(from + const Offset(0, hour));
      await tester.pump();

      expect(find.byKey(const ValueKey('live-label')), findsOneWidget);
      // The database has the old time until the pointer goes up.
      expect(store.blocks(DayRange.single(wednesday)).single.startMinute, 660);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('live-label')), findsNothing);
      expect(store.blocks(DayRange.single(wednesday)).single.startMinute, 720);
    });

    testWidgets('a drag to the side moves a block to the next day', (
      tester,
    ) async {
      final store = plannerStore();
      store.createFromDraft(
        title: 'Lunch',
        day: wednesday,
        start: 11 * 60,
        end: 12 * 60,
        asEvent: true,
      );
      await pumpPlanner(tester, store);

      final from = pointAt(tester, wednesday, 11 * 60 + 30);
      final to = pointAt(tester, wednesday.adding(days: 2), 11 * 60 + 30);
      await mouseDrag(tester, from, to - from);

      expect(store.blocks(DayRange.single(wednesday)), isEmpty);
      final block = store
          .blocks(DayRange.single(wednesday.adding(days: 2)))
          .single;
      expect(block.title, 'Lunch');
      expect(block.startMinute, 11 * 60);
      expect(block.endMinute, 12 * 60);
    });

    testWidgets('a finger moves a block with press, hold and drag', (
      tester,
    ) async {
      final store = plannerStore();
      store.createFromDraft(
        title: 'Lunch',
        day: wednesday,
        start: 11 * 60,
        end: 12 * 60,
        asEvent: true,
      );
      await pumpPlanner(tester, store);

      await touchDrag(
        tester,
        pointAt(tester, wednesday, 11 * 60 + 30),
        const Offset(0, hour / 2),
      );
      final block = store.blocks(DayRange.single(wednesday)).single;
      expect(block.startMinute, 11 * 60 + 30);
      expect(block.endMinute, 12 * 60 + 30);
    });

    testWidgets('the bottom edge changes the end', (tester) async {
      final store = plannerStore();
      store.createFromDraft(
        title: 'Lunch',
        day: wednesday,
        start: 11 * 60,
        end: 12 * 60,
        asEvent: true,
      );
      final id = blockNamed(store, 'Lunch').id;
      await pumpPlanner(tester, store);

      final handle = tester.getCenter(find.byKey(ValueKey('resizeBottom-$id')));
      await mouseDrag(tester, handle, const Offset(0, hour / 2));

      final block = store.blocks(DayRange.single(wednesday)).single;
      expect(block.startMinute, 11 * 60);
      expect(block.endMinute, 12 * 60 + 30);
      expect(store.undoName, 'Resize Block');
    });

    testWidgets('the top edge changes the start; 15 minutes is the least', (
      tester,
    ) async {
      final store = plannerStore();
      store.createFromDraft(
        title: 'Lunch',
        day: wednesday,
        start: 11 * 60,
        end: 12 * 60,
        asEvent: true,
      );
      final id = blockNamed(store, 'Lunch').id;
      await pumpPlanner(tester, store);

      // Two hours down: the start stops 15 minutes before the end.
      final handle = tester.getCenter(find.byKey(ValueKey('resizeTop-$id')));
      await mouseDrag(tester, handle, const Offset(0, hour * 2));

      final block = store.blocks(DayRange.single(wednesday)).single;
      expect(block.startMinute, 11 * 60 + 45);
      expect(block.endMinute, 12 * 60);
    });

    testWidgets('a finger changes the end at the bottom edge', (tester) async {
      final store = plannerStore();
      store.createFromDraft(
        title: 'Lunch',
        day: wednesday,
        start: 11 * 60,
        end: 12 * 60,
        asEvent: true,
      );
      final id = blockNamed(store, 'Lunch').id;
      await pumpPlanner(tester, store);

      final handle = tester.getCenter(find.byKey(ValueKey('resizeBottom-$id')));
      final gesture = await tester.startGesture(handle);
      await tester.pump();
      for (var i = 1; i <= 8; i++) {
        await gesture.moveTo(handle + Offset(0, hour * i / 8));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      final block = store.blocks(DayRange.single(wednesday)).single;
      expect(block.startMinute, 11 * 60);
      expect(block.endMinute, 13 * 60);
    });
  });

  group('overlap', () {
    testWidgets('two blocks at the same time are both in view', (tester) async {
      final store = plannerStore();
      store
        ..createFromDraft(
          title: 'First',
          day: wednesday,
          start: 11 * 60,
          end: 13 * 60,
          asEvent: true,
        )
        ..createFromDraft(
          title: 'Second',
          day: wednesday,
          start: 11 * 60 + 30,
          end: 12 * 60 + 30,
          asEvent: true,
        );
      await pumpPlanner(tester, store);

      final first = tester.getRect(blockFinder(blockNamed(store, 'First').id));
      final second = tester.getRect(
        blockFinder(blockNamed(store, 'Second').id),
      );
      final column = tester.getRect(columnFinder(wednesday));
      // The later block starts more to the right and stays in the column.
      expect(second.left, greaterThan(first.left));
      expect(second.right, lessThanOrEqualTo(column.right));
      expect(first.left, greaterThanOrEqualTo(column.left));
      // The title of the first block is not under the second block.
      expect(find.text('First'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('keys', () {
    Future<AppStore> withLunch(WidgetTester tester) async {
      final store = plannerStore();
      store.createFromDraft(
        title: 'Lunch',
        day: wednesday,
        start: 11 * 60,
        end: 12 * 60,
        asEvent: true,
      );
      await pumpPlanner(tester, store);
      await mouseTap(tester, pointAt(tester, wednesday, 11 * 60 + 30));
      await endTapWindow(tester);
      expect(store.selection, hasLength(1));
      return store;
    }

    PlannerBlock lunch(AppStore store) => blockNamed(store, 'Lunch');

    testWidgets('the arrows move the selected block', (tester) async {
      final store = await withLunch(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(lunch(store).startMinute, 11 * 60 + 15);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(lunch(store).startMinute, 10 * 60 + 45);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(lunch(store).day, wednesday.adding(days: 1));
    });

    testWidgets('Shift with an arrow changes the length', (tester) async {
      final store = await withLunch(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      expect(lunch(store).startMinute, 11 * 60);
      expect(lunch(store).endMinute, 12 * 60 + 15);
    });

    testWidgets('Delete removes the block; Escape clears the selection', (
      tester,
    ) async {
      final store = await withLunch(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(store.selection, isEmpty);

      await mouseTap(tester, pointAt(tester, wednesday, 11 * 60 + 30));
      await endTapWindow(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(store.blocks(DayRange.single(wednesday)), isEmpty);
    });

    testWidgets('N starts a new block in the next free time', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);
      // A click on empty time gives the keys to the grid.
      await mouseTap(tester, pointAt(tester, wednesday, 15 * 60));
      await endTapWindow(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();

      expect(gridState(tester).draft, isNotNull);
      expect(find.byType(InlineTitleField), findsOneWidget);
    });

    testWidgets('Enter renames a task block', (tester) async {
      final store = plannerStore();
      store.createFromDraft(
        title: 'Draft',
        day: wednesday,
        start: 11 * 60,
        end: 12 * 60,
        asEvent: false,
      );
      await pumpPlanner(tester, store);
      await mouseTap(tester, pointAt(tester, wednesday, 11 * 60 + 30));
      await endTapWindow(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), 'Final');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(blockNamed(store, 'Final').startMinute, 11 * 60);
    });
  });

  group('undo', () {
    testWidgets('Undo puts a moved block back; Redo moves it again', (
      tester,
    ) async {
      final store = plannerStore();
      store.createFromDraft(
        title: 'Lunch',
        day: wednesday,
        start: 11 * 60,
        end: 12 * 60,
        asEvent: true,
      );
      await pumpPlanner(tester, store);
      await mouseDrag(
        tester,
        pointAt(tester, wednesday, 11 * 60 + 30),
        const Offset(0, hour),
      );
      expect(blockNamed(store, 'Lunch').startMinute, 12 * 60);

      // The tests run as on Android: Ctrl is the command key.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(blockNamed(store, 'Lunch').startMinute, 11 * 60);
      expect(
        tester.getTopLeft(blockFinder(blockNamed(store, 'Lunch').id)).dy,
        closeTo(pointAt(tester, wednesday, 11 * 60).dy, 1.5),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(blockNamed(store, 'Lunch').startMinute, 12 * 60);
      await endToast(tester);
    });

    testWidgets('Undo removes a new block', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);
      await mouseDrag(
        tester,
        pointAt(tester, wednesday, 11 * 60),
        const Offset(0, hour),
      );
      await tester.enterText(find.byType(EditableText), 'Write report');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(store.blocks(DayRange.single(wednesday)), hasLength(1));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(store.blocks(DayRange.single(wednesday)), isEmpty);
      await endToast(tester);
    });
  });

  group('task blocks', () {
    testWidgets('the check box marks the task done', (tester) async {
      final store = plannerStore();
      store.createFromDraft(
        title: 'Write report',
        day: wednesday,
        start: 11 * 60,
        end: 12 * 60,
        asEvent: false,
      );
      final block = blockNamed(store, 'Write report');
      await pumpPlanner(tester, store);

      await tester.tap(find.byKey(ValueKey('check-${block.id}')));
      await tester.pumpAndSettle();
      expect(store.task(block.taskId!)!.isDone, isTrue);
      // The time of the block did not change.
      expect(blockNamed(store, 'Write report').startMinute, 11 * 60);
    });

    testWidgets('a tall block shows subtasks, then "+N more"', (tester) async {
      final store = plannerStore();
      store.createFromDraft(
        title: 'Pack',
        day: wednesday,
        start: 11 * 60,
        end: 12 * 60 + 30,
        asEvent: false,
      );
      final taskId = blockNamed(store, 'Pack').taskId!;
      for (final name in ['Socks', 'Shirts', 'Shoes', 'Soap', 'Maps', 'Keys']) {
        store.addSubtask(to: taskId, title: name);
      }
      await pumpPlanner(tester, store);

      expect(find.text('Socks'), findsOneWidget);
      expect(find.textContaining('more'), findsOneWidget);
      expect(find.text('Keys'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a short block shows a count of the subtasks', (tester) async {
      final store = plannerStore();
      store.createFromDraft(
        title: 'Pack',
        day: wednesday,
        start: 11 * 60,
        end: 11 * 60 + 30,
        asEvent: false,
      );
      final taskId = blockNamed(store, 'Pack').taskId!;
      store
        ..addSubtask(to: taskId, title: 'Socks')
        ..addSubtask(to: taskId, title: 'Shirts');
      await pumpPlanner(tester, store);

      expect(find.text('Socks'), findsNothing);
      expect(find.text('0/2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('tasks with no time', () {
    testWidgets('the strip shows the task of the day as a sticky note', (
      tester,
    ) async {
      final store = plannerStore();
      final task = store.quickAdd(
        'Call the bank',
        placement: TaskPlacement.day(wednesday),
      )!;
      await pumpPlanner(tester, store);

      expect(find.byKey(ValueKey('sticky-${task.id}')), findsOneWidget);
      expect(find.text('Call the bank'), findsOneWidget);

      // The fold button hides the notes and keeps the count.
      await tester.tap(find.byKey(const ValueKey('sticky-fold')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('sticky-${task.id}')), findsNothing);
      expect(find.text('1 with no time'), findsOneWidget);
      expect(store.prefs.getBool(StickyStrip.openKey), isFalse);
    });

    testWidgets('long titles do not make the planner wider', (tester) async {
      final store = plannerStore();
      for (var i = 0; i < 5; i++) {
        store.quickAdd(
          'A very long title that does not end and does not end $i ' * 3,
          placement: TaskPlacement.day(wednesday),
        );
      }
      await pumpPlanner(tester, store);

      final grid = tester.getRect(find.byType(PlannerGrid));
      final strip = tester.getRect(find.byType(StickyStrip));
      expect(strip.width, grid.width);
      expect(strip.right, lessThanOrEqualTo(desktopSize.width));
      expect(strip.height, lessThanOrEqualTo(150));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the fit button gives the task the next free time', (
      tester,
    ) async {
      final store = plannerStore();
      final task = store.quickAdd(
        'Call the bank',
        placement: TaskPlacement.day(wednesday),
      )!;
      await pumpPlanner(tester, store);

      await tester.tap(find.byKey(ValueKey('fit-${task.id}')));
      await tester.pumpAndSettle();

      final block = store.blocks(DayRange.single(wednesday)).single;
      expect(block.taskId, task.id);
      expect(find.byKey(ValueKey('sticky-${task.id}')), findsNothing);
    });

    testWidgets('a note dragged onto the grid gets that time', (tester) async {
      final store = plannerStore();
      final task = store.quickAdd(
        'Call the bank',
        placement: TaskPlacement.day(wednesday),
      )!;
      await pumpPlanner(tester, store);

      final from = tester.getCenter(find.byKey(ValueKey('sticky-${task.id}')));
      final to = pointAt(tester, wednesday.adding(days: 1), 14 * 60);
      await mouseDrag(tester, from, to - from);

      final block = store
          .blocks(DayRange.single(wednesday.adding(days: 1)))
          .single;
      expect(block.taskId, task.id);
      expect(block.startMinute, 14 * 60);
    });

    testWidgets('a task block dragged up to the strip loses its time', (
      tester,
    ) async {
      final store = plannerStore();
      store.createFromDraft(
        title: 'Write report',
        day: wednesday,
        start: 9 * 60 + 30,
        end: 10 * 60 + 30,
        asEvent: false,
      );
      final taskId = blockNamed(store, 'Write report').taskId!;
      await pumpPlanner(tester, store);

      final from = tester.getCenter(
        blockFinder(blockNamed(store, 'Write report').id),
      );
      final strip = tester.getRect(find.byType(StickyStrip));
      final to = Offset(from.dx, strip.center.dy);

      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
      await tester.pump();
      await gesture.moveTo(to);
      await tester.pump();
      expect(find.text('Release to unschedule'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(store.blocks(DayRange.single(wednesday)), isEmpty);
      expect(store.task(taskId), isNotNull);
      expect(store.undoName, 'Unschedule');
      expect(find.text('Release to unschedule'), findsNothing);
    });
  });

  group('plan my day', () {
    testWidgets('the list shows the plan; Apply makes the blocks', (
      tester,
    ) async {
      final store = plannerStore();
      store
        ..quickAdd('Call the bank', placement: TaskPlacement.day(wednesday))
        ..quickAdd('Buy bread', placement: TaskPlacement.day(wednesday));
      await pumpPlanner(tester, store);

      await tester.tap(find.byKey(const ValueKey('plan-my-day')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Grove will place these tasks'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('plan-apply')));
      await tester.pumpAndSettle();
      expect(store.blocks(DayRange.single(wednesday)), hasLength(2));
      expect(store.undoName, 'Plan My Day');
    });

    testWidgets('with nothing to plan, a short message shows', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);

      await tester.tap(find.byKey(const ValueKey('plan-my-day')));
      await tester.pump();
      expect(store.toast, contains('Nothing to plan'));
      await endToast(tester);
    });
  });
}
