// A block turns from a task into an activity, and back: a line of the block
// menu, and the Task · Activity chips of the event editor (owner,
// 2026-10-27). The chips of the task panel: task_inspector_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/calendar/event_editor.dart';

import 'planner_support.dart';

Finder menuLine(String label) =>
    find.widgetWithText(PopupMenuItem<VoidCallback>, label);

Finder key(String name) => find.byKey(ValueKey(name));

/// A task block from 12:00 to 13:00 on Wednesday.
PlannerBlock addTaskBlock(AppStore store, String title) {
  store
    ..createFromDraft(
      title: title,
      day: wednesday,
      start: 12 * 60,
      end: 13 * 60,
      asEvent: false,
    )
    ..selection = {};
  return blockNamed(store, title);
}

/// An activity from 12:00 to 13:00 on Wednesday.
PlannerBlock addActivity(AppStore store, String title) {
  store
    ..createFromDraft(
      title: title,
      day: wednesday,
      start: 12 * 60,
      end: 13 * 60,
      asEvent: false,
      asActivity: true,
    )
    ..selection = {};
  return blockNamed(store, title);
}

Future<void> openMenu(WidgetTester tester) =>
    rightClick(tester, pointAt(tester, wednesday, 12 * 60 + 30));

void main() {
  group('the block menu', () {
    testWidgets('"Turn into Activity" on a task block', (tester) async {
      final store = plannerStore();
      final block = addTaskBlock(store, 'Write report');
      await pumpPlanner(tester, store);

      await openMenu(tester);
      expect(menuLine('Turn into Task'), findsNothing);
      await tester.tap(menuLine('Turn into Activity'));
      await tester.pumpAndSettle();

      expect(store.event(block.id)!.kind, EventKind.activity);
      expect(store.repos.tasks.all(), isEmpty);
      expect(blockFinder(block.id), findsOneWidget);
      expect(blockNamed(store, 'Write report').isActivity, isTrue);
    });

    testWidgets('"Turn into Task" on an activity', (tester) async {
      final store = plannerStore();
      final block = addActivity(store, 'Lunch');
      await pumpPlanner(tester, store);

      await openMenu(tester);
      expect(menuLine('Turn into Activity'), findsNothing);
      await tester.tap(menuLine('Turn into Task'));
      await tester.pumpAndSettle();

      final e = store.event(block.id)!;
      expect(e.kind, EventKind.block);
      expect(store.task(e.taskId!)!.title, 'Lunch');
      expect(blockNamed(store, 'Lunch').isTaskBlock, isTrue);
    });

    testWidgets('a plain event has neither line', (tester) async {
      final store = plannerStore();
      store.createFromDraft(
        title: 'Call',
        day: wednesday,
        start: 12 * 60,
        end: 13 * 60,
        asEvent: true,
      );
      await pumpPlanner(tester, store);
      await openMenu(tester);
      expect(menuLine('Duration'), findsOneWidget);
      expect(menuLine('Turn into Activity'), findsNothing);
      expect(menuLine('Turn into Task'), findsNothing);
    });

    testWidgets('a task with subtasks asks first: Cancel keeps it', (
      tester,
    ) async {
      final store = plannerStore();
      final block = addTaskBlock(store, 'Write report');
      store.addSubtask(to: block.taskId!, title: 'Outline');
      await pumpPlanner(tester, store);

      await openMenu(tester);
      await tester.tap(menuLine('Turn into Activity'));
      await tester.pumpAndSettle();
      expect(key('kind-confirm'), findsOneWidget);
      expect(find.textContaining('1 subtask'), findsOneWidget);
      await tester.tap(key('kind-cancel'));
      await tester.pumpAndSettle();
      expect(store.event(block.id)!.kind, EventKind.block);
      expect(store.task(block.taskId!), isNotNull);

      await openMenu(tester);
      await tester.tap(menuLine('Turn into Activity'));
      await tester.pumpAndSettle();
      await tester.tap(key('kind-confirm'));
      await tester.pumpAndSettle();
      expect(store.event(block.id)!.kind, EventKind.activity);
      expect(store.repos.tasks.all(), isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('the event editor', () {
    testWidgets('an activity has the chips: Task makes it a task', (
      tester,
    ) async {
      final store = plannerStore();
      final block = addActivity(store, 'Lunch');
      await pumpPlanner(tester, store);
      await tester.tap(blockFinder(block.id));
      await tester.pumpAndSettle();
      expect(find.byType(EventEditor), findsOneWidget);
      expect(key('event-kind-task'), findsOneWidget);
      expect(key('event-kind-activity'), findsOneWidget);

      await tester.tap(key('event-kind-task'));
      await tester.pumpAndSettle();

      final e = store.event(block.id)!;
      expect(e.kind, EventKind.block);
      expect(store.task(e.taskId!)!.title, 'Lunch');
      expect(find.byType(EventEditor), findsNothing);
      expect(store.selectedTaskId, e.taskId);
    });

    testWidgets('a change that is not saved yet is saved first', (
      tester,
    ) async {
      final store = plannerStore();
      final block = addActivity(store, 'Lunch');
      await pumpPlanner(tester, store);
      await tester.tap(blockFinder(block.id));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: key('event-title'),
          matching: find.byType(EditableText),
        ),
        'Lunch with Ana',
      );
      await tester.pump();

      await tester.tap(key('event-kind-task'));
      await tester.pumpAndSettle();

      final e = store.event(block.id)!;
      expect(e.kind, EventKind.block);
      expect(store.task(e.taskId!)!.title, 'Lunch with Ana');
    });

    testWidgets('all day, not saved yet: it is saved, and nothing switches', (
      tester,
    ) async {
      final store = plannerStore();
      final block = addActivity(store, 'Lunch');
      await pumpPlanner(tester, store);
      await tester.tap(blockFinder(block.id));
      await tester.pumpAndSettle();
      await tester.tap(key('event-all-day'));
      await tester.pump();

      await tester.tap(key('event-kind-task'));
      await tester.pumpAndSettle();

      final e = store.event(block.id)!;
      expect(e.allDay, isTrue);
      expect(e.kind, EventKind.activity);
      expect(store.repos.tasks.all(), isEmpty);
      expect(find.byType(EventEditor), findsNothing);
      expect(store.toast, contains('cannot be a task'));
      // The toast goes away by itself.
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a plain event has no chips', (tester) async {
      final store = plannerStore();
      store.createFromDraft(
        title: 'Call',
        day: wednesday,
        start: 12 * 60,
        end: 13 * 60,
        asEvent: true,
      );
      final call = blockNamed(store, 'Call');
      await pumpPlanner(tester, store);
      await tester.tap(blockFinder(call.id));
      await tester.pumpAndSettle();
      expect(find.byType(EventEditor), findsOneWidget);
      expect(key('event-kind-task'), findsNothing);
    });
  });
}
