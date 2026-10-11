// Golden screenshots of the screens of milestone F10: the Garden and the
// Settings.
//
// Make the pictures again after a wanted change of the look:
//   cd app && flutter test --update-goldens test/ui/goldens
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/store_app.dart';

import '../planner/planner_support.dart';
import '../settings/settings_support.dart'
    show SettingsTab, openSettings, textOffPixels;
import '../tasks/tasks_support.dart' show addTask;

/// A garden with `done` finished tasks.
AppStore _garden(int done, {ThemeId theme = ThemeId.grove, bool dark = false}) {
  final store = plannerStore(now: 10 * 60 + 20)
    ..setTheme(theme)
    ..setAppearance(dark ? AppearanceMode.dark : AppearanceMode.light)
    ..screen = Screen.garden;
  for (var i = 0; i < done; i++) {
    addTask(store, 'Task $i', id: 'DONE-$i');
    store.toggleDone(taskId: 'DONE-$i');
  }
  return store;
}

/// A window that shows the plant and the ladder of the stages.
const _tall = Size(1100, 900);

Future<void> _shot(
  WidgetTester tester,
  AppStore store,
  String name, {
  Size size = desktopSize,
}) => withRealShadows(() async {
  await pumpPlanner(tester, store, size: size);
  await expectLater(find.byType(StoreApp), matchesGoldenFile('$name.png'));
});

/// The Settings window on `tab`, over the planner.
Future<void> _settingsShot(
  WidgetTester tester,
  String name, {
  SettingsTab tab = SettingsTab.appearance,
  ThemeId theme = ThemeId.grove,
  bool dark = false,
  Size size = desktopSize,
}) => withRealShadows(() async {
  final store = plannerStore(now: 10 * 60 + 20)
    ..setTheme(theme)
    ..setAppearance(dark ? AppearanceMode.dark : AppearanceMode.light);
  await openSettings(tester, store, tab: tab, size: size);
  // A text on a part of a pixel looks different on each system.
  expect(textOffPixels(tester), isEmpty);
  await expectLater(find.byType(StoreApp), matchesGoldenFile('$name.png'));
});

void main() {
  setUpAll(() async {
    TolerantGoldenComparator.install();
    await loadIconFont();
  });

  for (final theme in ThemeId.values) {
    final t = theme.name;
    testWidgets('garden desktop $t', (tester) async {
      await _shot(
        tester,
        _garden(40, theme: theme),
        'garden_desktop_${t}_light',
        size: _tall,
      );
    });
  }

  testWidgets('garden desktop grove dark', (tester) async {
    await _shot(
      tester,
      _garden(40, dark: true),
      'garden_desktop_grove_dark',
      size: _tall,
    );
  });

  testWidgets('garden: a new seed', (tester) async {
    await _shot(tester, _garden(0), 'garden_desktop_grove_light_seed');
  });

  testWidgets('garden: an ancient tree', (tester) async {
    await _shot(
      tester,
      _garden(120),
      'garden_desktop_grove_light_full',
      size: _tall,
    );
  });

  testWidgets('garden phone grove', (tester) async {
    await _shot(
      tester,
      _garden(12),
      'garden_phone_grove_light',
      size: phoneSize,
    );
  });

  for (final tab in SettingsTab.values) {
    testWidgets('settings desktop grove: ${tab.name}', (tester) async {
      await _settingsShot(
        tester,
        'settings_desktop_grove_light_${tab.name}',
        tab: tab,
      );
    });
  }

  for (final theme in ThemeId.values.where((t) => t != ThemeId.grove)) {
    final t = theme.name;
    testWidgets('settings desktop $t', (tester) async {
      await _settingsShot(
        tester,
        'settings_desktop_${t}_light_appearance',
        theme: theme,
      );
    });
  }

  testWidgets('settings desktop grove dark', (tester) async {
    await _settingsShot(
      tester,
      'settings_desktop_grove_dark_planner',
      tab: SettingsTab.planner,
      dark: true,
    );
  });

  testWidgets('settings phone grove', (tester) async {
    await _settingsShot(
      tester,
      'settings_phone_grove_light_appearance',
      size: phoneSize,
    );
  });
}
