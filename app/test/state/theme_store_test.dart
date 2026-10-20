// Port of Tests/GroveTests/ThemeStoreTests.swift.
//
// The Swift store also made the SwiftUI `Theme` and `ColorScheme`. The Dart
// store keeps only the theme id and the light/dark/system choice; the screens
// make the colours. So a `colorScheme` check is an `appearance` check here.
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  test('the default is grove with motion on', () {
    final s = makeStore();
    expect(s.themeId, ThemeId.grove);
    expect(s.motionSetting, isTrue);
  });

  test('a chosen theme is saved and comes back', () {
    final prefs = MemoryPrefs();
    makeStore(prefs: prefs).setTheme(ThemeId.vintage);
    expect(prefs.getString('appearance.theme'), 'vintage');
    expect(makeStore(prefs: prefs).themeId, ThemeId.vintage);
  });

  test('an unknown saved theme falls back to grove', () {
    final prefs = MemoryPrefs({'appearance.theme': 'neon-rainbow'});
    expect(makeStore(prefs: prefs).themeId, ThemeId.grove);
  });

  test('next theme walks the list and wraps around', () {
    final s = makeStore();
    final seen = <ThemeId>[];
    for (var i = 0; i < 5; i++) {
      s.nextTheme();
      seen.add(s.themeId);
    }
    expect(seen, [
      ThemeId.minimal,
      ThemeId.futuristic,
      ThemeId.vintage,
      ThemeId.grove,
      ThemeId.minimal,
    ]);
  });

  test('the motion switch is saved', () {
    final prefs = MemoryPrefs();
    final s = makeStore(prefs: prefs);
    s.setMotion(false);
    expect(s.motionSetting, isFalse);
    expect(makeStore(prefs: prefs).motionSetting, isFalse);
    s.setMotion(true);
    expect(makeStore(prefs: prefs).motionSetting, isTrue);
  });

  test('the theme commands run from the palette', () {
    final s = makeStore();
    s.run(PaletteCommandId.toggleTheme);
    expect(s.themeId, ThemeId.minimal);
    s.run(PaletteCommandId.toggleMotion);
    expect(s.motionSetting, isFalse);
    expect(s.paletteOpen, isFalse);
  });

  test('the theme is live in the store', () {
    final s = makeStore();
    s.setTheme(ThemeId.futuristic);
    expect(s.themeId, ThemeId.futuristic);
    // The theme does not pick light or dark.
    expect(s.appearance, AppearanceMode.system);
    s.setTheme(ThemeId.grove);
    expect(s.appearance, AppearanceMode.system);
  });

  test('the appearance starts on system', () {
    final s = makeStore();
    expect(s.appearance, AppearanceMode.system);
  });

  test('a chosen appearance is saved and comes back', () {
    final prefs = MemoryPrefs();
    final s = makeStore(prefs: prefs);
    s.setAppearance(AppearanceMode.dark);
    expect(s.appearance, AppearanceMode.dark);
    expect(prefs.getString('appearance.mode'), 'dark');
    expect(makeStore(prefs: prefs).appearance, AppearanceMode.dark);
    s.setAppearance(AppearanceMode.light);
    expect(makeStore(prefs: prefs).appearance, AppearanceMode.light);
  });

  test('an unknown saved appearance falls back to system', () {
    final prefs = MemoryPrefs({'appearance.mode': 'sepia'});
    expect(makeStore(prefs: prefs).appearance, AppearanceMode.system);
  });

  test('changing the theme keeps light or dark', () {
    final s = makeStore();
    s.setAppearance(AppearanceMode.dark);
    for (final id in ThemeId.values) {
      s.setTheme(id);
      expect(s.appearance, AppearanceMode.dark, reason: '$id changed the mode');
    }
    s.setAppearance(AppearanceMode.light);
    s.setTheme(ThemeId.futuristic);
    expect(s.appearance, AppearanceMode.light);
  });

  test('changing light or dark keeps the theme', () {
    final s = makeStore();
    s.setTheme(ThemeId.vintage);
    s.setAppearance(AppearanceMode.dark);
    expect(s.themeId, ThemeId.vintage);
  });
}
