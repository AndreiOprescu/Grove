import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/goals/goal_row.dart';
import 'package:grove/ui/goals/goals_pane.dart';
import 'package:grove/ui/theme/panel.dart' show DashedBorder;

import '../tasks/tasks_support.dart';

Finder byKey(String key) => find.byKey(ValueKey(key));

/// The top half of the panel, and the bottom half.
final projects = byKey('goal-section-projects');
final habits = byKey('goal-section-habits');

/// The "+" of each half.
final newProject = byKey('goal-new-project');
final newHabit = byKey('goal-new-habit');

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

/// "Edit goal…" in an open goal.
Finder editLine(GoalItem goal) => byKey('goal-edit-${goal.id}');

Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// A turn of the mouse wheel over the middle of `scope`.
Future<void> wheel(WidgetTester tester, Finder scope, double dy) async {
  final mouse = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(mouse.hover(tester.getCenter(scope)));
  await tester.sendEventToBinding(mouse.scroll(Offset(0, dy)));
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
    testWidgets('an empty panel has a Projects half and a Habits half', (
      tester,
    ) async {
      await pumpGoals(tester);
      expect(find.text('Goals'), findsOneWidget);
      expect(find.text('This week'), findsOneWidget);
      expect(
        find.descendant(of: projects, matching: find.text('Projects')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: habits, matching: find.text('Habits')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: projects, matching: find.text('No projects yet')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: habits, matching: find.text('No habits yet')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: projects, matching: newProject),
        findsOneWidget,
      );
      expect(find.descendant(of: habits, matching: newHabit), findsOneWidget);
      // The box of an empty half is one line high, not the whole half.
      final empty = find.ancestor(
        of: find.text('No projects yet'),
        matching: find.byType(DashedBorder),
      );
      expect(tester.getSize(empty).height, lessThan(60));
      // The old add line is gone.
      expect(byKey('goal-add'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Projects half is on top, and the halves are the same '
        'height', (tester) async {
      // A count beside one heading and none beside the other.
      await pumpGoals(tester, before: (store) => store.addGoal(title: 'Read'));
      final top = tester.getRect(projects);
      final bottom = tester.getRect(habits);
      expect(top.bottom, lessThanOrEqualTo(bottom.top));
      expect(top.height, closeTo(bottom.height, 1));
      // The two "+" sit one over the other, at the right.
      expect(tester.getCenter(newProject).dx, tester.getCenter(newHabit).dx);
    });

    testWidgets('a project is in the top half, a habit in the bottom half', (
      tester,
    ) async {
      late GoalItem trip;
      late GoalItem read;
      await pumpGoals(
        tester,
        before: (store) {
          read = store.addGoal(title: 'Read')!;
          trip = store.addProject(title: 'Trip')!;
        },
      );
      expect(
        find.descendant(of: projects, matching: goalRow(trip)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: habits, matching: goalRow(read)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: habits, matching: goalRow(trip)),
        findsNothing,
      );
      expect(
        find.descendant(of: projects, matching: goalRow(read)),
        findsNothing,
      );
      expect(find.text('No projects yet'), findsNothing);
      expect(find.text('No habits yet'), findsNothing);
    });

    testWidgets('each half scrolls on its own', (tester) async {
      await pumpGoals(
        tester,
        before: (store) {
          for (var i = 0; i < 8; i++) {
            store.addProject(title: 'Project $i');
          }
          for (var i = 0; i < 15; i++) {
            store.addGoal(title: 'Habit $i');
          }
        },
      );
      ScrollPosition positionOf(Finder half) => tester
          .state<ScrollableState>(
            find.descendant(of: half, matching: find.byType(Scrollable)).first,
          )
          .position;

      expect(positionOf(projects).maxScrollExtent, greaterThan(0));
      expect(positionOf(habits).maxScrollExtent, greaterThan(0));

      await wheel(tester, habits, 200);
      expect(positionOf(habits).pixels, greaterThan(0));
      expect(positionOf(projects).pixels, 0);

      await wheel(tester, projects, 120);
      expect(positionOf(projects).pixels, greaterThan(0));
      // The habits stay where they were.
      expect(positionOf(habits).pixels, greaterThan(0));
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

  group('the + of the Projects half', () {
    testWidgets('it opens the form of a project, with no choice of type', (
      tester,
    ) async {
      await pumpGoals(tester);
      await tapOn(tester, newProject);
      expect(find.text('New project'), findsOneWidget);
      expect(byKey('form-type-project'), findsNothing);
      expect(byKey('form-type-habit'), findsNothing);
      expect(byKey('form-done-when'), findsOneWidget);
    });

    testWidgets('Create makes a project and opens its map', (tester) async {
      final store = await pumpGoals(tester);
      await tapOn(tester, newProject);
      await tester.enterText(byKey('form-title'), 'Trip');
      await tester.pump();
      await tapOn(tester, byKey('form-save'));

      final goal = store.goals().single;
      expect(goal.isProject, isTrue);
      expect(goal.title, 'Trip');
      expect(store.screen, Screen.goals);
      expect(store.shownMapGoal?.id, goal.id);
    });

    testWidgets('Cancel makes nothing', (tester) async {
      final store = await pumpGoals(tester);
      await tapOn(tester, newProject);
      await tapOn(tester, find.text('Cancel'));
      expect(store.goals(), isEmpty);
    });
  });

  group('the + of the Habits half', () {
    testWidgets('it opens the form of a habit, with no choice of type', (
      tester,
    ) async {
      await pumpGoals(tester);
      await tapOn(tester, newHabit);
      expect(find.text('New habit'), findsOneWidget);
      expect(byKey('form-type-project'), findsNothing);
      expect(byKey('form-type-habit'), findsNothing);
      expect(byKey('form-done-when'), findsNothing);
      expect(find.text('5 h / week'), findsOneWidget);
    });

    testWidgets('Create makes a habit and opens it', (tester) async {
      final store = await pumpGoals(tester);
      await tapOn(tester, newHabit);
      await tester.enterText(byKey('form-title'), 'Gym');
      await tapOn(tester, find.text('Sessions'));
      await tapOn(tester, byKey('target-less'));
      await tapOn(tester, byKey('form-save'));

      final goal = store.goals().single;
      expect(goal.isProject, isFalse);
      expect(goal.title, 'Gym');
      expect(goal.kind, GoalKind.sessions);
      expect(goal.targetCount, 2);
      // The new habit is open in the bottom half, without its editor.
      expect(
        find.descendant(of: habits, matching: editLine(goal)),
        findsOneWidget,
      );
      expect(find.byType(GoalEditor), findsNothing);
      expect(store.screen, isNot(Screen.goals));
    });

    testWidgets('a new habit at the end of a long list is shown', (
      tester,
    ) async {
      final store = await pumpGoals(
        tester,
        before: (store) {
          for (var i = 0; i < 15; i++) {
            store.addGoal(title: 'Habit $i');
          }
        },
      );
      await tapOn(tester, newHabit);
      await tester.enterText(byKey('form-title'), 'Last');
      await tester.pump();
      await tapOn(tester, byKey('form-save'));
      final goal = store.goals().last;
      expect(goal.title, 'Last');
      final half = tester.getRect(habits);
      final row = tester.getRect(goalRow(goal));
      expect(row.top, greaterThanOrEqualTo(half.top));
      expect(row.bottom, lessThanOrEqualTo(half.bottom));
    });

    testWidgets('a habit needs a name', (tester) async {
      final store = await pumpGoals(tester);
      await tapOn(tester, newHabit);
      await tester.tap(byKey('form-save'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(store.goals(), isEmpty);
      expect(byKey('form-save'), findsOneWidget);
    });

    testWidgets('Cancel makes nothing', (tester) async {
      final store = await pumpGoals(tester);
      await tapOn(tester, newHabit);
      await tapOn(tester, find.text('Cancel'));
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

    // A click on a goal opens its subtasks. The editor is one more click
    // away: "Edit goal…" in the open goal.
    Future<void> openEditor(WidgetTester tester, GoalItem goal) async {
      await tapOn(tester, goalRow(goal));
      await tapOn(tester, editLine(goal));
    }

    testWidgets('"Edit goal…" in the open goal opens it, a click on the goal '
        'closes it', (tester) async {
      await withGoals(tester);
      expect(find.byType(GoalEditor), findsNothing);
      await tapOn(tester, goalRow(read));
      expect(find.byType(GoalEditor), findsNothing);
      await tapOn(tester, editLine(read));
      expect(nameField(read), findsOneWidget);
      await tapOn(tester, goalRow(read));
      expect(find.byType(GoalEditor), findsNothing);
      // The goal opens without the editor the next time.
      await tapOn(tester, goalRow(read));
      expect(find.byType(GoalEditor), findsNothing);
    });

    testWidgets('one goal is open at a time', (tester) async {
      await withGoals(tester);
      await openEditor(tester, read);
      await openEditor(tester, gym);
      expect(nameField(read), findsNothing);
      expect(editLine(read), findsNothing);
      expect(nameField(gym), findsOneWidget);
    });

    testWidgets('one goal is open at a time, with projects in the panel too', (
      tester,
    ) async {
      final store = await pumpGoals(
        tester,
        size: const Size(320, 800),
        before: (store) {
          store.addProject(title: 'Trip');
          read = store.addGoal(title: 'Read')!;
          gym = store.addGoal(title: 'Gym')!;
        },
      );
      await tapOn(tester, goalRow(read));
      expect(editLine(read), findsOneWidget);
      await tapOn(tester, goalRow(gym));
      expect(editLine(read), findsNothing);
      expect(editLine(gym), findsOneWidget);
      // A new habit made with the "+" is the one open goal.
      await tapOn(tester, newHabit);
      await tester.enterText(byKey('form-title'), 'Walk');
      await tester.pump();
      await tapOn(tester, byKey('form-save'));
      final walk = store.goals().firstWhere((g) => g.title == 'Walk');
      expect(editLine(gym), findsNothing);
      expect(editLine(walk), findsOneWidget);
    });

    testWidgets('Return saves the name and closes the editor', (tester) async {
      final store = await withGoals(tester);
      await openEditor(tester, read);
      await typeLine(tester, nameField(read), 'Read books');
      expect(store.goal(read.id)!.title, 'Read books');
      expect(find.byType(GoalEditor), findsNothing);
    });

    testWidgets('Esc drops the typed name and closes the editor', (
      tester,
    ) async {
      final store = await withGoals(tester);
      await openEditor(tester, read);
      await tester.tap(nameField(read));
      await tester.enterText(input(nameField(read)), 'Read books');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(store.goal(read.id)!.title, 'Read');
      expect(find.byType(GoalEditor), findsNothing);
    });

    testWidgets('a typed name is saved when the editor closes', (tester) async {
      final store = await withGoals(tester);
      await openEditor(tester, read);
      await tester.tap(nameField(read));
      await tester.enterText(input(nameField(read)), 'Read books');
      await tapOn(tester, goalRow(gym));
      expect(store.goal(read.id)!.title, 'Read books');
    });

    testWidgets('the kind, the target and the colour are saved at once', (
      tester,
    ) async {
      final store = await withGoals(tester);
      await openEditor(tester, read);
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
      await openEditor(tester, read);
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
      expect(find.text('No habits yet'), findsOneWidget);

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
    await tapOn(tester, editLine(goal));
    expect(nameField(goal), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final (name, size) in [
    ('a phone', phoneSize),
    ('a short window', paneSize),
  ]) {
    testWidgets('on $name each half shows its "+" and a row or more', (
      tester,
    ) async {
      late GoalItem firstProject;
      late GoalItem firstHabit;
      await pumpGoals(
        tester,
        size: size,
        before: (store) {
          firstProject = store.addProject(title: 'Project 0')!;
          for (var i = 1; i < 6; i++) {
            store.addProject(title: 'Project $i');
          }
          firstHabit = store.addGoal(title: 'Habit 0')!;
          for (var i = 1; i < 12; i++) {
            store.addGoal(title: 'Habit $i');
          }
        },
      );
      expect(tester.takeException(), isNull);
      for (final (half, plus, row) in [
        (projects, newProject, goalRow(firstProject)),
        (habits, newHabit, goalRow(firstHabit)),
      ]) {
        final box = tester.getRect(half);
        expect(box.height, greaterThan(100));
        for (final part in [plus, row]) {
          final rect = tester.getRect(part);
          expect(rect.top, greaterThanOrEqualTo(box.top));
          expect(rect.bottom, lessThanOrEqualTo(box.bottom));
        }
        // The "+" takes a tap where it is drawn.
        expect(plus.hitTestable(), findsOneWidget);
      }
    });
  }
}
