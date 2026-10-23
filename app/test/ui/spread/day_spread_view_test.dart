// The Day Spread (milestone F9): the home screen. The tasks, the timeline
// of the day and the note of the day, side by side.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/notes/note_editor_pane.dart';
import 'package:grove/ui/notes/notes_pane.dart';
import 'package:grove/ui/planner/inline_title_field.dart';
import 'package:grove/ui/planner/planner_grid.dart';
import 'package:grove/ui/shell/shell_layout.dart';
import 'package:grove/ui/spread/day_spread_view.dart';
import 'package:grove/ui/spread/spread_rules.dart';
import 'package:grove/ui/tasks/notice_cards.dart';
import 'package:grove/ui/tasks/task_inspector.dart';
import 'package:grove/ui/tasks/task_widgets.dart' show Segments;
import 'package:grove/ui/tasks/tasks_pane.dart';
import 'package:grove/ui/theme/growing_plant.dart';
import 'package:grove/ui/theme/panel.dart';

import '../planner/planner_support.dart';
import '../tasks/tasks_support.dart'
    show addTask, checkFinder, rowFinder, textOffPixels, typeLine;

AppStore spreadStore({int now = 10 * 60}) =>
    plannerStore(now: now)..screen = Screen.today;

Finder key(String name) => find.byKey(ValueKey(name));

/// A window where the three columns have room, with the widest task list.
const wide = Size(1280, 720);

/// The day after the Wednesday of the tests.
final thursday = wednesday.adding(days: 1);

/// The "Today / Tomorrow" switch of the header, and one of its two words.
/// The same words are in the task list and in the tabs of the window.
final daySwitch = key('spread-day-switch');
Finder dayButton(String word) =>
    find.descendant(of: daySwitch, matching: find.text(word));

/// The box around the switch that takes a touch.
final dayTouch = key('spread-day-touch');

final nowLine = key('now-line');
final headerPlant = find.descendant(
  of: find.byType(SpreadHeader),
  matching: find.byType(GrowingPlant),
);

/// The words of the date or of the line under it, as the screen gives them
/// (a theme can show the date in capitals).
String textOf(WidgetTester tester, String name) {
  final widget = tester.widget(key(name));
  return widget is ThemedHeading ? widget.text : (widget as Text).data!;
}

/// A click on "Tomorrow" in the header.
Future<void> showTomorrow(WidgetTester tester) async {
  await tester.tap(dayButton('Tomorrow'));
  await tester.pumpAndSettle();
}

/// Taps "Start a note" in the note column.
Future<void> startNote(WidgetTester tester) async {
  await tester.tap(key('spread-start-note'));
  await tester.pumpAndSettle();
}

