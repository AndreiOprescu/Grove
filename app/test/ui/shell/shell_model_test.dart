// Port of LeftPaneTests and the navigation parts of LeftPaneStoreTests
// (Tests/GroveTests/LeftDockTests.swift), ScreenStoreTests
// (SpreadTests.swift) and ThemeStoreTests.swift. The parts that need the
// database or saved settings come with the F5 store.
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/shell/shell_layout.dart';
import 'package:grove/ui/shell/shell_model.dart';
import 'package:grove/ui/theme/theme_spec.dart';

void main() {
  group('the screens', () {
    test('run in the order of the switch', () {
      expect(Screen.values, [
        Screen.today,
        Screen.planner,
        Screen.calendar,
        Screen.notes,
        Screen.garden,
      ]);
      expect(Screen.values.map((s) => s.title), [
        'Today',
        'Planner',
        'Calendar',
        'Notes',
        'Garden',
      ]);
    });

    test('the window starts on Today', () {
      expect(LocalShellModel().screen, Screen.today);
    });

    test('show today keeps the Planner and the Calendar where they are', () {
      final m = LocalShellModel();
      for (final screen in [Screen.planner, Screen.calendar]) {
        m.screen = screen;
        m.showToday();
        expect(m.screen, screen);
      }
      for (final screen in [Screen.notes, Screen.garden, Screen.today]) {
        m.screen = screen;
        m.showToday();
        expect(m.screen, Screen.today);
      }
    });

    test('show tasks opens the Planner with the Tasks panel', () {
      final m = LocalShellModel()..screen = Screen.notes;
      m.showTasks();
      expect((m.screen, m.leftPane), (Screen.planner, LeftPane.tasks));
    });

    test('a change of screen tells the listeners once', () {
      final m = LocalShellModel();
      var calls = 0;
      m.addListener(() => calls++);
      m.screen = Screen.notes;
      m.screen = Screen.notes;
      expect(calls, 1);
    });
  });

  group('the left panels', () {
    test('three panels, in the order of the buttons', () {
      expect(LeftPane.values.map((p) => p.name), ['notes', 'tasks', 'goals']);
      expect(LeftPane.storageKey, 'shell.leftPane');
      expect(LeftPane.plannerWidth, 320);
    });

    test('a click on a closed panel opens it', () {
      for (final pane in LeftPane.values) {
        expect(LeftPane.toggled(current: null, tapped: pane), pane);
      }
    });

    test('a click on the open panel closes it', () {
      for (final pane in LeftPane.values) {
        expect(LeftPane.toggled(current: pane, tapped: pane), isNull);
      }
    });

    test('a click on another panel replaces the open one', () {
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

    test('the saved text names the panel; empty or unknown is closed', () {
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

    test('every panel has a title and a tooltip that names the next click', () {
      expect(LeftPane.values.map((p) => p.title), ['Notes', 'Tasks', 'Goals']);
      expect(LeftPane.notes.tooltip(isOpen: false), 'Show notes');
      expect(LeftPane.notes.tooltip(isOpen: true), 'Hide notes');
    });

    test('the model toggles the panel like the buttons', () {
      final m = LocalShellModel();
      expect(m.leftPane, isNull);
      m.toggleLeftPane(LeftPane.notes);
      expect(m.leftPane, LeftPane.notes);
      m.toggleLeftPane(LeftPane.goals);
      expect(m.leftPane, LeftPane.goals);
      m.toggleLeftPane(LeftPane.goals);
      expect(m.leftPane, isNull);
    });

    test('show a panel: stays on Today and the Planner, else goes to the '
        'Planner', () {
      final m = LocalShellModel();
      m.showLeftPane(LeftPane.notes);
      expect((m.screen, m.leftPane), (Screen.today, LeftPane.notes));
      m.screen = Screen.garden;
      m.showLeftPane(LeftPane.goals);
      expect((m.screen, m.leftPane), (Screen.planner, LeftPane.goals));
    });
  });

  group('theme, light or dark, motion', () {
    test('the default is Grove, the look of the system, motion on', () {
      final m = LocalShellModel();
      expect(m.themeId, ThemeId.grove);
      expect(m.appearance, AppearanceMode.system);
      expect(m.motionSetting, isTrue);
      expect(m.intensity, 1);
    });

    test('next theme walks the list and wraps around', () {
      final m = LocalShellModel();
      final seen = <ThemeId>[];
      for (var i = 0; i < 5; i++) {
        m.nextTheme();
        seen.add(m.themeId);
      }
      expect(seen, [
        ThemeId.minimal,
        ThemeId.futuristic,
        ThemeId.vintage,
        ThemeId.grove,
        ThemeId.minimal,
      ]);
    });

    test('the same theme or mode again tells no one', () {
      final m = LocalShellModel();
      var calls = 0;
      m.addListener(() => calls++);
      m.setTheme(ThemeId.grove);
      m.setAppearance(AppearanceMode.system);
      expect(calls, 0);
      m.setTheme(ThemeId.vintage);
      m.setAppearance(AppearanceMode.dark);
      expect(calls, 2);
      expect((m.themeId, m.appearance), (ThemeId.vintage, AppearanceMode.dark));
    });

    // testWidgets gives a fake clock, so the 2.2 s of a message pass at once.
    testWidgets('the motion switch shows a short message', (tester) async {
      final m = LocalShellModel();
      m.setMotion(false);
      expect(m.motionSetting, isFalse);
      expect(m.toast, 'Motion off');
      m.setMotion(true);
      expect(m.toast, 'Motion on');
      await tester.pump(const Duration(milliseconds: 2100));
      expect(m.toast, 'Motion on');
      await tester.pump(const Duration(milliseconds: 200));
      expect(m.toast, isNull);
      m.dispose();
    });

    testWidgets('a new message restarts the clock', (tester) async {
      final m = LocalShellModel();
      m.showToast('One');
      await tester.pump(const Duration(seconds: 2));
      m.showToast('Two');
      await tester.pump(const Duration(seconds: 2));
      expect(m.toast, 'Two');
      await tester.pump(const Duration(milliseconds: 300));
      expect(m.toast, isNull);
      m.dispose();
    });

    testWidgets('a closed model leaves no timer behind', (tester) async {
      // A timer that is still waiting at the end fails a widget test.
      LocalShellModel()
        ..showToast('Bye')
        ..dispose();
    });
  });

  group('phone or desktop', () {
    test('under 700 points wide is a phone', () {
      expect(ShellRules.phoneBreakpoint, 700);
      expect(ShellRules.layoutFor(390), ShellLayout.phone);
      expect(ShellRules.layoutFor(699.9), ShellLayout.phone);
      expect(ShellRules.layoutFor(700), ShellLayout.desktop);
      expect(ShellRules.layoutFor(1280), ShellLayout.desktop);
    });

    test('the switch shows its words only when there is room', () {
      expect(ShellRules.switchShowsLabels(1280), isTrue);
      expect(ShellRules.switchShowsLabels(960), isTrue);
      expect(ShellRules.switchShowsLabels(959), isFalse);
      expect(ShellRules.switchShowsLabels(700), isFalse);
    });

    test('a button on a phone is big enough for a finger', () {
      expect(
        ShellRules.dockButton(ShellLayout.phone).height,
        greaterThanOrEqualTo(36),
      );
      expect(ShellRules.dockButton(ShellLayout.desktop).width, 28);
      expect(ShellRules.dockButton(ShellLayout.desktop).height, 22);
    });
  });
}
