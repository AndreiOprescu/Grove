// Activities: reserved time that is not a task, like lunch or a train.
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/calendar/event_editor.dart';

import 'planner_support.dart';

/// A line of the open menu.
Finder menuLine(String label) =>
    find.widgetWithText(PopupMenuItem<VoidCallback>, label);

/// An activity from 12:00 to 13:00 on Wednesday. Gives the block.
PlannerBlock addActivity(AppStore store, String title) {
  store.createFromDraft(
    title: title,
    day: wednesday,
    start: 12 * 60,
    end: 13 * 60,
    asEvent: false,
    asActivity: true,
  );
  return blockNamed(store, title);
}

void main() {
  group('the store', () {
    test('a draft as an activity makes one activity and no task', () {
      final store = plannerStore();
      final tasksBefore = store.repos.tasks.all().length;

      final block = addActivity(store, 'Lunch');

      expect(block.kind, EventKind.activity);
      expect(block.isActivity, isTrue);
      expect(block.isTaskBlock, isFalse);
      expect(block.isDone, isFalse);
      expect(store.repos.tasks.all().length, tasksBefore);
      expect(store.repos.events.get(block.id)?.kind, EventKind.activity);
      expect(store.selection, {block.id});
    });

    test('the month view counts an activity like an event', () {
      final store = plannerStore();
      addActivity(store, 'Train to Lyon');

      final info = store.dayInfo(DayRange.single(wednesday))[wednesday]!;
      expect(info.events.map((e) => e.title), ['Train to Lyon']);
    });
  });

  group('the draft', () {
    testWidgets('the activity icon makes the draft an activity', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);

      await mouseDrag(
        tester,
        pointAt(tester, wednesday, 12 * 60),
        const Offset(0, hour),
      );
      expect(find.text('New task'), findsOneWidget);
      expect(find.byKey(const ValueKey('draft-task')), findsOneWidget);

      // A mouse click outside a text field takes its focus away. This one
      // must not: the draft would close.
      await tester.tap(
        find.byKey(const ValueKey('draft-activity')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      // The tap does not close the draft or take the keys from the title.
      expect(find.byKey(const ValueKey('planner-draft')), findsOneWidget);
      expect(gridState(tester).draft!.asActivity, isTrue);
      expect(find.text('New activity'), findsOneWidget);
      expect(store.blocks(DayRange.single(wednesday)), isEmpty);

      await tester.enterText(find.byType(EditableText), 'Lunch');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final block = blockNamed(store, 'Lunch');
      expect(block.isActivity, isTrue);
      expect(block.isTaskBlock, isFalse);
      expect(find.byKey(ValueKey('check-${block.id}')), findsNothing);
      expect(find.byKey(ValueKey('activity-${block.id}')), findsOneWidget);
    }, variant: TargetPlatformVariant.desktop());

    testWidgets('an activity has no list of tasks to schedule', (tester) async {
      final store = plannerStore();
      store.quickAdd('Lunch money', placement: TaskPlacement.day(wednesday));
      await pumpPlanner(tester, store);

      await mouseDrag(
        tester,
        pointAt(tester, wednesday, 12 * 60),
        const Offset(0, hour),
      );
      await tester.enterText(find.byType(EditableText), 'Lun');
      await tester.pumpAndSettle();
      expect(find.text('Schedule existing task'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('draft-activity')));
      await tester.pumpAndSettle();
      expect(find.text('Schedule existing task'), findsNothing);
    });

    testWidgets('a new week saves the draft as an activity', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);

      await mouseDrag(
        tester,
        pointAt(tester, wednesday, 12 * 60),
        const Offset(0, hour),
      );
      await tester.tap(find.byKey(const ValueKey('draft-activity')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), 'Lunch');
      store.selectedDay = wednesday.adding(days: 7);
      await tester.pumpAndSettle();

      expect(blockNamed(store, 'Lunch').isActivity, isTrue);
    });

    testWidgets('the task icon turns it back into a task', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);

      await mouseDrag(
        tester,
        pointAt(tester, wednesday, 12 * 60),
        const Offset(0, hour),
      );
      await tester.tap(find.byKey(const ValueKey('draft-activity')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('draft-task')));
      await tester.pumpAndSettle();
      expect(find.text('New task'), findsOneWidget);

      await tester.enterText(find.byType(EditableText), 'Write report');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(blockNamed(store, 'Write report').isTaskBlock, isTrue);
    });
  });

  group('an activity on the grid', () {
    testWidgets('a click opens the editor, with no Deadline switch', (
      tester,
    ) async {
      final store = plannerStore();
      final block = addActivity(store, 'Lunch');
      await pumpPlanner(tester, store);

      await tester.tap(blockFinder(block.id));
      await tester.pumpAndSettle();

      expect(find.byType(EventEditor), findsOneWidget);
      expect(store.editingEvent?.item.id, block.id);
      expect(find.byKey(const ValueKey('event-deadline')), findsNothing);
      expect(find.bySemanticsLabel('Activity'), findsOneWidget);
    });

    testWidgets('the menu has "Edit Activity…" and no Mark Done', (
      tester,
    ) async {
      final store = plannerStore();
      addActivity(store, 'Lunch');
      await pumpPlanner(tester, store);

      await rightClick(tester, pointAt(tester, wednesday, 12 * 60 + 30));

      expect(menuLine('Edit Activity…'), findsOneWidget);
      expect(menuLine('Delete Activity'), findsOneWidget);
      expect(menuLine('Mark Done'), findsNothing);
      expect(menuLine('Start Focus'), findsNothing);
      expect(menuLine('Unschedule'), findsNothing);
    });
  });
}
