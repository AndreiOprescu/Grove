// Golden screenshots of the Tasks panel and the panel of one task
// (milestone F8).
//
// Make the pictures again after a wanted change of the look:
//   cd app && flutter test --update-goldens test/ui/tasks
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/store_app.dart';
import 'package:grove/ui/tasks/task_inspector.dart';
import 'package:grove/ui/tasks/tasks_pane.dart';

import '../planner/planner_support.dart' show plannerStore, pumpPlanner;
import 'tasks_support.dart';

/// A desktop window with room for the two panels and the planner.
const wideSize = Size(1360, 800);

/// Tasks of every kind: late, with no day, done today, with a priority, a
/// colour, a due date, tags and subtasks. All ids are fixed.
AppStore _scene({ThemeId theme = ThemeId.grove, bool dark = false}) {
  final store = plannerStore(now: 10 * 60 + 20);
  store
    ..setTheme(theme)
    ..setAppearance(dark ? AppearanceMode.dark : AppearanceMode.light);
  addTask(
    store,
    'Send the invoice',
    id: 'invoice',
    day: wednesday.adding(days: -2),
    priority: 2,
    sort: 1,
  );
  addTask(
    store,
    'Fix the bike',
    id: 'bike',
    day: wednesday.adding(days: -1),
    color: 'teal',
    estimateMin: 60,
    sort: 2,
  );
  addTask(
    store,
    'Renew the passport',
    id: 'passport',
    bucket: TaskBucket.inbox,
    priority: 3,
    due: '2026-10-09',
    sort: 3,
  );
  addTask(
    store,
    'Plan the birthday party',
    id: 'party',
    bucket: TaskBucket.inbox,
    priority: 1,
    color: 'purple',
    estimateMin: 90,
    due: '2026-10-16T18:00',
    notes: 'Ask Ana for the list of guests.\nBook the room before Friday.',
    sort: 4,
  );
  addTask(
    store,
    'Book the dentist',
    id: 'dentist',
    bucket: TaskBucket.inbox,
    estimateMin: 15,
    sort: 5,
  );
  addTask(
    store,
    'Water the plants',
    id: 'plants',
    bucket: TaskBucket.inbox,
    sort: 6,
  );
  store
    ..setSummary('party', 'Saturday, at home')
    ..setTags(taskId: 'party', to: ['family', 'home'])
    ..toggleDone(taskId: 'plants');
  store.repos.tasks
    ..save(
      TaskItem(id: 'party-1', title: 'Invite the guests', parentId: 'party'),
    )
    ..save(
      TaskItem(
        id: 'party-2',
        title: 'Order the cake',
        parentId: 'party',
        sort: 1,
        estimateMin: 15,
        status: TaskStatus.done,
        completedAt: '2026-10-06T09:00:00',
      ),
    );
  return store;
}

/// The same tasks, planned for today. For the list of the Today screen.
AppStore _today() {
  final store = paneStore(now: 10 * 60 + 20);
  addTask(store, 'Send the invoice', id: 'invoice', priority: 3, sort: 1);
  addTask(
    store,
    'Fix the bike',
    id: 'bike',
    color: 'teal',
    estimateMin: 60,
    priority: 2,
    sort: 2,
  );
  addTask(
    store,
    'Plan the birthday party',
    id: 'party',
    priority: 1,
    color: 'purple',
    due: '2026-10-09',
    sort: 3,
  );
  addTask(store, 'Book the dentist', id: 'dentist', estimateMin: 15, sort: 4);
  addTask(store, 'Water the plants', id: 'plants', sort: 5);
  store.repos.tasks.save(
    TaskItem(id: 'party-1', title: 'Invite the guests', parentId: 'party'),
  );
  store.toggleDone(taskId: 'plants');
  // An open task with a block yesterday: the card of yesterday shows.
  final yesterday = wednesday.adding(days: -1);
  addTask(store, 'Email the bank', id: 'bank', day: yesterday);
  store.repos.events.save(
    EventItem(
      id: 'bank-block',
      title: 'Email the bank',
      start: WallTime(day: yesterday, minute: 540),
      end: WallTime(day: yesterday, minute: 600),
      kind: EventKind.block,
      taskId: 'bank',
    ),
  );
  return store;
}

