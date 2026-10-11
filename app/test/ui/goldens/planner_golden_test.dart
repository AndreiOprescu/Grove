// Golden screenshots of the Day Planner with a full day on it (milestone
// F7). The look to match is the Day Planner demo of design/layouts.html.
//
// Make the pictures again after a wanted change of the look:
//   cd app && flutter test --update-goldens test/ui/goldens
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/store_app.dart';

import '../planner/planner_support.dart';

/// A day with every kind of block: events, task blocks, an overlap, a done
/// task, subtasks, a selected block, an all-day event and tasks with no time.
AppStore _fullDay({ThemeId theme = ThemeId.grove, bool dark = false}) {
  final store = plannerStore(now: 10 * 60 + 20);
  store
    ..setTheme(theme)
    ..setAppearance(dark ? AppearanceMode.dark : AppearanceMode.light)
    ..createFromDraft(
      title: 'Stand-up',
      day: wednesday,
      start: 9 * 60,
      end: 9 * 60 + 30,
      asEvent: true,
    )
    ..createFromDraft(
      title: 'Write the report',
      day: wednesday,
      start: 10 * 60,
      end: 12 * 60,
      asEvent: false,
    )
    ..createFromDraft(
      title: 'Call with Ana',
      day: wednesday,
      start: 11 * 60,
      end: 11 * 60 + 45,
      asEvent: true,
    )
    ..createFromDraft(
      title: 'Lunch',
      day: wednesday,
      start: 12 * 60 + 30,
      end: 13 * 60 + 15,
      asEvent: true,
    )
    ..createFromDraft(
      title: 'Pack for the trip',
      day: wednesday.adding(days: 1),
      start: 9 * 60 + 30,
      end: 11 * 60,
      asEvent: false,
    )
    ..createFromDraft(
      title: 'Email the bank',
      day: wednesday.adding(days: -1),
      start: 9 * 60,
      end: 9 * 60 + 30,
      asEvent: false,
    );
  final report = blockNamed(store, 'Write the report');
  for (final name in ['Outline', 'Numbers', 'Summary']) {
    store.addSubtask(to: report.taskId!, title: name);
  }
  final pack = blockNamed(store, 'Pack for the trip');
  for (final name in ['Socks', 'Shirts', 'Shoes', 'Soap', 'Maps', 'Keys']) {
    store.addSubtask(to: pack.taskId!, title: name);
  }
  store.toggleDone(taskId: blockNamed(store, 'Email the bank').taskId!);
  _note(store, 'NOTE-1', 'Buy bread', wednesday, 101);
  _note(store, 'NOTE-2', 'Water the plants', wednesday, 102);
  _note(store, 'NOTE-3', 'Book the train', wednesday.adding(days: 2), 103);
  store.selection = {blockNamed(store, 'Lunch').id};
  return store;
}

/// A task with no time on `day`. The id is fixed, because the tilt and the
/// colour of a sticky note come from the id. A random id gives a new picture
/// on each run.
void _note(AppStore store, String id, String title, DayKey day, double sort) {
  final task = store.placed(
    TaskItem(id: id, title: title, sort: sort),
    TaskPlacement.day(day),
  );
  store.commit(Mutation('New Task')..tasks.add((before: null, after: task)));
}

void main() {
  setUpAll(() async {
    TolerantGoldenComparator.install();
    await loadIconFont();
  });

  for (final theme in ThemeId.values) {
    testWidgets('planner desktop ${theme.name}', (tester) async {
      await withRealShadows(() async {
        final store = _fullDay(theme: theme);
        await pumpPlanner(tester, store);
        await expectLater(
          find.byType(StoreApp),
          matchesGoldenFile('planner_desktop_${theme.name}_light.png'),
        );
      });
    });
  }

  testWidgets('planner desktop grove dark', (tester) async {
    await withRealShadows(() async {
      final store = _fullDay(dark: true);
      await pumpPlanner(tester, store);
      await expectLater(
        find.byType(StoreApp),
        matchesGoldenFile('planner_desktop_grove_dark.png'),
      );
    });
  });

  testWidgets('planner phone grove', (tester) async {
    await withRealShadows(() async {
      final store = _fullDay();
      await pumpPlanner(tester, store, size: phoneSize);
      await expectLater(
        find.byType(StoreApp),
        matchesGoldenFile('planner_phone_grove_light.png'),
      );
    });
  });
}
