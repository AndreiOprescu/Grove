// The day menu: a right-click (a long press on a phone) on a day name of the
// Planner week, or on a day of the Calendar month.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../planner/planner_support.dart';

Finder header(DayKey day) => find.byKey(ValueKey('day-header-${day.string}'));
Finder cell(DayKey day) => find.byKey(ValueKey('month-day-${day.string}'));

/// A line of the open menu (the planner has its own "Plan my day" button).
Finder line(String text) => find.descendant(
  of: find.byWidgetPredicate((w) => w is PopupMenuItem),
  matching: find.text(text),
);

final friday = d('2026-10-09');
final monday = d('2026-10-05');

TaskItem planned(AppStore store, String title, DayKey day) {
  final t = TaskItem(title: title, bucket: TaskBucket.day, planDate: day);
  store.repos.tasks.save(t);
  return t;
}

void main() {
  group('the planner day name', () {
    testWidgets('a right-click opens the menu of that day', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);
      await rightClick(tester, tester.getCenter(header(friday)));

      expect(line('Friday 9 October'), findsOneWidget);
      for (final text in [
        'New event',
        'New deadline',
        'New task…',
        'Open daily note',
        'Open weekly note',
        'Plan my day',
      ]) {
        expect(line(text), findsOneWidget, reason: text);
      }
      // No open task on Friday, and the planner is already there.
      expect(line('Move open tasks to…'), findsNothing);
      expect(line('Show in Planner'), findsNothing);
    });

    testWidgets('"Plan my day" is not offered for a past day', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);
      await rightClick(tester, tester.getCenter(header(monday)));
      expect(line('New event'), findsOneWidget);
      expect(line('Plan my day'), findsNothing);
    });

    testWidgets('"New deadline" opens the card with Deadline on', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);
      await rightClick(tester, tester.getCenter(header(friday)));
      await tester.tap(find.text('New deadline'));
      await tester.pumpAndSettle();

      final editing = store.editingEvent!;
      expect(editing.isNew, isTrue);
      expect(editing.item.isDeadline, isTrue);
      expect(editing.item.start.day, friday);
    });

    testWidgets('"New task…" plans a task for that day', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);
      await rightClick(tester, tester.getCenter(header(friday)));
      await tester.tap(find.text('New task…'));
      await tester.pumpAndSettle();

      expect(find.text('New task for Fri 9 Oct'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('day-new-task-field')),
        'Buy stamps',
      );
      await tester.pump(); // Add turns on with the text.
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      final tasks = store.openTasks(TaskPlacement.day(friday));
      expect(tasks.map((t) => t.title), ['Buy stamps']);
      expect(find.byKey(const ValueKey('day-new-task')), findsNothing);
    });

    testWidgets('"Open daily note" opens the note of that day', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);
      await rightClick(tester, tester.getCenter(header(friday)));
      await tester.tap(find.text('Open daily note'));
      await tester.pumpAndSettle();

      expect(store.screen, Screen.notes);
      expect(store.selectedNoteId, store.existingDailyNote(friday)!.id);
    });

    testWidgets('"Move open tasks to…" moves them to the picked day', (
      tester,
    ) async {
      final store = plannerStore();
      planned(store, 'Write report', wednesday);
      await pumpPlanner(tester, store);
      await rightClick(tester, tester.getCenter(header(wednesday)));
      await tester.tap(find.text('Move open tasks to…'));
      await tester.pumpAndSettle();

      // The picker starts on the next day, Thursday 8 October.
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(store.openTasks(TaskPlacement.day(wednesday)), isEmpty);
      expect(
        store.openTasks(TaskPlacement.day(d('2026-10-08'))).map((t) => t.title),
        ['Write report'],
      );
      expect(store.toast, 'Moved 1 task to Thu 8 Oct');
      await endToast(tester);
    });

    testWidgets('a long press on a phone opens the menu', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store, size: phoneSize);
      await tester.longPress(header(wednesday));
      await tester.pumpAndSettle();
      expect(line('Wednesday 7 October'), findsOneWidget);
      expect(line('New deadline'), findsOneWidget);
    });

    testWidgets('a click still only picks the day', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);
      await mouseTap(tester, tester.getCenter(header(friday)));
      await tester.pumpAndSettle();
      expect(store.selectedDay, friday);
      expect(line('New deadline'), findsNothing);
    });
  });

  group('the calendar day', () {
    AppStore calendarStore() => plannerStore()..screen = Screen.calendar;

    testWidgets('a right-click opens the menu, with "Show in Planner"', (
      tester,
    ) async {
      final store = calendarStore();
      planned(store, 'Write report', friday);
      await pumpPlanner(tester, store);
      await rightClick(tester, tester.getCenter(cell(friday)));
      await endTapWindow(tester);

      expect(line('Friday 9 October'), findsOneWidget);
      expect(line('New deadline'), findsOneWidget);
      expect(line('Show in Planner'), findsOneWidget);
      expect(line('Move open tasks to…'), findsOneWidget);
      // The Calendar has no plan button.
      expect(line('Plan my day'), findsNothing);
      // The right-click does not open the day or start an event.
      expect(store.screen, Screen.calendar);
      expect(store.editingEvent, isNull);
    });

    testWidgets('"Show in Planner" opens the Planner on that week', (
      tester,
    ) async {
      final store = calendarStore();
      await pumpPlanner(tester, store);
      await rightClick(tester, tester.getCenter(cell(d('2026-10-20'))));
      await tester.tap(find.text('Show in Planner'));
      await tester.pumpAndSettle();
      expect(store.selectedDay, d('2026-10-20'));
      expect(store.screen, Screen.planner);
    });

    testWidgets('"New deadline" starts a deadline on that day', (tester) async {
      final store = calendarStore();
      await pumpPlanner(tester, store);
      await rightClick(tester, tester.getCenter(cell(d('2026-10-20'))));
      await tester.tap(find.text('New deadline'));
      await tester.pumpAndSettle();
      final editing = store.editingEvent!;
      expect(editing.item.isDeadline, isTrue);
      expect(editing.item.start.day, d('2026-10-20'));
      expect(store.screen, Screen.calendar);
    });

    testWidgets('a long press on a phone opens the menu', (tester) async {
      final store = calendarStore();
      await pumpPlanner(tester, store, size: phoneSize);
      await tester.longPress(cell(friday));
      await tester.pumpAndSettle();
      expect(line('Friday 9 October'), findsOneWidget);
      expect(store.screen, Screen.calendar);
    });
  });
}