void main() {
  setUpAll(() async {
    TolerantGoldenComparator.install();
    await loadIconFont();
  });

  for (final theme in ThemeId.values) {
    testWidgets('tasks desktop ${theme.name}', (tester) async {
      await withRealShadows(() async {
        final store = _scene(theme: theme)
          ..leftPane = LeftPane.tasks
          ..selectedTaskId = 'party';
        await pumpPlanner(tester, store, size: wideSize);
        await tester.tap(find.byKey(const ValueKey('done-toggle')));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(StoreApp),
          matchesGoldenFile('goldens/tasks_desktop_${theme.name}_light.png'),
        );
      });
    });
  }

  testWidgets('tasks desktop grove dark', (tester) async {
    await withRealShadows(() async {
      final store = _scene(dark: true)
        ..leftPane = LeftPane.tasks
        ..selectedTaskId = 'party';
      await pumpPlanner(tester, store, size: wideSize);
      await expectLater(
        find.byType(StoreApp),
        matchesGoldenFile('goldens/tasks_desktop_grove_dark.png'),
      );
    });
  });

  testWidgets('tasks smallest desktop window', (tester) async {
    await withRealShadows(() async {
      final store = _scene()
        ..leftPane = LeftPane.tasks
        ..selectedTaskId = 'passport';
      await pumpPlanner(tester, store);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(StoreApp),
        matchesGoldenFile('goldens/tasks_desktop_small_grove_light.png'),
      );
    });
  });

  testWidgets('tasks phone grove', (tester) async {
    await withRealShadows(() async {
      final store = _scene()..leftPane = LeftPane.tasks;
      await pumpPlanner(tester, store, size: phoneSize);
      await expectLater(
        find.byType(StoreApp),
        matchesGoldenFile('goldens/tasks_phone_grove_light.png'),
      );
    });
  });

  for (final dark in [false, true]) {
    testWidgets('task panel phone grove ${dark ? 'dark' : 'light'}', (
      tester,
    ) async {
      await withRealShadows(() async {
        final store = _scene(dark: dark)
          ..leftPane = LeftPane.tasks
          ..selectedTaskId = 'party';
        await pumpPlanner(tester, store, size: phoneSize);
        await expectLater(
          find.byType(StoreApp),
          matchesGoldenFile(
            'goldens/task_panel_phone_grove_${dark ? 'dark' : 'light'}.png',
          ),
        );
      });
    });
  }

  for (final theme in ThemeId.values) {
    testWidgets('list of today ${theme.name}', (tester) async {
      await withRealShadows(() async {
        final store = _today();
        await pumpPane(
          tester,
          Padding(
            padding: const EdgeInsets.all(12),
            child: TasksPane(store: store, mode: TasksPaneMode.today),
          ),
          size: const Size(344, 700),
          themeId: theme,
        );
        await tester.tap(find.byKey(const ValueKey('subtasks-party')));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/today_list_${theme.name}_light.png'),
        );
      });
    });
  }

  testWidgets('a subtask open in the panel of the task', (tester) async {
    await withRealShadows(() async {
      final store = _scene();
      await pumpPane(
        tester,
        Padding(
          padding: const EdgeInsets.all(12),
          child: TaskInspector(store: store, taskId: 'party'),
        ),
        size: const Size(TaskInspector.width + 24, 900),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('sub-toggle-party-1')),
      );
      await tester.tap(find.byKey(const ValueKey('sub-toggle-party-1')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/task_panel_subtask_grove_light.png'),
      );
    });
  });
}
