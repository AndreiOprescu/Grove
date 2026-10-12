// The subtasks of a goal in the Goals panel. A closed goal shows the next
// three that are not done. A click on the goal opens it: all subtasks, and a
// line to add one.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/goal_subtask.dart';
import 'package:grove/ui/goals/goal_row.dart';
import 'package:grove/ui/goals/goals_pane.dart';
import 'package:grove/ui/theme/check_box.dart';

import '../planner/planner_support.dart' show plannerStore, pumpPlanner;
import '../tasks/tasks_support.dart';

Finder byKey(String key) => find.byKey(ValueKey(key));

Finder input(Finder field) =>
    find.descendant(of: field, matching: find.byType(EditableText));

Finder goalRow(GoalItem goal) => byKey('goal-${goal.id}');

/// The line to add a subtask to `goal`. Only an open goal has it.
Finder addField(GoalItem goal) => byKey('goal-subtask-add-${goal.id}');

/// The line under a closed goal that says what is not shown.
Finder moreLine(GoalItem goal) => byKey('goal-subtasks-more-${goal.id}');

/// "Edit goal…" in an open goal.
Finder editLine(GoalItem goal) => byKey('goal-edit-${goal.id}');

Finder subRow(GoalSubtaskItem sub) => byKey('goal-subtask-${sub.id}');
Finder subCheck(GoalSubtaskItem sub) => byKey('goal-subtask-check-${sub.id}');
Finder subName(GoalSubtaskItem sub) => byKey('goal-subtask-name-${sub.id}');
Finder subDelete(GoalSubtaskItem sub) => byKey('goal-subtask-delete-${sub.id}');

final anySubRow = find.byWidgetPredicate((w) {
  final key = w.key;
  return key is ValueKey<String> &&
      key.value.startsWith('goal-subtask-') &&
      !key.value.startsWith('goal-subtask-check-') &&
      !key.value.startsWith('goal-subtask-name-') &&
      !key.value.startsWith('goal-subtask-delete-') &&
      !key.value.startsWith('goal-subtask-add-');
});

Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<AppStore> pumpGoals(
  WidgetTester tester, {
  void Function(AppStore store)? before,
  Size size = const Size(320, 800),
}) async {
  final store = paneStore();
  before?.call(store);
  await pumpPane(tester, GoalsPane(store: store), size: size);
  return store;
}

List<String> names(AppStore store, GoalItem goal) => [
  for (final s in store.goalSubtasks(goal.id)) s.title,
];

/// Is the box of this subtask ticked on screen?
bool ticked(WidgetTester tester, GoalSubtaskItem sub) => tester
    .widget<CheckBox>(
      find.descendant(of: subCheck(sub), matching: find.byType(CheckBox)),
    )
    .isOn;

