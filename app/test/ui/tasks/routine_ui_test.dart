import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/tasks/task_widgets.dart';
import 'package:grove/ui/tasks/tasks_pane.dart';
import 'package:grove/ui/theme/grove_theme.dart';

import 'task_inspector_test.dart' show byKey, host, inspectorSize, pick, tapKey;
import 'tasks_support.dart';

// Routines: a "Routines" list at the top of the Tasks pane, with a bar that
// fills as time runs out, and a Routine switch in the Task panel.

Widget unscheduled(AppStore store) =>
    TasksPane(store: store, mode: TasksPaneMode.unscheduled);

final weekly = RoutineRule(every: 1, unit: RoutineUnit.weeks);

/// A routine turned on [since] (Wednesday 7 Oct, "today", when null).
TaskItem addRoutine(
  AppStore store,
  String title, {
  DayKey? since,
  RoutineRule? rule,
}) {
  final t = addTask(
    store,
    title,
    bucket: TaskBucket.inbox,
  ).copyWith(routine: rule ?? weekly, routineSince: since ?? wednesday);
  store.repos.tasks.save(t);
  return t;
}

ProgressBar barOf(WidgetTester tester, String id) =>
    tester.widget<ProgressBar>(byKey('routine-bar-$id'));

void main() {
  group('the Routines list', () {
    testWidgets('it is at the top and always there', (tester) async {
      final store = paneStore();
      addTask(store, 'No day', bucket: TaskBucket.inbox);
      await pumpPane(tester, unscheduled(store));

      expect(find.text('Routines'), findsOneWidget);
      expect(find.text('No routines yet.'), findsOneWidget);
      final routines = tester.getTopLeft(find.text('Routines')).dy;
      expect(routines, lessThan(tester.getTopLeft(find.text('No day')).dy));
    });

    testWidgets('late first, then the least time left, and never in '
        'Unscheduled', (tester) async {
      final store = paneStore();
      addRoutine(store, 'Water plants');
      addRoutine(store, 'Clean filter', since: wednesday.adding(days: -9));
      await pumpPane(tester, unscheduled(store));

      expect(find.text('Nothing waiting'), findsOneWidget);
      expect(find.text('7 days left'), findsOneWidget);
      expect(find.text('Late 2 days'), findsOneWidget);
      final late = tester.getTopLeft(find.text('Clean filter')).dy;
      final fresh = tester.getTopLeft(find.text('Water plants')).dy;
      expect(late, lessThan(fresh));
      final theme = GroveTheme.of(tester.element(find.text('Routines')));
      expect(barOf(tester, 'clean-filter').fraction, 1);
      expect(barOf(tester, 'clean-filter').color, theme.accent2);
      expect(barOf(tester, 'water-plants').fraction, 0);
      expect(barOf(tester, 'water-plants').color, theme.accent);
    });

    testWidgets('a tick marks it done today and it stays', (tester) async {
      final store = paneStore();
      addRoutine(store, 'Clean filter', since: wednesday.adding(days: -9));
      await pumpPane(tester, unscheduled(store));

      await tester.tap(checkFinder('clean-filter'));
      await tester.pumpAndSettle();
      expect(store.routineDoneToday('clean-filter'), isTrue);
      expect(find.text('Clean filter'), findsOneWidget);
      expect(find.text('7 days left'), findsOneWidget);
      expect(find.textContaining('Done today'), findsNothing);
      expect(barOf(tester, 'clean-filter').fraction, 0);

      await tester.tap(checkFinder('clean-filter'));
      await tester.pumpAndSettle();
      expect(store.routineDoneToday('clean-filter'), isFalse);
      expect(find.text('Late 2 days'), findsOneWidget);
    });

    testWidgets('its menu has no Move To', (tester) async {
      final store = paneStore();
      addRoutine(store, 'Water plants');
      await pumpPane(tester, unscheduled(store));
      await rightClick(tester, rowFinder('water-plants'));
      expect(find.text('Move To'), findsNothing);
      expect(find.text('Mark Done'), findsOneWidget);
    });
  });

  group('the Task panel', () {
    Future<AppStore> pumpPanel(WidgetTester tester) async {
      final store = paneStore();
      addTask(store, 'Water plants', id: 'plants', due: '2026-10-09');
      store.selectedTaskId = 'plants';
      await pumpPane(tester, host(store), size: inspectorSize);
      return store;
    }

    testWidgets('the switch makes a routine and hides Due and Repeat', (
      tester,
    ) async {
      final store = await pumpPanel(tester);
      expect(find.text('Repeat'), findsWidgets);
      expect(byKey('inspector-routine-every'), findsNothing);

      await tapKey(tester, 'inspector-routine');
      final t = store.task('plants')!;
      expect(t.routine, RoutineRule(every: 1, unit: RoutineUnit.weeks));
      expect(t.routineSince, wednesday);
      expect(t.due, isNull);
      expect(byKey('inspector-repeat'), findsNothing);
      expect(byKey('inspector-due-add'), findsNothing);
      expect(byKey('inspector-plan'), findsNothing);
      expect(find.text('Not done yet'), findsOneWidget);
      expect(find.text('7 days left'), findsOneWidget);

      await tapKey(tester, 'inspector-routine-more');
      expect(store.task('plants')!.routine!.every, 2);
      await pick(tester, 'inspector-routine-unit', 'months');
      expect(
        store.task('plants')!.routine,
        RoutineRule(every: 2, unit: RoutineUnit.months),
      );

      store.toggleDone(taskId: 'plants');
      await tester.pumpAndSettle();
      expect(find.text('Done once, last on 7 Oct'), findsOneWidget);

      await tapKey(tester, 'inspector-routine');
      expect(store.task('plants')!.isRoutine, isFalse);
      expect(byKey('inspector-repeat'), findsOneWidget);
    });
  });
}
