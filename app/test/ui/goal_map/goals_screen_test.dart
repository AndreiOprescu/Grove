// The Goals screen: the map, the form, the sheet of a square and the keys.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/goal_map/goals_screen.dart';

import '../tasks/tasks_support.dart';

Finder byKey(String key) => find.byKey(ValueKey(key));
Finder square(String id) => byKey('square-$id');

const wide = Size(1100, 760);
const phone = Size(390, 800);

Future<AppStore> pumpGoals(
  WidgetTester tester, {
  Size size = wide,
  void Function(AppStore store)? setUp,
}) async {
  final store = paneStore();
  setUp?.call(store);
  await pumpPane(tester, GoalsScreen(store: store), size: size);
  return store;
}

/// A project "Trip" with the steps "Book" and "Pack", both under the root.
GoalItem addTrip(AppStore store) {
  final goal = store.addProject(title: 'Trip')!;
  final root = GoalSquare.rootIdOf(goal.id);
  store.addSquare(parentId: root, title: 'Book');
  store.addSquare(parentId: root, title: 'Pack');
  store.showMapGoal(goal.id);
  return goal;
}

String idOf(AppStore store, GoalItem goal, String title) {
  final graph = store.goalGraph(goal.id)!;
  return graph.ids.firstWhere((id) => graph.square(id).title == title);
}

Future<void> tapSquare(WidgetTester tester, String id) async {
  // The name, not the middle: the icon at the left is the tick.
  final box = tester.getRect(square(id));
  await tester.tapAt(box.topLeft + Offset(box.width * 0.6, box.height / 2));
  await tester.pumpAndSettle();
}

