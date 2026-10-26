import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/planner/planner_grid.dart';
import 'package:grove/ui/tasks/tasks_pane.dart';

import '../planner/planner_support.dart';
import '../tasks/tasks_support.dart' show addTask, rowFinder;

final grid = find.byType(PlannerGrid);
final tasksPane = find.byType(TasksPane);

/// A finger drag: press and hold on `from`, then move to `to`. `to` is
/// read once the drag is on, so it can be on a part that only shows then.
/// With `lift` false the finger stays down at the end.
Future<TestGesture> fingerDrag(
  WidgetTester tester,
  Finder from,
  Offset Function() to, {
  bool lift = true,
}) async {
  final start = tester.getCenter(from);
  final gesture = await tester.startGesture(start);
  await tester.pump(const Duration(milliseconds: 600));
  // A first small step starts the drag.
  await gesture.moveTo(start + const Offset(0, 12));
  await tester.pump(const Duration(milliseconds: 16));
  final end = to();
  for (var i = 1; i <= 8; i++) {
    await gesture.moveTo(Offset.lerp(start, end, i / 8)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  if (lift) {
    await gesture.up();
    await tester.pumpAndSettle();
  }
  return gesture;
}

Offset Function() at(WidgetTester tester, int minute) =>
    () => pointAt(tester, wednesday, minute);

void main() {
  group('a phone', () {
    testWidgets('a held row of the Tasks panel takes the panel away; a drop '
        'on the grid makes a block and the panel stays closed', (tester) async {
      final store = plannerStore();
      addTask(store, 'Write report', id: 'report', bucket: TaskBucket.inbox);
      store.leftPane = LeftPane.tasks;
      await pumpPlanner(tester, store, size: phoneSize);
      expect(grid.hitTestable(), findsNothing);

      final gesture = await fingerDrag(
        tester,
        rowFinder('report'),
        at(tester, 11 * 60),
        lift: false,
      );
      expect(tasksPane.hitTestable(), findsNothing);
      expect(grid.hitTestable(), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
      final block = blockNamed(store, 'Write report');
      expect(block.taskId, 'report');
      expect(block.day, wednesday);
      expect(block.startMinute, 11 * 60);
      expect(store.leftPane, isNull);
      expect(grid.hitTestable(), findsOneWidget);
      await endToast(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a goal of the Goals panel drops on the grid', (tester) async {
      final store = plannerStore();
      final goal = store.addGoal(title: 'Read')!;
      store.leftPane = LeftPane.goals;
      await pumpPlanner(tester, store, size: phoneSize);

      await fingerDrag(
        tester,
        find.byKey(ValueKey('goal-${goal.id}')),
        at(tester, 11 * 60),
      );

      final event = store.repos.events.all().single;
      expect(event.goalId, goal.id);
      expect(event.start.day, wednesday);
      expect(store.leftPane, isNull);
      await endToast(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a subtask of the Goals panel drops on a block of its goal', (
      tester,
    ) async {
      final store = plannerStore()..leftPane = LeftPane.goals;
      final blockId = goalBlock(store);
      final goal = store.goals().single;
      store.addGoalSubtask(to: goal.id, title: 'Chapter 1');
      await pumpPlanner(tester, store, size: phoneSize);
      final sub = store.goalSubtasks(goal.id).single;
      final row = find.byKey(ValueKey('goal-subtask-${sub.id}'));
      if (row.hitTestable().evaluate().isEmpty) {
        await tester.tap(find.byKey(ValueKey('goal-${goal.id}')));
        await tester.pumpAndSettle();
      }

      await fingerDrag(
        tester,
        row,
        () => tester.getCenter(blockFinder(blockId)),
      );

      expect(store.goalSubtasks(goal.id).single.eventId, blockId);
      expect(store.leftPane, isNull);
      await endToast(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a drop on no place brings the panel back', (tester) async {
      final store = plannerStore();
      addTask(store, 'Write report', id: 'report', bucket: TaskBucket.inbox);
      store.leftPane = LeftPane.tasks;
      await pumpPlanner(tester, store, size: phoneSize);

      // The top strip of the window takes no drop.
      await fingerDrag(
        tester,
        rowFinder('report'),
        () => Offset(phoneSize.width / 2, 20),
      );

      expect(store.leftPane, LeftPane.tasks);
      expect(rowFinder('report').hitTestable(), findsOneWidget);
      expect(grid.hitTestable(), findsNothing);
      expect(store.task('report')!.planDate, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the panel comes back when the dragged row goes away', (
      tester,
    ) async {
      final store = plannerStore();
      addTask(store, 'Write report', id: 'report', bucket: TaskBucket.inbox);
      addTask(store, 'Call the bank', id: 'bank', bucket: TaskBucket.inbox);
      store.leftPane = LeftPane.tasks;
      await pumpPlanner(tester, store, size: phoneSize);

      final gesture = await fingerDrag(
        tester,
        rowFinder('report'),
        () => Offset(phoneSize.width / 2, 20),
        lift: false,
      );
      expect(tasksPane.hitTestable(), findsNothing);

      // For example a sync takes the task away.
      store.deleteTask('report');
      await tester.pump();
      await tester.pump();
      expect(rowFinder('bank').hitTestable(), findsOneWidget);
      expect(store.leftPane, LeftPane.tasks);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(rowFinder('bank').hitTestable(), findsOneWidget);
      await endToast(tester);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a desktop window keeps the panel during a drag', (tester) async {
    final store = plannerStore();
    addTask(store, 'Write report', id: 'report', bucket: TaskBucket.inbox);
    store.leftPane = LeftPane.tasks;
    await pumpPlanner(tester, store);

    final gesture = await fingerDrag(
      tester,
      rowFinder('report'),
      () => tester.getCenter(rowFinder('report')) + const Offset(0, 30),
      lift: false,
    );
    expect(tasksPane.hitTestable(), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(store.leftPane, LeftPane.tasks);
  });
}
