// Port of Tests/GroveTests/LeftDockTests.swift.
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  group('the three left panels', () {
    test('the names are what is saved in the setting', () {
      expect(
        [for (final p in LeftPane.values) p.name],
        ['notes', 'tasks', 'goals'],
      );
      expect(LeftPane.storageKey, 'shell.leftPane');
    });

    test('a tap opens the panel when none is open', () {
      for (final pane in LeftPane.values) {
        expect(LeftPane.toggled(current: null, tapped: pane), pane);
      }
    });

    test('a tap on the open panel closes it', () {
      for (final pane in LeftPane.values) {
        expect(LeftPane.toggled(current: pane, tapped: pane), isNull);
      }
    });

    test('a tap on another panel switches to it', () {
      expect(
        LeftPane.toggled(current: LeftPane.notes, tapped: LeftPane.goals),
        LeftPane.goals,
      );
      expect(
        LeftPane.toggled(current: LeftPane.goals, tapped: LeftPane.tasks),
        LeftPane.tasks,
      );
      expect(
        LeftPane.toggled(current: LeftPane.tasks, tapped: LeftPane.notes),
        LeftPane.notes,
      );
    });

    test('saved text becomes a panel; empty or unknown text means closed', () {
      expect(LeftPane.fromSaved('notes'), LeftPane.notes);
      expect(LeftPane.fromSaved('tasks'), LeftPane.tasks);
      expect(LeftPane.fromSaved('goals'), LeftPane.goals);
      expect(LeftPane.fromSaved(''), isNull);
      expect(LeftPane.fromSaved('inbox'), isNull);
      expect(LeftPane.savedText(null), '');
      expect(LeftPane.savedText(LeftPane.goals), 'goals');
    });

    test('only Today and the Planner have the buttons', () {
      for (final screen in Screen.values) {
        expect(
          LeftPane.isAvailable(screen),
          screen == Screen.today || screen == Screen.planner,
        );
      }
    });

    test('every panel has a title, a symbol and a help text', () {
      expect(
        [for (final p in LeftPane.values) p.icon],
        ['note.text', 'checklist', 'target'],
      );
      expect(
        [for (final p in LeftPane.values) p.title],
        ['Notes', 'Tasks', 'Goals'],
      );
      for (final pane in LeftPane.values) {
        expect(pane.help, isNotEmpty);
      }
    });
  });

  group('the left panel in the store', () {
    test('the store reads and writes the saved panel', () {
      final prefs = MemoryPrefs();
      final s = makeStore(prefs: prefs);
      s.leftPane = LeftPane.notes;
      expect(prefs.getString(LeftPane.storageKey), 'notes');
      expect(s.leftPane, LeftPane.notes);
      s.leftPane = null;
      expect(prefs.getString(LeftPane.storageKey), '');
      expect(s.leftPane, isNull);
    });

    test('the View menu opens a panel; other screens move to the Planner', () {
      final s = makeStore(prefs: MemoryPrefs({LeftPane.storageKey: ''}));
      s.screen = Screen.today;
      s.showLeftPane(LeftPane.notes);
      expect(s.screen, Screen.today);
      expect(s.leftPane, LeftPane.notes);
      s.screen = Screen.garden;
      s.showLeftPane(LeftPane.goals);
      expect(s.screen, Screen.planner);
      expect(s.leftPane, LeftPane.goals);
    });

    test('New Task on the Planner opens the Tasks panel', () {
      final s = makeStore(prefs: MemoryPrefs({LeftPane.storageKey: 'notes'}));
      s.screen = Screen.planner;
      final before = s.quickAddRequest;
      s.run(PaletteCommandId.newTask);
      expect(s.screen, Screen.planner);
      expect(s.leftPane, LeftPane.tasks);
      expect(s.quickAddRequest, before + 1);
      // The field that appears takes the request.
      expect(s.quickAddHandled, lessThan(s.quickAddRequest));
    });

    test("New Task on Today shows today's list, so another panel closes", () {
      for (final open in ['notes', 'goals', 'tasks']) {
        final s = makeStore(prefs: MemoryPrefs({LeftPane.storageKey: open}));
        s.screen = Screen.today;
        s.run(PaletteCommandId.newTask);
        expect(s.screen, Screen.today);
        expect(s.leftPane, isNull);
      }
    });
  });
}