void main() {
  late GoalItem read;
  late GoalItem gym;

  /// "Read" with this many subtasks ("Chapter 1" …), and "Gym" with none.
  Future<AppStore> withGoals(
    WidgetTester tester, {
    int subtasks = 0,
    Size size = const Size(320, 800),
  }) => pumpGoals(
    tester,
    size: size,
    before: (store) {
      read = store.addGoal(title: 'Read')!;
      gym = store.addGoal(title: 'Gym', kind: GoalKind.sessions, target: 3)!;
      for (var i = 1; i <= subtasks; i++) {
        store.addGoalSubtask(to: read.id, title: 'Chapter $i');
      }
    },
  );

  group('a click on a goal', () {
    testWidgets('a goal with no subtasks looks as before when it is closed', (
      tester,
    ) async {
      await withGoals(tester);
      expect(anySubRow, findsNothing);
      expect(addField(read), findsNothing);
      expect(moreLine(read), findsNothing);
    });

    testWidgets('opens it, and a typed line with Return is a new subtask '
        'under the goal', (tester) async {
      final store = await withGoals(tester);
      await tapOn(tester, goalRow(read));
      expect(addField(read), findsOneWidget);
      expect(addField(gym), findsNothing);

      await typeLine(tester, addField(read), 'Chapter 3');
      expect(names(store, read), ['Chapter 3']);
      expect(find.text('Chapter 3'), findsOneWidget);
      // The line is empty again and keeps the keys for the next one.
      final field = tester.widget<EditableText>(input(addField(read)));
      expect(field.controller.text, '');
      expect(field.focusNode.hasFocus, isTrue);

      await typeLine(tester, addField(read), 'Chapter 4');
      expect(names(store, read), ['Chapter 3', 'Chapter 4']);
      expect(names(store, gym), isEmpty);

      // Closed again, the subtasks still show under the goal.
      await tapOn(tester, goalRow(read));
      expect(addField(read), findsNothing);
      expect(find.text('Chapter 3'), findsOneWidget);
      expect(find.text('Chapter 4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a mouse click opens it too', (tester) async {
      await withGoals(tester);
      await tester.tap(goalRow(read), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(addField(read), findsOneWidget);
    });

    testWidgets('the line to add has the keys at once when the goal has no '
        'subtask yet, and not when it has some', (tester) async {
      await withGoals(tester);
      await tapOn(tester, goalRow(read));
      expect(
        tester.widget<EditableText>(input(addField(read))).focusNode.hasFocus,
        isTrue,
      );
      await tapOn(tester, goalRow(read));

      final store = tester.widget<GoalsPane>(find.byType(GoalsPane)).store;
      store.addGoalSubtask(to: gym.id, title: 'Legs');
      await tester.pumpAndSettle();
      await tapOn(tester, goalRow(gym));
      expect(
        tester.widget<EditableText>(input(addField(gym))).focusNode.hasFocus,
        isFalse,
      );
    });

    testWidgets('an empty line adds nothing, and Esc clears the line', (
      tester,
    ) async {
      final store = await withGoals(tester);
      await tapOn(tester, goalRow(read));
      await typeLine(tester, addField(read), '   ');
      expect(names(store, read), isEmpty);

      await tester.enterText(input(addField(read)), 'Chap');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(names(store, read), isEmpty);
      expect(
        tester.widget<EditableText>(input(addField(read))).controller.text,
        '',
      );
    });

    testWidgets('a typed line is added when the line loses the keys', (
      tester,
    ) async {
      final store = await withGoals(tester);
      await tapOn(tester, goalRow(read));
      await tester.enterText(input(addField(read)), 'Chapter 3');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(names(store, read), ['Chapter 3']);
    });

    testWidgets('one goal is open at a time', (tester) async {
      await withGoals(tester);
      await tapOn(tester, goalRow(read));
      await tapOn(tester, goalRow(gym));
      expect(addField(read), findsNothing);
      expect(addField(gym), findsOneWidget);
    });
  });

  group('a goal with five subtasks', () {
    testWidgets('shows three when it is closed and says that there are more', (
      tester,
    ) async {
      final store = await withGoals(tester, subtasks: 5);
      final subs = store.goalSubtasks(read.id);
      for (final s in subs.take(3)) {
        expect(subRow(s), findsOneWidget, reason: s.title);
      }
      for (final s in subs.skip(3)) {
        expect(subRow(s), findsNothing, reason: s.title);
      }
      expect(find.text('Chapter 1'), findsOneWidget);
      expect(find.text('Chapter 4'), findsNothing);
      expect(moreLine(read), findsOneWidget);
      expect(find.text('+2 more'), findsOneWidget);
      // A closed goal has no line to add and no fields.
      expect(addField(read), findsNothing);
      expect(find.byType(EditableText), findsOneWidget);
    });

    testWidgets('a click shows all five, a second click three again', (
      tester,
    ) async {
      final store = await withGoals(tester, subtasks: 5);
      final subs = store.goalSubtasks(read.id);
      await tapOn(tester, goalRow(read));
      for (final s in subs) {
        expect(subRow(s), findsOneWidget, reason: s.title);
      }
      expect(moreLine(read), findsNothing);
      expect(addField(read), findsOneWidget);

      await tapOn(tester, goalRow(read));
      expect(anySubRow, findsNWidgets(3));
      expect(find.text('+2 more'), findsOneWidget);
    });

    testWidgets('a click on a subtask or on the "more" line opens the goal '
        'too', (tester) async {
      final store = await withGoals(tester, subtasks: 5);
      await tapOn(tester, find.text('Chapter 2'));
      expect(anySubRow, findsNWidgets(5));
      await tapOn(tester, goalRow(read));
      expect(anySubRow, findsNWidgets(3));
      await tapOn(tester, moreLine(read));
      expect(anySubRow, findsNWidgets(5));
      expect(store.goalSubtasks(read.id).every((s) => !s.isDone), isTrue);
    });

    testWidgets('a tick in the closed goal takes the subtask away and shows '
        'the next one', (tester) async {
      final store = await withGoals(tester, subtasks: 5);
      final subs = store.goalSubtasks(read.id);
      await tapOn(tester, subCheck(subs[1]));

      expect(store.goalSubtasks(read.id)[1].isDone, isTrue);
      // The goal stays closed.
      expect(addField(read), findsNothing);
      expect(subRow(subs[1]), findsNothing);
      expect(subRow(subs[0]), findsOneWidget);
      expect(subRow(subs[2]), findsOneWidget);
      expect(subRow(subs[3]), findsOneWidget);
      expect(find.text('+1 more · 1 done'), findsOneWidget);

      store.undo();
      await tester.pumpAndSettle();
      expect(subRow(subs[1]), findsOneWidget);
      expect(find.text('+2 more'), findsOneWidget);
      await endToast(tester);
    });

    testWidgets('a tick in the open goal stays in its place, with a line '
        'through the name', (tester) async {
      final store = await withGoals(tester, subtasks: 5);
      final subs = store.goalSubtasks(read.id);
      await tapOn(tester, goalRow(read));
      expect(ticked(tester, subs[1]), isFalse);
      await tapOn(tester, subCheck(subs[1]));

      expect(store.goalSubtasks(read.id)[1].isDone, isTrue);
      expect(ticked(tester, subs[1]), isTrue);
      expect(anySubRow, findsNWidgets(5));
      final name = tester.widget<EditableText>(input(subName(subs[1])));
      expect(name.style.decoration, TextDecoration.lineThrough);

      // A second tick opens it again.
      await tapOn(tester, subCheck(subs[1]));
      expect(store.goalSubtasks(read.id)[1].isDone, isFalse);
      expect(ticked(tester, subs[1]), isFalse);
    });

    testWidgets('the tick is still there after the panel went away and came '
        'back', (tester) async {
      final store = await withGoals(tester, subtasks: 5);
      final subs = store.goalSubtasks(read.id);
      await tapOn(tester, goalRow(read));
      await tapOn(tester, subCheck(subs[0]));

      // Another screen, then the panel again (a new one, closed).
      await pumpPane(tester, const SizedBox(), size: const Size(320, 800));
      expect(find.byType(GoalsPane), findsNothing);
      await pumpPane(
        tester,
        GoalsPane(store: store),
        size: const Size(320, 800),
      );
      expect(subRow(subs[0]), findsNothing);
      expect(find.text('+1 more · 1 done'), findsOneWidget);
      await tapOn(tester, goalRow(read));
      expect(ticked(tester, subs[0]), isTrue);
      expect(ticked(tester, subs[1]), isFalse);
    });
  });

  group('the open goal', () {
    testWidgets('a new name with Return is saved, and is one undo step', (
      tester,
    ) async {
      final store = await withGoals(tester, subtasks: 2);
      final subs = store.goalSubtasks(read.id);
      await tapOn(tester, goalRow(read));
      await typeLine(tester, subName(subs[0]), 'Chapter 1 and 2');
      expect(names(store, read), ['Chapter 1 and 2', 'Chapter 2']);
      expect(store.undoName, 'Rename Subtask');

      store.undo();
      await tester.pumpAndSettle();
      expect(names(store, read), ['Chapter 1', 'Chapter 2']);
      await endToast(tester);
    });

    testWidgets('a typed name is saved when the goal closes', (tester) async {
      final store = await withGoals(tester, subtasks: 2);
      final subs = store.goalSubtasks(read.id);
      await tapOn(tester, goalRow(read));
      await tester.tap(subName(subs[1]));
      await tester.enterText(input(subName(subs[1])), 'Chapter two');
      await tapOn(tester, goalRow(gym));
      expect(names(store, read), ['Chapter 1', 'Chapter two']);
    });

    testWidgets('an empty name is not saved', (tester) async {
      final store = await withGoals(tester, subtasks: 1);
      final sub = store.goalSubtasks(read.id).single;
      await tapOn(tester, goalRow(read));
      await typeLine(tester, subName(sub), '  ');
      expect(names(store, read), ['Chapter 1']);
      expect(
        tester.widget<EditableText>(input(subName(sub))).controller.text,
        'Chapter 1',
      );
    });

    testWidgets('the bin deletes a subtask, and undo brings it back', (
      tester,
    ) async {
      final store = await withGoals(tester, subtasks: 3);
      final subs = store.goalSubtasks(read.id);
      await tapOn(tester, goalRow(read));
      await tapOn(tester, subDelete(subs[1]));
      expect(names(store, read), ['Chapter 1', 'Chapter 3']);
      expect(subRow(subs[1]), findsNothing);

      store.undo();
      await tester.pumpAndSettle();
      expect(names(store, read), ['Chapter 1', 'Chapter 2', 'Chapter 3']);
      expect(subRow(subs[1]), findsOneWidget);
      await endToast(tester);
    });

    testWidgets('a subtask from Undo or another device shows at once', (
      tester,
    ) async {
      final store = await withGoals(tester, subtasks: 1);
      await tapOn(tester, goalRow(read));
      store.addGoalSubtask(to: read.id, title: 'From elsewhere');
      await tester.pumpAndSettle();
      expect(anySubRow, findsNWidgets(2));
      final sub = store.goalSubtasks(read.id).first;
      store.renameGoalSubtask(sub.id, to: 'New name');
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(input(subName(sub))).controller.text,
        'New name',
      );
    });

    testWidgets('"Edit goal…" shows the editor of the goal under the '
        'subtasks, and hides it again', (tester) async {
      final store = await withGoals(tester, subtasks: 2);
      await tapOn(tester, goalRow(read));
      expect(find.byType(GoalEditor), findsNothing);
      expect(find.text('Edit goal…'), findsOneWidget);

      await tapOn(tester, editLine(read));
      expect(byKey('goal-name-${read.id}'), findsOneWidget);
      expect(anySubRow, findsNWidgets(2));
      expect(find.text('Close editor'), findsOneWidget);

      await tapOn(tester, editLine(read));
      expect(find.byType(GoalEditor), findsNothing);
      // The goal is still open.
      expect(addField(read), findsOneWidget);
      expect(store.goal(read.id)!.title, 'Read');
    });

    testWidgets('a deleted goal takes its subtasks out of the panel, and '
        'undo shows them again', (tester) async {
      final store = await withGoals(tester, subtasks: 2);
      await tapOn(tester, goalRow(read));
      store.deleteGoal(read.id);
      await tester.pumpAndSettle();
      expect(anySubRow, findsNothing);
      expect(tester.takeException(), isNull);

      store.undo();
      await tester.pumpAndSettle();
      expect(anySubRow, findsNWidgets(2));
      await endToast(tester);
    });
  });

  group('a phone', () {
    testWidgets('a tap opens the goal, the keyboard adds a subtask, a tap '
        'ticks it', (tester) async {
      late GoalItem goal;
      final store = await pumpGoals(
        tester,
        size: phoneSize,
        before: (store) {
          goal = store.addGoal(
            title: 'A goal with a very long name that needs more than one line',
          )!;
          for (var i = 0; i < 12; i++) {
            store.addGoal(title: 'Goal $i');
          }
        },
      );
      // `tester.tap` is a finger.
      await tapOn(tester, goalRow(goal));
      await typeLine(tester, addField(goal), 'First');
      await typeLine(
        tester,
        addField(goal),
        'A subtask with a very long name that does not fit in one line of a '
        'phone',
      );
      expect(store.goalSubtasks(goal.id).length, 2);
      final first = store.goalSubtasks(goal.id).first;

      await tapOn(tester, subCheck(first));
      expect(store.goalSubtasks(goal.id).first.isDone, isTrue);

      await tapOn(tester, goalRow(goal));
      expect(subRow(first), findsNothing);
      expect(find.text('1 done'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the places to tap are as large as a finger needs', (
      tester,
    ) async {
      final store = await withGoals(tester, subtasks: 5, size: phoneSize);
      final subs = store.goalSubtasks(read.id);
      Size size(Finder f) => tester.getSize(f);

      expect(size(subCheck(subs[0])).shortestSide, greaterThanOrEqualTo(28));
      expect(size(moreLine(read)).height, greaterThanOrEqualTo(28));

      await tapOn(tester, goalRow(read));
      for (final f in [subCheck(subs[0]), subDelete(subs[0]), editLine(read)]) {
        expect(size(f).shortestSide, greaterThanOrEqualTo(28));
      }
      expect(size(addField(read)).height, greaterThanOrEqualTo(28));
      expect(tester.takeException(), isNull);
    });
  });

  // The same steps as the device test "goals: …" in
  // `integration_test/planner_test.dart`, in the whole window.
  for (final (name, size) in [
    ('a computer window', const Size(1100, 620)),
    ('a phone', phoneSize),
  ]) {
    testWidgets('in the whole app on $name: a tap opens a goal, a typed line '
        'is a subtask, a tap ticks it', (tester) async {
      final store = plannerStore()..leftPane = LeftPane.goals;
      final goal = store.addGoal(title: 'Read')!;
      await pumpPlanner(tester, store, size: size);
      expect(goalRow(goal).hitTestable(), findsOneWidget);

      await tester.tap(goalRow(goal));
      await tester.pumpAndSettle();
      await tester.enterText(input(addField(goal)), 'Chapter 3');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final sub = store.goalSubtasks(goal.id).single;
      expect(sub.title, 'Chapter 3');

      await tapOn(tester, subCheck(sub));
      expect(store.goalSubtasks(goal.id).single.isDone, isTrue);

      await tapOn(
        tester,
        find.descendant(of: goalRow(goal), matching: find.text('Read')),
      );
      expect(addField(goal), findsNothing);
      expect(find.text('1 done'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the texts of the subtasks sit on whole pixels', (tester) async {
    await withGoals(tester, subtasks: 5);
    expect(textOffPixels(tester), isEmpty);
    await tapOn(tester, goalRow(read));
    expect(textOffPixels(tester), isEmpty);
    await tapOn(tester, editLine(read));
    expect(textOffPixels(tester), isEmpty);
  });

  testWidgets('a screen reader can tick a subtask and open the goal', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final store = await withGoals(tester, subtasks: 1);
    final sub = store.goalSubtasks(read.id).single;
    expect(find.bySemanticsLabel('Mark Chapter 1 as done'), findsOneWidget);
    await tapOn(tester, goalRow(read));
    expect(find.bySemanticsLabel('Delete subtask Chapter 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Add a subtask'), findsWidgets);
    store.toggleGoalSubtask(sub.id);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Mark Chapter 1 as not done'), findsOneWidget);
    handle.dispose();
  });
}
