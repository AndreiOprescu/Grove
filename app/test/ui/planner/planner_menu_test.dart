// The menu of a block and the clicks on a block, through the screen
// (PLAN §5.1.4: "Right-click", "Click a block", "Double-click empty space").
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/calendar/event_editor.dart';
import 'package:grove/ui/planner/inline_title_field.dart';
import 'package:grove/ui/tasks/task_inspector.dart';

import 'planner_support.dart';

/// A line of the open menu.
Finder menuLine(String label) =>
    find.widgetWithText(PopupMenuItem<VoidCallback>, label);

/// Clicks a line of the open menu.
Future<void> pick(WidgetTester tester, String label) async {
  await tester.tap(menuLine(label));
  await tester.pumpAndSettle();
}

/// A block from 11:00 on Wednesday. Gives the block.
PlannerBlock addBlock(
  AppStore store,
  String title, {
  bool asEvent = false,
  int start = 11 * 60,
  int length = 60,
}) {
  store.createFromDraft(
    title: title,
    day: wednesday,
    start: start,
    end: start + length,
    asEvent: asEvent,
  );
  return blockNamed(store, title);
}

List<PlannerBlock> blocksOfWednesday(AppStore store) =>
    store.blocks(DayRange.single(wednesday));

void main() {
  group('the menu of a block', () {
    /// The planner with one block from 11:00 to 12:00, and its menu open.
    Future<(AppStore, PlannerBlock)> withMenu(
      WidgetTester tester, {
      bool asEvent = false,
      int length = 60,
    }) async {
      final store = plannerStore();
      final block = addBlock(store, 'Lunch', asEvent: asEvent, length: length);
      await pumpPlanner(tester, store);
      await rightClick(
        tester,
        pointAt(tester, wednesday, 11 * 60 + length ~/ 2),
      );
      return (store, block);
    }

    testWidgets('a right click on a task block shows its lines', (
      tester,
    ) async {
      await withMenu(tester);

      for (final line in [
        'Duration',
        'Colour',
        'Duplicate',
        'Split in Two',
        'Mark Done',
        'Start Focus',
        'Unschedule',
        'Delete Task',
      ]) {
        expect(menuLine(line), findsOneWidget, reason: line);
      }
      expect(menuLine('Edit Event…'), findsNothing);
      expect(menuLine('Delete Event'), findsNothing);
      expect(menuLine('Delete Goal Block'), findsNothing);
    });

    testWidgets('a right click on an event shows its lines', (tester) async {
      await withMenu(tester, asEvent: true);

      for (final line in [
        'Edit Event…',
        'Duration',
        'Colour',
        'Duplicate',
        'Split in Two',
        'Delete Event',
      ]) {
        expect(menuLine(line), findsOneWidget, reason: line);
      }
      for (final line in [
        'Mark Done',
        'Start Focus',
        'Unschedule',
        'Delete Task',
      ]) {
        expect(menuLine(line), findsNothing, reason: line);
      }
    });

    testWidgets('a click away closes the menu and changes nothing', (
      tester,
    ) async {
      final (store, block) = await withMenu(tester);

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(menuLine('Duration'), findsNothing);
      expect(blocksOfWednesday(store).single, block);
      expect(store.undoName, isNot('Change Duration'));
    });

    testWidgets('"Duration" gives the block a new length', (tester) async {
      final (store, block) = await withMenu(tester);
      final before = tester.getSize(blockFinder(block.id)).height;

      await pick(tester, 'Duration');
      // The lengths of PLAN §5.1.4, and four hours as on the Mac.
      for (final line in ['15m', '30m', '45m', '1h', '1h 30m', '2h', '3h']) {
        expect(menuLine(line), findsOneWidget, reason: line);
      }
      await pick(tester, '1h 30m');

      final after = blockNamed(store, 'Lunch');
      expect(after.startMinute, 11 * 60);
      expect(after.endMinute, 12 * 60 + 30);
      expect(store.undoName, 'Change Duration');
      expect(
        tester.getSize(blockFinder(block.id)).height,
        before + hour / 2,
        reason: 'the block on the screen is 30 minutes taller',
      );
    });

    testWidgets('"Colour" gives the block a colour of the theme', (
      tester,
    ) async {
      final (store, block) = await withMenu(tester, asEvent: true);
      expect(block.color, isNot('accent3'));

      await pick(tester, 'Colour');
      for (final line in ['Accent', 'Accent2', 'Accent3', 'Muted']) {
        expect(menuLine(line), findsOneWidget, reason: line);
      }
      await pick(tester, 'Accent3');

      expect(blockNamed(store, 'Lunch').color, 'accent3');
      expect(store.undoName, 'Change Colour');
    });

    testWidgets('"Duplicate" puts a copy right after the block', (
      tester,
    ) async {
      final (store, block) = await withMenu(tester, asEvent: true);

      await pick(tester, 'Duplicate');

      final blocks = blocksOfWednesday(store);
      expect(blocks, hasLength(2));
      final copy = blocks.firstWhere((b) => b.id != block.id);
      expect(copy.title, 'Lunch');
      expect(copy.startMinute, 12 * 60);
      expect(copy.endMinute, 13 * 60);
      expect(store.selection, {copy.id}, reason: 'the copy is selected');
      expect(blockFinder(copy.id), findsOneWidget);
      expect(blockFinder(block.id), findsOneWidget);
    });

    testWidgets('"Split in Two" cuts the block in the middle', (tester) async {
      final (store, block) = await withMenu(tester, asEvent: true);

      await pick(tester, 'Split in Two');

      final blocks = blocksOfWednesday(store)
        ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
      expect(blocks, hasLength(2));
      expect(blocks.first.id, block.id);
      expect((blocks[0].startMinute, blocks[0].endMinute), (660, 690));
      expect((blocks[1].startMinute, blocks[1].endMinute), (690, 720));
      expect(blocks[1].title, 'Lunch');
      expect(find.text('Lunch'), findsNWidgets(2));
    });

    testWidgets('"Split in Two" on a block of 15 minutes says why not', (
      tester,
    ) async {
      final (store, block) = await withMenu(tester, asEvent: true, length: 15);

      await pick(tester, 'Split in Two');

      expect(blocksOfWednesday(store).single, block);
      expect(find.text('Block is too short to split.'), findsOneWidget);
      await endToast(tester);
      expect(find.text('Block is too short to split.'), findsNothing);
    });

    testWidgets('"Mark Done" checks the task off; "Mark Not Done" opens it '
        'again', (tester) async {
      final (store, block) = await withMenu(tester);

      await pick(tester, 'Mark Done');
      expect(blockNamed(store, 'Lunch').isDone, isTrue);
      expect(store.task(block.taskId!)!.status, TaskStatus.done);

      await rightClick(tester, pointAt(tester, wednesday, 11 * 60 + 30));
      expect(menuLine('Mark Done'), findsNothing);
      // A done task has nothing to focus on.
      expect(menuLine('Start Focus'), findsNothing);
      await pick(tester, 'Mark Not Done');
      expect(blockNamed(store, 'Lunch').isDone, isFalse);
      expect(store.task(block.taskId!)!.status, TaskStatus.open);
    });

    testWidgets('"Unschedule" takes the time away; the task stays as a '
        'sticky note', (tester) async {
      final (store, block) = await withMenu(tester);

      await pick(tester, 'Unschedule');

      expect(blocksOfWednesday(store), isEmpty);
      expect(blockFinder(block.id), findsNothing);
      final task = store.task(block.taskId!)!;
      expect(task.status, TaskStatus.open);
      expect(find.byKey(ValueKey('sticky-${task.id}')), findsOneWidget);
      expect(store.undoName, 'Unschedule');
    });

    testWidgets('"Delete Task" removes the block and the task', (tester) async {
      final (store, block) = await withMenu(tester);

      await pick(tester, 'Delete Task');

      expect(blocksOfWednesday(store), isEmpty);
      expect(store.task(block.taskId!), isNull);
      expect(find.text('Lunch'), findsNothing);

      store.undo();
      await tester.pumpAndSettle();
      expect(blockNamed(store, 'Lunch').taskId, block.taskId);
      expect(find.text('Lunch'), findsOneWidget);
      await endToast(tester);
    });

    testWidgets('"Edit Event…" opens the card of the event', (tester) async {
      final (store, block) = await withMenu(tester, asEvent: true);
      expect(find.byType(EventEditor), findsNothing);

      await pick(tester, 'Edit Event…');

      expect(store.editingEvent?.item.id, block.id);
      expect(find.byType(EventEditor), findsOneWidget);
    });

    testWidgets('"Delete Event" removes the event', (tester) async {
      final (store, block) = await withMenu(tester, asEvent: true);

      await pick(tester, 'Delete Event');

      expect(blocksOfWednesday(store), isEmpty);
      expect(blockFinder(block.id), findsNothing);
      expect(store.undoName, 'Delete Event');
    });

    testWidgets('a goal block has its own lines', (tester) async {
      final store = plannerStore();
      final id = goalBlock(store);
      await pumpPlanner(tester, store);
      final at = pointAt(tester, wednesday, 11 * 60 + 30);

      await rightClick(tester, at);
      expect(menuLine('Goal block · 1h 30m'), findsOneWidget);
      expect(
        tester
            .widget<PopupMenuItem<VoidCallback>>(
              menuLine('Goal block · 1h 30m'),
            )
            .enabled,
        isFalse,
      );
      expect(menuLine('Unschedule'), findsNothing);
      expect(menuLine('Delete Event'), findsNothing);
      await pick(tester, 'Mark Done');
      expect(store.blocks(DayRange.single(wednesday)).single.isDone, isTrue);

      await rightClick(tester, at);
      await pick(tester, 'Mark Not Done');
      expect(store.blocks(DayRange.single(wednesday)).single.isDone, isFalse);

      await rightClick(tester, at);
      await pick(tester, 'Delete Goal Block');
      expect(blocksOfWednesday(store), isEmpty);
      expect(blockFinder(id), findsNothing);
      expect(store.undoName, 'Delete Goal Block');
    });

    testWidgets('the menu of a selected block works on all selected blocks', (
      tester,
    ) async {
      final store = plannerStore();
      final a = addBlock(store, 'Alpha', asEvent: true, start: 10 * 60);
      final b = addBlock(store, 'Beta', asEvent: true, start: 12 * 60);
      final c = addBlock(store, 'Gamma', asEvent: true, start: 14 * 60);
      await pumpPlanner(tester, store);
      store.selection = {a.id, b.id};
      await tester.pumpAndSettle();

      await rightClick(tester, pointAt(tester, wednesday, 10 * 60 + 30));
      await pick(tester, 'Duration');
      await pick(tester, '30m');

      expect(blockNamed(store, 'Alpha').length, 30);
      expect(blockNamed(store, 'Beta').length, 30);
      expect(blockNamed(store, 'Gamma').length, 60);

      // One undo step for the two blocks.
      store.undo();
      await tester.pumpAndSettle();
      expect(blockNamed(store, 'Alpha').length, 60);
      expect(blockNamed(store, 'Beta').length, 60);
      await endToast(tester);

      // A block that is not selected: the menu is for this block alone.
      await rightClick(tester, pointAt(tester, wednesday, 14 * 60 + 30));
      await pick(tester, 'Delete Event');
      expect(
        {for (final block in blocksOfWednesday(store)) block.id},
        {a.id, b.id},
      );
      expect(blockFinder(c.id), findsNothing);
    });

    testWidgets('a long press with a finger opens the menu', (tester) async {
      final store = plannerStore();
      final block = addBlock(store, 'Lunch', asEvent: true);
      await pumpPlanner(tester, store, size: phoneSize);

      await tester.longPressAt(pointAt(tester, wednesday, 11 * 60 + 30));
      await tester.pumpAndSettle();

      expect(menuLine('Duration'), findsOneWidget);
      await pick(tester, 'Duplicate');
      expect(blocksOfWednesday(store), hasLength(2));
      expect(blockNamed(store, 'Lunch').id, isNotNull);
      expect(blockFinder(block.id), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('clicks', () {
    testWidgets('a click on a task block selects it and shows the task at '
        'the side', (tester) async {
      final store = plannerStore();
      final block = addBlock(store, 'Write report');
      await pumpPlanner(tester, store);
      expect(find.byType(TaskInspector), findsNothing);

      await mouseTap(tester, pointAt(tester, wednesday, 11 * 60 + 30));
      await endTapWindow(tester);
      await tester.pumpAndSettle();

      expect(store.selection, {block.id});
      expect(store.selectedTaskId, block.taskId);
      expect(find.byType(TaskInspector), findsOneWidget);
      // The block is still on the screen, next to the panel.
      expect(blockFinder(block.id), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a click on an event selects it and opens its card', (
      tester,
    ) async {
      final store = plannerStore();
      final block = addBlock(store, 'Lunch', asEvent: true);
      await pumpPlanner(tester, store);

      await mouseTap(tester, pointAt(tester, wednesday, 11 * 60 + 30));
      await endTapWindow(tester);
      await tester.pumpAndSettle();

      expect(store.selection, {block.id});
      expect(store.selectedTaskId, isNull);
      expect(store.editingEvent?.item.id, block.id);
      expect(find.byType(EventEditor), findsOneWidget);
      expect(find.byType(TaskInspector), findsNothing);
    });

    testWidgets('a double click on a task block opens its title', (
      tester,
    ) async {
      final store = plannerStore();
      final block = addBlock(store, 'Draft');
      await pumpPlanner(tester, store);

      await mouseTap(tester, pointAt(tester, wednesday, 11 * 60 + 30));
      // The panel of the task opens at the first click, so the block moves.
      await mouseTap(tester, tester.getCenter(blockFinder(block.id)));
      await tester.pumpAndSettle();

      final field = find.descendant(
        of: find.byType(InlineTitleField),
        matching: find.byType(EditableText),
      );
      expect(field, findsOneWidget);
      expect(tester.widget<EditableText>(field).controller.text, 'Draft');

      await tester.enterText(field, 'Final');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(blockNamed(store, 'Final').id, block.id);
      expect(find.byType(InlineTitleField), findsNothing);
    });

    testWidgets('a double click on a goal block opens its title', (
      tester,
    ) async {
      final store = plannerStore();
      final id = goalBlock(store);
      await pumpPlanner(tester, store);

      await mouseTap(tester, pointAt(tester, wednesday, 11 * 60 + 30));
      // The goal panel opens at the first click, so the block moves.
      await mouseTap(tester, tester.getCenter(blockFinder(id)));
      await tester.pumpAndSettle();

      expect(store.selection, {id});
      expect(store.selectedGoalBlockId, id);
      expect(find.byType(InlineTitleField), findsOneWidget);
    });

    testWidgets('a double click on an event opens its card, not a title', (
      tester,
    ) async {
      final store = plannerStore();
      final block = addBlock(store, 'Lunch', asEvent: true);
      await pumpPlanner(tester, store);
      final at = pointAt(tester, wednesday, 11 * 60 + 30);

      await mouseTap(tester, at);
      await mouseTap(tester, at);
      await tester.pumpAndSettle();

      expect(find.byType(InlineTitleField), findsNothing);
      expect(store.editingEvent?.item.id, block.id);
      expect(find.byType(EventEditor), findsOneWidget);
    });

    testWidgets('two slow clicks on a task block open no title', (
      tester,
    ) async {
      final store = plannerStore();
      final block = addBlock(store, 'Draft');
      await pumpPlanner(tester, store);

      await mouseTap(tester, pointAt(tester, wednesday, 11 * 60 + 30));
      await endTapWindow(tester);
      await mouseTap(tester, tester.getCenter(blockFinder(block.id)));
      await endTapWindow(tester);
      await tester.pumpAndSettle();

      expect(find.byType(InlineTitleField), findsNothing);
      expect(store.selection, {block.id});
    });

    testWidgets('a double click on empty time starts a block of 30 minutes', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);
      // 13:08 snaps to 13:15.
      final at = pointAt(tester, wednesday, 13 * 60 + 8);

      await mouseTap(tester, at);
      expect(gridState(tester).draft, isNull, reason: 'one click is not two');
      await mouseTap(tester, at);
      await tester.pumpAndSettle();

      final draft = gridState(tester).draft!;
      expect(draft.day, wednesday);
      expect(draft.start, 13 * 60 + 15);
      expect(draft.end, 13 * 60 + 45);
      expect(find.byKey(const ValueKey('planner-draft')), findsOneWidget);
      expect(find.text('13:15 – 13:45 · 30m'), findsOneWidget);

      await tester.enterText(find.byType(EditableText), 'Tea');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final block = blockNamed(store, 'Tea');
      expect((block.startMinute, block.endMinute), (795, 825));
      expect(block.isTaskBlock, isTrue);
    });

    testWidgets('two slow clicks on empty time start nothing', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);
      final at = pointAt(tester, wednesday, 13 * 60);

      await mouseTap(tester, at);
      await endTapWindow(tester);
      await mouseTap(tester, at);
      await endTapWindow(tester);

      expect(gridState(tester).draft, isNull);
      expect(find.byKey(const ValueKey('planner-draft')), findsNothing);
    });

    testWidgets('a double tap with a finger on empty time starts a block', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpPlanner(tester, store, size: phoneSize);
      final at = pointAt(tester, wednesday, 11 * 60);

      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(at);
      await tester.pumpAndSettle();

      final draft = gridState(tester).draft!;
      expect((draft.start, draft.end), (660, 690));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a click on empty time clears the selection', (tester) async {
      final store = plannerStore();
      final block = addBlock(store, 'Lunch', asEvent: true);
      await pumpPlanner(tester, store);
      store.selection = {block.id};
      await tester.pumpAndSettle();

      await mouseTap(tester, pointAt(tester, wednesday, 14 * 60));
      await endTapWindow(tester);

      expect(store.selection, isEmpty);
    });
  });
}
