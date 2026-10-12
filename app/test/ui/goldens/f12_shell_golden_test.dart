// Golden screenshots of the shell gaps of milestone F12: the command
// palette and the small window of an error.
//
// Make the pictures again after a wanted change of the look:
//   cd app && flutter test --update-goldens test/ui/goldens
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/shell/command_palette.dart';
import 'package:grove/ui/store_app.dart';

import '../planner/planner_support.dart';
import '../tasks/tasks_support.dart' show addTask, textOffPixels;

AppStore _store({ThemeId theme = ThemeId.grove, bool dark = false}) {
  final store = plannerStore(now: 10 * 60 + 20)
    ..setTheme(theme)
    ..setAppearance(dark ? AppearanceMode.dark : AppearanceMode.light);
  addTask(store, 'Water the ferns', id: 'FERNS');
  addTask(store, 'Call the plumber', id: 'PLUMBER');
  return store;
}

/// The command palette over the planner, with `text` in its field.
Future<void> _paletteShot(
  WidgetTester tester,
  String name, {
  ThemeId theme = ThemeId.grove,
  bool dark = false,
  String text = '',
  Size size = desktopSize,
}) => withRealShadows(() async {
  final store = _store(theme: theme, dark: dark);
  await pumpPlanner(tester, store, size: size);
  store.togglePalette();
  await tester.pumpAndSettle();
  if (text.isNotEmpty) {
    await tester.enterText(find.byKey(const ValueKey('palette-field')), text);
    await tester.pumpAndSettle();
  }
  // A text on a part of a pixel looks different on each system.
  expect(textOffPixels(tester, within: find.byType(CommandPalette)), isEmpty);
  await expectLater(find.byType(StoreApp), matchesGoldenFile('$name.png'));
});

/// The window of an error over the planner.
Future<void> _errorShot(
  WidgetTester tester,
  String name, {
  ThemeId theme = ThemeId.grove,
  bool dark = false,
  Size size = desktopSize,
}) => withRealShadows(() async {
  final store = _store(theme: theme, dark: dark);
  await pumpPlanner(tester, store, size: size);
  store.errorMessage = 'Could not save: the disk is full';
  await tester.pumpAndSettle();
  expect(
    textOffPixels(tester, within: find.byKey(const ValueKey('error-alert'))),
    isEmpty,
  );
  await expectLater(find.byType(StoreApp), matchesGoldenFile('$name.png'));
});

void main() {
  setUpAll(() async {
    TolerantGoldenComparator.install();
    await loadIconFont();
  });

  for (final theme in ThemeId.values) {
    final t = theme.name;
    testWidgets('palette desktop $t', (tester) async {
      await _paletteShot(tester, 'palette_desktop_${t}_light', theme: theme);
    });
  }

  testWidgets('palette desktop grove dark', (tester) async {
    await _paletteShot(tester, 'palette_desktop_grove_dark', dark: true);
  });

  testWidgets('palette: the rows that match a text', (tester) async {
    await _paletteShot(
      tester,
      'palette_desktop_grove_light_typed',
      text: 'fern',
    );
  });

  testWidgets('palette: nothing found', (tester) async {
    await _paletteShot(
      tester,
      'palette_desktop_grove_light_empty',
      text: 'qqqq',
    );
  });

  testWidgets('palette phone grove', (tester) async {
    await _paletteShot(tester, 'palette_phone_grove_light', size: phoneSize);
  });

  testWidgets('error desktop grove', (tester) async {
    await _errorShot(tester, 'error_desktop_grove_light');
  });

  testWidgets('error desktop grove dark', (tester) async {
    await _errorShot(tester, 'error_desktop_grove_dark', dark: true);
  });

  testWidgets('error phone grove', (tester) async {
    await _errorShot(tester, 'error_phone_grove_light', size: phoneSize);
  });
}
