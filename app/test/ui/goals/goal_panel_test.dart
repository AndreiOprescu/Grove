// The goal panel on the screen: one tap on a goal block opens it at the
// right, as the task panel opens for a task block (CONTEXT.md, "Goal
// panel"; ADR 0002).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/goal_subtask.dart';
import 'package:grove/ui/goals/goal_panel.dart';
import 'package:grove/ui/notes/note_editor_pane.dart';
import 'package:grove/ui/planner/block_subtask_editor.dart';
import 'package:grove/ui/planner/planner_grid.dart';
import 'package:grove/ui/tasks/task_inspector.dart';

import '../planner/planner_support.dart';
import '../tasks/tasks_support.dart' show typeLine;

final panel = find.byType(GoalPanel);
Finder key(String name) => find.byKey(ValueKey(name));

/// The goal "Read" of the block.
GoalItem readGoal(AppStore store) =>
    store.goals().firstWhere((g) => g.title == 'Read');

/// The subtask of "Read" with this title, as the database has it now.
GoalSubtaskItem sub(AppStore store, String title) =>
    store.goalSubtasks(readGoal(store).id).firstWhere((s) => s.title == title);

/// A tap on the goal block, then the time for a double tap ends.
Future<void> tapBlock(WidgetTester tester, String id) async {
  await tester.tap(blockFinder(id));
  await endTapWindow(tester);
  await tester.pumpAndSettle();
}

