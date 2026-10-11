import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/tasks/notice_cards.dart';
import 'package:grove/ui/tasks/quick_add_field.dart';
import 'package:grove/ui/tasks/tasks_pane.dart';

import 'tasks_support.dart';

Widget today(AppStore store) =>
    TasksPane(store: store, mode: TasksPaneMode.today);

Widget unscheduled(AppStore store) =>
    TasksPane(store: store, mode: TasksPaneMode.unscheduled);

final quickAdd = find.byKey(const ValueKey('quick-add'));

/// An open task with a time block yesterday. The card of yesterday lists it.
void addYesterday(AppStore store, String title, {int minute = 540}) {
  final yesterday = wednesday.adding(days: -1);
  final task = addTask(store, title, day: yesterday);
  store.repos.events.save(
    EventItem(
      title: title,
      start: WallTime(day: yesterday, minute: minute),
      end: WallTime(day: yesterday, minute: minute + 60),
      kind: EventKind.block,
      taskId: task.id,
    ),
  );
}

void main() {
  group('the list of today', () {
    testWidgets('an empty day says so', (tester) async {
      final store = paneStore();
      await pumpPane(tester, today(store));

      expect(find.text('Tasks'), findsOneWidget);
      expect(find.text('Nothing planned'), findsOneWidget);
      expect(find.text('Today'), findsWidgets);
      expect(
        find.text('Nothing planned. Add a task above, or drop one here.'),
        findsOneWidget,
      );
    });

    testWidgets('Return in the quick-add field adds a task to today', (
      tester,
    ) async {
      final store = paneStore();
      await pumpPane(tester, today(store));

      await typeLine(tester, quickAdd, 'Buy milk');

      final tasks = store.openTasks(TaskPlacement.day(wednesday));
      expect(tasks.map((t) => t.title), ['Buy milk']);
      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.text('0 of 1 done'), findsOneWidget);
      expect(store.toast, isNull);
    });

    testWidgets('a date in the text sends the task there and says so', (
      tester,
    ) async {
      final store = paneStore();
      await pumpPane(tester, today(store));

      await typeLine(tester, quickAdd, 'Call mum tomorrow');

      final tomorrow = wednesday.adding(days: 1);
      expect(store.openTasks(TaskPlacement.day(tomorrow)), hasLength(1));
      expect(store.toast, 'Added to Tomorrow');
      expect(find.text('Call mum'), findsNothing);
      await endToast(tester);
    });

    testWidgets('the field shows what the parser understood', (tester) async {
      final store = paneStore();
      await pumpPane(tester, today(store));

      expect(find.text(QuickAddField.hint), findsNothing);
      await tester.tap(quickAdd);
      await tester.pump();
      expect(find.text(QuickAddField.hint), findsOneWidget);

      await tester.enterText(
        find.descendant(of: quickAdd, matching: find.byType(EditableText)),
        'Call mum 6pm for 20m !2',
      );
      await tester.pump();
      expect(find.text(QuickAddField.hint), findsNothing);
      expect(find.text('20m'), findsOneWidget);
    });

    testWidgets('a click on the check box marks the task as done', (
      tester,
    ) async {
      final store = paneStore();
      addTask(store, 'Buy milk');
      addTask(store, 'Call the bank', sort: 1);
      await pumpPane(tester, today(store));
      expect(find.text('0 of 2 done'), findsOneWidget);

      await tester.tap(checkFinder('buy-milk'));
      await tester.pumpAndSettle();

      expect(store.task('buy-milk')!.isDone, isTrue);
      expect(find.text('1 of 2 done'), findsOneWidget);
      expect(find.text('Done · 1'), findsOneWidget);
      // The done list is closed at first.
      expect(find.text('Buy milk'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('done-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Buy milk'), findsOneWidget);

      await tester.tap(checkFinder('buy-milk'));
      await tester.pumpAndSettle();
      expect(store.task('buy-milk')!.isDone, isFalse);
      expect(find.text('Done · 1'), findsNothing);
    });

    testWidgets('a click on a row chooses the task, a second click lets go', (
      tester,
    ) async {
      final store = paneStore();
      addTask(store, 'Buy milk');
      await pumpPane(tester, today(store));

      await tester.tap(find.text('Buy milk'));
      await tester.pumpAndSettle();
      expect(store.selectedTaskId, 'buy-milk');

      await tester.tap(find.text('Buy milk'));
      await tester.pumpAndSettle();
      expect(store.selectedTaskId, isNull);
    });

    testWidgets('the labels of a row', (tester) async {
      final store = paneStore();
      addTask(
        store,
        'Write the report',
        estimateMin: 90,
        due: '2026-10-09',
        notes: 'Two pages.',
      );
      store.setTags(taskId: 'write-the-report', to: ['work']);
      await pumpPane(tester, today(store));

      expect(find.text('1h 30m'), findsOneWidget);
      expect(find.text('due Fri 9 Oct'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('#work'), findsOneWidget);
    });

    testWidgets('the menu of a row moves the task', (tester) async {
      final store = paneStore();
      addTask(store, 'Buy milk');
      await pumpPane(tester, today(store));

      await rightClick(tester, rowFinder('buy-milk'));
      for (final line in [
        'Mark Done',
        'Move To',
        'Today',
        'Tomorrow',
        'This Week',
        'Next Week',
        'Inbox',
        'Someday',
        'Priority',
        'None',
        'Low',
        'Medium',
        'High',
        'Add Subtask',
        'Rename',
        'Delete',
      ]) {
        expect(find.textContaining(line), findsWidgets, reason: line);
      }

      await tester.tap(find.text('Someday'));
      await tester.pumpAndSettle();
      expect(store.task('buy-milk')!.bucket, TaskBucket.someday);
      expect(find.text('Buy milk'), findsNothing);
    });

    testWidgets('the menu sets the priority', (tester) async {
      final store = paneStore();
      addTask(store, 'Buy milk');
      await pumpPane(tester, today(store));

      await rightClick(tester, rowFinder('buy-milk'));
      await tester.tap(find.text('High'));
      await tester.pumpAndSettle();
      expect(store.task('buy-milk')!.priority, 3);

      await rightClick(tester, rowFinder('buy-milk'));
      expect(find.text('✓ High'), findsOneWidget);
    });

    testWidgets('the menu renames and deletes', (tester) async {
      final store = paneStore();
      addTask(store, 'Buy milk');
      await pumpPane(tester, today(store));

      await rightClick(tester, rowFinder('buy-milk'));
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('rename-buy-milk'));
      expect(field, findsOneWidget);
      await tester.enterText(
        find.descendant(of: field, matching: find.byType(EditableText)),
        'Buy oat milk',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(store.task('buy-milk')!.title, 'Buy oat milk');
      expect(field, findsNothing);

      await rightClick(tester, rowFinder('buy-milk'));
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(store.task('buy-milk'), isNull);
      store.undo();
      await tester.pumpAndSettle();
      expect(find.text('Buy oat milk'), findsOneWidget);
      await endToast(tester);
    });

    testWidgets('subtasks: add, count, check and hide', (tester) async {
      final store = paneStore();
      addTask(store, 'Plan the trip');
      await pumpPane(tester, today(store));
      final field = find.byKey(const ValueKey('add-subtask-plan-the-trip'));
      expect(field, findsNothing);

      await rightClick(tester, rowFinder('plan-the-trip'));
      await tester.tap(find.text('Add Subtask'));
      await tester.pumpAndSettle();
      expect(field, findsOneWidget);

      await typeLine(tester, field, 'Book the train');
      await typeLine(tester, field, 'Find a room');
      final subs = store.subtasks('plan-the-trip');
      expect(subs.map((s) => s.title), ['Book the train', 'Find a room']);
      expect(find.text('0/2'), findsOneWidget);

      await tester.tap(checkFinder(subs.first.id));
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsOneWidget);
      expect(store.task(subs.first.id)!.isDone, isTrue);

      await tester.tap(find.byKey(const ValueKey('subtasks-plan-the-trip')));
      await tester.pumpAndSettle();
      expect(find.text('Book the train'), findsNothing);
      expect(find.text('1/2'), findsOneWidget);
    });

    testWidgets('a row dropped on a row goes in front of it', (tester) async {
      final store = paneStore();
      addTask(store, 'One', sort: 1);
      addTask(store, 'Two', sort: 2);
      addTask(store, 'Three', sort: 3);
      await pumpPane(tester, today(store));

      await dragOnto(tester, find.text('Three'), find.text('One'));

      expect(
        store.openTasks(TaskPlacement.day(wednesday)).map((t) => t.title),
        ['Three', 'One', 'Two'],
      );
    });

    testWidgets('a row dropped on the end of the list goes last', (
      tester,
    ) async {
      final store = paneStore();
      addTask(store, 'One', sort: 1);
      addTask(store, 'Two', sort: 2);
      addTask(store, 'Three', sort: 3);
      await pumpPane(tester, today(store));

      final last = tester.getRect(rowFinder('three'));
      await dragOnto(
        tester,
        find.text('One'),
        rowFinder('three'),
        toOffset: Offset(0, last.height / 2 + 11),
      );

      expect(
        store.openTasks(TaskPlacement.day(wednesday)).map((t) => t.title),
        ['Two', 'Three', 'One'],
      );
    });

    testWidgets('a finger drags a row after a long press', (tester) async {
      final store = paneStore();
      addTask(store, 'One', sort: 1);
      addTask(store, 'Two', sort: 2);
      await pumpPane(tester, today(store));

      final from = tester.getCenter(find.text('Two'));
      final to = tester.getCenter(find.text('One'));
      final gesture = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 600));
      for (var i = 1; i <= 8; i++) {
        await gesture.moveTo(Offset.lerp(from, to, i / 8)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        store.openTasks(TaskPlacement.day(wednesday)).map((t) => t.title),
        ['Two', 'One'],
      );
    });

    testWidgets('the card of yesterday moves the open tasks to today', (
      tester,
    ) async {
      final store = paneStore();
      addYesterday(store, 'Old one');
      addYesterday(store, 'Old two', minute: 600);
      await pumpPane(tester, today(store));

      expect(find.text(RollOverCard.title(2)), findsOneWidget);
      expect(find.text('Old one'), findsOneWidget);

      await tester.tap(find.text('Move to today'));
      await tester.pumpAndSettle();

      expect(find.text(RollOverCard.title(2)), findsNothing);
      expect(store.openTasks(TaskPlacement.day(wednesday)), hasLength(2));
    });

    testWidgets('"Leave" closes the card of yesterday', (tester) async {
      final store = paneStore();
      addYesterday(store, 'Old one');
      await pumpPane(tester, today(store));
      expect(find.text('1 thing from yesterday'), findsOneWidget);

      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();

      expect(find.text('1 thing from yesterday'), findsNothing);
      expect(store.openTasks(TaskPlacement.day(wednesday)), isEmpty);
    });

    testWidgets('a phone-wide panel has no overflow', (tester) async {
      final store = paneStore();
      addTask(
        store,
        'A task with a very long title that needs more than one line to fit',
        estimateMin: 90,
        due: '2026-10-09',
        notes: 'x',
        priority: 3,
        color: 'teal',
      );
      await pumpPane(tester, today(store), size: const Size(300, 500));
      expect(tester.takeException(), isNull);
    });
  });

  group('the unscheduled list', () {
    testWidgets('an empty list says so', (tester) async {
      final store = paneStore();
      await pumpPane(tester, unscheduled(store));

      expect(find.text('Nothing waiting'), findsOneWidget);
      expect(find.text('Overdue'), findsNothing);
      expect(
        find.text('Nothing waiting. Every task has a day.'),
        findsOneWidget,
      );
    });

    testWidgets('late tasks come first, then the tasks with no day', (
      tester,
    ) async {
      final store = paneStore();
      addTask(store, 'Late one', day: wednesday.adding(days: -2));
      addTask(store, 'No day', bucket: TaskBucket.inbox);
      addTask(store, 'One day', bucket: TaskBucket.someday);
      addTask(store, 'Planned today');
      await pumpPane(tester, unscheduled(store));

      expect(find.text('3 waiting'), findsOneWidget);
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Late one'), findsOneWidget);
      expect(find.text('Mon 5 Oct'), findsOneWidget);
      expect(find.text('No day'), findsOneWidget);
      expect(find.text('Someday'), findsOneWidget);
      expect(find.text('Planned today'), findsNothing);
      final late = tester.getTopLeft(find.text('Late one')).dy;
      final noDay = tester.getTopLeft(find.text('No day')).dy;
      expect(late, lessThan(noDay));
    });

    testWidgets('quick-add puts the task in the inbox', (tester) async {
      final store = paneStore();
      await pumpPane(tester, unscheduled(store));

      await typeLine(tester, quickAdd, 'Buy milk');

      expect(store.openTasks(TaskPlacement.inbox).map((t) => t.title), [
        'Buy milk',
      ]);
      expect(find.text('1 waiting'), findsOneWidget);
      await endToast(tester);
    });

    testWidgets('rows take no drops here', (tester) async {
      final store = paneStore();
      addTask(store, 'One', bucket: TaskBucket.inbox, sort: 1);
      addTask(store, 'Two', bucket: TaskBucket.inbox, sort: 2);
      await pumpPane(tester, unscheduled(store));
      final before = store
          .unscheduledTasks(today: wednesday)
          .unscheduled
          .map((t) => t.title)
          .toList();

      await dragOnto(tester, find.text('Two'), find.text('One'));

      expect(
        store
            .unscheduledTasks(today: wednesday)
            .unscheduled
            .map((t) => t.title),
        before,
      );
    });

    testWidgets('the tasks checked off today can be opened again', (
      tester,
    ) async {
      final store = paneStore();
      addTask(store, 'No day', bucket: TaskBucket.inbox);
      await pumpPane(tester, unscheduled(store));

      await tester.tap(checkFinder('no-day'));
      await tester.pumpAndSettle();
      expect(find.text('Done today · 1'), findsOneWidget);
      expect(find.text('Nothing waiting'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('done-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(checkFinder('no-day'));
      await tester.pumpAndSettle();
      expect(store.task('no-day')!.isDone, isFalse);
      expect(find.text('1 waiting'), findsOneWidget);
    });
  });
}