/// An event with a time, not a task.
void addEvent(AppStore store, String title, DayKey day, int start) =>
    store.createFromDraft(
      title: title,
      day: day,
      start: start,
      end: start + 60,
      asEvent: true,
    );

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
    // no note is made by a look at the day
    expect(store.existingDailyNote(wednesday), isNull);
    expect(find.text('No note for this day yet.'), findsOneWidget);
    expect(find.byType(NoteEditorPane), findsNothing);

    await startNote(tester);
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
    await startNote(tester);
    await tester.enterText(
      find.descendant(
        of: key('note-text'),
        matching: find.byType(EditableText),
      ),
      'A good day',
    );
    await tester.pump(NoteEditorPane.saveDelay);
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

  testWidgets('the screen keeps its own day: today, or tomorrow', (
    tester,
  ) async {
    final store = spreadStore();
    await pumpPlanner(tester, store, size: wide);
    store.selectedDay = d('2026-10-20');
    await tester.pumpAndSettle();
    expect(store.selectedDay, wednesday);

    await showTomorrow(tester);
    store.selectedDay = d('2026-10-20');
    await tester.pumpAndSettle();
    expect(store.selectedDay, thursday);
  });

  testWidgets('"Open in the Notes screen" shows the note of today there', (
    tester,
  ) async {
    final store = spreadStore();
    await pumpPlanner(tester, store, size: wide);
    await startNote(tester);
    final daily = store.existingDailyNote(wednesday)!;
    await tester.tap(key('note-open'));
    await tester.pumpAndSettle();
    expect(store.screen, Screen.notes);
    expect(store.selectedNoteId, daily.id);
    // the editor of the Notes screen shows it, so the empty note stays
    expect(store.note(daily.id), isNotNull);
  });

  testWidgets('text typed in the note of today is saved', (tester) async {
    final store = spreadStore();
    await pumpPlanner(tester, store, size: wide);
    await startNote(tester);
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

  group('an empty note of a day', () {
    testWidgets('is forgotten when the user leaves it', (tester) async {
      final store = spreadStore();
      await pumpPlanner(tester, store, size: wide);
      await startNote(tester);
      expect(store.existingDailyNote(wednesday), isNotNull);

      await showTomorrow(tester);
      expect(store.existingDailyNote(wednesday), isNull);
      await tester.tap(dayButton('Today'));
      await tester.pumpAndSettle();
      expect(find.text('No note for this day yet.'), findsOneWidget);
      expect(store.undoStack, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps text typed just before the user leaves', (tester) async {
      final store = spreadStore();
      await pumpPlanner(tester, store, size: wide);
      await startNote(tester);
      // no wait for the save: the editor writes the text when it goes
      await tester.enterText(
        find.descendant(
          of: key('note-text'),
          matching: find.byType(EditableText),
        ),
        'A good day',
      );
      await showTomorrow(tester);
      expect(store.existingDailyNote(wednesday)!.body, 'A good day');
    });

    testWidgets('a note emptied by the user goes when the user leaves', (
      tester,
    ) async {
      final store = spreadStore();
      store.setNoteBody(store.dailyNote(wednesday).id, 'A good day');
      await pumpPlanner(tester, store, size: wide);
      await tester.enterText(
        find.descendant(
          of: key('note-text'),
          matching: find.byType(EditableText),
        ),
        '',
      );
      await tester.pump(NoteEditorPane.saveDelay);
      // it stays while the user can see it
      expect(store.existingDailyNote(wednesday), isNotNull);
      await showTomorrow(tester);
      expect(store.existingDailyNote(wednesday), isNull);
    });
  });

  // Swift: CheckBoxClickTests. A click in the middle of the box checks the
  // task off in each theme; the row does not take that click.
  for (final theme in ThemeId.values) {
    testWidgets('the check box takes its click, theme ${theme.name}', (
      tester,
    ) async {
      final store = spreadStore()..setTheme(theme);
      addTask(store, 'Water the plants', id: 'water');
      await pumpPlanner(tester, store, size: wide);

      await tester.tapAt(tester.getCenter(checkFinder('water')));
      await tester.pumpAndSettle();
      expect(store.task('water')!.isDone, isTrue);
      expect(store.selectedTaskId, isNull);
    });
  }

  testWidgets('a click on the title chooses the task and does not check it', (
    tester,
  ) async {
    final store = spreadStore();
    addTask(store, 'Water the plants', id: 'water');
    await pumpPlanner(tester, store, size: wide);

    // The strip of tasks with no time shows the title too.
    await tester.tap(
      find.descendant(
        of: rowFinder('water'),
        matching: find.text('Water the plants'),
      ),
    );
    await tester.pumpAndSettle();
    expect(store.task('water')!.isDone, isFalse);
    expect(store.selectedTaskId, 'water');
  });

  group('the tomorrow view', () {
    testWidgets('the header has a switch, and it starts on Today', (
      tester,
    ) async {
      final store = spreadStore();
      await pumpPlanner(tester, store, size: wide);
      expect(tester.takeException(), isNull);

      expect(dayButton('Today'), findsOneWidget);
      expect(dayButton('Tomorrow'), findsOneWidget);
      expect(tester.widget<Segments<bool>>(daySwitch).value, isFalse);
      expect(store.showsTomorrow, isFalse);

      // on whole points, left of the plant, beside the date
      final box = tester.getRect(daySwitch);
      expect(box.width, SpreadRules.daySwitchWidth);
      for (final v in [box.left, box.top, box.width, box.height]) {
        expect(v, v.roundToDouble());
      }
      expect(box.right, lessThan(tester.getRect(headerPlant).left));
      final date = tester.getRect(key('spread-date'));
      expect(box.left, greaterThan(date.left));
      expect(box.center.dy, inInclusiveRange(date.top, date.bottom + 20));
      expect(textOffPixels(tester, within: daySwitch), isEmpty);
      // the header is as high as before: the plant is the highest part
      expect(tester.getSize(find.byType(SpreadHeader)).height, 44);
    });

    testWidgets('a click on Tomorrow shows only tomorrow', (tester) async {
      final store = spreadStore();
      addTask(store, 'Write report', id: 'report');
      addTask(store, 'Pack the bag', id: 'pack', day: thursday);
      addEvent(store, 'Standup', wednesday, 11 * 60);
      addEvent(store, 'Dentist', thursday, 11 * 60);
      await pumpPlanner(tester, store, size: wide);

      // today, as before
      expect(find.text('Wednesday 7 October'), findsOneWidget);
      expect(columnFinder(wednesday), findsOneWidget);
      expect(nowLine, findsOneWidget);
      expect(headerPlant, findsOneWidget);
      expect(find.text('Standup'), findsOneWidget);
      expect(find.text('Dentist'), findsNothing);
      final switchAt = tester.getRect(daySwitch);

      await showTomorrow(tester);
      expect(tester.takeException(), isNull);
      expect(store.showsTomorrow, isTrue);
      expect(store.selectedDay, thursday);
      expect(tester.widget<Segments<bool>>(daySwitch).value, isTrue);

      // the header names the day, and says it is tomorrow
      expect(textOf(tester, 'spread-date'), 'Thursday 8 October');
      expect(find.text('Wednesday 7 October'), findsNothing);
      expect(textOf(tester, 'spread-subtitle'), 'Tomorrow · 1 task planned');
      // nothing of the real today: no greeting, no growth, no plant
      expect(find.textContaining('Good morning'), findsNothing);
      expect(find.textContaining('grown'), findsNothing);
      expect(headerPlant, findsNothing);
      // the switch stays where it is
      expect(tester.getRect(daySwitch), switchAt);

      // the timeline: the column of tomorrow, and no line for "now"
      expect(columnFinder(thursday), findsOneWidget);
      expect(columnFinder(wednesday), findsNothing);
      expect(nowLine, findsNothing);
      expect(find.text('Dentist'), findsOneWidget);
      expect(find.text('Standup'), findsNothing);

      // the tasks of tomorrow
      final pane = tester.widget<TasksPane>(find.byType(TasksPane));
      expect(pane.day, thursday);
      expect(rowFinder('pack'), findsOneWidget);
      expect(rowFinder('report'), findsNothing);

      // the note of tomorrow is not made by a look at the day
      expect(find.text('No note for this day yet.'), findsOneWidget);
      expect(find.byType(NoteEditorPane), findsNothing);
      expect(store.existingDailyNote(thursday), isNull);
    });

    testWidgets('a click on Today goes back', (tester) async {
      final store = spreadStore();
      addTask(store, 'Write report', id: 'report');
      addTask(store, 'Pack the bag', id: 'pack', day: thursday);
      await pumpPlanner(tester, store, size: wide);
      await showTomorrow(tester);

      await tester.tap(dayButton('Today'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(store.showsTomorrow, isFalse);
      expect(store.selectedDay, wednesday);
      expect(textOf(tester, 'spread-date'), 'Wednesday 7 October');
      expect(
        textOf(tester, 'spread-subtitle'),
        'Good morning · 0% of today grown',
      );
      expect(headerPlant, findsOneWidget);
      expect(columnFinder(wednesday), findsOneWidget);
      expect(columnFinder(thursday), findsNothing);
      expect(nowLine, findsOneWidget);
      expect(rowFinder('report'), findsOneWidget);
      expect(rowFinder('pack'), findsNothing);
      expect(find.text('No note for this day yet.'), findsOneWidget);
      expect(store.existingDailyNote(wednesday), isNull);
    });

    testWidgets('a task typed in the list lands on tomorrow', (tester) async {
      final store = spreadStore();
      await pumpPlanner(tester, store, size: wide);
      await showTomorrow(tester);
      expect(textOf(tester, 'spread-subtitle'), 'Tomorrow · No tasks yet');

      await typeLine(tester, key('quick-add'), 'Buy milk');
      final task = store.openTasks(TaskPlacement.day(thursday)).single;
      expect(task.title, 'Buy milk');
      expect(store.openTasks(TaskPlacement.day(wednesday)), isEmpty);
      expect(rowFinder(task.id), findsOneWidget);
      // it is in view, so no message says where it went
      expect(store.toast, isNull);
      expect(textOf(tester, 'spread-subtitle'), 'Tomorrow · 1 task planned');

      // a time alone is a time tomorrow
      await typeLine(tester, key('quick-add'), 'Call Ana 3pm');
      final block = store.blocks(DayRange.single(thursday)).single;
      expect(block.title, 'Call Ana');
      expect(block.startMinute, 15 * 60);
      expect(store.blocks(DayRange.single(wednesday)), isEmpty);
      expect(store.toast, isNull);
      expect(blockFinder(block.id), findsOneWidget);
    });

    testWidgets('a block drawn on the timeline lands on tomorrow', (
      tester,
    ) async {
      final store = spreadStore();
      await pumpPlanner(tester, store, size: wide);
      await showTomorrow(tester);

      await mouseDrag(
        tester,
        pointAt(tester, thursday, 11 * 60),
        const Offset(0, hour),
      );
      await tester.enterText(
        find.descendant(
          of: find.byType(InlineTitleField),
          matching: find.byType(EditableText),
        ),
        'Deep work',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final block = blockNamed(store, 'Deep work');
      expect(block.day, thursday);
      expect((block.startMinute, block.endMinute), (660, 720));
      expect(
        store.openTasks(TaskPlacement.day(thursday)).single.title,
        ('Deep work'),
      );
      expect(store.blocks(DayRange.single(wednesday)), isEmpty);
    });

    testWidgets('a task dragged on the timeline gets its block tomorrow', (
      tester,
    ) async {
      final store = spreadStore();
      addTask(store, 'Pack the bag', id: 'pack', day: thursday);
      await pumpPlanner(tester, store, size: wide);
      await showTomorrow(tester);

      final from = tester.getCenter(rowFinder('pack'));
      final to = pointAt(tester, thursday, 11 * 60);
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      for (var i = 1; i <= 8; i++) {
        await gesture.moveTo(Offset.lerp(from, to, i / 8)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      final block = blockNamed(store, 'Pack the bag');
      expect(block.taskId, 'pack');
      expect(block.day, thursday);
      expect(store.task('pack')!.planDate, thursday);
      await endToast(tester);
    });

    testWidgets('"Plan my day" plans tomorrow, and says so', (tester) async {
      final store = spreadStore();
      store.quickAdd('Call the bank', placement: TaskPlacement.day(thursday));
      await pumpPlanner(tester, store, size: wide);
      expect(
        find.byTooltip(
          "Plan my day: fit today's unscheduled tasks into free "
          'working hours',
        ),
        findsOneWidget,
      );

      await showTomorrow(tester);
      expect(
        find.byTooltip(
          "Plan my day: fit tomorrow's unscheduled tasks into free "
          'working hours',
        ),
        findsOneWidget,
      );
      await tester.tap(key('plan-my-day'));
      await tester.pumpAndSettle();
      await tester.tap(key('plan-apply'));
      await tester.pumpAndSettle();

      // from the start of the working hours, not from "now"
      final block = store.blocks(DayRange.single(thursday)).single;
      expect(block.title, 'Call the bank');
      expect(block.startMinute, 9 * 60);
      expect(store.blocks(DayRange.single(wednesday)), isEmpty);
    });

    testWidgets('the card of yesterday is not in the tomorrow view', (
      tester,
    ) async {
      final store = spreadStore();
      final tuesday = wednesday.adding(days: -1);
      addTask(store, 'Old report', id: 'old', day: tuesday);
      store.repos.events.save(
        EventItem(
          title: 'Old report',
          start: WallTime(day: tuesday, minute: 540),
          end: WallTime(day: tuesday, minute: 600),
          kind: EventKind.block,
          taskId: 'old',
        ),
      );
      await pumpPlanner(tester, store, size: wide);
      expect(find.byType(RollOverCard), findsOneWidget);

      await showTomorrow(tester);
      expect(find.byType(RollOverCard), findsNothing);

      await tester.tap(dayButton('Today'));
      await tester.pumpAndSettle();
      expect(find.byType(RollOverCard), findsOneWidget);
    });

    testWidgets('the choice stays while the user is on another screen', (
      tester,
    ) async {
      final store = spreadStore();
      await pumpPlanner(tester, store, size: wide);
      await showTomorrow(tester);

      store.screen = Screen.planner;
      await tester.pumpAndSettle();
      expect(find.byType(DaySpreadView), findsNothing);
      store.selectedDay = d('2026-10-20');
      await tester.pumpAndSettle();

      store.screen = Screen.today;
      await tester.pumpAndSettle();
      expect(textOf(tester, 'spread-date'), 'Thursday 8 October');
      expect(columnFinder(thursday), findsOneWidget);
      expect(store.selectedDay, thursday);
      expect(tester.widget<Segments<bool>>(daySwitch).value, isTrue);
    });

    testWidgets('the key of "Today" goes back to today', (tester) async {
      final store = spreadStore();
      await pumpPlanner(tester, store, size: wide);
      await showTomorrow(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(store.showsTomorrow, isFalse);
      expect(textOf(tester, 'spread-date'), 'Wednesday 7 October');
      expect(columnFinder(wednesday), findsOneWidget);
      expect(nowLine, findsOneWidget);
    });

    testWidgets('a phone: the switch has its own row, and a finger has room', (
      tester,
    ) async {
      final store = spreadStore();
      addEvent(store, 'Dentist', thursday, 11 * 60);
      await pumpPlanner(tester, store, size: phoneSize);
      expect(tester.takeException(), isNull);

      final box = tester.getRect(daySwitch);
      final touch = tester.getRect(dayTouch);
      final subtitle = tester.getRect(key('spread-subtitle'));
      // under the date and its line, from side to side
      expect(box.top, greaterThan(subtitle.bottom));
      expect((box.left, box.right), (12, phoneSize.width - 12));
      for (final v in [box.left, box.top, box.width, box.height]) {
        expect(v, v.roundToDouble());
      }
      expect(textOffPixels(tester, within: daySwitch), isEmpty);
      // the place that takes a touch is as high as a button of the dock
      expect(touch.height, SpreadRules.daySwitchTouch);
      expect(
        touch.height,
        greaterThanOrEqualTo(ShellRules.dockButton(ShellLayout.phone).height),
      );
      expect(touch.top, lessThan(box.top));
      expect(touch.bottom, greaterThan(box.bottom));
      expect((touch.left, touch.right), (box.left, box.right));
      // the timeline starts under it
      expect(
        tester.getRect(find.byType(PlannerGrid)).top,
        greaterThan(touch.bottom),
      );

      // a finger on the word
      await tester.tap(dayButton('Tomorrow'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(textOf(tester, 'spread-date'), 'Thursday 8 October');
      expect(textOf(tester, 'spread-subtitle'), 'Tomorrow · No tasks yet');
      expect(columnFinder(thursday), findsOneWidget);
      expect(columnFinder(wednesday), findsNothing);
      expect(nowLine, findsNothing);
      expect(find.text('Dentist'), findsOneWidget);
      expect(headerPlant, findsNothing);
      // the switch did not move
      expect(tester.getRect(daySwitch), box);

      // a finger just over "Today", in the empty space of the touch area
      await tester.tapAt(Offset(touch.left + touch.width / 4, touch.top + 1));
      await tester.pumpAndSettle();
      expect(store.showsTomorrow, isFalse);
      expect(textOf(tester, 'spread-date'), 'Wednesday 7 October');
      // and just under "Tomorrow"
      await tester.tapAt(
        Offset(touch.left + touch.width * 3 / 4, touch.bottom - 1),
      );
      await tester.pumpAndSettle();
      expect(store.showsTomorrow, isTrue);
      // a second touch on the same side changes nothing
      await tester.tapAt(
        Offset(touch.left + touch.width * 3 / 4, touch.bottom - 1),
      );
      await tester.pumpAndSettle();
      expect(store.showsTomorrow, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a block added on a phone lands on tomorrow', (tester) async {
      final store = spreadStore();
      await pumpPlanner(tester, store, size: phoneSize);
      await tester.tap(dayButton('Tomorrow'));
      await tester.pumpAndSettle();

      // File ▸ New Event: on the day in view, and the screen stays
      store.newEventNow();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(store.screen, Screen.today);
      final event = store.repos.events.all().single;
      expect(event.start, WallTime(day: thursday, minute: 9 * 60));
      expect(store.showsTomorrow, isTrue);
      store.closeEditor();
      await tester.pumpAndSettle();
      expect(textOf(tester, 'spread-date'), 'Thursday 8 October');
      expect(blockFinder(event.id), findsOneWidget);
    });

    testWidgets('at midnight the tomorrow view keeps its date, as today', (
      tester,
    ) async {
      final store = spreadStore(now: 23 * 60 + 58);
      addTask(store, 'Pack the bag', id: 'pack', day: thursday);
      await pumpPlanner(tester, store, size: wide);
      await showTomorrow(tester);
      // a screen that nobody touches asks for no frame
      await tester.pump(const Duration(seconds: 21));
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(textOf(tester, 'spread-subtitle'), 'Tomorrow · 1 task planned');

      store.clockOverride = WallTime(day: thursday, minute: 1);
      await tester.pump(const Duration(seconds: 21));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // the same day, now with the name and the parts of today
      expect(textOf(tester, 'spread-date'), 'Thursday 8 October');
      expect(textOf(tester, 'spread-subtitle'), endsWith('0% of today grown'));
      expect(store.showsTomorrow, isFalse);
      expect(store.selectedDay, thursday);
      expect(tester.widget<Segments<bool>>(daySwitch).value, isFalse);
      expect(columnFinder(thursday), findsOneWidget);
      expect(nowLine, findsOneWidget);
      expect(headerPlant, findsOneWidget);
      expect(rowFinder('pack'), findsOneWidget);
      // no note is made for the new day
      expect(store.existingDailyNote(thursday), isNull);
      expect(find.text('No note for this day yet.'), findsOneWidget);

      // "Tomorrow" is now Friday
      await showTomorrow(tester);
      expect(textOf(tester, 'spread-date'), 'Friday 9 October');
    });

    testWidgets('at midnight the today view moves to the new day', (
      tester,
    ) async {
      final store = spreadStore(now: 23 * 60 + 58);
      await pumpPlanner(tester, store, size: wide);
      expect(textOf(tester, 'spread-date'), 'Wednesday 7 October');

      store.clockOverride = WallTime(day: thursday, minute: 1);
      await tester.pump(const Duration(seconds: 21));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(textOf(tester, 'spread-date'), 'Thursday 8 October');
      expect(store.showsTomorrow, isFalse);
      expect(store.selectedDay, thursday);
      expect(columnFinder(thursday), findsOneWidget);
      expect(columnFinder(wednesday), findsNothing);
      expect(tester.widget<TasksPane>(find.byType(TasksPane)).day, thursday);
    });

    for (final theme in ThemeId.values) {
      testWidgets('the switch works in the theme ${theme.name}', (
        tester,
      ) async {
        final store = spreadStore()..setTheme(theme);
        await pumpPlanner(tester, store, size: wide);
        expect(tester.takeException(), isNull);
        // both words fit: none is cut
        for (final word in ['Today', 'Tomorrow']) {
          final text = tester.renderObject<RenderParagraph>(dayButton(word));
          expect(text.didExceedMaxLines, isFalse, reason: word);
        }
        await showTomorrow(tester);
        expect(textOf(tester, 'spread-date'), 'Thursday 8 October');
        expect(tester.takeException(), isNull);
      });
    }
  });
}
