import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/tasks/notice_cards.dart';
import 'package:grove/ui/tasks/quick_add_field.dart';
import 'package:grove/ui/tasks/task_row.dart';
import 'package:grove/ui/tasks/task_section.dart';
import 'package:grove/ui/tasks/task_widgets.dart';
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

/// A store on a new database: the three sample tasks and the welcome card.
AppStore firstRunStore([FakeNotifier? notifier]) {
  final repos = Repos(Database.inMemory());
  FirstRun.seedIfNew(repos, today: wednesday);
  return makeStore(
    repos: repos,
    notifier: notifier,
    prefs: MemoryPrefs()..set('appearance.motion', false),
    clock: WallTime(day: wednesday, minute: 10 * 60),
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

    testWidgets('a new task is kept when the person clicks away', (
      tester,
    ) async {
      final store = paneStore();
      await pumpPane(tester, today(store));
      final field = find.descendant(
        of: quickAdd,
        matching: find.byType(EditableText),
      );

      // No Return: the text is typed, then a click lands next to the field.
      await tester.tap(quickAdd);
      await tester.pump();
      await tester.enterText(field, 'Buy milk');
      await tester.pump();
      expect(store.openTasks(TaskPlacement.day(wednesday)), isEmpty);
      await tester.tap(find.text('Tasks'), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      expect(tester.widget<EditableText>(field).focusNode.hasFocus, isFalse);
      expect(titles(store.openTasks(TaskPlacement.day(wednesday))), [
        'Buy milk',
      ]);
      expect(tester.widget<EditableText>(field).controller.text, isEmpty);
      expect(
        rowFinder(store.openTasks(TaskPlacement.day(wednesday)).single.id),
        findsOneWidget,
      );
    });

    testWidgets('a click away from an empty field adds no task', (
      tester,
    ) async {
      final store = paneStore();
      await pumpPane(tester, today(store));

      await tester.tap(quickAdd);
      await tester.pump();
      await tester.enterText(
        find.descendant(of: quickAdd, matching: find.byType(EditableText)),
        '   ',
      );
      await tester.pump();
      await tester.tap(find.text('Tasks'), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      expect(store.openTasks(TaskPlacement.day(wednesday)), isEmpty);
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

    testWidgets('the chips of a row: its list, its time block and "Repeats"', (
      tester,
    ) async {
      final store = paneStore();
      store.repos.lists.save(ListItem(id: 'work', name: 'Work'));
      final task = addTask(store, 'Write the report');
      store.repos.tasks.save(
        task.copyWith(
          listId: 'work',
          recurrence: RecurrenceRule(freq: Freq.weekly),
        ),
      );
      store.repos.events.save(
        EventItem(
          title: 'Write the report',
          start: WallTime(day: wednesday, minute: 14 * 60),
          end: WallTime(day: wednesday, minute: 15 * 60 + 30),
          kind: EventKind.block,
          taskId: task.id,
        ),
      );
      addTask(store, 'Buy milk', sort: 1);
      await pumpPane(tester, today(store));

      Finder chip(String id, String text) => find.descendant(
        of: rowFinder(id),
        matching: find.widgetWithText(TaskChip, text),
      );
      IconData? icon(String text) =>
          tester.widget<TaskChip>(chip(task.id, text)).icon;
      expect(icon('Work'), Icons.folder_outlined);
      expect(icon('14:00–15:30'), Icons.schedule);
      expect(icon('Repeats'), Icons.repeat);
      // A plain task has none of the three.
      expect(
        find.descendant(
          of: rowFinder('buy-milk'),
          matching: find.byType(TaskChip),
        ),
        findsNothing,
      );
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

    testWidgets('the welcome card: "Got it" closes it and keeps the samples', (
      tester,
    ) async {
      final fake = FakeNotifier(status: NotifyAuthorization.notAsked);
      final store = firstRunStore(fake);
      await pumpPane(tester, today(store));
      expect(find.byType(WelcomeCard), findsOneWidget);
      expect(find.text('Welcome to Grove'), findsOneWidget);
      expect(find.byType(TaskRow), findsNWidgets(3));

      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();

      expect(find.byType(WelcomeCard), findsNothing);
      expect(find.text('Welcome to Grove'), findsNothing);
      expect(find.byType(TaskRow), findsNWidgets(3));
      expect(store.repos.tasks.all(), hasLength(3));
      // The card stays closed for a new store on the same data.
      expect(FirstRun.welcomeVisible(store.repos), isFalse);
      // Grove asks for notifications after the card, not before.
      await tester.runAsync(() => store.welcomeAsk!);
      expect(fake.asked, 1);
    });

    testWidgets('the welcome card: "Remove samples" closes it and deletes the '
        'samples, and undo brings them back', (tester) async {
      final store = firstRunStore(FakeNotifier());
      addTask(store, 'Mine');
      await pumpPane(tester, today(store));
      expect(find.byType(WelcomeCard), findsOneWidget);
      expect(find.byType(TaskRow), findsNWidgets(4));

      await tester.tap(find.text('Remove samples'));
      await tester.pumpAndSettle();

      expect(find.byType(WelcomeCard), findsNothing);
      expect(find.byType(TaskRow), findsOneWidget);
      expect(find.text('Mine'), findsOneWidget);
      expect(titles(store.repos.tasks.all()), ['Mine']);
      expect(store.undoName, 'Remove Samples');

      store.undo();
      await tester.pumpAndSettle();
      expect(find.byType(TaskRow), findsNWidgets(4));
      expect(find.byType(WelcomeCard), findsNothing);
      // The message of the undo goes away after a moment.
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('each button of the panel has a label for a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final store = firstRunStore();
      addYesterday(store, 'Old one');
      addTask(store, 'Plan the trip', sort: -1);
      store.repos.tasks.save(
        TaskItem(
          id: 'book',
          title: 'Book the train',
          bucket: TaskBucket.day,
          planDate: wednesday,
          parentId: 'plan-the-trip',
        ),
      );
      final done = addTask(store, 'Pay rent');
      store.toggleDone(taskId: done.id);
      await pumpPane(tester, today(store), size: const Size(320, 1400));
      final pane = find.byType(TasksPane);

      expect(
        tester.getSemantics(checkFinder('plan-the-trip')),
        isSemantics(
          label: 'Mark Plan the trip as done',
          isButton: true,
          hasCheckedState: true,
          isChecked: false,
          hasTapAction: true,
        ),
      );
      var labels = buttonLabels(tester, pane);
      expect(
        labels,
        containsAll([
          'Got it',
          'Remove samples',
          'Move to today',
          'Leave',
          'Mark Plan the trip as done',
          'Show subtasks',
          'Done · 1',
        ]),
      );
      expect(labels, everyElement(isNotEmpty));

      // The open parts: the subtasks and the done tasks.
      await tester.tap(find.bySemanticsLabel('Show subtasks'));
      await tester.tap(find.bySemanticsLabel('Done · 1'));
      await tester.pumpAndSettle();
      labels = buttonLabels(tester, pane);
      expect(
        labels,
        containsAll([
          'Hide subtasks',
          'Mark Book the train as done',
          'Mark Pay rent as not done',
        ]),
      );
      expect(labels, everyElement(isNotEmpty));
      expect(
        tester.getSemantics(checkFinder('pay-rent')),
        isSemantics(
          label: 'Mark Pay rent as not done',
          isButton: true,
          hasCheckedState: true,
          isChecked: true,
        ),
      );
      // The field says what it is for.
      expect(find.bySemanticsLabel('Add a task…'), findsOneWidget);
      // Nothing that can be pressed is read with no name.
      expect(unnamedPresses(tester, pane), isEmpty);
      handle.dispose();
    });

    testWidgets('the buttons of the unscheduled list have labels too', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final store = paneStore();
      addTask(store, 'Late one', day: wednesday.adding(days: -2));
      addTask(store, 'Some day', bucket: TaskBucket.inbox);
      final done = addTask(store, 'Pay rent');
      store.toggleDone(taskId: done.id);
      await pumpPane(tester, unscheduled(store));

      final labels = buttonLabels(tester, find.byType(TasksPane));
      expect(
        labels,
        containsAll([
          'Mark Late one as done',
          'Mark Some day as done',
          'Done today · 1',
        ]),
      );
      expect(labels, everyElement(isNotEmpty));
      expect(unnamedPresses(tester, find.byType(TasksPane)), isEmpty);
      handle.dispose();
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

  group('the list of tomorrow', () {
    final thursday = wednesday.adding(days: 1);
    Widget tomorrow(AppStore store) =>
        TasksPane(store: store, mode: TasksPaneMode.today, day: thursday);
    Finder inDay(Finder what) => find.descendant(
      of: find.byKey(const ValueKey('part-day')),
      matching: what,
    );

    testWidgets('it shows the tasks of tomorrow under "Tomorrow"', (
      tester,
    ) async {
      final store = paneStore();
      addTask(store, 'Buy milk');
      addTask(store, 'Pack the bag', day: thursday);
      addTask(store, 'Print the ticket', day: thursday, sort: 1);
      store.toggleDone(taskId: 'print-the-ticket');
      await pumpPane(tester, tomorrow(store));

      expect(inDay(find.text('Tomorrow')), findsOneWidget);
      expect(inDay(find.text('Today')), findsNothing);
      expect(rowFinder('pack-the-bag'), findsOneWidget);
      expect(rowFinder('buy-milk'), findsNothing);
      // the count and the bar are of tomorrow
      expect(find.text('1 of 2 done'), findsOneWidget);
      expect(find.text('Done · 1'), findsOneWidget);
    });

    testWidgets('Return in the quick-add field adds a task to tomorrow', (
      tester,
    ) async {
      final store = paneStore();
      await pumpPane(tester, tomorrow(store));

      await typeLine(tester, quickAdd, 'Buy milk');

      final tasks = store.openTasks(TaskPlacement.day(thursday));
      expect(tasks.map((t) => t.title), ['Buy milk']);
      expect(store.openTasks(TaskPlacement.day(wednesday)), isEmpty);
      expect(rowFinder(tasks.single.id), findsOneWidget);
      // the task is in the list in view, so no message says where it went
      expect(store.toast, isNull);
    });

    testWidgets('a time with no day is a time tomorrow, and the field says '
        'so before Return', (tester) async {
      final store = paneStore();
      await pumpPane(tester, tomorrow(store));

      await tester.tap(quickAdd);
      await tester.pump();
      await tester.enterText(
        find.descendant(of: quickAdd, matching: find.byType(EditableText)),
        'Call Ana 3pm',
      );
      await tester.pump();
      expect(find.text('Thu 8 Oct'), findsOneWidget);
      expect(find.text('Wed 7 Oct'), findsNothing);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final task = store.openTasks(TaskPlacement.day(thursday)).single;
      expect(task.title, 'Call Ana');
      final block = store.blocks(DayRange.single(thursday)).single;
      expect(block.taskId, task.id);
      expect(block.startMinute, 15 * 60);
      expect(store.blocks(DayRange.single(wednesday)), isEmpty);
      expect(store.toast, isNull);
    });

    testWidgets('with no words typed, the field names the day', (tester) async {
      final store = paneStore();
      await pumpPane(tester, tomorrow(store));
      await tester.tap(quickAdd);
      await tester.pump();
      await tester.enterText(
        find.descendant(of: quickAdd, matching: find.byType(EditableText)),
        'Buy milk',
      );
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(QuickAddField),
          matching: find.text('Tomorrow'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the card of yesterday is a card of today only', (
      tester,
    ) async {
      final store = paneStore();
      addYesterday(store, 'Old report');
      await pumpPane(tester, today(store));
      expect(find.byType(RollOverCard), findsOneWidget);

      await pumpPane(tester, tomorrow(store));
      expect(find.byType(RollOverCard), findsNothing);
      expect(find.byKey(const ValueKey('card-yesterday')), findsNothing);
    });

    testWidgets('the welcome card is a card of today only', (tester) async {
      final repos = Repos(Database.inMemory());
      FirstRun.seedIfNew(repos, today: wednesday);
      final store = makeStore(
        repos: repos,
        prefs: MemoryPrefs()..set('appearance.motion', false),
        clock: WallTime(day: wednesday, minute: 10 * 60),
      );
      await pumpPane(tester, today(store));
      expect(find.byType(WelcomeCard), findsOneWidget);

      await pumpPane(tester, tomorrow(store));
      expect(find.byType(WelcomeCard), findsNothing);
    });

    testWidgets('a due day is still named from the real today', (tester) async {
      final store = paneStore();
      addTask(store, 'Pack the bag', day: thursday, due: '2026-10-08');
      addTask(store, 'Send the form', day: thursday, due: '2026-10-06');
      await pumpPane(tester, tomorrow(store));
      // Thursday is "tomorrow" and Tuesday is "yesterday": the list of
      // tomorrow does not move the day the words count from
      expect(find.text('due Tomorrow'), findsOneWidget);
      expect(find.text('due Yesterday'), findsOneWidget);
      expect(find.text('due Today'), findsNothing);
    });

    testWidgets('the text of the panel sits on whole pixels', (tester) async {
      final store = paneStore();
      addTask(store, 'Pack the bag', day: thursday);
      await pumpPane(tester, tomorrow(store));
      expect(textOffPixels(tester), isEmpty);
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

  // The list builds the rows in or near the view, and no others. With all
  // rows built, a scroll frame of 1 000 tasks took about 3 ms.
  group('a long list', () {
    testWidgets('with 1 000 tasks only the rows near the view are built', (
      tester,
    ) async {
      final store = paneStore();
      addMany(store, 1000);
      await pumpPane(tester, unscheduled(store));

      expect(find.text('1000 waiting'), findsOneWidget);
      expect(find.text('Task 0'), findsOneWidget);
      expect(find.text('Task 999'), findsNothing);
      // The panel is 570 points high and a row about 40. About 12 rows are
      // in view, and some more wait just under the edge.
      expect(builtRows(tester), inInclusiveRange(10, 40));
    });

    testWidgets('the list goes to its last row, and few rows are built there '
        'too', (tester) async {
      final store = paneStore();
      addMany(store, 1000);
      await pumpPane(tester, unscheduled(store));

      final position = listPosition(tester);
      for (
        var i = 0;
        i < 400 && find.text('Task 999').evaluate().isEmpty;
        i++
      ) {
        position.jumpTo(position.pixels + 400);
        await tester.pump();
      }
      // The length of a lazy list is a guess until its end is built.
      for (var i = 0; i < 3; i++) {
        position.jumpTo(position.maxScrollExtent);
        await tester.pump();
      }
      expect(position.pixels, position.maxScrollExtent);
      expect(position.pixels, greaterThan(30000));

      expect(find.text('Task 999'), findsOneWidget);
      expect(find.text('Task 0'), findsNothing);
      expect(builtRows(tester), inInclusiveRange(10, 40));
      // The last row is all in view, with the gap under the list.
      final panel = tester.getRect(find.byType(TasksPane));
      expect(
        tester.getRect(rowFinder('task-999')).bottom,
        lessThan(panel.bottom - 12),
      );
    });

    testWidgets('the place in the list stays when a task changes', (
      tester,
    ) async {
      final store = paneStore();
      addMany(store, 200);
      await pumpPane(tester, unscheduled(store));
      final position = listPosition(tester)..jumpTo(3000);
      await tester.pump();
      final shown = store
          .unscheduledTasks(today: wednesday)
          .unscheduled
          .firstWhere(
            (t) => rowFinder(t.id).hitTestable().evaluate().isNotEmpty,
          );
      final top = tester.getTopLeft(rowFinder(shown.id)).dy;

      store.editTask(
        shown.id,
        (t) => t.copyWith(priority: 3),
        name: 'Set Priority',
      );
      await tester.pumpAndSettle();
      expect(position.pixels, 3000);
      expect(tester.getTopLeft(rowFinder(shown.id)).dy, top);

      // A click on a row far down chooses it and does not move the list.
      await tester.tap(rowFinder(shown.id));
      await tester.pumpAndSettle();
      expect(store.selectedTaskId, shown.id);
      expect(position.pixels, 3000);
    });

    testWidgets('a row far down opens its subtasks and its menu', (
      tester,
    ) async {
      final store = paneStore();
      addMany(store, 200);
      await pumpPane(tester, unscheduled(store));
      listPosition(tester).jumpTo(4000);
      await tester.pump();
      final shown = store
          .unscheduledTasks(today: wednesday)
          .unscheduled
          .where((t) => rowFinder(t.id).hitTestable().evaluate().isNotEmpty)
          .elementAt(3);

      await rightClick(tester, rowFinder(shown.id));
      await tester.tap(find.text('Add Subtask'));
      await tester.pumpAndSettle();
      final field = find.byKey(ValueKey('add-subtask-${shown.id}'));
      expect(field, findsOneWidget);
      await typeLine(tester, field, 'A small step');
      expect(store.subtasks(shown.id).map((s) => s.title), ['A small step']);
      expect(find.text('A small step'), findsOneWidget);
      expect(find.text('0/1'), findsOneWidget);
    });

    testWidgets('a row keeps a half-typed subtask when the row over it goes '
        'away', (tester) async {
      final store = paneStore();
      addMany(store, 30);
      await pumpPane(tester, unscheduled(store));

      await rightClick(tester, rowFinder('task-2'));
      await tester.tap(find.text('Add Subtask'));
      await tester.pumpAndSettle();
      final field = find.descendant(
        of: find.byKey(const ValueKey('add-subtask-task-2')),
        matching: find.byType(EditableText),
      );
      await tester.enterText(field, 'Half a wo');
      await tester.pump();

      // The row above is checked off: each row under it moves one place up.
      await tester.tap(checkFinder('task-0'));
      await tester.pumpAndSettle();

      expect(find.text('Task 0'), findsNothing);
      expect(tester.widget<EditableText>(field).controller.text, 'Half a wo');
      expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
    });

    testWidgets('a row keeps a half-typed subtask when it goes out of view', (
      tester,
    ) async {
      final store = paneStore();
      addMany(store, 200);
      await pumpPane(tester, unscheduled(store));

      await rightClick(tester, rowFinder('task-2'));
      await tester.tap(find.text('Add Subtask'));
      await tester.pumpAndSettle();
      final field = find.descendant(
        of: find.byKey(const ValueKey('add-subtask-task-2')),
        matching: find.byType(EditableText),
      );
      await tester.enterText(field, 'Half a wo');
      await tester.pump();
      // The click on another field takes the keyboard away from the row.
      await tester.tap(quickAdd);
      await tester.pump();

      final position = listPosition(tester)..jumpTo(5000);
      await tester.pump();
      expect(find.text('Task 2').hitTestable(), findsNothing);
      position.jumpTo(0);
      await tester.pump();

      expect(tester.widget<EditableText>(field).controller.text, 'Half a wo');
    });

    testWidgets('a row that is dragged can still be dropped when the list '
        'moved it out of view', (tester) async {
      final store = paneStore();
      addMany(store, 200);
      String? dropped;
      await pumpPane(
        tester,
        Flex(
          direction: Axis.horizontal,
          children: [
            SizedBox(width: 320, child: unscheduled(store)),
            Expanded(
              child: DragTarget<String>(
                key: const ValueKey('target'),
                onAcceptWithDetails: (details) => dropped = details.data,
                builder: (context, _, _) => const SizedBox.expand(),
              ),
            ),
          ],
        ),
        size: const Size(640, 570),
      );

      final start = tester.getCenter(find.text('Task 1'));
      final end = tester.getCenter(find.byKey(const ValueKey('target')));
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      for (var i = 1; i <= 8; i++) {
        await gesture.moveTo(Offset.lerp(start, end, i / 8)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      // The wheel turns during the drag.
      listPosition(tester).jumpTo(5000);
      await tester.pump();
      expect(find.text('Task 1').hitTestable(), findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(dropped, DragPayload.task('task-1'));
    });

    testWidgets('a long list of today takes a drop on a row far down', (
      tester,
    ) async {
      final store = paneStore();
      for (var i = 0; i < 100; i++) {
        addTask(store, 'Task $i', sort: i.toDouble());
      }
      await pumpPane(tester, today(store));
      listPosition(tester).jumpTo(2000);
      await tester.pump();
      final shown = [
        for (final t in store.openTasks(TaskPlacement.day(wednesday)))
          if (find.text(t.title).hitTestable().evaluate().isNotEmpty) t,
      ];
      final from = shown[4], to = shown[1];

      await dragOnto(tester, find.text(from.title), find.text(to.title));

      final order = [
        for (final t in store.openTasks(TaskPlacement.day(wednesday))) t.id,
      ];
      expect(order.indexOf(from.id), order.indexOf(to.id) - 1);
      expect(order, hasLength(100));
    });
  });
}

/// `count` open tasks with no day: "Task 0", "Task 1", and so on.
void addMany(AppStore store, int count) {
  store.repos.db.transaction(() {
    for (var i = 0; i < count; i++) {
      addTask(store, 'Task $i', bucket: TaskBucket.inbox, sort: i.toDouble());
    }
  });
}

/// How many task rows the panel has built.
int builtRows(WidgetTester tester) => find.byType(TaskRow).evaluate().length;

/// The scroll place of the list of the panel.
ScrollPosition listPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .ancestor(
            of: find.byType(TaskSection),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;