void main() {
  group('the goal panel opens and closes', () {
    testWidgets('a tap on a goal block opens the goal panel at the right. It '
        'shows the goal, the time and the week', (tester) async {
      final store = plannerStore();
      final id = goalBlock(store);
      await pumpPlanner(tester, store);
      expect(panel, findsNothing);

      await tapBlock(tester, id);

      expect(store.selectedGoalBlockId, id);
      expect(store.selection, {id});
      expect(panel, findsOneWidget);
      expect(find.byType(TaskInspector), findsNothing);
      expect(tester.getSize(panel).width, TaskInspector.width);
      expect(
        tester.getRect(panel).right,
        greaterThan(tester.getRect(find.byType(PlannerGrid)).right),
      );
      final title = tester.widget<Text>(key('goal-panel-title'));
      expect(title.data, 'Read');
      final time = tester.widget<Text>(key('goal-panel-time'));
      expect(
        time.data,
        '${PlannerMath.label(start: 660, end: 750)} · '
        '${PlannerMath.duration(90)}',
      );
      expect(key('goal-panel-progress'), findsOneWidget);
      expect(find.textContaining('Nothing planned here yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the close button and Escape close the panel', (tester) async {
      final store = plannerStore();
      final id = goalBlock(store);
      await pumpPlanner(tester, store);

      await tapBlock(tester, id);
      await tester.tap(key('goal-panel-close'));
      await tester.pumpAndSettle();
      expect(store.selectedGoalBlockId, isNull);
      expect(panel, findsNothing);

      await tapBlock(tester, id);
      expect(panel, findsOneWidget);
      // As with the task panel: the first Escape clears the selection of
      // the planner, the next one closes the panel.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(store.selection, isEmpty);
      expect(panel, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(store.selectedGoalBlockId, isNull);
      expect(panel, findsNothing);
    });

    testWidgets('a tap on a task block shows the task panel in its place', (
      tester,
    ) async {
      final store = plannerStore();
      final id = goalBlock(store);
      store.createFromDraft(
        title: 'Pay the bill',
        day: wednesday,
        start: 14 * 60,
        end: 15 * 60,
        asEvent: false,
      );
      final task = blockNamed(store, 'Pay the bill');
      await pumpPlanner(tester, store);

      await tapBlock(tester, id);
      expect(panel, findsOneWidget);
      await tapBlock(tester, task.id);

      expect(store.selectedGoalBlockId, isNull);
      expect(store.selectedTaskId, task.taskId);
      expect(panel, findsNothing);
      expect(find.byType(TaskInspector), findsOneWidget);
    });

    testWidgets('a tap on another goal block shows that block', (tester) async {
      final store = plannerStore();
      final first = goalBlock(store);
      final second = goalBlock(store, start: 14 * 60, length: 60);
      await pumpPlanner(tester, store);

      await tapBlock(tester, first);
      await tapBlock(tester, second);

      expect(store.selectedGoalBlockId, second);
      expect(panel, findsOneWidget);
      expect(
        tester.widget<Text>(key('goal-panel-time')).data,
        startsWith(PlannerMath.label(start: 840, end: 900)),
      );
    });

    testWidgets('"Subtasks…" in the menu of a goal block opens the panel, '
        'not the old window', (tester) async {
      final store = plannerStore();
      final id = goalBlock(store);
      await pumpPlanner(tester, store);

      await rightClick(tester, pointAt(tester, wednesday, 11 * 60 + 30));
      await tester.tap(find.text('Add Subtasks…'));
      await tester.pumpAndSettle();

      expect(store.selectedGoalBlockId, id);
      expect(panel, findsOneWidget);
      expect(find.byType(BlockSubtaskEditor), findsNothing);
    });

    testWidgets('on a phone the panel takes the place of the planner', (
      tester,
    ) async {
      final store = plannerStore();
      final id = goalBlock(store);
      await pumpPlanner(tester, store, size: phoneSize);

      store.openGoalPanel(id);
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);
      expect(find.byType(PlannerGrid).hitTestable(), findsNothing);
      expect(tester.getRect(panel).width, phoneSize.width - 24);
      expect(tester.takeException(), isNull);

      await tester.tap(key('goal-panel-close'));
      await tester.pumpAndSettle();
      expect(find.byType(PlannerGrid).hitTestable(), findsOneWidget);
    });

    testWidgets('on Today the panel takes the place of the note', (
      tester,
    ) async {
      final store = plannerStore()..screen = Screen.today;
      final id = goalBlock(store);
      await pumpPlanner(tester, store, size: const Size(1280, 720));
      await tester.tap(key('spread-start-note'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditorPane), findsOneWidget);
      final note = tester.getRect(key('spread-note'));

      await tapBlock(tester, id);

      expect(store.selectedGoalBlockId, id);
      expect(panel, findsOneWidget);
      expect(find.byType(NoteEditorPane), findsNothing);
      expect(tester.getRect(panel), note);
      expect(tester.takeException(), isNull);
    });
  });

  group('the subtasks in the panel', () {
    late AppStore store;
    late String blockId;

    Future<void> withPanel(
      WidgetTester tester, {
      List<String> planned = const [],
      List<String> free = const [],
    }) async {
      store = plannerStore();
      blockId = goalBlock(store);
      final goalId = readGoal(store).id;
      for (final t in planned) {
        store.addGoalSubtaskToBlock(blockId, title: t);
      }
      for (final t in free) {
        store.addGoalSubtask(to: goalId, title: t);
      }
      store.openGoalPanel(blockId);
      await pumpPlanner(tester, store);
    }

    testWidgets('"In this block" shows the planned ones, "Add from goal" the '
        'open ones that are in no block', (tester) async {
      await withPanel(tester, planned: ['Chapter 1'], free: ['Chapter 2']);
      store.addGoalSubtask(to: readGoal(store).id, title: 'Chapter 3');
      store.toggleGoalSubtask(sub(store, 'Chapter 3').id);
      await tester.pumpAndSettle();

      expect(
        key('goal-panel-sub-${sub(store, 'Chapter 1').id}'),
        findsOneWidget,
      );
      expect(
        key('goal-panel-free-${sub(store, 'Chapter 2').id}'),
        findsOneWidget,
      );
      // A done subtask is not offered.
      expect(
        key('goal-panel-free-${sub(store, 'Chapter 3').id}'),
        findsNothing,
      );
      expect(find.text('Add from goal'), findsOneWidget);
    });

    testWidgets('a tick marks the subtask done. It stays in the block', (
      tester,
    ) async {
      await withPanel(tester, planned: ['Chapter 1']);
      final id = sub(store, 'Chapter 1').id;

      await tester.tap(key('goal-panel-sub-check-$id'));
      await tester.pumpAndSettle();

      expect(sub(store, 'Chapter 1').isDone, isTrue);
      expect(sub(store, 'Chapter 1').eventId, blockId);
      expect(key('goal-panel-sub-$id'), findsOneWidget);
      // No tick on the block itself: the user marks it done.
      expect(store.event(blockId)!.doneAt, isNull);
    });

    testWidgets('"Remove from the planner" takes the subtask out of the '
        'block. It stays open in the goal, and one Undo puts it back', (
      tester,
    ) async {
      await withPanel(tester, planned: ['Chapter 1']);
      final id = sub(store, 'Chapter 1').id;

      await tester.tap(key('goal-panel-sub-unplan-$id'));
      await tester.pumpAndSettle();

      expect(sub(store, 'Chapter 1').eventId, isNull);
      expect(sub(store, 'Chapter 1').isDone, isFalse);
      expect(key('goal-panel-sub-$id'), findsNothing);
      expect(key('goal-panel-free-$id'), findsOneWidget);
      // The empty block stays.
      expect(store.event(blockId), isNotNull);

      store.undo();
      await tester.pumpAndSettle();
      expect(sub(store, 'Chapter 1').eventId, blockId);
      await endToast(tester);
    });

    testWidgets('a "+" in "Add from goal" plans the subtask in the block', (
      tester,
    ) async {
      await withPanel(tester, free: ['Chapter 2']);
      final id = sub(store, 'Chapter 2').id;

      await tester.tap(key('goal-panel-free-$id'));
      await tester.pumpAndSettle();

      expect(sub(store, 'Chapter 2').eventId, blockId);
      expect(key('goal-panel-sub-$id'), findsOneWidget);
      expect(key('goal-panel-free-$id'), findsNothing);
      expect(find.text('Add from goal'), findsNothing);
    });

    testWidgets('the add field makes a subtask of the goal, planned in the '
        'block, and keeps the keys for the next one', (tester) async {
      await withPanel(tester);

      await typeLine(tester, key('goal-panel-add'), 'Chapter 4');

      final made = sub(store, 'Chapter 4');
      expect(made.eventId, blockId);
      expect(key('goal-panel-sub-${made.id}'), findsOneWidget);
      expect(store.undoName, 'New Subtask');
      final field = find.descendant(
        of: key('goal-panel-add'),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(field).controller.text, isEmpty);
      expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
    });

    testWidgets('a day of a repeating goal block becomes its own block when '
        'it takes a subtask. The panel goes with it', (tester) async {
      store = plannerStore();
      store.addGoal(title: 'Read', target: 300);
      final goal = readGoal(store);
      store.repos.events.save(
        EventItem(
          title: 'Read',
          start: WallTime(day: wednesday, minute: 11 * 60),
          end: WallTime(day: wednesday, minute: 12 * 60),
          kind: EventKind.block,
          goalId: goal.id,
          recurrence: RecurrenceRule(freq: Freq.weekly),
        ),
      );
      store.addGoalSubtask(to: goal.id, title: 'Chapter 1');
      final day = blockNamed(store, 'Read').id;
      expect(OccurrenceId.parse(day), isNotNull);
      store.openGoalPanel(day);
      await pumpPlanner(tester, store);
      // A day of a series cannot be marked done here.
      expect(key('goal-panel-done'), findsNothing);

      await tester.tap(key('goal-panel-free-${sub(store, 'Chapter 1').id}'));
      await tester.pumpAndSettle();

      final own = sub(store, 'Chapter 1').eventId!;
      expect(OccurrenceId.parse(own), isNull);
      expect(store.selectedGoalBlockId, own);
      expect(panel, findsOneWidget);
      expect(
        key('goal-panel-sub-${sub(store, 'Chapter 1').id}'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the buttons of the panel', () {
    testWidgets('"Edit goal" closes the panel and opens the editor of the '
        'goal in the Goals panel', (tester) async {
      final store = plannerStore();
      final id = goalBlock(store);
      final goal = readGoal(store);
      store.openGoalPanel(id);
      await pumpPlanner(tester, store);
      expect(key('goal-editor-${goal.id}'), findsNothing);

      await tester.tap(key('goal-panel-edit'));
      await tester.pumpAndSettle();

      expect(panel, findsNothing);
      expect(store.leftPane, LeftPane.goals);
      expect(key('goal-editor-${goal.id}'), findsOneWidget);
      expect(store.goalToEdit, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('"Mark done" ticks the block; the button then says "Mark not '
        'done"', (tester) async {
      final store = plannerStore();
      final id = goalBlock(store);
      store.openGoalPanel(id);
      await pumpPlanner(tester, store);

      await tester.tap(key('goal-panel-done'));
      await tester.pumpAndSettle();
      expect(store.event(id)!.doneAt, isNotNull);
      expect(find.text('Mark not done'), findsOneWidget);

      await tester.tap(key('goal-panel-done'));
      await tester.pumpAndSettle();
      expect(store.event(id)!.doneAt, isNull);
    });

    testWidgets('"Delete goal block" deletes the block and closes the panel. '
        'The subtasks go back to the goal', (tester) async {
      final store = plannerStore();
      final id = goalBlock(store);
      store.addGoalSubtaskToBlock(id, title: 'Chapter 1');
      store.openGoalPanel(id);
      await pumpPlanner(tester, store);

      await tester.tap(key('goal-panel-delete'));
      await tester.pumpAndSettle();

      expect(store.event(id), isNull);
      expect(store.selectedGoalBlockId, isNull);
      expect(panel, findsNothing);
      expect(blockFinder(id), findsNothing);
      expect(sub(store, 'Chapter 1').eventId, isNull);
      expect(store.undoName, 'Delete Goal Block');
      await endToast(tester);
    });

    testWidgets('the linked note row makes a note of the block', (
      tester,
    ) async {
      final store = plannerStore();
      final id = goalBlock(store);
      store.openGoalPanel(id);
      await pumpPlanner(tester, store);
      expect(find.text('Create linked note'), findsOneWidget);

      await tester.tap(key('goal-panel-note'));
      await tester.pumpAndSettle();

      expect(store.withMeetingNote([store.event(id)!]), isNotEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a panel whose block is gone says so', (tester) async {
      final store = plannerStore();
      final id = goalBlock(store);
      store.openGoalPanel(id);
      await pumpPlanner(tester, store);

      // Another device deletes the block: the store has no row for it.
      store.repos.events.delete(id);
      store.selectedGoalBlockId = id;
      await tester.pumpAndSettle();

      expect(find.text('This goal block is gone.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
