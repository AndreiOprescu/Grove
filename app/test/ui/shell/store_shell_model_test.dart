// The shell on the real store (milestone F5, Track A). See docs/tracks.md,
// "Requests to Track B".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/state/state.dart' as state;
import 'package:grove/ui/shell/shell_model.dart';
import 'package:grove/ui/shell/store_shell_model.dart';

import '../../state/support.dart' show makeStore;
import '../support.dart';

/// Motion off, so `pumpAndSettle` can finish.
state.MemoryPrefs stillPrefs([Map<String, Object?> more = const {}]) =>
    state.MemoryPrefs({'appearance.motion': false, ...more});

void main() {
  group('one set of enums', () {
    test('the shell and the store use the same four', () {
      // These lines do not compile with two sets.
      const state.Screen screen = Screen.garden;
      const state.LeftPane pane = LeftPane.goals;
      const state.ThemeId theme = ThemeId.vintage;
      const state.AppearanceMode mode = AppearanceMode.dark;
      expect([screen, pane, theme, mode], hasLength(4));
    });

    test('light or dark still gives a brightness', () {
      expect(AppearanceMode.system.brightness, isNull);
      expect(AppearanceMode.light.brightness, Brightness.light);
      expect(AppearanceMode.dark.brightness, Brightness.dark);
    });
  });

  group('the adapter', () {
    test('reads every value from the store', () {
      final store = makeStore(
        prefs: state.MemoryPrefs({
          'appearance.theme': 'futuristic',
          'appearance.mode': 'dark',
          'appearance.motion': false,
          'appearance.intensity': 0.5,
          LeftPane.storageKey: 'goals',
        }),
      );
      store.screen = Screen.planner;
      final ShellModel model = StoreShellModel(store);
      expect(model.screen, Screen.planner);
      expect(model.leftPane, LeftPane.goals);
      expect(model.themeId, ThemeId.futuristic);
      expect(model.appearance, AppearanceMode.dark);
      expect(model.motionSetting, isFalse);
      expect(model.intensity, 0.5);
      expect(model.toast, isNull);
    });

    test('passes every action to the store', () {
      final store = makeStore();
      final ShellModel model = StoreShellModel(store);

      model.screen = Screen.notes;
      expect(store.screen, Screen.notes);

      model.showToday();
      expect(store.screen, Screen.today);
      store.screen = Screen.calendar;
      model.showToday();
      expect(store.screen, Screen.calendar, reason: 'the Calendar stays open');

      model.showTasks();
      expect(store.screen, Screen.planner);
      expect(store.leftPane, LeftPane.tasks);

      model.toggleLeftPane(LeftPane.tasks);
      expect(store.leftPane, isNull);

      store.screen = Screen.garden;
      model.showLeftPane(LeftPane.notes);
      expect(store.screen, Screen.planner);
      expect(store.leftPane, LeftPane.notes);

      model.setTheme(ThemeId.minimal);
      expect(store.themeId, ThemeId.minimal);
      model.nextTheme();
      expect(store.themeId, ThemeId.futuristic);

      model.setAppearance(AppearanceMode.light);
      expect(store.appearance, AppearanceMode.light);

      model.setMotion(false);
      expect(store.motionSetting, isFalse);
      expect(store.toast, 'Motion off');

      model.showToast('Saved');
      expect(store.toast, 'Saved');
      expect(model.toast, 'Saved');
    });

    test('tells its listeners when the store changes', () {
      final store = makeStore();
      final ShellModel model = StoreShellModel(store);
      var calls = 0;
      void listener() => calls += 1;

      model.addListener(listener);
      store.screen = Screen.garden;
      expect(calls, greaterThan(0));

      model.removeListener(listener);
      final before = calls;
      store.screen = Screen.notes;
      expect(calls, before);
    });

    test('the choices are saved and come back in a new store', () {
      final prefs = state.MemoryPrefs();
      final ShellModel model = StoreShellModel(makeStore(prefs: prefs));
      model.setTheme(ThemeId.vintage);
      model.setAppearance(AppearanceMode.dark);
      model.setMotion(false);
      model.toggleLeftPane(LeftPane.goals);

      expect(prefs.getString('appearance.theme'), 'vintage');
      expect(prefs.getString('appearance.mode'), 'dark');
      expect(prefs.getBool('appearance.motion'), isFalse);
      expect(prefs.getString(LeftPane.storageKey), 'goals');

      final ShellModel again = StoreShellModel(makeStore(prefs: prefs));
      expect(again.themeId, ThemeId.vintage);
      expect(again.appearance, AppearanceMode.dark);
      expect(again.motionSetting, isFalse);
      expect(again.leftPane, LeftPane.goals);
    });
  });

  group('the shell on the store', () {
    testWidgets('a dock click opens the panel in the store', (tester) async {
      final store = makeStore(prefs: stillPrefs());
      await pumpApp(tester, StoreShellModel(store), size: desktopSize);

      await tester.tap(find.byKey(const ValueKey('dock-tasks')));
      await tester.pumpAndSettle();
      expect(store.leftPane, LeftPane.tasks);
      expect(find.byKey(const ValueKey('pane-tasks')), findsOneWidget);
    });

    testWidgets('a change in the store shows in the shell', (tester) async {
      final store = makeStore(prefs: stillPrefs());
      await pumpApp(tester, StoreShellModel(store), size: desktopSize);
      expect(find.byKey(const ValueKey('content-today')), findsOneWidget);

      store.screen = Screen.garden;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('content-garden')), findsOneWidget);
    });

    testWidgets('the app starts in the saved theme', (tester) async {
      final store = makeStore(
        prefs: stillPrefs({
          'appearance.theme': 'vintage',
          'appearance.mode': 'dark',
        }),
      );
      await pumpApp(tester, StoreShellModel(store), size: phoneSize);
      final context = tester.element(
        find.byKey(const ValueKey('content-today')),
      );
      expect(Theme.of(context).brightness, Brightness.dark);
      expect(Theme.of(context).scaffoldBackgroundColor, isNot(Colors.white));
      expect(store.themeId, ThemeId.vintage);
    });

    testWidgets('a message from the store shows and goes away', (tester) async {
      final store = makeStore(prefs: stillPrefs());
      await pumpApp(tester, StoreShellModel(store), size: desktopSize);

      store.showToast('Task done');
      await tester.pumpAndSettle();
      expect(find.text('Task done'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2300));
      await tester.pumpAndSettle();
      expect(find.text('Task done'), findsNothing);
    });
  });
}
