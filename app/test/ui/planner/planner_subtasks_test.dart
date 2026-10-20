// Subtasks of a goal block on the screen: the rows in the block, the menu
// line and the window that edits them. The Mac app has these in
// `Planner/BlockView.swift`, `Planner/PlannerGrid.swift` and
// `Planner/BlockSubtaskEditor.swift` (branch `feat/planner-subtasks`).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/goal_subtask.dart';
import 'package:grove/ui/goals/goal_panel.dart';
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

      // A goal block shows its subtasks in the goal panel (ADR 0002).
      expect(store.selectedGoalBlockId, id);
      expect(find.byType(GoalPanel), findsOneWidget);
      expect(editor, findsNothing);
    });

    testWidgets('a goal block with subtasks has "Subtasks…"', (tester) async {
      final store = plannerStore();
      final id = goalBlock(store);
      store.addGoalSubtaskToBlock(id, title: 'Chapter 3');
      await pumpPlanner(tester, store);

      await openMenuAt(tester, 11 * 60 + 30);
      expect(find.text('Add Subtasks…'), findsNothing);
      await tester.tap(find.text('Subtasks…'));
      await tester.pumpAndSettle();

      expect(store.selectedGoalBlockId, id);
      expect(find.byType(GoalPanel), findsOneWidget);
      expect(editor, findsNothing);
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

  group('subtasks of the goal in the window of a block', () {
    late AppStore store;
    late GoalItem goal;
    late String id;

    /// The subtask of the goal with this name, as the database has it now.
    GoalSubtaskItem sub(String title) =>
        store.goalSubtasks(goal.id).firstWhere((s) => s.title == title);

    Finder free(String title) =>
        find.byKey(ValueKey('block-goal-subtask-free-${sub(title).id}'));

    double top(WidgetTester tester, String label) =>
        tester.getTopLeft(find.bySemanticsLabel(label)).dy;

    /// "Read" has a block on Wednesday at 11:00 and the subtasks
    /// "Chapter 1" and "Chapter 2". `planned` are in the block already.
    Future<void> open(
      WidgetTester tester, {
      List<String> planned = const [],
      List<String> own = const [],
      void Function()? before,
      Size size = desktopSize,
    }) async {
      store = plannerStore();
      id = goalBlock(store);
      goal = store.goals().single;
      store
        ..addGoalSubtask(to: goal.id, title: 'Chapter 1')
        ..addGoalSubtask(to: goal.id, title: 'Chapter 2');
      for (final name in planned) {
        store.assignGoalSubtask(sub(name).id, to: id);
      }
      for (final name in own) {
        store.addBlockSubtask(to: id, title: name);
      }
      before?.call();
      await pumpPlanner(tester, store, size: size);
      store.openBlockSubtasks(id);
      await tester.pumpAndSettle();
      expect(editor, findsOneWidget);
    }

    testWidgets('a planned subtask of the goal shows in the block, and the '
        'menu of the block says "Subtasks…"', (tester) async {
      store = plannerStore();
      id = goalBlock(store);
      goal = store.goals().single;
      store.addGoalSubtask(to: goal.id, title: 'Chapter 1');
      store.assignGoalSubtask(sub('Chapter 1').id, to: id);
      await pumpPlanner(tester, store);

      expect(
        find.descendant(of: blockFinder(id), matching: find.text('Chapter 1')),
        findsOneWidget,
      );
      await openMenuAt(tester, 11 * 60 + 30);
      expect(find.text('Subtasks…'), findsOneWidget);
      expect(find.text('Add Subtasks…'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the subtasks of the goal first, then the ones of the '
        'block, and counts both', (tester) async {
      await open(tester, planned: ['Chapter 2'], own: ['Own one']);
      store.toggleBlockSubtask(store.blockSubtasks(id).single.id);
      await tester.pumpAndSettle();

      expect(find.text('Subtasks  1/2'), findsOneWidget);
      expect(
        top(tester, 'Mark Chapter 2 as done'),
        lessThan(top(tester, 'Mark Own one as not done')),
      );
      expect(
        find.text(
          'The ones with an arrow are from the goal. Only this block has '
          'the others.',
        ),
        findsOneWidget,
      );
      // Only a subtask of the goal can go back to the goal.
      expect(
        find.bySemanticsLabel('Put Chapter 2 back in the goal'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Put Own one back in the goal'),
        findsNothing,
      );
      // The field for a new one does not take the keys: the list has rows.
      expect(tester.widget<TextField>(addField).focusNode!.hasFocus, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tick ticks the subtask of the goal, and a second tick '
        'opens it again', (tester) async {
      await open(tester, planned: ['Chapter 1']);

      await tester.tap(find.bySemanticsLabel('Mark Chapter 1 as done'));
      await tester.pumpAndSettle();
      expect(sub('Chapter 1').isDone, isTrue);
      expect(sub('Chapter 1').eventId, id);
      expect(store.undoName, 'Complete Subtask');
      expect(find.text('Subtasks  1/1'), findsOneWidget);
      // The block itself is not done, and it has no subtask of its own.
      expect(store.blocks(DayRange.single(wednesday)).single.isDone, isFalse);
      expect(store.blockSubtasks(id), isEmpty);

      await tester.tap(find.bySemanticsLabel('Mark Chapter 1 as not done'));
      await tester.pumpAndSettle();
      expect(sub('Chapter 1').isDone, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a new name with Return is the name of the subtask of the '
        'goal', (tester) async {
      await open(tester, planned: ['Chapter 1']);
      final field = find.byKey(
        ValueKey('block-goal-subtask-name-${sub('Chapter 1').id}'),
      );

      await tester.enterText(field, 'Chapter one');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(store.goalSubtasks(goal.id).first.title, 'Chapter one');
      expect(store.undoName, 'Rename Subtask');
      expect(store.blockSubtasks(id), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the arrow puts the subtask back in the goal: the block no '
        'longer has it, and "From the goal" has it', (tester) async {
      await open(tester, planned: ['Chapter 1', 'Chapter 2']);
      expect(find.text('From the goal'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Put Chapter 1 back in the goal'));
      await tester.pumpAndSettle();

      expect(sub('Chapter 1').eventId, isNull);
      expect(sub('Chapter 2').eventId, id);
      expect(store.undoName, 'Unplan Subtask');
      expect(find.bySemanticsLabel('Mark Chapter 1 as done'), findsNothing);
      expect(find.text('From the goal'), findsOneWidget);
      expect(free('Chapter 1'), findsOneWidget);
      expect(find.text('Subtasks  0/1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the bin deletes the subtask from the goal too', (
      tester,
    ) async {
      await open(tester, planned: ['Chapter 1']);

      await tester.tap(find.bySemanticsLabel('Delete subtask Chapter 1'));
      await tester.pumpAndSettle();

      expect(
        [for (final s in store.goalSubtasks(goal.id)) s.title],
        ['Chapter 2'],
      );
      expect(store.undoName, 'Delete Subtask');
      expect(find.bySemanticsLabel('Mark Chapter 1 as done'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('"From the goal" has the open subtasks of the goal that are '
        'in no block, and a click puts one in this block', (tester) async {
      await open(
        tester,
        before: () {
          // "Chapter 3" is done. "Chapter 4" is in another block.
          store
            ..addGoalSubtask(to: goal.id, title: 'Chapter 3')
            ..addGoalSubtask(to: goal.id, title: 'Chapter 4');
          store.toggleGoalSubtask(sub('Chapter 3').id);
          final other = goalBlock(store, start: 14 * 60, length: 60);
          store.assignGoalSubtask(sub('Chapter 4').id, to: other);
        },
      );

      expect(find.text('From the goal'), findsOneWidget);
      expect(free('Chapter 1'), findsOneWidget);
      expect(free('Chapter 2'), findsOneWidget);
      expect(free('Chapter 3'), findsNothing);
      expect(free('Chapter 4'), findsNothing);
      expect(
        find.text(
          'Only this block has these. Other blocks of the goal keep their '
          'own.',
        ),
        findsOneWidget,
      );

      await tester.tap(free('Chapter 2'));
      await tester.pumpAndSettle();

      expect(sub('Chapter 2').eventId, id);
      expect(sub('Chapter 1').eventId, isNull);
      expect(store.undoName, 'Plan Subtask');
      expect(free('Chapter 2'), findsNothing);
      expect(free('Chapter 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Mark Chapter 2 as done'), findsOneWidget);
      expect(find.text('Subtasks  0/1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a block with its own subtasks only, of a goal with no free '
        'subtask, has no "From the goal" part', (tester) async {
      await open(
        tester,
        own: ['Own one'],
        before: () {
          store
            ..toggleGoalSubtask(sub('Chapter 1').id)
            ..toggleGoalSubtask(sub('Chapter 2').id);
        },
      );
      expect(find.text('From the goal'), findsNothing);
      expect(find.text('Subtasks  0/1'), findsOneWidget);
    });

    testWidgets('on a phone: one tap on a line of "From the goal" puts the '
        'subtask in the block, and the places to tap fit a finger', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await open(tester, planned: ['Chapter 1'], size: phoneSize);

      final box = tester.getRect(editor);
      expect(box.left, greaterThanOrEqualTo(0));
      expect(box.right, lessThanOrEqualTo(phoneSize.width));
      expect(box.bottom, lessThanOrEqualTo(phoneSize.height));
      for (final f in [
        find.bySemanticsLabel('Put Chapter 1 back in the goal'),
        find.bySemanticsLabel('Delete subtask Chapter 1'),
        find.bySemanticsLabel('Put Chapter 2 in this block'),
      ]) {
        expect(f, findsOneWidget);
        expect(tester.getSize(f).shortestSide, greaterThanOrEqualTo(28));
      }

      await tester.tap(free('Chapter 2'));
      await tester.pumpAndSettle();

      expect(sub('Chapter 2').eventId, id);
      expect(find.text('From the goal'), findsNothing);
      expect(find.text('Subtasks  0/2'), findsOneWidget);
      // Goal order in the window: "Chapter 1" is over "Chapter 2".
      expect(
        top(tester, 'Mark Chapter 1 as done'),
        lessThan(top(tester, 'Mark Chapter 2 as done')),
      );
      handle.dispose();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the window stays when the last subtask of the goal goes '
        'back to the goal', (tester) async {
      await open(tester, planned: ['Chapter 1']);

      await tester.tap(find.bySemanticsLabel('Put Chapter 1 back in the goal'));
      await tester.pumpAndSettle();

      expect(editor, findsOneWidget);
      expect(find.text('Subtasks'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
