// The Day Spread (milestone F9): the home screen. The tasks, the timeline
// of the day and the note of the day, side by side.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/notes/note_editor_pane.dart';
import 'package:grove/ui/notes/notes_pane.dart';
import 'package:grove/ui/planner/planner_grid.dart';
import 'package:grove/ui/spread/day_spread_view.dart';
import 'package:grove/ui/spread/spread_rules.dart';
import 'package:grove/ui/tasks/task_inspector.dart';
import 'package:grove/ui/tasks/tasks_pane.dart';

import '../planner/planner_support.dart';
import '../tasks/tasks_support.dart' show addTask, rowFinder;

AppStore spreadStore({int now = 10 * 60}) =>
    plannerStore(now: now)..screen = Screen.today;

Finder key(String name) => find.byKey(ValueKey(name));

/// A window where the three columns have room, with the widest task list.
const wide = Size(1280, 720);

void main() {
  testWidgets('three columns: the tasks, the timeline, the note of today', (
    tester,
  ) async {
    final store = spreadStore();
    addTask(store, 'Write report', id: 'report');
    await pumpPlanner(tester, store, size: wide);
    expect(tester.takeException(), isNull);

    expect(find.text('Wednesday 7 October'), findsOneWidget);
    expect(find.text('Good morning · 0% of today grown'), findsOneWidget);

    final tasks = tester.getRect(key('spread-tasks'));
    final timeline = tester.getRect(key('spread-timeline'));
    final note = tester.getRect(key('spread-note'));
    expect(tasks.left, SpreadRules.side);
    expect(tasks.width, SpreadRules.tasksDefault);
    expect(timeline.left, tasks.right + SpreadRules.gap);
    expect(note.left, timeline.right + SpreadRules.gap);
    expect(note.width, SpreadRules.noteWidth);
    expect(note.right, wide.width - SpreadRules.side);
    expect(timeline.width, greaterThanOrEqualTo(SpreadRules.timelineMinimum));

    final pane = tester.widget<TasksPane>(find.byType(TasksPane));
    expect(pane.mode, TasksPaneMode.today);
    expect(rowFinder('report'), findsOneWidget);
    expect(find.byType(PlannerGrid), findsOneWidget);
    // the note of today is made when the column opens
    final daily = store.existingDailyNote(wednesday);
    expect(daily, isNotNull);
    final editor = tester.widget<NoteEditorPane>(find.byType(NoteEditorPane));
    expect(editor.noteId, daily!.id);
    expect(editor.compact, isTrue);
    expect(find.text("Today's note"), findsOneWidget);
  });

  testWidgets('the greeting follows the hour, the growth follows the tasks', (
    tester,
  ) async {
    final store = spreadStore(now: 19 * 60);
    addTask(store, 'One', id: 'one');
    addTask(store, 'Two', id: 'two');
    await pumpPlanner(tester, store, size: wide);
    expect(find.text('Good evening · 0% of today grown'), findsOneWidget);
    store.toggleDone(taskId: 'one');
    await tester.pumpAndSettle();
    expect(find.text('Good evening · 50% of today grown'), findsOneWidget);
  });

  testWidgets('the panel of a chosen task takes the place of the note', (
    tester,
  ) async {
    final store = spreadStore();
    addTask(store, 'Write report', id: 'report');
    await pumpPlanner(tester, store, size: wide);
    final before = tester.getRect(key('spread-timeline'));
    expect(find.byType(TaskInspector), findsNothing);

    await tester.tap(rowFinder('report'));
    await tester.pumpAndSettle();
    expect(store.selectedTaskId, 'report');
    expect(find.byType(TaskInspector), findsOneWidget);
    expect(find.byType(NoteEditorPane), findsNothing);
    // the panel is in the third column; the timeline does not move
    expect(
      tester.getRect(find.byType(TaskInspector)),
      tester.getRect(key('spread-note')),
    );
    expect(tester.getRect(key('spread-timeline')), before);

    store.selectedTaskId = null;
    await tester.pumpAndSettle();
    expect(find.byType(TaskInspector), findsNothing);
    expect(find.byType(NoteEditorPane), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape closes the panel of the task from any place', (
    tester,
  ) async {
    final store = spreadStore();
    addTask(store, 'Write report', id: 'report');
    store.selectedTaskId = 'report';
    await pumpPlanner(tester, store, size: wide);
    expect(find.byType(TaskInspector), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(store.selectedTaskId, isNull);
    expect(find.byType(TaskInspector), findsNothing);
  });

  testWidgets('a drag of the edge changes the width of the task list, and '
      'the width is kept', (tester) async {
    final store = spreadStore();
    await pumpPlanner(tester, store, size: wide);
    final handle = tester.getCenter(key('spread-handle'));
    final gesture = await tester.startGesture(
      handle,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(4.4, 0));
      await tester.pump();
    }
    expect(tester.getSize(key('spread-tasks')).width, 384);
    // nothing is saved before the drag ends
    expect(store.prefs.getDouble(SpreadRules.tasksWidthKey), isNull);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(store.prefs.getDouble(SpreadRules.tasksWidthKey), 384);
    expect(tester.getSize(key('spread-tasks')).width, 384);

    // the list stops at its widest and at its narrowest
    await tester.dragFrom(
      tester.getCenter(key('spread-handle')),
      const Offset(300, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(key('spread-tasks')).width, SpreadRules.tasksMax);
    await tester.dragFrom(
      tester.getCenter(key('spread-handle')),
      const Offset(-600, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(key('spread-tasks')).width, SpreadRules.tasksMin);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the saved width is used when the screen opens', (tester) async {
    final store = spreadStore();
    store.prefs.set(SpreadRules.tasksWidthKey, 400.0);
    await pumpPlanner(tester, store, size: wide);
    expect(tester.getSize(key('spread-tasks')).width, 400);
  });

  testWidgets('the smallest desktop window keeps the three columns', (
    tester,
  ) async {
    final store = spreadStore();
    await pumpPlanner(tester, store);
    expect(tester.takeException(), isNull);
    expect(key('spread-note'), findsOneWidget);
    expect(
      tester.getSize(key('spread-timeline')).width,
      greaterThanOrEqualTo(SpreadRules.timelineMinimum),
    );
  });

  testWidgets('an open left panel stands in the place of the task list', (
    tester,
  ) async {
    final store = spreadStore();
    store.newNote(title: 'Alpha');
    store
      ..screen = Screen.today
      ..leftPane = LeftPane.notes;
    await pumpPlanner(tester, store, size: wide);
    expect(tester.takeException(), isNull);
    expect(find.byType(NotesPane), findsOneWidget);
    expect(key('spread-tasks'), findsNothing);
    expect(key('spread-handle'), findsNothing);
    expect(key('spread-timeline'), findsOneWidget);
    expect(key('spread-note'), findsOneWidget);

    store.leftPane = null;
    await tester.pumpAndSettle();
    expect(key('spread-tasks'), findsOneWidget);
  });

  testWidgets('a window with no room for the note: two columns, and the '
      'panel of a task covers the timeline', (tester) async {
    final store = spreadStore();
    addTask(store, 'Write report', id: 'report');
    await pumpPlanner(tester, store, size: const Size(800, 620));
    expect(tester.takeException(), isNull);
    expect(key('spread-tasks'), findsOneWidget);
    expect(key('spread-note'), findsNothing);
    expect(find.byType(NoteEditorPane), findsNothing);
    expect(find.byType(PlannerGrid), findsOneWidget);

    await tester.tap(rowFinder('report'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskInspector), findsOneWidget);
    expect(find.byType(PlannerGrid), findsNothing);
    expect(
      tester.getRect(find.byType(TaskInspector)),
      tester.getRect(key('spread-timeline')),
    );
    store.selectedTaskId = null;
    await tester.pumpAndSettle();
    expect(find.byType(PlannerGrid), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a phone shows one day column', (tester) async {
    final store = spreadStore();
    addTask(store, 'Write report', id: 'report');
    await pumpPlanner(tester, store, size: phoneSize);
    expect(tester.takeException(), isNull);
    expect(find.byType(DaySpreadView), findsOneWidget);
    expect(find.text('Wednesday 7 October'), findsOneWidget);
    expect(find.byType(PlannerGrid), findsOneWidget);
    expect(find.byType(TasksPane), findsNothing);
    expect(find.byType(NoteEditorPane), findsNothing);

    // the panel of a chosen task covers the screen
    store.selectedTaskId = 'report';
    await tester.pumpAndSettle();
    expect(find.byType(TaskInspector), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the screen is always today', (tester) async {
    final store = spreadStore();
    await pumpPlanner(tester, store, size: wide);
    store.selectedDay = d('2026-10-20');
    await tester.pumpAndSettle();
    expect(store.selectedDay, wednesday);
  });

  testWidgets('"Open in the Notes screen" shows the note of today there', (
    tester,
  ) async {
    final store = spreadStore();
    await pumpPlanner(tester, store, size: wide);
    final daily = store.existingDailyNote(wednesday)!;
    await tester.tap(key('note-open'));
    await tester.pumpAndSettle();
    expect(store.screen, Screen.notes);
    expect(store.selectedNoteId, daily.id);
  });

  testWidgets('text typed in the note of today is saved', (tester) async {
    final store = spreadStore();
    await pumpPlanner(tester, store, size: wide);
    final daily = store.existingDailyNote(wednesday)!;
    await tester.enterText(
      find.descendant(
        of: key('note-text'),
        matching: find.byType(EditableText),
      ),
      'A good day',
    );
    await tester.pump(NoteEditorPane.saveDelay);
    await tester.pump();
    expect(store.note(daily.id)!.body, 'A good day');
    // the mood of the day
    await tester.tap(key('mood-sun'));
    await tester.pumpAndSettle();
    expect(store.note(daily.id)!.mood, Mood.sun.value);
  });
}
