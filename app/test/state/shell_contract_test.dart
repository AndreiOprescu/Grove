// What the app shell of Track B reads from the store and is not in a Swift
// test: the dock click and the accent intensity. See docs/tracks.md.
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  group('the shell contract', () {
    test('a dock click opens a panel, changes it and closes it', () {
      final s = makeStore();
      expect(s.leftPane, isNull);
      s.toggleLeftPane(LeftPane.tasks);
      expect(s.leftPane, LeftPane.tasks);
      s.toggleLeftPane(LeftPane.goals);
      expect(s.leftPane, LeftPane.goals);
      s.toggleLeftPane(LeftPane.goals);
      expect(s.leftPane, isNull);
    });

    test('a dock click tells the listeners and keeps the screen', () {
      final s = makeStore();
      s.screen = Screen.today;
      var calls = 0;
      s.addListener(() => calls += 1);
      s.toggleLeftPane(LeftPane.notes);
      expect(calls, greaterThan(0));
      expect(s.screen, Screen.today);
    });

    test('the open panel is saved', () {
      final prefs = MemoryPrefs();
      makeStore(prefs: prefs).toggleLeftPane(LeftPane.goals);
      expect(prefs.getString(LeftPane.storageKey), 'goals');
      expect(makeStore(prefs: prefs).leftPane, LeftPane.goals);
    });

    test('the intensity is 1 on a new install', () {
      expect(makeStore().intensity, 1.0);
    });

    test('the intensity is saved and stays inside its limits', () {
      final prefs = MemoryPrefs();
      final s = makeStore(prefs: prefs);
      s.setIntensity(0.5);
      expect(s.intensity, 0.5);
      expect(prefs.getDouble('appearance.intensity'), 0.5);
      expect(makeStore(prefs: prefs).intensity, 0.5);
      s.setIntensity(9);
      expect(s.intensity, SettingsRules.maxIntensity);
      s.setIntensity(-1);
      expect(s.intensity, SettingsRules.minIntensity);
    });

    test('a saved intensity outside the limits is pulled back', () {
      final s = makeStore(prefs: MemoryPrefs({'appearance.intensity': 7.0}));
      expect(s.intensity, SettingsRules.maxIntensity);
    });

    test('the screens have the words of the switch', () {
      expect(Screen.values.map((s) => s.title), [
        'Today',
        'Planner',
        'Calendar',
        'Notes',
        'Garden',
      ]);
    });

    test('saved text that is unknown gives the first choice', () {
      expect(ThemeId.fromSaved('vintage'), ThemeId.vintage);
      expect(ThemeId.fromSaved('neon'), ThemeId.initial);
      expect(ThemeId.fromSaved(null), ThemeId.initial);
      expect(AppearanceMode.fromSaved('dark'), AppearanceMode.dark);
      expect(AppearanceMode.fromSaved('pink'), AppearanceMode.system);
      expect(AppearanceMode.fromSaved(null), AppearanceMode.system);
      expect(LeftPane.fromSaved(null), isNull);
    });

    test('a new intensity tells the listeners', () {
      final s = makeStore();
      var calls = 0;
      s.addListener(() => calls += 1);
      s.setIntensity(0.25);
      expect(calls, greaterThan(0));
    });
  });
}
