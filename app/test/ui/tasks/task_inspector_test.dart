import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/editor/editor_tools.dart';
import 'package:grove/ui/editor/rich_text_field.dart';
import 'package:grove/ui/tasks/task_inspector.dart';
import 'package:grove/ui/tasks/task_widgets.dart';

import 'tasks_support.dart';

const inspectorSize = Size(TaskInspector.width, 900);

Finder byKey(String key) => find.byKey(ValueKey(key));

/// The text field inside the widget with `key`.
Finder input(String key) =>
    find.descendant(of: byKey(key), matching: find.byType(EditableText));

/// The text of the description, as the editor has it (with the marks).
String notesShown(WidgetTester tester) =>
    tester.widget<EditableText>(input('inspector-notes')).controller.text;

/// The panel of the chosen task, as the app shows it. "closed" when no
/// task is chosen.
Widget host(AppStore store) => StoreBuilder(
  store: store,
  builder: (context) {
    final id = store.selectedTaskId;
    return id == null
        ? const Center(child: Text('closed'))
        : TaskInspector(store: store, taskId: id);
  },
);

/// Shows the panel for a new task "Write report" with the id `report`.
Future<AppStore> pumpInspector(
  WidgetTester tester, {
  void Function(AppStore store)? before,
  Size size = inspectorSize,
}) async {
  final store = paneStore();
  addTask(store, 'Write report', id: 'report');
  before?.call(store);
  store.selectedTaskId = 'report';
  await pumpPane(tester, host(store), size: size);
  return store;
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(byKey(key));
  await tester.pumpAndSettle();
}

/// Opens the menu of the widget with `key` and picks the line `line`.
Future<void> pick(WidgetTester tester, String key, String line) async {
  await tapKey(tester, key);
  await tester.tap(find.text(line).last);
  await tester.pumpAndSettle();
}

/// Clicks the part `name` of the row of buttons with `key`.
Future<void> segment(WidgetTester tester, String key, String name) async {
  await tester.ensureVisible(byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: byKey(key), matching: find.text(name)));
  await tester.pumpAndSettle();
}

