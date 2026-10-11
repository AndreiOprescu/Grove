import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/goals/goals_pane.dart';
import 'package:grove/ui/planner/planner_grid.dart';
import 'package:grove/ui/tasks/task_inspector.dart';
import 'package:grove/ui/tasks/tasks_pane.dart';

import '../planner/planner_support.dart';
import 'tasks_support.dart' show addTask, rowFinder;

/// A mouse drag from the middle of `from` to the point `to`.
Future<void> dragTo(WidgetTester tester, Finder from, Offset to) async {
  final start = tester.getCenter(from);
  final gesture = await tester.startGesture(
    start,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  for (var i = 1; i <= 8; i++) {
    await gesture.moveTo(Offset.lerp(start, to, i / 8)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

final inspector = find.byType(TaskInspector);

void main() {
  group('a desktop window', () {
    testWidgets('the Tasks panel lists the tasks with no time', (tester) async {
      final store = plannerStore();
      addTask(store, 'Write report', id: 'report', bucket: TaskBucket.inbox);
      store.leftPane = LeftPane.tasks;
      await pumpPlanner(tester, store);

      final pane = tester.widget<TasksPane>(find.byType(TasksPane));
      expect(pane.mode, TasksPaneMode.unscheduled);
      expect(rowFinder('report'), findsOneWidget);
      expect(find.byType(PlannerGrid), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Goals panel lists the goals', (tester) async {
      final store = plannerStore();
      store.addGoal(title: 'Read');
      store.leftPane = LeftPane.goals;
      await pumpPlanner(tester, store);

      expect(find.byType(GoalsPane), findsOneWidget);
      expect(find.text('0 / 5 h done'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a click on a task opens its panel at the right', (
      tester,
    ) async {
      final store = plannerStore();
      addTask(store, 'Write report', id: 'report', bucket: TaskBucket.inbox);
      store.leftPane = LeftPane.tasks;
      await pumpPlanner(tester, store);
      expect(inspector, findsNothing);

      await tester.tap(rowFinder('report'));
      await tester.pumpAndSettle();

      final panel = tester.getRect(inspector);
      expect(panel.width, TaskInspector.width);
      expect(panel.right, desktopSize.width - 16);
      // The panel of tasks and the planner stay.
      expect(find.byType(TasksPane), findsOneWidget);
      final grid = tester.getRect(find.byType(PlannerGrid));
      expect(grid.right, lessThanOrEqualTo(panel.left));
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('inspector-close')));
      await tester.pumpAndSettle();
      expect(inspector, findsNothing);
    });

    testWidgets('the planner keeps its place when the panel opens', (
      tester,
    ) async {
      final store = plannerStore();
      addTask(store, 'Write report', id: 'report');
      await pumpPlanner(tester, store);
      final before = gridState(tester);

      store.selectedTaskId = 'report';
      await tester.pumpAndSettle();
      expect(inspector, findsOneWidget);
      expect(gridState(tester), same(before));

      store.selectedTaskId = null;
      await tester.pumpAndSettle();
      expect(gridState(tester), same(before));
    });

    testWidgets('a task dragged from the panel onto a day gets a block', (
      tester,
    ) async {
      final store = plannerStore();
      addTask(store, 'Write report', id: 'report', bucket: TaskBucket.inbox);
      store.leftPane = LeftPane.tasks;
      await pumpPlanner(tester, store);

      await dragTo(
        tester,
        rowFinder('report'),
        pointAt(tester, wednesday, 11 * 60),
      );

      final block = blockNamed(store, 'Write report');
      expect(block.taskId, 'report');
      expect(block.day, wednesday);
      expect(store.task('report')!.planDate, wednesday);
      await endToast(tester);
    });

    testWidgets('a goal dragged from the panel onto a day gets a block', (
      tester,
    ) async {
      final store = plannerStore();
      final goal = store.addGoal(title: 'Read')!;
      store.leftPane = LeftPane.goals;
      await pumpPlanner(tester, store);

      await dragTo(
        tester,
        find.byKey(ValueKey('goal-${goal.id}')),
        pointAt(tester, wednesday, 11 * 60),
      );

      final event = store.repos.events.all().single;
      expect(event.goalId, goal.id);
      expect(event.start.day, wednesday);
      expect(find.text('Nothing planned yet'), findsNothing);
      await endToast(tester);
    });

    testWidgets('the Today screen shows the panel of the task too', (
      tester,
    ) async {
      final store = plannerStore();
      addTask(store, 'Write report', id: 'report');
      store
        ..screen = Screen.today
        ..selectedTaskId = 'report';
      await pumpPlanner(tester, store);
      expect(inspector, findsOneWidget);
      expect(find.byType(PlannerGrid), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('a phone', () {
    testWidgets('the panel of the task takes the place of the Tasks panel', (
      tester,
    ) async {
      final store = plannerStore();
      addTask(store, 'Write report', id: 'report', bucket: TaskBucket.inbox);
      store.leftPane = LeftPane.tasks;
      await pumpPlanner(tester, store, size: phoneSize);
      expect(rowFinder('report').hitTestable(), findsOneWidget);

      await tester.tap(rowFinder('report'));
      await tester.pumpAndSettle();
      expect(inspector, findsOneWidget);
      expect(rowFinder('report').hitTestable(), findsNothing);
      expect(tester.getRect(inspector).width, phoneSize.width - 24);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('inspector-close')));
      await tester.pumpAndSettle();
      expect(inspector, findsNothing);
      expect(rowFinder('report').hitTestable(), findsOneWidget);
    });

    testWidgets('the panel of the task takes the place of the planner', (
      tester,
    ) async {
      final store = plannerStore();
      addTask(store, 'Write report', id: 'report');
      await pumpPlanner(tester, store, size: phoneSize);
      final before = gridState(tester);

      store.selectedTaskId = 'report';
      await tester.pumpAndSettle();
      expect(inspector, findsOneWidget);
      expect(find.byType(PlannerGrid).hitTestable(), findsNothing);
      expect(tester.getRect(inspector).width, phoneSize.width - 24);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('inspector-close')));
      await tester.pumpAndSettle();
      expect(gridState(tester), same(before));
      expect(find.byType(PlannerGrid).hitTestable(), findsOneWidget);
    });

    testWidgets('the Goals panel fills the screen', (tester) async {
      final store = plannerStore();
      store.addGoal(title: 'Read');
      store.leftPane = LeftPane.goals;
      await pumpPlanner(tester, store, size: phoneSize);
      expect(find.byType(GoalsPane), findsOneWidget);
      expect(find.byType(PlannerGrid), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
