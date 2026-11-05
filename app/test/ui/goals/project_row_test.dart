// A project in the Goals panel: its ready squares, its waiting squares, and a
// closed part with the later steps.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/goals/goals_pane.dart';
import 'package:grove/ui/goals/project_row.dart';
import 'package:grove/ui/planner/payload_drag.dart';

import '../tasks/tasks_support.dart';

Finder byKey(String key) => find.byKey(ValueKey(key));

/// Root ← Book ← Dates, and Root ← Pack.
GoalItem addTrip(AppStore store) {
  final goal = store.addProject(title: 'Trip')!;
  final root = GoalSquare.rootIdOf(goal.id);
  final book = store.addSquare(parentId: root, title: 'Book')!;
  store.addSquare(parentId: book.id, title: 'Dates');
  store.addSquare(parentId: root, title: 'Pack');
  return goal;
}

String idOf(AppStore store, GoalItem goal, String title) {
  final graph = store.goalGraph(goal.id)!;
  return graph.ids.firstWhere((id) => graph.square(id).title == title);
}

void main() {
  testWidgets('it lists the ready steps. The later steps are closed', (
    tester,
  ) async {
    final store = paneStore();
    final goal = addTrip(store);
    await pumpPane(tester, GoalsPane(store: store));

    expect(find.byType(ProjectRow), findsOneWidget);
    expect(find.text('Dates'), findsOneWidget);
    expect(find.text('Pack'), findsOneWidget);
    expect(find.text('Book'), findsNothing);
    expect(find.text('Later steps · 2'), findsOneWidget);

    await tester.tap(byKey('project-later-${goal.id}'));
    await tester.pumpAndSettle();
    expect(find.text('Book'), findsOneWidget);
    expect(find.text('Trip'), findsWidgets);
  });

  testWidgets('a waiting step says so', (tester) async {
    final store = paneStore();
    final goal = addTrip(store);
    store.startWaiting(idOf(store, goal, 'Pack'), minutes: 2 * 24 * 60);
    await pumpPane(tester, GoalsPane(store: store));
    expect(find.textContaining('Waiting, 2 days'), findsOneWidget);
  });

  testWidgets('a tap on the box ticks the step', (tester) async {
    final store = paneStore();
    final goal = addTrip(store);
    final pack = idOf(store, goal, 'Pack');
    await pumpPane(tester, GoalsPane(store: store));
    await tester.tap(byKey('project-square-check-$pack'));
    await tester.pumpAndSettle();
    expect(store.goalSquare(pack)!.isDone, isTrue);
    expect(find.text('Pack'), findsNothing);
  });

  testWidgets('a tap on the head opens the map', (tester) async {
    final store = paneStore();
    final goal = addTrip(store);
    await pumpPane(tester, GoalsPane(store: store));
    await tester.tap(byKey('goal-${goal.id}'));
    await tester.pumpAndSettle();
    expect(store.screen, Screen.goals);
    expect(store.shownMapGoal?.id, goal.id);
  });

  testWidgets('a step drags, and the head does not', (tester) async {
    final store = paneStore();
    final goal = addTrip(store);
    final pack = idOf(store, goal, 'Pack');
    await pumpPane(tester, GoalsPane(store: store));
    final drag = tester.widget<PayloadDrag>(byKey('project-square-$pack'));
    expect(drag.payload, DragPayload.square(pack));
    expect(
      find.ancestor(
        of: byKey('goal-${goal.id}'),
        matching: find.byType(PayloadDrag),
      ),
      findsNothing,
    );
  });

  testWidgets('a finished project shows no steps', (tester) async {
    final store = paneStore();
    final goal = addTrip(store);
    store.toggleSquareDone(GoalSquare.rootIdOf(goal.id));
    await pumpPane(tester, GoalsPane(store: store));
    expect(find.text('Pack'), findsNothing);
    expect(find.textContaining('Later steps'), findsNothing);
    expect(byKey('goal-${goal.id}'), findsOneWidget);
  });

  testWidgets('the steps of a project with no name still read well', (
    tester,
  ) async {
    final store = paneStore();
    final goal = store.addProject()!;
    store.addSquare(parentId: GoalSquare.rootIdOf(goal.id));
    await pumpPane(tester, GoalsPane(store: store));
    expect(find.text('Untitled'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a right click opens the map, the form or the delete question', (
    tester,
  ) async {
    final store = paneStore();
    final goal = addTrip(store);
    await pumpPane(tester, GoalsPane(store: store));

    Future<void> openMenu() async {
      await tester.tap(byKey('goal-${goal.id}'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
    }

    await openMenu();
    expect(find.text('Open Map'), findsOneWidget);
    expect(find.text('Delete Goal…'), findsOneWidget);
    await tester.tap(find.text('Open Map'));
    await tester.pumpAndSettle();
    expect(store.screen, Screen.goals);

    await openMenu();
    await tester.tap(find.text('Edit…'));
    await tester.pumpAndSettle();
    expect(byKey('form-save'), findsOneWidget);
  });
}