void main() {
  group('what the panel shows', () {
    testWidgets('the fields of the task', (tester) async {
      final store = await pumpInspector(
        tester,
        before: (store) {
          store.repos.tasks.save(
            store
                .task('report')!
                .copyWith(summary: 'For the board', notes: 'Three pages.'),
          );
        },
      );

      expect(store.task('report'), isNotNull);
      expect(find.text('Write report'), findsOneWidget);
      expect(find.text('For the board'), findsOneWidget);
      expect(find.text('Three pages.'), findsOneWidget);
      for (final name in const [
        'Short description',
        'Description',
        'Plan',
        'Details',
        'Tags',
        'Subtasks',
      ]) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      expect(find.text('Wed 7 Oct'), findsOneWidget);
      expect(find.text('30m'), findsOneWidget);
      expect(find.text('Does not repeat'), findsOneWidget);
      expect(find.text('No list'), findsOneWidget);
      expect(find.text('Add a due date'), findsOneWidget);
      expect(find.text('Linked here'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a task that is gone says so', (tester) async {
      final store = paneStore();
      await pumpPane(
        tester,
        TaskInspector(store: store, taskId: 'nothing'),
        size: inspectorSize,
      );
      expect(find.text('This task is gone.'), findsOneWidget);
    });

    testWidgets('the note the task came from, and the items that link to it', (
      tester,
    ) async {
      final store = await pumpInspector(
        tester,
        before: (store) {
          store.repos.notes.save(Note(id: 'n1', title: 'Board meeting'));
          store.repos.tasks.save(
            store.task('report')!.copyWith(sourceNoteId: 'n1'),
          );
        },
      );

      expect(find.text('Linked here'), findsOneWidget);
      final row = find.text('Created from note “Board meeting”');
      expect(row, findsOneWidget);
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(store.screen, Screen.notes);
    });
  });

  group('the text of the task', () {
    testWidgets('Return in the title renames the task', (tester) async {
      final store = await pumpInspector(tester);
      await typeLine(tester, byKey('inspector-title'), 'Write the report');
      expect(store.task('report')!.title, 'Write the report');

      store.undo();
      await tester.pumpAndSettle();
      expect(store.task('report')!.title, 'Write report');
      await endToast(tester);
    });

    testWidgets('an empty title is not saved', (tester) async {
      final store = await pumpInspector(tester);
      await typeLine(tester, byKey('inspector-title'), '   ');
      expect(store.task('report')!.title, 'Write report');
      expect(find.text('Write report'), findsOneWidget);
    });

    testWidgets('the short description is saved after a short stop', (
      tester,
    ) async {
      final store = await pumpInspector(tester);
      await tester.tap(byKey('inspector-summary'));
      await tester.enterText(input('inspector-summary'), 'For the board');
      await tester.pump(const Duration(milliseconds: 300));
      expect(store.task('report')!.summary, '');
      await tester.pump(const Duration(milliseconds: 300));
      expect(store.task('report')!.summary, 'For the board');
    });

    testWidgets('the description is saved after a short stop', (tester) async {
      final store = await pumpInspector(tester);
      await tester.tap(byKey('inspector-notes'));
      await tester.enterText(
        input('inspector-notes'),
        'Three pages.\nNo more.',
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(store.task('report')!.notes, '');
      await tester.pump(const Duration(milliseconds: 300));
      expect(store.task('report')!.notes, 'Three pages.\nNo more.');
    });

    testWidgets('the description is the editor with its row of buttons', (
      tester,
    ) async {
      await pumpInspector(tester);
      final editor = find.descendant(
        of: byKey('inspector-notes'),
        matching: find.byType(RichTextField),
      );
      expect(editor, findsOneWidget);
      expect(
        find.descendant(of: editor, matching: find.byType(EditorToolbar)),
        findsOneWidget,
      );
      expect(
        find.text('The longer description. Type [[ to mention a task.'),
        findsOneWidget,
      );
      // The panel alone has no window to pick a picture: no button, in the
      // row or in its "…" menu.
      expect(find.bySemanticsLabel('Add an image'), findsNothing);
      await tester.tap(
        find.descendant(
          of: byKey('inspector-notes'),
          matching: find.byTooltip('More tools'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Divider'), findsOneWidget);
      expect(find.text('Add an image'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('in the app, which gives the window to pick a picture, the '
        'description has "Add an image"', (tester) async {
      final store = paneStore();
      addTask(store, 'Write report', id: 'report');
      store.selectedTaskId = 'report';
      await pumpPane(
        tester,
        EditorTools(pickImages: () async => const [], child: host(store)),
        size: inspectorSize,
      );
      // The panel is narrow: the tool is in the "…" menu of the row.
      await tester.tap(
        find.descendant(
          of: byKey('inspector-notes'),
          matching: find.byTooltip('More tools'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Add an image'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a button of the row changes the description, and the '
        'change is saved', (tester) async {
      final store = await pumpInspector(
        tester,
        before: (store) => store.repos.tasks.save(
          store.task('report')!.copyWith(notes: 'buy milk'),
        ),
      );
      await tester.tap(find.bySemanticsLabel('Checklist'));
      await tester.pump();
      expect(notesShown(tester), '- [ ] buy milk');
      await tester.pump(const Duration(milliseconds: 600));
      expect(store.task('report')!.notes, '- [ ] buy milk');
    });

    testWidgets('[[ opens the list, with no row for the task itself, and a '
        'pick makes a link', (tester) async {
      // A link holds the id of its item only when the id has the form of
      // the ids of the app.
      const mum = '0A1B2C3D-0000-4000-8000-00000000000A';
      final store = await pumpInspector(
        tester,
        before: (store) => addTask(store, 'Call mum', id: mum),
      );
      await tester.tap(byKey('inspector-notes'));
      await tester.enterText(input('inspector-notes'), 'After [[');
      await tester.pump();
      expect(byKey('mention-$mum'), findsOneWidget);
      expect(byKey('mention-report'), findsNothing);

      await tester.tap(byKey('mention-$mum'));
      await tester.pump();
      expect(notesShown(tester), 'After [[Call mum|$mum]]');
      await tester.pump(const Duration(milliseconds: 600));
      expect(store.task('report')!.notes, 'After [[Call mum|$mum]]');
      expect(
        [
          for (final item in store.linkedItems(
            const ItemRef(ItemType.task, mum),
          ))
            item.id,
        ],
        ['report'],
      );
    });

    testWidgets('a link typed by hand gets its id. The editor shows the saved '
        'text when it loses the keyboard, not before', (tester) async {
      final store = await pumpInspector(
        tester,
        before: (store) => addTask(store, 'Call mum', id: 'mum'),
      );
      await tester.tap(byKey('inspector-notes'));
      await tester.enterText(input('inspector-notes'), 'After [[Call mum]]');
      await tester.pump(const Duration(milliseconds: 600));
      expect(store.task('report')!.notes, 'After [[Call mum|mum]]');
      // The user is still in the text. It does not change under the caret.
      expect(notesShown(tester), 'After [[Call mum]]');

      await tester.tap(byKey('inspector-summary'));
      await tester.pumpAndSettle();
      expect(notesShown(tester), 'After [[Call mum|mum]]');
      expect(store.task('report')!.notes, 'After [[Call mum|mum]]');
    });

    testWidgets('undo from another place shows in the description when the '
        'user is not in it', (tester) async {
      final store = await pumpInspector(tester);
      await tester.tap(byKey('inspector-notes'));
      await tester.enterText(input('inspector-notes'), 'Three pages.');
      await tester.tap(byKey('inspector-summary'));
      await tester.pumpAndSettle();
      expect(store.task('report')!.notes, 'Three pages.');

      store.undo();
      await tester.pumpAndSettle();
      expect(store.task('report')!.notes, '');
      expect(notesShown(tester), '');
      await endToast(tester);
    });

    testWidgets('text that is not saved yet is kept when the panel closes', (
      tester,
    ) async {
      final store = await pumpInspector(tester);
      await tester.tap(byKey('inspector-notes'));
      await tester.enterText(input('inspector-notes'), 'Three pages.');
      await tester.enterText(input('inspector-summary'), 'For the board');
      await tester.enterText(input('inspector-title'), 'Write the report');
      await tapKey(tester, 'inspector-close');

      expect(find.text('closed'), findsOneWidget);
      final task = store.task('report')!;
      expect(task.notes, 'Three pages.');
      expect(task.summary, 'For the board');
      expect(task.title, 'Write the report');
    });

    testWidgets('text that is not saved yet goes to its own task when a new '
        'task is chosen', (tester) async {
      final store = await pumpInspector(
        tester,
        before: (store) => addTask(store, 'Call mum', id: 'mum'),
      );
      await tester.tap(byKey('inspector-notes'));
      await tester.enterText(input('inspector-notes'), 'Three pages.');
      store.selectedTaskId = 'mum';
      await tester.pumpAndSettle();

      expect(store.task('report')!.notes, 'Three pages.');
      expect(store.task('mum')!.notes, '');
      expect(find.text('Call mum'), findsOneWidget);
      expect(find.text('Three pages.'), findsNothing);
      expect(notesShown(tester), '');

      // The editor is now the one of the new task: its `[[` list has the
      // first task, and not the new one.
      await tester.tap(byKey('inspector-notes'));
      await tester.enterText(input('inspector-notes'), '[[');
      await tester.pump();
      expect(byKey('mention-report'), findsOneWidget);
      expect(byKey('mention-mum'), findsNothing);
      await tester.tap(byKey('mention-report'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(store.task('mum')!.notes, '[[Write report|report]]');
      expect(store.task('report')!.notes, 'Three pages.');
    });

    testWidgets('a change from another place shows in the panel', (
      tester,
    ) async {
      final store = await pumpInspector(tester);
      store.editTask(
        'report',
        (t) => t.copyWith(title: 'New name'),
        name: 'Rename Task',
      );
      store.setNotes('report', 'From the planner');
      await tester.pumpAndSettle();
      expect(find.text('New name'), findsOneWidget);
      expect(find.text('From the planner'), findsOneWidget);
    });
  });

  group('the plan of the task', () {
    testWidgets('the row of buttons moves the task', (tester) async {
      final store = await pumpInspector(tester);

      await segment(tester, 'inspector-plan', 'Week');
      expect(store.task('report')!.bucket, TaskBucket.week);
      expect(store.task('report')!.planWeek, d('2026-10-05'));
      expect(find.text('Week of'), findsOneWidget);

      await segment(tester, 'inspector-plan', 'Someday');
      expect(store.task('report')!.bucket, TaskBucket.someday);
      expect(byKey('inspector-plan-day'), findsNothing);

      await segment(tester, 'inspector-plan', 'Inbox');
      expect(store.task('report')!.bucket, TaskBucket.inbox);

      await segment(tester, 'inspector-plan', 'Day');
      expect(store.task('report')!.planDate, wednesday);
    });

    testWidgets('the date button moves the task to the day picked', (
      tester,
    ) async {
      final store = await pumpInspector(tester, size: const Size(800, 900));
      await tapKey(tester, 'inspector-plan-day');
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(store.task('report')!.planDate, d('2026-10-15'));
      expect(find.text('Thu 15 Oct'), findsOneWidget);
    });

    testWidgets('the date window fits on a phone', (tester) async {
      await pumpInspector(tester, size: phoneSize);
      await tapKey(tester, 'inspector-plan-day');
      expect(find.text('OK'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('the details of the task', () {
    testWidgets('priority', (tester) async {
      final store = await pumpInspector(tester);
      await segment(tester, 'inspector-priority', 'High');
      expect(store.task('report')!.priority, 3);
      await segment(tester, 'inspector-priority', 'None');
      expect(store.task('report')!.priority, 0);
    });

    testWidgets('colour', (tester) async {
      final store = await pumpInspector(tester);
      await tapKey(tester, 'colour-teal');
      expect(store.task('report')!.color, 'teal');
      await tapKey(tester, 'colour-none');
      expect(store.task('report')!.color, '');
    });

    testWidgets('length', (tester) async {
      final store = await pumpInspector(tester);
      await tapKey(tester, 'inspector-length');
      expect(find.text('✓ 30m'), findsOneWidget);
      await tester.tap(find.text('1h 30m'));
      await tester.pumpAndSettle();
      expect(store.task('report')!.estimateMin, 90);
      expect(find.text('1h 30m'), findsOneWidget);
    });

    testWidgets('due date: add and remove', (tester) async {
      final store = await pumpInspector(tester);
      await tapKey(tester, 'inspector-due-add');
      expect(store.task('report')!.due, '2026-10-07');
      expect(byKey('inspector-due'), findsOneWidget);

      await tapKey(tester, 'inspector-due-clear');
      expect(store.task('report')!.due, isNull);
      expect(byKey('inspector-due-add'), findsOneWidget);
    });

    testWidgets('a new due day keeps the time of the old one', (tester) async {
      final store = await pumpInspector(
        tester,
        size: const Size(800, 900),
        before: (store) => store.repos.tasks.save(
          store.task('report')!.copyWith(due: '2026-10-09T14:30'),
        ),
      );
      await tapKey(tester, 'inspector-due');
      await tester.tap(find.text('20'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(store.task('report')!.due, '2026-10-20T14:30');
    });

    testWidgets('repeat', (tester) async {
      final store = await pumpInspector(tester);
      await tapKey(tester, 'inspector-repeat');
      expect(find.text('Custom'), findsNothing);
      await tester.tap(find.text('Every week'));
      await tester.pumpAndSettle();
      expect(store.task('report')!.recurrence, isNotNull);
      expect(find.text('Every week'), findsOneWidget);

      await pick(tester, 'inspector-repeat', 'Does not repeat');
      expect(store.task('report')!.recurrence, isNull);
    });

    testWidgets('list', (tester) async {
      final store = await pumpInspector(
        tester,
        before: (store) =>
            store.repos.lists.save(ListItem(id: 'work', name: 'Work')),
      );
      await pick(tester, 'inspector-list', 'Work');
      expect(store.task('report')!.listId, 'work');
      expect(find.text('Work'), findsOneWidget);

      await pick(tester, 'inspector-list', 'No list');
      expect(store.task('report')!.listId, isNull);
    });

    testWidgets('tags: add and remove', (tester) async {
      final store = await pumpInspector(tester);
      await tester.ensureVisible(byKey('add-tag'));
      await typeLine(tester, byKey('add-tag'), 'board');
      await typeLine(tester, byKey('add-tag'), 'urgent');
      expect(store.tagNames('report'), ['board', 'urgent']);
      expect(find.text('#board'), findsOneWidget);

      await tapKey(tester, 'remove-tag-board');
      expect(store.tagNames('report'), ['urgent']);
      expect(find.text('#board'), findsNothing);
    });
  });

  group('subtasks', () {
    Future<(AppStore, String)> withSubtask(WidgetTester tester) async {
      final store = await pumpInspector(tester);
      await tester.ensureVisible(byKey('inspector-add-subtask'));
      await typeLine(
        tester,
        byKey('inspector-add-subtask'),
        'Find the numbers',
      );
      return (store, store.subtasks('report').single.id);
    }

    testWidgets('a new subtask opens, so its details can be set', (
      tester,
    ) async {
      final (store, id) = await withSubtask(tester);
      expect(store.subtasks('report').single.title, 'Find the numbers');
      expect(byKey('sub-notes-$id'), findsOneWidget);
      expect(find.textContaining('Subtasks  0/1'), findsOneWidget);

      await typeLine(tester, byKey('inspector-add-subtask'), 'Write page 1');
      final second = store.subtasks('report').last.id;
      expect(byKey('sub-notes-$id'), findsNothing);
      expect(byKey('sub-notes-$second'), findsOneWidget);
    });

    testWidgets('the arrow opens and closes a subtask', (tester) async {
      final (_, id) = await withSubtask(tester);
      await tapKey(tester, 'sub-toggle-$id');
      expect(byKey('sub-notes-$id'), findsNothing);
      await tapKey(tester, 'sub-toggle-$id');
      expect(byKey('sub-notes-$id'), findsOneWidget);
    });

    testWidgets('the check box marks a subtask as done', (tester) async {
      final (store, id) = await withSubtask(tester);
      await tapKey(tester, 'sub-check-$id');
      expect(store.task(id)!.isDone, isTrue);
      expect(find.textContaining('Subtasks  1/1'), findsOneWidget);
    });

    testWidgets('rename, description and length', (tester) async {
      final (store, id) = await withSubtask(tester);
      await typeLine(tester, byKey('sub-title-$id'), 'Find all the numbers');
      expect(store.task(id)!.title, 'Find all the numbers');

      await tester.tap(byKey('sub-notes-$id'));
      await tester.enterText(input('sub-notes-$id'), 'Ask finance');
      await tester.pump(const Duration(milliseconds: 600));
      expect(store.task(id)!.notes, 'Ask finance');

      await pick(tester, 'sub-length-$id', '45m');
      expect(store.task(id)!.estimateMin, 45);
      expect(find.textContaining('· 45m'), findsOneWidget);
    });

    testWidgets('a description that is not saved yet is kept when the '
        'subtask closes', (tester) async {
      final (store, id) = await withSubtask(tester);
      await tester.tap(byKey('sub-notes-$id'));
      await tester.enterText(input('sub-notes-$id'), 'Ask finance');
      await tapKey(tester, 'sub-toggle-$id');
      expect(store.task(id)!.notes, 'Ask finance');
    });

    testWidgets('delete', (tester) async {
      final (store, id) = await withSubtask(tester);
      await tapKey(tester, 'sub-delete-$id');
      expect(store.subtasks('report'), isEmpty);
      expect(store.task('report'), isNotNull);
      await endToast(tester);
    });
  });

  group('the buttons at the top', () {
    testWidgets('the check box marks the task as done', (tester) async {
      final store = await pumpInspector(tester);
      await tapKey(tester, 'inspector-check');
      expect(store.task('report')!.isDone, isTrue);
      await tapKey(tester, 'inspector-check');
      expect(store.task('report')!.isDone, isFalse);
    });

    testWidgets('delete removes the task and closes the panel', (tester) async {
      final store = await pumpInspector(tester);
      await tapKey(tester, 'inspector-delete');
      expect(store.task('report'), isNull);
      expect(store.selectedTaskId, isNull);
      expect(find.text('closed'), findsOneWidget);

      store.undo();
      await tester.pumpAndSettle();
      expect(store.task('report'), isNotNull);
      await endToast(tester);
    });

    testWidgets('the cross closes the panel', (tester) async {
      final store = await pumpInspector(tester);
      await tapKey(tester, 'inspector-close');
      expect(store.selectedTaskId, isNull);
      expect(store.task('report'), isNotNull);
    });

    testWidgets('Esc closes the panel when the keys are in it', (tester) async {
      final store = await pumpInspector(tester);
      await tester.tap(byKey('inspector-summary'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(store.selectedTaskId, isNull);
    });

    testWidgets('Esc does nothing when the keys are in another place', (
      tester,
    ) async {
      final store = await pumpInspector(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(store.selectedTaskId, 'report');
    });
  });

  testWidgets('the panel fits a phone', (tester) async {
    await pumpInspector(
      tester,
      size: phoneSize,
      before: (store) {
        store.repos.tasks.save(
          store
              .task('report')!
              .copyWith(
                title:
                    'A very long title of a task that needs more than one line',
                due: '2026-10-09T14:30',
                priority: 3,
              ),
        );
        store.setTags(taskId: 'report', to: ['board', 'urgent', 'finance']);
        store.addSubtask(to: 'report', title: 'Find the numbers');
      },
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Linked here'), findsNothing);
  });
}
