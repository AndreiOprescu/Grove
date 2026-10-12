// Golden screenshots of the Goals panel (milestone F8).
//
// Make the pictures again after a wanted change of the look:
//   cd app && flutter test --update-goldens test/ui/goals
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/goal_subtask.dart';
import 'package:grove/ui/store_app.dart';

import '../planner/planner_support.dart';
import '../tasks/tasks_support.dart' show textOffPixels;

/// Three goals with blocks in the week: one of hours with done and planned
/// time, one of sessions over its target, one with nothing planned. The
/// first has five subtasks (one is done), the second two, the third none.
AppStore _scene({ThemeId theme = ThemeId.grove, bool dark = false}) {
  final store = plannerStore(now: 10 * 60 + 20);
  store
    ..setTheme(theme)
    ..setAppearance(dark ? AppearanceMode.dark : AppearanceMode.light);
  store.repos.goals
    ..upsert(GoalItem(id: 'read', title: 'Read', color: 'teal', sort: 1))
    ..upsert(
      GoalItem(
        id: 'gym',
        title: 'Gym',
        color: 'orange',
        kind: GoalKind.sessions,
        targetCount: 2,
        sort: 2,
      ),
    )
    ..upsert(
      GoalItem(
        id: 'thesis',
        title: 'Write the thesis, one chapter at a time',
        targetMin: 600,
        sort: 3,
      ),
    );
  void block(String id, String goal, int dayOffset, int start, int length) {
    final day = wednesday.adding(days: dayOffset);
    store.repos.events.save(
      EventItem(
        id: id,
        title: store.goal(goal)!.title,
        start: WallTime(day: day, minute: start),
        end: WallTime(day: day, minute: start + length),
        kind: EventKind.block,
        goalId: goal,
        color: store.goal(goal)!.color,
        doneAt: dayOffset < 0 ? '2026-10-06T12:00:00' : null,
      ),
    );
  }

  block('read-1', 'read', -1, 9 * 60, 90);
  block('read-2', 'read', 0, 11 * 60, 60);
  block('read-3', 'read', 1, 9 * 60, 60);
  block('gym-1', 'gym', -2, 10 * 60, 60);
  block('gym-2', 'gym', -1, 11 * 60, 60);
  block('gym-3', 'gym', 2, 10 * 60, 60);
  void subtask(String goal, int at, String title, {bool done = false}) =>
      store.repos.goalSubtasks.save(
        GoalSubtaskItem(
          id: '$goal-s$at',
          goalId: goal,
          title: title,
          sort: at + 0.0,
          doneAt: done ? '2026-10-06T12:00:00' : null,
          createdAt: '2026-10-05T09:00:00',
        ),
      );
  subtask('read', 1, 'Chapter 3', done: true);
  subtask('read', 2, 'Chapter 4');
  subtask('read', 3, 'Notes for the book club on Thursday evening');
  subtask('read', 4, 'Return the library books');
  subtask('read', 5, 'Pick the next book');
  subtask('gym', 1, 'Legs');
  subtask('gym', 2, 'Stretch after');
  return store..leftPane = LeftPane.goals;
}

/// A click on the goal: it shows all its subtasks.
Future<void> _open(WidgetTester tester, String goal) async {
  await tester.tap(find.byKey(ValueKey('goal-$goal')));
  await tester.pumpAndSettle();
}

/// The open goal with its editor too.
Future<void> _openEditor(WidgetTester tester, String goal) async {
  await _open(tester, goal);
  await tester.tap(find.byKey(ValueKey('goal-edit-$goal')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TolerantGoldenComparator.install();
    await loadIconFont();
  });

  for (final theme in ThemeId.values) {
    testWidgets('goals desktop ${theme.name}', (tester) async {
      await withRealShadows(() async {
        final store = _scene(theme: theme);
        await pumpPlanner(tester, store);
        await _open(tester, 'read');
        expect(textOffPixels(tester), isEmpty);
        await expectLater(
          find.byType(StoreApp),
          matchesGoldenFile('goldens/goals_desktop_${theme.name}_light.png'),
        );
      });
    });
  }

  testWidgets('goals desktop grove dark', (tester) async {
    await withRealShadows(() async {
      final store = _scene(dark: true);
      await pumpPlanner(tester, store);
      await _openEditor(tester, 'gym');
      expect(textOffPixels(tester), isEmpty);
      await expectLater(
        find.byType(StoreApp),
        matchesGoldenFile('goldens/goals_desktop_grove_dark.png'),
      );
    });
  });

  testWidgets('goals phone grove', (tester) async {
    await withRealShadows(() async {
      final store = _scene();
      await pumpPlanner(tester, store, size: phoneSize);
      expect(textOffPixels(tester), isEmpty);
      await expectLater(
        find.byType(StoreApp),
        matchesGoldenFile('goldens/goals_phone_grove_light.png'),
      );
    });
  });

  testWidgets('no goals yet', (tester) async {
    await withRealShadows(() async {
      final store = plannerStore()..leftPane = LeftPane.goals;
      await pumpPlanner(tester, store);
      expect(textOffPixels(tester), isEmpty);
      await expectLater(
        find.byType(StoreApp),
        matchesGoldenFile('goldens/goals_desktop_empty_grove_light.png'),
      );
    });
  });
}