void main() {
  group('a new goal', () {
    testWidgets('with no goals the screen says so and offers a new goal', (
      tester,
    ) async {
      await pumpGoals(tester);
      expect(find.textContaining('No goals yet'), findsOneWidget);
      expect(byKey('map-new-goal'), findsOneWidget);
    });

    testWidgets('no field of a project is needed. The map shows', (
      tester,
    ) async {
      final store = await pumpGoals(tester);
      await tester.tap(byKey('map-new-goal'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('form-save'));
      await tester.pumpAndSettle();

      final goal = store.goals().single;
      expect(goal.isProject, isTrue);
      expect(goal.title, '');
      expect(store.shownMapGoal?.id, goal.id);
      expect(square(GoalSquare.rootIdOf(goal.id)), findsOneWidget);
    });

    testWidgets('all fields of a project are saved', (tester) async {
      final store = await pumpGoals(tester);
      await tester.tap(byKey('map-new-goal'));
      await tester.pumpAndSettle();
      await tester.enterText(byKey('form-title'), 'Delft AI Hub');
      await tester.enterText(byKey('form-what'), 'The work');
      await tester.enterText(byKey('form-done-when'), 'Report sent');
      await tester.enterText(byKey('form-work'), '2,5');
      await tester.enterText(byKey('form-why'), 'It pays');
      await tester.tap(byKey('form-save'));
      await tester.pumpAndSettle();

      final goal = store.goals().single;
      expect(goal.title, 'Delft AI Hub');
      expect(goal.notes, 'The work');
      expect(goal.doneWhen, 'Report sent');
      expect(goal.workMinutes, 150);
      expect(goal.why, 'It pays');
      expect(goal.dueDay, isNull);
    });

    testWidgets('a habit needs a name', (tester) async {
      final store = await pumpGoals(tester);
      await tester.tap(byKey('map-new-goal'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('form-type-habit'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('form-save'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(store.goals(), isEmpty);
      expect(byKey('form-save'), findsOneWidget);

      await tester.enterText(byKey('form-title'), 'Read');
      await tester.pump();
      await tester.tap(byKey('form-save'));
      await tester.pumpAndSettle();
      final goal = store.goals().single;
      expect(goal.isProject, isFalse);
      expect(goal.title, 'Read');
    });

    testWidgets('cancel makes nothing', (tester) async {
      final store = await pumpGoals(tester);
      await tester.tap(byKey('map-new-goal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.goals(), isEmpty);
    });

    testWidgets('a form with a date can lose the date', (tester) async {
      late GoalItem goal;
      final store = await pumpGoals(
        tester,
        setUp: (s) {
          goal = s.addProject(title: 'Trip', dueDay: d('2026-10-20'))!;
          s.showMapGoal(goal.id);
        },
      );
      expect(find.textContaining('By '), findsOneWidget);
      await tester.tap(byKey('map-edit'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('form-due-clear'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('form-save'));
      await tester.pumpAndSettle();
      expect(store.goal(goal.id)!.dueDay, isNull);
      expect(find.textContaining('By '), findsNothing);
    });
  });

  group('a habit', () {
    testWidgets('has no map, and a button makes it a project', (tester) async {
      late GoalItem goal;
      final store = await pumpGoals(
        tester,
        setUp: (s) {
          goal = s.addGoal(title: 'Read', kind: GoalKind.hours, target: 60)!;
          s.addGoalSubtask(to: goal.id, title: 'Chapter 1');
          s.showMapGoal(goal.id);
        },
      );
      final root = GoalSquare.rootIdOf(goal.id);
      expect(square(root), findsNothing);

      await tester.tap(byKey('make-project'));
      await tester.pumpAndSettle();

      expect(store.goal(goal.id)!.isProject, isTrue);
      expect(square(root), findsOneWidget);
      expect(find.text('Chapter 1'), findsOneWidget);
    });
  });

  group('the tool bar', () {
    testWidgets('add with nothing selected adds a loose step, selects the '
        'new step and asks for its name', (tester) async {
      late GoalItem goal;
      final store = await pumpGoals(
        tester,
        setUp: (s) {
          goal = s.addProject(title: 'Trip')!;
          s.showMapGoal(goal.id);
        },
      );
      await tester.tap(byKey('map-tool-add'));
      await tester.pumpAndSettle();

      final graph = store.goalGraph(goal.id)!;
      // The new step has no line yet, so it does not count as a step.
      expect(graph.ids, hasLength(2));
      expect(graph.stepCount, 0);
      final made = graph.ids.firstWhere((i) => i != graph.rootId);
      expect(graph.isLoose(made), isTrue);
      expect(byKey('square-sheet'), findsOneWidget);
      await tester.enterText(byKey('square-name'), 'Book');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final id = store
          .goalGraph(goal.id)!
          .ids
          .firstWhere((i) => i != graph.rootId);
      expect(store.goalSquare(id)!.title, 'Book');
    });

    testWidgets('link lights up the targets, and a tap links', (tester) async {
      late GoalItem goal;
      final store = await pumpGoals(tester, setUp: (s) => goal = addTrip(s));
      final book = idOf(store, goal, 'Book');
      final pack = idOf(store, goal, 'Pack');
      await tapSquare(tester, book);
      await tester.tap(byKey('map-tool-link'));
      await tester.pumpAndSettle();
      expect(byKey('map-link-banner'), findsOneWidget);

      await tapSquare(tester, pack);

      expect(byKey('map-link-banner'), findsNothing);
      expect(store.goalGraph(goal.id)!.childrenOf(pack), contains(book));
    });

    testWidgets('fit shows the whole map', (tester) async {
      await pumpGoals(tester, setUp: addTrip);
      await tester.tap(byKey('map-tool-fit'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('the sheet of a square', () {
    testWidgets('shows beside the map on a wide window, over it on a phone', (
      tester,
    ) async {
      late GoalItem goal;
      var store = await pumpGoals(tester, setUp: (s) => goal = addTrip(s));
      await tapSquare(tester, idOf(store, goal, 'Book'));
      expect(tester.getSize(byKey('square-sheet')).width, 280);

      store = await pumpGoals(
        tester,
        size: phone,
        setUp: (s) => goal = addTrip(s),
      );
      await tapSquare(tester, GoalSquare.rootIdOf(goal.id));
      expect(tester.getSize(byKey('square-sheet')).width, phone.width - 24);
      expect(store.goal(goal.id), isNotNull);
    });

    testWidgets('start waiting, then stop waiting', (tester) async {
      late GoalItem goal;
      final store = await pumpGoals(tester, setUp: (s) => goal = addTrip(s));
      final book = idOf(store, goal, 'Book');
      await tapSquare(tester, book);

      await tester.tap(find.byKey(const ValueKey('wait-more')));
      await tester.pump();
      await tester.tap(byKey('square-start-wait'));
      await tester.pumpAndSettle();

      final waiting = store.goalSquare(book)!;
      expect(waiting.waitMinutes, 4 * 24 * 60);
      expect(waiting.isWaiting, isTrue);
      expect(byKey('square-wait-label'), findsOneWidget);

      await tester.tap(byKey('square-stop-wait'));
      await tester.pumpAndSettle();
      expect(store.goalSquare(book)!.isWaiting, isFalse);
    });

    testWidgets('the tick marks the step done', (tester) async {
      late GoalItem goal;
      final store = await pumpGoals(tester, setUp: (s) => goal = addTrip(s));
      final book = idOf(store, goal, 'Book');
      await tapSquare(tester, book);
      await tester.tap(byKey('square-tick'));
      await tester.pumpAndSettle();
      expect(store.goalSquare(book)!.isDone, isTrue);
    });

    testWidgets('a link can go, and the last one leaves the step loose', (
      tester,
    ) async {
      late GoalItem goal;
      final store = await pumpGoals(tester, setUp: (s) => goal = addTrip(s));
      final root = GoalSquare.rootIdOf(goal.id);
      final book = idOf(store, goal, 'Book');
      final pack = idOf(store, goal, 'Pack');

      store.linkSquares(child: book, parent: pack);
      await tester.pumpAndSettle();
      await tapSquare(tester, book);
      expect(byKey('square-unlink-$book-$root'), findsOneWidget);
      await tester.tap(byKey('square-unlink-$book-$pack'));
      await tester.pumpAndSettle();
      expect(store.goalGraph(goal.id)!.parentsOf(book), [root]);

      // The last link can go too. The step then has no line.
      await tester.tap(byKey('square-unlink-$book-$root'));
      await tester.pumpAndSettle();
      final graph = store.goalGraph(goal.id)!;
      expect(graph.parentsOf(book), isEmpty);
      expect(graph.isLoose(book), isTrue);
      expect(byKey('square-unlink-$book-$root'), findsNothing);
    });

    testWidgets('delete joins the children to the parents', (tester) async {
      late GoalItem goal;
      late String child;
      final store = await pumpGoals(
        tester,
        setUp: (s) {
          goal = addTrip(s);
          child = s
              .addSquare(parentId: idOf(s, goal, 'Book'), title: 'Find dates')!
              .id;
        },
      );
      final book = idOf(store, goal, 'Book');
      await tapSquare(tester, book);
      await tester.ensureVisible(byKey('square-delete'));
      await tester.tap(byKey('square-delete'));
      await tester.pumpAndSettle();
      final graph = store.goalGraph(goal.id)!;
      expect(graph.contains(book), isFalse);
      expect(graph.parentsOf(child), [graph.rootId]);
      expect(byKey('square-sheet'), findsOneWidget);
    });

    testWidgets('the root has no delete and no wait', (tester) async {
      late GoalItem goal;
      await pumpGoals(tester, setUp: (s) => goal = addTrip(s));
      await tapSquare(tester, GoalSquare.rootIdOf(goal.id));
      expect(byKey('square-delete'), findsNothing);
      expect(byKey('square-start-wait'), findsNothing);
    });

    testWidgets('an undo takes the selected square away and the sheet closes', (
      tester,
    ) async {
      late GoalItem goal;
      final store = await pumpGoals(tester, setUp: (s) => goal = addTrip(s));
      await tapSquare(tester, idOf(store, goal, 'Pack'));
      expect(byKey('square-sheet'), findsOneWidget);
      store.undo();
      await tester.pumpAndSettle();
      expect(byKey('square-sheet'), findsNothing);
      // The line that says what the undo did goes away by itself.
      await tester.pump(const Duration(seconds: 10));
    });
  });

  group('finishing', () {
    testWidgets('with open steps it asks first. No keeps it open', (
      tester,
    ) async {
      late GoalItem goal;
      final store = await pumpGoals(tester, setUp: (s) => goal = addTrip(s));
      final root = GoalSquare.rootIdOf(goal.id);
      await tapSquare(tester, root);
      await tester.tap(byKey('square-tick'));
      await tester.pumpAndSettle();
      expect(
        find.text('2 steps are still open. Finish anyway?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.isProjectFinished(goal.id), isFalse);

      await tester.tap(byKey('square-tick'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('finish-early-confirm'));
      await tester.pumpAndSettle();
      expect(store.isProjectFinished(goal.id), isTrue);
      // The steps stay open, and the tick opens the project again.
      expect(store.goalGraph(goal.id)!.stepCount, 2);
      await tester.tap(byKey('square-tick'));
      await tester.pumpAndSettle();
      expect(store.isProjectFinished(goal.id), isFalse);
    });

    testWidgets('with all steps done it does not ask', (tester) async {
      late GoalItem goal;
      final store = await pumpGoals(
        tester,
        setUp: (s) {
          goal = addTrip(s);
          s.toggleSquareDone(idOf(s, goal, 'Book'));
          s.toggleSquareDone(idOf(s, goal, 'Pack'));
        },
      );
      await tapSquare(tester, GoalSquare.rootIdOf(goal.id));
      await tester.tap(byKey('square-tick'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Finish anyway'), findsNothing);
      expect(store.isProjectFinished(goal.id), isTrue);
    });
  });

  group('the keys', () {
    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    testWidgets('Tab adds a child and Enter adds a step next to it', (
      tester,
    ) async {
      late GoalItem goal;
      final store = await pumpGoals(tester, setUp: (s) => goal = addTrip(s));
      final book = idOf(store, goal, 'Book');
      await tapSquare(tester, book);

      await press(tester, LogicalKeyboardKey.tab);
      expect(store.goalGraph(goal.id)!.childrenOf(book), hasLength(1));
      // The new step asks for its name, so the keys go to the text field.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final child = store.goalGraph(goal.id)!.childrenOf(book).single;
      await press(tester, LogicalKeyboardKey.enter);
      final graph = store.goalGraph(goal.id)!;
      expect(graph.childrenOf(book), hasLength(2));
      expect(graph.childrenOf(book), contains(child));
    });

    testWidgets('Delete takes the step away, and the root stays', (
      tester,
    ) async {
      late GoalItem goal;
      final store = await pumpGoals(tester, setUp: (s) => goal = addTrip(s));
      final book = idOf(store, goal, 'Book');
      await tapSquare(tester, book);
      await press(tester, LogicalKeyboardKey.delete);
      expect(store.goalGraph(goal.id)!.contains(book), isFalse);

      await tapSquare(tester, GoalSquare.rootIdOf(goal.id));
      await press(tester, LogicalKeyboardKey.backspace);
      expect(store.goalGraph(goal.id)!.stepCount, 1);
    });

    testWidgets('Escape ends the link, then the selection', (tester) async {
      late GoalItem goal;
      final store = await pumpGoals(tester, setUp: (s) => goal = addTrip(s));
      await tapSquare(tester, idOf(store, goal, 'Book'));
      await tester.tap(byKey('map-tool-link'));
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.escape);
      expect(byKey('map-link-banner'), findsNothing);
      expect(byKey('square-sheet'), findsOneWidget);

      await press(tester, LogicalKeyboardKey.escape);
      expect(byKey('square-sheet'), findsNothing);
    });

    testWidgets('keys typed in the name stay in the name', (tester) async {
      late GoalItem goal;
      final store = await pumpGoals(tester, setUp: (s) => goal = addTrip(s));
      final book = idOf(store, goal, 'Book');
      await tapSquare(tester, book);
      await tester.tap(byKey('square-name'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expect(store.goalGraph(goal.id)!.contains(book), isTrue);
    });
  });

  group('the list', () {
    testWidgets('changes the goal on the map', (tester) async {
      late GoalItem trip;
      late GoalItem move;
      final store = await pumpGoals(
        tester,
        setUp: (s) {
          trip = addTrip(s);
          move = s.addProject(title: 'Move')!;
          s.showMapGoal(trip.id);
        },
      );
      expect(square(GoalSquare.rootIdOf(trip.id)), findsOneWidget);
      await tester.tap(byKey('map-goal-${move.id}'));
      await tester.pumpAndSettle();
      expect(store.shownMapGoal?.id, move.id);
      expect(square(GoalSquare.rootIdOf(move.id)), findsOneWidget);
      expect(square(GoalSquare.rootIdOf(trip.id)), findsNothing);
    });

    testWidgets('fits on a phone with no overflow', (tester) async {
      await pumpGoals(tester, size: phone, setUp: addTrip);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('on a phone, the keyboard leaves the square and its plus free', (
    tester,
  ) async {
    const size = Size(412, 560);
    final store = paneStore();
    final goal = store.addProject(title: 'Trip')!;
    final root = GoalSquare.rootIdOf(goal.id);
    store.addSquare(parentId: root, title: 'Book');
    store.openGoalMap(goal.id);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await pumpPane(tester, GoalsScreen(store: store), size: size);
    await tester.tap(find.byKey(ValueKey('square-$root')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('map-goal-list')), findsNothing);
    expect(find.byKey(const ValueKey('map-header')), findsNothing);
    expect(
      find.byKey(const ValueKey('square-add-child')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('square-add-child')));
    await tester.pumpAndSettle();
    expect(store.goalGraph(goal.id)!.ids.length, 3);
  });

  testWidgets('on a phone, each new step comes out from under the sheet', (
    tester,
  ) async {
    final store = paneStore();
    final goal = store.addProject(title: 'Trip')!;
    store.openGoalMap(goal.id);
    await pumpPane(
      tester,
      GoalsScreen(store: store),
      size: const Size(412, 800),
    );
    await tester.tap(
      find.byKey(ValueKey('square-${GoalSquare.rootIdOf(goal.id)}')),
    );
    await tester.pumpAndSettle();
    final plus = find.byKey(const ValueKey('square-add-child'));
    for (var count = 2; count <= 6; count++) {
      expect(plus.hitTestable(), findsOneWidget);
      await tester.tap(plus);
      await tester.pumpAndSettle();
      expect(store.goalGraph(goal.id)!.ids.length, count);
    }
  });
}
