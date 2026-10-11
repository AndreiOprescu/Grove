// Subtasks of a goal block on the screen: the rows in the block, the menu
// line and the window that edits them. The Mac app has these in
// `Planner/BlockView.swift`, `Planner/PlannerGrid.swift` and
// `Planner/BlockSubtaskEditor.swift` (branch `feat/planner-subtasks`).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/planner/block_subtask_editor.dart';

import 'planner_support.dart';

List<String> names(AppStore store, String blockId) => [
  for (final s in store.blockSubtasks(blockId)) s.title,
];

Finder get editor => find.byType(BlockSubtaskEditor);
Finder get addField => find.byKey(const ValueKey('block-subtask-add'));

/// The menu of the block that lies on Wednesday at `minute`.
Future<void> openMenuAt(WidgetTester tester, int minute) =>
    rightClick(tester, pointAt(tester, wednesday, minute));

void main() {
  group('subtasks in a goal block', () {
    testWidgets('a tall goal block shows its subtasks, then "+N more"', (
      tester,
    ) async {
      final store = plannerStore();
      final id = goalBlock(store);
      for (final name in ['Socks', 'Shirts', 'Shoes', 'Soap', 'Maps', 'Keys']) {
        store.addBlockSubtask(to: id, title: name);
      }
      await pumpPlanner(tester, store);

      expect(find.text('Socks'), findsOneWidget);
      expect(find.textContaining('more'), findsOneWidget);
      expect(find.text('Keys'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a short goal block shows a count of the subtasks', (
      tester,
    ) async {
      final store = plannerStore();
      final id = goalBlock(store, length: 30);
      final first = store.addBlockSubtask(to: id, title: 'Socks')!;
      store
        ..addBlockSubtask(to: id, title: 'Shirts')
        ..toggleBlockSubtask(first);
      await pumpPlanner(tester, store);

      expect(find.text('Socks'), findsNothing);
      expect(find.text('1/2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the other block of the goal keeps its own subtasks', (
      tester,
    ) async {
      final store = plannerStore();
      final morning = goalBlock(store);
      final later = goalBlock(store, start: 15 * 60);
      store.addBlockSubtask(to: morning, title: 'Chapter 3');
      await pumpPlanner(tester, store);

      expect(
        find.descendant(
          of: blockFinder(morning),
          matching: find.text('Chapter 3'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: blockFinder(later),
          matching: find.text('Chapter 3'),
        ),
        findsNothing,
      );
    });

    testWidgets('a done subtask shows with a tick', (tester) async {
      final store = plannerStore();
      final id = goalBlock(store);
      final sub = store.addBlockSubtask(to: id, title: 'Chapter 3')!;
      store.toggleBlockSubtask(sub);
      await pumpPlanner(tester, store);

      expect(find.bySemanticsLabel('Done: Chapter 3'), findsOneWidget);
    });
  });

  group('the menu line for subtasks', () {
    testWidgets('a goal block with no subtasks has "Add Subtasks…"', (
      tester,
    ) async {
      final store = plannerStore();
      final id = goalBlock(store);
      await pumpPlanner(tester, store);

      await openMenuAt(tester, 11 * 60 + 30);
      expect(find.text('Subtasks…'), findsNothing);
      await tester.tap(find.text('Add Subtasks…'));
      await tester.pumpAndSettle();

      expect(store.editingBlockSubtasks, id);
      expect(editor, findsOneWidget);
    });

    testWidgets('a goal block with subtasks has "Subtasks…"', (tester) async {
      final store = plannerStore();
      final id = goalBlock(store);
      store.addBlockSubtask(to: id, title: 'Chapter 3');
      await pumpPlanner(tester, store);

      await openMenuAt(tester, 11 * 60 + 30);
      expect(find.text('Add Subtasks…'), findsNothing);
      await tester.tap(find.text('Subtasks…'));
      await tester.pumpAndSettle();

      expect(store.editingBlockSubtasks, id);
      expect(editor, findsOneWidget);
    });

    testWidgets('a task block and a plain event have no such line', (
      tester,
    ) async {
      final store = plannerStore();
      store
        ..createFromDraft(
          title: 'Write report',
          day: wednesday,
          start: 11 * 60,
          end: 12 * 60,
          asEvent: false,
        )
        ..createFromDraft(
          title: 'Lunch',
          day: wednesday,
          start: 13 * 60,
          end: 14 * 60,
          asEvent: true,
        );
      await pumpPlanner(tester, store);

      for (final minute in [11 * 60 + 30, 13 * 60 + 30]) {
        await openMenuAt(tester, minute);
        expect(find.text('Duplicate'), findsOneWidget);
        expect(find.textContaining('Subtasks…'), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
    });
  });

  group('the subtask window of a goal block', () {
    Future<(AppStore, String)> open(
      WidgetTester tester, {
      List<String> subtasks = const [],
    }) async {
      final store = plannerStore();
      final id = goalBlock(store);
      for (final name in subtasks) {
        store.addBlockSubtask(to: id, title: name);
      }
      await pumpPlanner(tester, store);
      store.openBlockSubtasks(id);
      await tester.pumpAndSettle();
      expect(editor, findsOneWidget);
      return (store, id);
    }

    testWidgets('shows the title of the block, the count and the rows', (
      tester,
    ) async {
      final (store, id) = await open(tester, subtasks: ['One', 'Two']);
      store.toggleBlockSubtask(store.blockSubtasks(id).first.id);
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: editor, matching: find.text('Read')),
        findsOneWidget,
      );
      expect(find.text('Subtasks  1/2'), findsOneWidget);
      expect(
        find.text(
          'Only this block has these. Other blocks of the goal keep their '
          'own.',
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Mark One as not done'), findsOneWidget);
      expect(find.bySemanticsLabel('Mark Two as done'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with no subtasks the field for a new one has the keys', (
      tester,
    ) async {
      final (store, id) = await open(tester);

      expect(find.text('Subtasks'), findsOneWidget);
      // No tap on the field: the keys go to it at once.
      tester.testTextInput.enterText('Chapter 3');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(names(store, id), ['Chapter 3']);
      expect(store.undoName, 'New Subtask');
    });

    testWidgets('Return adds a subtask, clears the field and keeps the keys', (
      tester,
    ) async {
      final (store, id) = await open(tester, subtasks: ['One']);

      await tester.enterText(addField, '  Two ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(names(store, id), ['One', 'Two']);
      expect(tester.widget<TextField>(addField).controller!.text, isEmpty);

      // The next one goes in with no click.
      tester.testTextInput.enterText('Three');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(names(store, id), ['One', 'Two', 'Three']);
      // The block behind the window has the rows too.
      expect(
        find.descendant(of: blockFinder(id), matching: find.text('Two')),
        findsOneWidget,
      );
    });

    testWidgets('Return on an empty field adds nothing', (tester) async {
      final (store, id) = await open(tester, subtasks: ['One']);

      await tester.enterText(addField, '   ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(names(store, id), ['One']);
    });

    testWidgets('the check box ticks a subtask and opens it again', (
      tester,
    ) async {
      final (store, id) = await open(tester, subtasks: ['One']);

      await tester.tap(find.bySemanticsLabel('Mark One as done'));
      await tester.pumpAndSettle();
      expect(store.blockSubtasks(id).single.isDone, isTrue);
      expect(find.text('Subtasks  1/1'), findsOneWidget);
      // The block itself is not done.
      expect(store.blocks(DayRange.single(wednesday)).single.isDone, isFalse);

      await tester.tap(find.bySemanticsLabel('Mark One as not done'));
      await tester.pumpAndSettle();
      expect(store.blockSubtasks(id).single.isDone, isFalse);
    });

    testWidgets('Return in a name saves the new name', (tester) async {
      final (store, id) = await open(tester, subtasks: ['One']);
      final sub = store.blockSubtasks(id).single.id;

      await tester.enterText(
        find.byKey(ValueKey('block-subtask-name-$sub')),
        ' First ',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(names(store, id), ['First']);
      expect(store.undoName, 'Rename Subtask');
    });

    testWidgets('an empty name puts the saved name back', (tester) async {
      final (store, id) = await open(tester, subtasks: ['One']);
      final sub = store.blockSubtasks(id).single.id;
      final field = find.byKey(ValueKey('block-subtask-name-$sub'));

      await tester.enterText(field, '  ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(names(store, id), ['One']);
      expect(tester.widget<TextField>(field).controller!.text, 'One');
    });

    testWidgets('a name saves when the keys go to another field', (
      tester,
    ) async {
      final (store, id) = await open(tester, subtasks: ['One']);
      final sub = store.blockSubtasks(id).single.id;

      await tester.enterText(
        find.byKey(ValueKey('block-subtask-name-$sub')),
        'First',
      );
      await tester.tap(addField);
      await tester.pumpAndSettle();

      expect(names(store, id), ['First']);
    });

    testWidgets('a name that was typed saves when the window closes', (
      tester,
    ) async {
      final (store, id) = await open(tester, subtasks: ['One']);
      final sub = store.blockSubtasks(id).single.id;

      await tester.enterText(
        find.byKey(ValueKey('block-subtask-name-$sub')),
        'First',
      );
      await tester.tap(find.bySemanticsLabel('Done'));
      await tester.pumpAndSettle();

      expect(editor, findsNothing);
      expect(names(store, id), ['First']);
    });

    testWidgets('the bin deletes a subtask', (tester) async {
      final (store, id) = await open(tester, subtasks: ['One', 'Two']);

      await tester.tap(find.bySemanticsLabel('Delete subtask One'));
      await tester.pumpAndSettle();

      expect(names(store, id), ['Two']);
      expect(store.undoName, 'Delete Subtask');
      expect(find.bySemanticsLabel('Mark One as done'), findsNothing);
    });

    testWidgets('"Done" closes the window and tells the store', (tester) async {
      final (store, _) = await open(tester, subtasks: ['One']);

      await tester.tap(find.bySemanticsLabel('Done'));
      await tester.pumpAndSettle();

      expect(editor, findsNothing);
      expect(store.editingBlockSubtasks, isNull);
    });

    testWidgets('Escape closes the window and tells the store', (tester) async {
      final (store, _) = await open(tester, subtasks: ['One']);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(editor, findsNothing);
      expect(store.editingBlockSubtasks, isNull);
    });

    testWidgets('the window closes when the store closes it', (tester) async {
      final (store, _) = await open(tester, subtasks: ['One']);

      store.closeBlockSubtasks();
      await tester.pumpAndSettle();

      expect(editor, findsNothing);
    });

    testWidgets('the window closes when its block goes away', (tester) async {
      final (store, id) = await open(tester, subtasks: ['One']);

      store.deleteBlocks([id], name: 'Delete Goal Block');
      await tester.pumpAndSettle();

      expect(editor, findsNothing);
      expect(store.editingBlockSubtasks, isNull);
    });

    testWidgets('the window fits on a phone', (tester) async {
      final store = plannerStore();
      final id = goalBlock(store);
      for (var i = 0; i < 12; i++) {
        store.addBlockSubtask(
          to: id,
          title: 'A long name of a subtask that does not end $i',
        );
      }
      await pumpPlanner(tester, store, size: phoneSize);
      store.openBlockSubtasks(id);
      await tester.pumpAndSettle();

      final box = tester.getRect(editor);
      expect(box.left, greaterThanOrEqualTo(0));
      expect(box.right, lessThanOrEqualTo(phoneSize.width));
      expect(box.bottom, lessThanOrEqualTo(phoneSize.height));
      expect(tester.takeException(), isNull);
    });
  });
}
