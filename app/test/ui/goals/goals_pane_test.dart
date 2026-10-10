import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/goals/goal_row.dart';
import 'package:grove/ui/goals/goals_pane.dart';

import '../tasks/tasks_support.dart';

Finder byKey(String key) => find.byKey(ValueKey(key));

final addField = byKey('goal-add');

Finder input(Finder field) =>
    find.descendant(of: field, matching: find.byType(EditableText));

Finder goalRow(GoalItem goal) => byKey('goal-${goal.id}');

/// The text field for the name in the editor of `goal`.
Finder nameField(GoalItem goal) => byKey('goal-name-${goal.id}');

/// The plus or minus button of the stepper inside `scope`.
Finder step(Finder scope, {required bool up}) => find.descendant(
  of: scope,
  matching: byKey(up ? 'target-more' : 'target-less'),
);

final adder = find.byType(GoalAddRow);

Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<AppStore> pumpGoals(
  WidgetTester tester, {
  void Function(AppStore store)? before,
  Size size = paneSize,
}) async {
  final store = paneStore();
  before?.call(store);
  await pumpPane(tester, GoalsPane(store: store), size: size);
  return store;
}

void main() {
  group('the panel', () {
    testWidgets('an empty panel says what a goal is', (tester) async {
      await pumpGoals(tester);
      expect(find.text('Goals'), findsOneWidget);
      expect(find.text('This week'), findsOneWidget);
      expect(find.textContaining('No goals yet.'), findsOneWidget);
      expect(find.text('5 h / week'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the header names the week of the selected day', (
      tester,
    ) async {
      final store = await pumpGoals(tester);
      store.selectedDay = d('2026-10-14');
      await tester.pumpAndSettle();
      expect(find.text('12–18 Oct'), findsOneWidget);
    });

    testWidgets('a row shows the done and the planned time of the week', (
      tester,
    ) async {
      late GoalItem read;
      await pumpGoals(
        tester,
        before: (store) {
          read = store.addGoal(title: 'Read')!;
          store.scheduleGoal(
            goalId: read.id,
            day: wednesday,
            start: 600,
            length: 90,
          );
          store.scheduleGoal(
            goalId: read.id,
            day: wednesday.adding(days: 1),
            start: 600,
            length: 60,
          );
          final first = store.repos.events.all().firstWhere(
            (e) => e.start.day == wednesday,
          );
          store.toggleGoalBlockDone(eventId: first.id);
          // A block of the week after does not count.
          store.scheduleGoal(
            goalId: read.id,
            day: wednesday.adding(days: 7),
            start: 600,
          );
        },
      );

      expect(find.text('Read'), findsOneWidget);
      expect(find.text('1.5 / 5 h done'), findsOneWidget);
      expect(find.text('2.5 h planned'), findsOneWidget);
      final bar = tester.widget<GoalBar>(find.byType(GoalBar));
      expect(bar.parts.done, closeTo(0.3, 0.001));
      expect(bar.parts.planned, closeTo(0.5, 0.001));
    });

    testWidgets('a goal with no blocks says so', (tester) async {
      await pumpGoals(
        tester,
        before: (store) =>
            store.addGoal(title: 'Gym', kind: GoalKind.sessions, target: 3),
      );
      expect(find.text('0 / 3 sessions done'), findsOneWidget);
      expect(find.text('Nothing planned yet'), findsOneWidget);
    });
  });

  group('the line to add a goal', () {
    testWidgets('Return adds a goal of 5 hours a week', (tester) async {
      final store = await pumpGoals(tester);
      await typeLine(tester, addField, 'Deep work');

      final goal = store.goals().single;
      expect(goal.title, 'Deep work');
      expect(goal.kind, GoalKind.hours);
      expect(goal.targetMin, 300);
      expect(find.text('0 / 5 h done'), findsOneWidget);
      expect(tester.widget<EditableText>(input(addField)).controller.text, '');
    });

    testWidgets('the stepper sets the hours', (tester) async {
      final store = await pumpGoals(tester);
      await tapOn(tester, step(adder, up: true));
      await tapOn(tester, step(adder, up: true));
      expect(find.text('6 h / week'), findsOneWidget);
      await tapOn(tester, step(adder, up: false));
      expect(find.text('5.5 h / week'), findsOneWidget);

      await typeLine(tester, addField, 'Read');
      expect(store.goals().single.targetMin, 330);
      // The next goal starts from the default again.
      expect(find.text('5 h / week'), findsOneWidget);
    });

    testWidgets('a goal of sessions', (tester) async {
      final store = await pumpGoals(tester);
      await tapOn(
        tester,
        find.descendant(of: adder, matching: find.text('Sessions')),
      );
      expect(find.text('3 sessions / week'), findsOneWidget);
      await tapOn(tester, step(adder, up: false));
      await tapOn(tester, step(adder, up: false));
      expect(find.text('1 session / week'), findsOneWidget);
      // One is the least.
      await tapOn(tester, step(adder, up: false));
      expect(find.text('1 session / week'), findsOneWidget);

      await typeLine(tester, addField, 'Gym');
      final goal = store.goals().single;
      expect(goal.kind, GoalKind.sessions);
      expect(goal.targetCount, 1);
      // The kind stays for the next goal. The target starts again.
      expect(find.text('3 sessions / week'), findsOneWidget);
    });

    testWidgets('a name that is typed is added when the field loses the keys', (
      tester,
    ) async {
      final store = await pumpGoals(tester);
      await tester.tap(addField);
      await tester.enterText(input(addField), 'Read');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(store.goals().single.title, 'Read');
    });

    testWidgets('Esc clears the field and adds nothing', (tester) async {
      final store = await pumpGoals(tester);
      await tester.tap(addField);
      await tester.enterText(input(addField), 'Read');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(store.goals(), isEmpty);
      expect(tester.widget<EditableText>(input(addField)).controller.text, '');
    });

    testWidgets('an empty name adds nothing', (tester) async {
      final store = await pumpGoals(tester);
      await typeLine(tester, addField, '   ');
      expect(store.goals(), isEmpty);
    });
  });

  group('the editor of a goal', () {
    late GoalItem read;
    late GoalItem gym;

    Future<AppStore> withGoals(WidgetTester tester) => pumpGoals(
      tester,
      size: const Size(320, 800),
      before: (store) {
        read = store.addGoal(title: 'Read')!;
        gym = store.addGoal(title: 'Gym', kind: GoalKind.sessions, target: 3)!;
      },
    );

    testWidgets('a click opens it, a second click closes it', (tester) async {
      await withGoals(tester);
      expect(find.byType(GoalEditor), findsNothing);
      await tapOn(tester, goalRow(read));
      expect(nameField(read), findsOneWidget);
      await tapOn(tester, goalRow(read));
      expect(find.byType(GoalEditor), findsNothing);
    });

    testWidgets('one goal is open at a time', (tester) async {
      await withGoals(tester);
      await tapOn(tester, goalRow(read));
      await tapOn(tester, goalRow(gym));
      expect(nameField(read), findsNothing);
      expect(nameField(gym), findsOneWidget);
    });

    testWidgets('Return saves the name and closes the editor', (tester) async {
      final store = await withGoals(tester);
      await tapOn(tester, goalRow(read));
      await typeLine(tester, nameField(read), 'Read books');
      expect(store.goal(read.id)!.title, 'Read books');
      expect(find.byType(GoalEditor), findsNothing);
    });

    testWidgets('Esc drops the typed name and closes the editor', (
      tester,
    ) async {
      final store = await withGoals(tester);
      await tapOn(tester, goalRow(read));
      await tester.tap(nameField(read));
      await tester.enterText(input(nameField(read)), 'Read books');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(store.goal(read.id)!.title, 'Read');
      expect(find.byType(GoalEditor), findsNothing);
    });

    testWidgets('a typed name is saved when the editor closes', (tester) async {
      final store = await withGoals(tester);
      await tapOn(tester, goalRow(read));
      await tester.tap(nameField(read));
      await tester.enterText(input(nameField(read)), 'Read books');
      await tapOn(tester, goalRow(gym));
      expect(store.goal(read.id)!.title, 'Read books');
    });

    testWidgets('the kind, the target and the colour are saved at once', (
      tester,
    ) async {
      final store = await withGoals(tester);
      await tapOn(tester, goalRow(read));
      final editor = find.byType(GoalEditor);

      await tapOn(tester, step(editor, up: true));
      expect(store.goal(read.id)!.targetMin, 330);
      expect(find.text('0 / 5.5 h done'), findsOneWidget);

      await tapOn(
        tester,
        find.descendant(of: editor, matching: byKey('colour-teal')),
      );
      expect(store.goal(read.id)!.color, 'teal');

      await tapOn(
        tester,
        find.descendant(of: editor, matching: find.text('Sessions')),
      );
      expect(store.goal(read.id)!.kind, GoalKind.sessions);
      await tapOn(tester, step(editor, up: true));
      expect(store.goal(read.id)!.targetCount, 4);
      // The hours target is kept for a change back.
      expect(store.goal(read.id)!.targetMin, 330);
    });

    testWidgets('each change of the editor is one undo step', (tester) async {
      final store = await withGoals(tester);
      await tapOn(tester, goalRow(read));
      await tapOn(tester, step(find.byType(GoalEditor), up: true));
      store.undo();
      await tester.pumpAndSettle();
      expect(store.goal(read.id)!.targetMin, 300);
      await endToast(tester);
    });
  });

  group('the menu of a goal', () {
    late GoalItem read;

    Future<AppStore> withGoal(WidgetTester tester) => pumpGoals(
      tester,
      before: (store) {
        read = store.addGoal(title: 'Read')!;
        store.scheduleGoal(goalId: read.id, day: wednesday, start: 600);
      },
    );

    testWidgets('"Edit…" opens the editor', (tester) async {
      await withGoal(tester);
      await rightClick(tester, goalRow(read));
      await tester.tap(find.text('Edit…'));
      await tester.pumpAndSettle();
      expect(nameField(read), findsOneWidget);

      await rightClick(tester, goalRow(read));
      await tester.tap(find.text('Close Editor'));
      await tester.pumpAndSettle();
      expect(find.byType(GoalEditor), findsNothing);
    });

    testWidgets('"Delete Goal…" asks first', (tester) async {
      final store = await withGoal(tester);
      await rightClick(tester, goalRow(read));
      await tester.tap(find.text('Delete Goal…'));
      await tester.pumpAndSettle();
      expect(find.text('Delete “Read”?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.goals().single.title, 'Read');
    });

    testWidgets('a deleted goal leaves its blocks, and undo puts it back', (
      tester,
    ) async {
      final store = await withGoal(tester);
      await rightClick(tester, goalRow(read));
      await tester.tap(find.text('Delete Goal…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete Goal'));
      await tester.pumpAndSettle();

      expect(store.goals(), isEmpty);
      expect(store.repos.events.all().single.goalId, isNull);
      expect(find.textContaining('No goals yet.'), findsOneWidget);

      store.undo();
      await tester.pumpAndSettle();
      expect(store.goals().single.title, 'Read');
      expect(store.repos.events.all().single.goalId, read.id);
      await endToast(tester);
    });
  });

  testWidgets('the panel fits a phone and a long name', (tester) async {
    late GoalItem goal;
    await pumpGoals(
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
    await tapOn(tester, goalRow(goal));
    expect(nameField(goal), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
