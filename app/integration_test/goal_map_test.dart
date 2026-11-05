// The goal map on a real device, with real pointers and all animation on. A
// store in memory, so the data of the device stays as it is:
//   flutter test integration_test/goal_map_test.dart -d macos
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/goal_square.dart';
import 'package:grove/data/data.dart';
import 'package:grove/state/state.dart';
import 'package:grove/ui/store_app.dart';
import 'package:integration_test/integration_test.dart';

final wednesday = DayKey('2026-10-07');

Finder byKey(String key) => find.byKey(ValueKey(key));

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('make a project, add steps, wait, tick, finish, open again', (
    tester,
  ) async {
    final store = AppStore(
      repos: Repos(Database.inMemory()),
      prefs: MemoryPrefs(),
    );
    store.clockOverride = WallTime(day: wednesday, minute: 11 * 60);
    addTearDown(store.dispose);
    await tester.pumpWidget(StoreApp(key: UniqueKey(), store: store));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpAndSettle();

    // A new project, from the Goals screen.
    await tapKey(tester, 'screen-goals');
    expect(store.screen, Screen.goals);
    await tapKey(tester, 'map-new-goal');
    await tester.enterText(byKey('form-title'), 'Delft AI Hub work');
    await tester.pumpAndSettle();
    await tapKey(tester, 'form-save');
    final goal = store.goals().single;
    final root = GoalSquare.rootIdOf(goal.id);
    expect(byKey('square-$root'), findsOneWidget);

    // A step under the root, and a step under that one.
    await tapKey(tester, 'square-$root');
    await tapKey(tester, 'square-add-child');
    expect(store.goalGraph(goal.id)!.ids.length, 2);
    final send = store.goalGraph(goal.id)!.ids.firstWhere((id) => id != root);
    await tester.enterText(byKey('square-name'), 'Send application');
    await tester.pumpAndSettle();
    await tapKey(tester, 'square-add-child');
    expect(store.goalGraph(goal.id)!.ids.length, 3);
    final write = store
        .goalGraph(goal.id)!
        .ids
        .firstWhere((id) => id != root && id != send);
    await tester.enterText(byKey('square-name'), 'Write letter');
    await tester.pumpAndSettle();

    // The new step is ready. The one over it is not.
    expect(store.goalGraph(goal.id)!.readyIds, contains(write));
    expect(store.goalGraph(goal.id)!.readyIds, isNot(contains(send)));

    // Tick it: the next one is ready.
    await tapKey(tester, 'square-tick');
    expect(store.goalGraph(goal.id)!.readyIds, contains(send));

    // Close the sheet. Fit shows all squares again.
    await tapKey(tester, 'square-sheet-close');
    await tapKey(tester, 'map-tool-fit');

    // A wait of some days on the next one.
    await tapKey(tester, 'square-$send');
    await tapKey(tester, 'wait-more');
    await tapKey(tester, 'square-start-wait');
    expect(byKey('square-wait-label'), findsOneWidget);

    // Fit shows the whole map, on any size of screen.
    await tapKey(tester, 'square-sheet-close');
    await tapKey(tester, 'map-tool-fit');
    final view = tester.getRect(find.byType(Scaffold).first);
    expect(tester.getRect(byKey('square-$root')).right, lessThan(view.right));

    // Finish early: Grove asks first. Taking the tick away opens it again.
    await tapKey(tester, 'square-$root');
    await tapKey(tester, 'square-tick');
    await tapKey(tester, 'finish-early-confirm');
    expect(store.isProjectFinished(goal.id), isTrue);
    await tapKey(tester, 'square-tick');
    expect(store.isProjectFinished(goal.id), isFalse);
    expect(tester.takeException(), isNull);
  });
}
