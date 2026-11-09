// Golden screenshots of the Goals screen.
//
// Make the pictures again after a wanted change of the look:
//   cd app && flutter test --update-goldens test/ui/goal_map
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/store_app.dart';

import '../planner/planner_support.dart';
import '../tasks/tasks_support.dart' show textOffPixels;

const _done = '2026-10-06T12:00:00';

/// The project of the owner's example: it has each state a square can have,
/// a shared square and a wait that is over.
AppStore _scene({ThemeId theme = ThemeId.grove, bool dark = false}) {
  final store = plannerStore(now: 10 * 60 + 20);
  store
    ..setTheme(theme)
    ..setAppearance(dark ? AppearanceMode.dark : AppearanceMode.light);
  const goal = 'hub';
  store.repos.goals.upsert(
    GoalItem(
      id: goal,
      title: 'Delft AI Hub work',
      color: 'teal',
      notes: 'The grant report and the demo for the hub.',
      type: GoalType.project,
      dueDay: d('2026-10-30'),
      workMinutes: 40 * 60,
      sort: 1,
    ),
  );
  store.repos.goals.upsert(
    GoalItem(id: 'read', title: 'Read', color: 'orange', sort: 2),
  );
  final root = GoalSquare.rootIdOf(goal);
  void square(
    String id,
    String title, {
    bool done = false,
    int? wait,
    String? started,
    int sort = 0,
  }) => store.repos.goalSquares.save(
    GoalSquare(
      id: id,
      goalId: goal,
      title: title,
      doneAt: done ? _done : null,
      waitMinutes: wait,
      waitStartedAt: started,
      sort: sort + 0.0,
    ),
  );
  void link(String child, String parent) => store.repos.goalSquares.addLink(
    SquareLink(childId: child, parentId: parent),
  );
  square(root, '');
  square('report', 'Write the report', sort: 1);
  square('demo', 'Build the demo', sort: 2);
  square('data', 'Get the data', done: true, sort: 3);
  square(
    'apply',
    'Wait for access',
    wait: 3 * 24 * 60,
    started: '2026-10-06T09:00:00',
    sort: 4,
  );
  square('outline', 'Make an outline', sort: 5);
  square('over', 'Ask the lab', wait: 24 * 60, started: '2026-10-01T09:00:00');
  link('report', root);
  link('demo', root);
  link('data', 'report');
  link('data', 'demo');
  link('apply', 'demo');
  link('outline', 'report');
  link('over', 'data');
  store.resetAfterReplace();
  store.screen = Screen.goals;
  store.showMapGoal(goal);
  return store;
}

void main() {
  setUpAll(() async {
    TolerantGoldenComparator.install();
    await loadIconFont();
  });

  for (final (name, dark, theme) in [
    ('grove_light', false, ThemeId.grove),
    ('grove_dark', true, ThemeId.grove),
    ('futuristic_light', false, ThemeId.futuristic),
  ]) {
    testWidgets('the goals screen, $name', (tester) async {
      await withRealShadows(() async {
        final store = _scene(theme: theme, dark: dark);
        await pumpPlanner(tester, store);
        expect(textOffPixels(tester), isEmpty);
        await expectLater(
          find.byType(StoreApp),
          matchesGoldenFile('goldens/goals_screen_$name.png'),
        );
      });
    });
  }

  testWidgets('a selected square shows its sheet', (tester) async {
    await withRealShadows(() async {
      final store = _scene();
      await pumpPlanner(tester, store);
      final box = tester.getRect(find.byKey(const ValueKey('square-demo')));
      await tester.tapAt(box.topLeft + Offset(box.width * 0.6, box.height / 2));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(StoreApp),
        matchesGoldenFile('goldens/goals_screen_selected.png'),
      );
    });
  });

  testWidgets('the goals screen on a phone', (tester) async {
    await withRealShadows(() async {
      final store = _scene();
      await pumpPlanner(tester, store, size: const Size(390, 800));
      expect(textOffPixels(tester), isEmpty);
      await expectLater(
        find.byType(StoreApp),
        matchesGoldenFile('goldens/goals_screen_phone.png'),
      );
    });
  });

  testWidgets('a habit on the goals screen', (tester) async {
    await withRealShadows(() async {
      final store = _scene();
      await pumpPlanner(tester, store);
      await tester.tap(find.byKey(const ValueKey('map-goal-read')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(StoreApp),
        matchesGoldenFile('goldens/goals_screen_habit.png'),
      );
    });
  });
}
