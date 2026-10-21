// The Settings window (F10): how it opens, what each tab changes, and that
// the screens follow. Swift: Settings/SettingsView.swift.
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/auth/sync_card.dart';
import 'package:grove/ui/planner/planner_grid.dart';
import 'package:grove/ui/planner/planner_view.dart';
import 'package:grove/ui/settings/settings_tabs.dart';
import 'package:grove/ui/shell/appearance_button.dart';
import 'package:grove/ui/theme/panel.dart';

import 'settings_support.dart';

/// A store with a folder on disk, as the real app has.
AppStore _diskStore({Notifier? notifier}) {
  final dir = Directory.systemTemp.createTempSync('grove-settings-test');
  addTearDown(() => dir.deleteSync(recursive: true));
  final store = AppStore(
    repos: Repos(Database.inMemory()),
    prefs: MemoryPrefs()..set('appearance.motion', false),
    notifier: notifier,
    dataDir: dir.path,
  );
  store
    ..clockOverride = WallTime(day: wednesday, minute: 10 * 60)
    ..selectedDay = wednesday
    ..screen = Screen.planner;
  addTearDown(store.dispose);
  return store;
}

AppStore _notifyStore(FakeNotifier notifier, {bool enabled = true}) {
  final store = makeStore(
    notifier: notifier,
    prefs: MemoryPrefs()
      ..set('appearance.motion', false)
      ..set('notifications.enabled', enabled),
    clock: WallTime(day: wednesday, minute: 10 * 60),
  );
  store.screen = Screen.planner;
  return store;
}

/// A change of the reminders makes them again after a short wait. This
/// lets that wait end, so no timer is left when the test ends.
Future<void> _endReminders(WidgetTester tester, AppStore store) async {
  await tester.pump(store.reminderDelay + const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

void main() {
  group('opening', () {
    testWidgets('Ctrl and comma opens the window, the button closes it', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpApp(tester, store);
      expect(settingsView, findsNothing);
      await pressSettingsKey(tester);
      expect(settingsView, findsOneWidget);
      expect(
        inSettings(
          find.descendant(
            of: find.byType(ThemedHeading),
            matching: find.text('Settings'),
          ),
        ),
        findsOneWidget,
      );
      // The key does not open a second window over the first.
      await pressSettingsKey(tester);
      expect(settingsView, findsOneWidget);

      await tester.tap(keyed('settings-close'));
      await tester.pumpAndSettle();
      expect(settingsView, findsNothing);
    });

    testWidgets('the Appearance menu has "Settings…"', (tester) async {
      final store = plannerStore();
      await pumpApp(tester, store);
      await tester.tap(find.byType(AppearanceButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings…'));
      await tester.pumpAndSettle();
      expect(settingsView, findsOneWidget);
    });

    testWidgets('Escape closes the window', (tester) async {
      await openSettings(tester, plannerStore());
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(settingsView, findsNothing);
    });

    testWidgets('seven tabs, and each one shows its part', (tester) async {
      await openSettings(tester, plannerStore());
      expect(SettingsTab.values.map((t) => t.title), [
        'Appearance',
        'Planner',
        'Notes',
        'Notifications',
        'Sync',
        'Data',
        'Agent',
      ]);
      for (final tab in SettingsTab.values) {
        expect(tabButton(tab), findsOneWidget);
      }
      expect(keyed('settings-theme-grove'), findsOneWidget);

      const marks = {
        SettingsTab.planner: 'settings-hour-height',
        SettingsTab.notes: 'settings-template-daily',
        SettingsTab.notifications: 'settings-notify',
        SettingsTab.data: 'settings-data-path',
        SettingsTab.agent: 'settings-agent',
        SettingsTab.appearance: 'settings-theme-grove',
      };
      for (final MapEntry(key: tab, value: mark) in marks.entries) {
        await showTab(tester, tab);
        expect(keyed(mark), findsOneWidget, reason: tab.name);
        expect(
          tester.getSemantics(tabButton(tab)),
          matchesSemantics(
            label: tab.title,
            isButton: true,
            isSelected: true,
            hasSelectedState: true,
            hasTapAction: true,
          ),
        );
      }
      await showTab(tester, SettingsTab.sync);
      expect(inSettings(find.byType(SyncCard)), findsOneWidget);
    });

    testWidgets('a desktop window is 600 by 540', (tester) async {
      await openSettings(tester, plannerStore());
      expect(tester.getSize(keyed('settings-window')), const Size(600, 540));
    });

    testWidgets('a small desktop window makes it smaller', (tester) async {
      await openSettings(tester, plannerStore(), size: const Size(720, 420));
      final size = tester.getSize(keyed('settings-window'));
      expect(size.width, 600);
      expect(size.height, lessThanOrEqualTo(420));
      for (final tab in SettingsTab.values) {
        await showTab(tester, tab);
        expect(tester.takeException(), isNull, reason: tab.name);
      }
    });

    testWidgets('a phone gets the whole screen, and nothing runs over', (
      tester,
    ) async {
      await openSettings(tester, plannerStore(), size: phoneSize);
      expect(tester.getSize(keyed('settings-window')), phoneSize);
      for (final tab in SettingsTab.values) {
        await showTab(tester, tab);
        expect(tester.takeException(), isNull, reason: tab.name);
      }
      await tester.tap(keyed('settings-close'));
      await tester.pumpAndSettle();
      expect(settingsView, findsNothing);
    });

    testWidgets('the texts sit on whole pixels', (tester) async {
      for (final size in [desktopSize, phoneSize]) {
        await openSettings(tester, _diskStore(), size: size);
        for (final tab in SettingsTab.values) {
          await showTab(tester, tab);
          expect(
            textOffPixels(tester, within: settingsView),
            isEmpty,
            reason: '${tab.name} at $size',
          );
        }
      }
    });
  });

  group('Appearance', () {
    testWidgets('a theme card picks the theme', (tester) async {
      final store = plannerStore();
      await openSettings(tester, store);
      expect(store.themeId, ThemeId.grove);
      await tapIn(tester, keyed('settings-theme-vintage'));
      expect(store.themeId, ThemeId.vintage);
      expect(
        tester.getSemantics(keyed('settings-theme-vintage')),
        matchesSemantics(
          label: 'Vintage theme',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester
            .getSemantics(keyed('settings-theme-grove'))
            .flagsCollection
            .isSelected,
        Tristate.isFalse,
      );
    });

    testWidgets('light or dark', (tester) async {
      final store = plannerStore();
      await openSettings(tester, store);
      await tapIn(tester, inSettings(find.text('Dark')));
      expect(store.appearance, AppearanceMode.dark);
      await tapIn(tester, inSettings(find.text('System')));
      expect(store.appearance, AppearanceMode.system);
      expect(
        inSettings(
          find.text(
            'System follows your device. Every theme has a light and a '
            'dark look.',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the motion switch', (tester) async {
      final store = plannerStore();
      await openSettings(tester, store);
      expect(switchOn(tester, 'settings-motion'), isFalse);
      await tester.tap(keyed('settings-motion'));
      await tester.pump();
      expect(store.motionSetting, isTrue);
      expect(switchOn(tester, 'settings-motion'), isTrue);
      await tester.tap(keyed('settings-motion'));
      await tester.pump();
      expect(store.motionSetting, isFalse);
      await endToast(tester);
      expect(
        tester.getSemantics(keyed('settings-motion')),
        matchesSemantics(
          label: 'Moving background and small animations',
          hasToggledState: true,
          isToggled: false,
          hasTapAction: true,
        ),
      );
    });

    testWidgets('the accent intensity', (tester) async {
      final store = plannerStore();
      await openSettings(tester, store);
      expect(inSettings(find.text('100%')), findsOneWidget);
      final slider = tester.widget<Slider>(keyed('settings-intensity'));
      expect((slider.min, slider.max), (0.0, 1.5));
      await slideTo(tester, 'settings-intensity', 0.5);
      expect(store.intensity, 0.5);
      expect(inSettings(find.text('50%')), findsOneWidget);
    });
  });

  group('Planner', () {
    testWidgets('the length of a new event', (tester) async {
      final store = plannerStore();
      await openSettings(tester, store, tab: SettingsTab.planner);
      await pick(tester, 'settings-event-length', '45m');
      expect(store.prefs.getInt('planner.defaultLength'), 45);
      expect(tester.getSemantics(keyed('settings-event-length')).value, '45m');
    });

    testWidgets('the hour height, and the planner follows', (tester) async {
      final store = plannerStore();
      await openSettings(tester, store, tab: SettingsTab.planner);
      final slider = tester.widget<Slider>(keyed('settings-hour-height'));
      expect((slider.min, slider.max), (36.0, 160.0));
      expect(inSettings(find.text('64 pt')), findsOneWidget);
      await slideTo(tester, 'settings-hour-height', 100.4);
      expect(store.plannerHourHeight, 100);
      expect(inSettings(find.text('100 pt')), findsOneWidget);
      expect(
        tester.widget<PlannerGrid>(find.byType(PlannerGrid)).hourHeight,
        100,
      );
    });

    testWidgets('working hours stay one hour long at least', (tester) async {
      final store = plannerStore();
      await openSettings(tester, store, tab: SettingsTab.planner);
      expect(tester.getSemantics(keyed('settings-work-start')).value, '09:00');
      expect(tester.getSemantics(keyed('settings-work-end')).value, '18:00');

      await pick(tester, 'settings-work-start', '18:00');
      expect(store.prefs.getInt('planner.workStart'), 18 * 60);
      expect(store.prefs.getInt('planner.workEnd'), 19 * 60);

      await pick(tester, 'settings-work-end', '08:00');
      expect(store.prefs.getInt('planner.workStart'), 7 * 60);
      expect(store.prefs.getInt('planner.workEnd'), 8 * 60);
      expect(
        tester.widget<PlannerGrid>(find.byType(PlannerGrid)).workStart,
        7 * 60,
      );
    });

    testWidgets('the busy day limit', (tester) async {
      final store = plannerStore();
      await openSettings(tester, store, tab: SettingsTab.planner);
      expect(tester.getSemantics(keyed('settings-daily-limit')).value, '9h');
      await pick(tester, 'settings-daily-limit', '6h');
      expect(store.dailyLimitMinutes, 360);
    });

    testWidgets('tint days by mood', (tester) async {
      final store = plannerStore();
      await openSettings(tester, store, tab: SettingsTab.planner);
      expect(switchOn(tester, 'settings-mood-tint'), isFalse);
      await tapIn(tester, keyed('settings-mood-tint'));
      expect(store.prefs.getBool(PlannerView.moodTintKey), isTrue);
      expect(switchOn(tester, 'settings-mood-tint'), isTrue);
    });

    testWidgets('the first day of the week', (tester) async {
      final store = plannerStore();
      await openSettings(tester, store, tab: SettingsTab.planner);
      expect(store.weekStartsSunday, isFalse);
      await tapIn(tester, inSettings(find.text('Sunday')));
      expect(store.weekStartsSunday, isTrue);
      await tapIn(tester, inSettings(find.text('Monday')));
      expect(store.weekStartsSunday, isFalse);
    });
  });

  group('Notes', () {
    EditableText field(WidgetTester tester, String key) =>
        tester.widget<EditableText>(
          find.descendant(of: keyed(key), matching: find.byType(EditableText)),
        );

    testWidgets('a template saves as you type, and goes back', (tester) async {
      final store = plannerStore();
      final normal = store.template(NoteKind.daily);
      await openSettings(tester, store, tab: SettingsTab.notes);
      expect(field(tester, 'settings-template-daily').controller.text, normal);

      await tester.enterText(
        find.descendant(
          of: keyed('settings-template-daily'),
          matching: find.byType(EditableText),
        ),
        '## My day\n',
      );
      await tester.pumpAndSettle();
      expect(store.template(NoteKind.daily), '## My day\n');
      expect(store.template(NoteKind.weekly), NotesRules.template(.weekly));

      await tapIn(tester, keyed('settings-template-daily-reset'));
      expect(store.template(NoteKind.daily), normal);
      expect(field(tester, 'settings-template-daily').controller.text, normal);
    });

    testWidgets('"Show marks" is off at first and kept on this device', (
      tester,
    ) async {
      final store = plannerStore();
      await openSettings(tester, store, tab: SettingsTab.notes);
      expect(switchOn(tester, 'settings-show-marks'), isFalse);
      expect(store.editorServices().showMarks(), isFalse);
      await tapIn(tester, keyed('settings-show-marks'));
      expect(store.prefs.getBool(EditorServices.showMarksKey), isTrue);
      expect(switchOn(tester, 'settings-show-marks'), isTrue);
      expect(store.editorServices().showMarks(), isTrue);
      await tapIn(tester, keyed('settings-show-marks'));
      expect(store.prefs.getBool(EditorServices.showMarksKey), isFalse);
      expect(store.editorServices().showMarks(), isFalse);
    });

    testWidgets('the weekly template has its own field', (tester) async {
      final store = plannerStore();
      await openSettings(tester, store, tab: SettingsTab.notes);
      await tester.ensureVisible(keyed('settings-template-weekly'));
      await tester.enterText(
        find.descendant(
          of: keyed('settings-template-weekly'),
          matching: find.byType(EditableText),
        ),
        '## My week\n',
      );
      await tester.pumpAndSettle();
      expect(store.template(NoteKind.weekly), '## My week\n');
      expect(store.template(NoteKind.daily), NotesRules.template(.daily));
    });
  });

  group('Notifications', () {
    testWidgets('the switch turns reminders off, and the time goes grey', (
      tester,
    ) async {
      final notifier = FakeNotifier();
      final store = _notifyStore(notifier);
      await openSettings(tester, store, tab: SettingsTab.notifications);
      expect(switchOn(tester, 'settings-notify'), isTrue);
      expect(
        inSettings(find.text('Notifications are allowed for Grove.')),
        findsOneWidget,
      );
      expect(keyed('settings-notify-allow'), findsNothing);

      await pick(tester, 'settings-notify-lead', '10 minutes before');
      expect(store.notifyLead, 10);

      await tapIn(tester, keyed('settings-notify'));
      expect(store.notifyEnabled, isFalse);
      expect(notifier.asked, 0);
      // The picker is off: a tap opens no list.
      await tester.tap(keyed('settings-notify-lead'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('5 minutes before'), findsNothing);
      await _endReminders(tester, store);
    });

    testWidgets('the switch asks for permission the first time', (
      tester,
    ) async {
      final notifier = FakeNotifier(status: NotifyAuthorization.notAsked);
      final store = _notifyStore(notifier, enabled: false);
      await openSettings(tester, store, tab: SettingsTab.notifications);
      expect(
        inSettings(find.text('Grove has not asked for permission yet.')),
        findsOneWidget,
      );
      await tapIn(tester, keyed('settings-notify'));
      expect(store.notifyEnabled, isTrue);
      expect(notifier.asked, 1);
      expect(store.notifyStatus, NotifyAuthorization.allowed);
      expect(
        inSettings(find.text('Notifications are allowed for Grove.')),
        findsOneWidget,
      );
      await _endReminders(tester, store);
    });

    testWidgets('"Allow notifications" asks', (tester) async {
      final notifier = FakeNotifier(
        status: NotifyAuthorization.notAsked,
        answer: NotifyAuthorization.denied,
      );
      final store = _notifyStore(notifier);
      await openSettings(tester, store, tab: SettingsTab.notifications);
      await tapIn(tester, keyed('settings-notify-allow'));
      expect(notifier.asked, 1);
      expect(keyed('settings-notify-allow'), findsNothing);
      expect(
        tester.getSemantics(keyed('settings-notify-status')).label,
        startsWith('Problem: Notifications are off for Grove.'),
      );
    });

    testWidgets('the window reads the permission when it opens', (
      tester,
    ) async {
      final notifier = FakeNotifier(status: NotifyAuthorization.notAsked);
      final store = _notifyStore(notifier);
      await pumpApp(tester, store);
      // The person allowed it in the settings of the system.
      notifier.status = NotifyAuthorization.allowed;
      await pressSettingsKey(tester);
      await showTab(tester, SettingsTab.notifications);
      expect(store.notifyStatus, NotifyAuthorization.allowed);
    });
  });

  group('Agent', () {
    /// A store with motion off, on a phone (no runner) or on a computer
    /// with `runner`.
    AppStore agentStore({
      FakeAgentRunner? runner,
      Map<String, Object?> prefs = const {},
    }) {
      final store = makeStore(
        prefs: MemoryPrefs({'appearance.motion': false, ...prefs}),
        clock: WallTime(day: wednesday, minute: 10 * 60),
        agentRunner: runner,
      );
      store
        ..newTimer = ManualTimers().start
        ..screen = Screen.planner;
      return store;
    }

    bool greyed(WidgetTester tester, String key) => tester
        .widget<IgnorePointer>(
          find
              .ancestor(of: keyed(key), matching: find.byType(IgnorePointer))
              .first,
        )
        .ignoring;

    testWidgets('all off at first, with the safety text', (tester) async {
      await openSettings(tester, agentStore(), tab: SettingsTab.agent);
      for (final key in [
        'settings-agent',
        'settings-agent-runner',
        'settings-agent-email',
      ]) {
        expect(switchOn(tester, key), isFalse, reason: key);
      }
      for (final text in [
        'Use the agent',
        'This device runs agent tasks',
        // One runner: two could run the same job twice.
        'Turn this on on one computer only.',
        'Let the agent read my email',
        AgentSettings.gmailText,
        AgentSettings.safetyText,
        AgentSettings.needsText,
      ]) {
        expect(inSettings(find.text(text)), findsOneWidget, reason: text);
      }
    });

    testWidgets('"Use the agent" is kept on this device', (tester) async {
      final store = agentStore();
      await openSettings(tester, store, tab: SettingsTab.agent);
      await tapIn(tester, keyed('settings-agent'));
      expect(store.agentEnabled, isTrue);
      expect(store.prefs.getBool('agent.enabled'), isTrue);
      expect(switchOn(tester, 'settings-agent'), isTrue);
      await tapIn(tester, keyed('settings-agent'));
      expect(store.agentEnabled, isFalse);
    });

    testWidgets('a phone: the runner and email switches are grey, with help', (
      tester,
    ) async {
      final store = agentStore();
      await openSettings(tester, store, tab: SettingsTab.agent);
      expect(
        tester.widget<Text>(keyed('settings-agent-help')).data,
        SettingsRules.agentNoRunner,
      );
      expect(greyed(tester, 'settings-agent-runner'), isTrue);
      expect(greyed(tester, 'settings-agent-email'), isTrue);
      await tester.tap(keyed('settings-agent-runner'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(store.agentRunnerOn, isFalse);
    });

    testWidgets('a computer with Claude Code: the runner switch, then email', (
      tester,
    ) async {
      final store = agentStore(runner: FakeAgentRunner());
      await openSettings(tester, store, tab: SettingsTab.agent);
      expect(keyed('settings-agent-help'), findsNothing);
      expect(greyed(tester, 'settings-agent-runner'), isFalse);
      // Email waits for the runner switch.
      expect(greyed(tester, 'settings-agent-email'), isTrue);

      await tapIn(tester, keyed('settings-agent-runner'));
      expect(store.agentRunnerOn, isTrue);
      expect(store.prefs.getBool('agent.runner'), isTrue);
      expect(greyed(tester, 'settings-agent-email'), isFalse);

      await tapIn(tester, keyed('settings-agent-email'));
      expect(store.agentEmailOn, isTrue);
      expect(store.prefs.getBool('agent.email'), isTrue);
    });

    testWidgets('a computer with no Claude Code says so, and the switch can '
        'look again', (tester) async {
      final runner = FakeAgentRunner(exe: null);
      final store = agentStore(runner: runner);
      await openSettings(tester, store, tab: SettingsTab.agent);
      expect(
        tester.widget<Text>(keyed('settings-agent-help')).data,
        SettingsRules.agentNotFound,
      );
      final looks = runner.locates;
      runner.exe = '/fake/claude';
      await tapIn(tester, keyed('settings-agent-runner'));
      expect(runner.locates, looks + 1);
      expect(store.canRunAgent, isTrue);
      expect(keyed('settings-agent-help'), findsNothing);
    });
  });

  group('Data', () {
    String message(WidgetTester tester) =>
        tester.widget<Text>(keyed('settings-data-message')).data!;

    testWidgets('the folder, and a copy of its path', (tester) async {
      final store = _diskStore();
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await openSettings(tester, store, tab: SettingsTab.data);
      expect(
        tester.widget<Text>(keyed('settings-data-path')).data,
        store.dataDir,
      );
      await tapIn(tester, keyed('settings-copy-path'));
      expect(copied, [store.dataDir]);
      expect(message(tester), 'The path is copied.');
    });

    // Swift: `Button("Show data folder")` in the Data tab.
    testWidgets('"Show data folder" asks the system for the folder', (
      tester,
    ) async {
      final store = _diskStore();
      final files = FakeFiles()..canShowFolder = true;
      await openSettings(tester, store, tab: SettingsTab.data, files: files);
      expect(
        find.descendant(
          of: keyed('settings-show-folder'),
          matching: find.text('Show data folder'),
        ),
        findsOneWidget,
      );
      await tapIn(tester, keyed('settings-show-folder'));
      expect(files.shown, [store.dataDir]);
      // The folder is on the screen: the window says nothing more.
      expect(keyed('settings-data-message'), findsNothing);
      // The path can still be copied.
      expect(keyed('settings-copy-path'), findsOneWidget);
    });

    testWidgets('the system does not open the folder: the window says so', (
      tester,
    ) async {
      final files = FakeFiles()
        ..canShowFolder = true
        ..shows = false;
      await openSettings(
        tester,
        _diskStore(),
        tab: SettingsTab.data,
        files: files,
      );
      await tapIn(tester, keyed('settings-show-folder'));
      expect(
        message(tester),
        'Grove could not open the folder. You can copy its path.',
      );
      expect(keyed('settings-copy-path'), findsOneWidget);
    });

    testWidgets('an error of the system is a message, not a crash', (
      tester,
    ) async {
      final files = FakeFiles()
        ..canShowFolder = true
        ..failure = StateError('no');
      await openSettings(
        tester,
        _diskStore(),
        tab: SettingsTab.data,
        files: files,
      );
      await tapIn(tester, keyed('settings-show-folder'));
      expect(tester.takeException(), isNull);
      expect(
        message(tester),
        'Grove could not open the folder. You can copy its path.',
      );
    });

    testWidgets('no "Show data folder" on a phone, with no file windows and '
        'with no folder', (tester) async {
      // A phone: the system has no window of folders.
      await openSettings(
        tester,
        _diskStore(),
        tab: SettingsTab.data,
        files: FakeFiles(),
      );
      expect(keyed('settings-show-folder'), findsNothing);
      expect(keyed('settings-copy-path'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      // No file windows in this copy of Grove.
      await openSettings(tester, _diskStore(), tab: SettingsTab.data);
      expect(keyed('settings-show-folder'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      // A store in memory has no folder.
      await openSettings(
        tester,
        plannerStore(),
        tab: SettingsTab.data,
        files: FakeFiles()..canShowFolder = true,
      );
      expect(keyed('settings-show-folder'), findsNothing);
    });

    testWidgets('a store in memory says so', (tester) async {
      await openSettings(tester, plannerStore(), tab: SettingsTab.data);
      expect(
        tester.widget<Text>(keyed('settings-data-path')).data,
        'Grove cannot find its data folder.',
      );
      expect(keyed('settings-copy-path'), findsNothing);
    });

    testWidgets('no file window: no Export and no Import', (tester) async {
      await openSettings(tester, _diskStore(), tab: SettingsTab.data);
      expect(keyed('settings-export'), findsNothing);
      expect(keyed('settings-import'), findsNothing);
      expect(
        inSettings(
          find.text(
            'Export and Import are not in this copy of Grove yet. The '
            'daily backups are.',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a file window: Export and Import show', (tester) async {
      await openSettings(
        tester,
        _diskStore(),
        tab: SettingsTab.data,
        files: FakeFiles(),
      );
      expect(inSettings(find.text('Export JSON…')), findsOneWidget);
      expect(inSettings(find.text('Import JSON…')), findsOneWidget);
      expect(
        inSettings(
          find.text(
            'Export saves everything in one file. Import replaces '
            'everything with the file you pick.',
          ),
        ),
        findsOneWidget,
      );
      // A copy of Grove with no sync has nothing that blocks Import.
      expect(keyed('settings-import-blocked'), findsNothing);
    });

    testWidgets('a system with no save window: Import shows, Export does '
        'not', (tester) async {
      final files = FakeFiles()..canSave = false;
      await openSettings(
        tester,
        _diskStore(),
        tab: SettingsTab.data,
        size: phoneSize,
        files: files,
      );
      expect(keyed('settings-export'), findsNothing);
      expect(keyed('settings-import'), findsOneWidget);
      expect(
        inSettings(
          find.text(
            'Import replaces everything with the file you pick. Export is '
            'not on this device yet.',
          ),
        ),
        findsOneWidget,
      );
      await tapIn(tester, keyed('settings-import'));
      expect(files.opened, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the daily backups', (tester) async {
      final store = _diskStore();
      await openSettings(tester, store, tab: SettingsTab.data);
      expect(
        inSettings(
          find.text(
            'No backups yet. Grove makes one each day when it starts and '
            'keeps the newest 14.',
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(keyed('settings-close'));
      await tester.pumpAndSettle();

      File(
          '${store.dataDir}${Platform.pathSeparator}Backups'
          '${Platform.pathSeparator}grove-2026-10-04.sqlite',
        )
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(2400, 0));
      await pressSettingsKey(tester);
      await showTab(tester, SettingsTab.data);
      final row = keyed('settings-backup-grove-2026-10-04.sqlite');
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('Sunday, 4 October 2026')),
        findsOneWidget,
      );
      expect(find.descendant(of: row, matching: find.text('2 KB')), findsOne);
    });

    testWidgets('Export saves all data under the name of today', (
      tester,
    ) async {
      final store = _diskStore();
      addTask(store, 'Buy bread');
      final files = FakeFiles();
      await openSettings(tester, store, tab: SettingsTab.data, files: files);
      await tapIn(tester, keyed('settings-export'));
      expect(files.saved, hasLength(1));
      expect(files.saved.single.name, 'grove-export-2026-10-07.json');
      expect(files.saved.single.text, store.exportData());
      expect(message(tester), 'Saved grove-export-2026-10-07.json.');
    });

    testWidgets('Export: a closed window says nothing, an error says why', (
      tester,
    ) async {
      final store = _diskStore();
      final files = FakeFiles()..saves = false;
      await openSettings(tester, store, tab: SettingsTab.data, files: files);
      await tapIn(tester, keyed('settings-export'));
      expect(keyed('settings-data-message'), findsNothing);

      files.failure = const FileSystemException('The disk is full');
      await tapIn(tester, keyed('settings-export'));
      expect(message(tester), startsWith('Grove could not save the file. '));
      expect(message(tester), contains('The disk is full'));
      expect(
        tester.getSemantics(keyed('settings-data-message')).label,
        startsWith('Problem: Grove could not save the file.'),
      );
    });

    /// The file of another Grove, with two tasks and one event.
    String otherFile() {
      final other = makeStore();
      addTask(other, 'From the file 1');
      addTask(other, 'From the file 2');
      other.createFromDraft(
        title: 'Flight',
        day: wednesday,
        start: 7 * 60,
        end: 9 * 60,
        asEvent: true,
      );
      return other.exportData();
    }

    Set<String> taskTitles(AppStore s) => {
      for (final t in s.repos.tasks.all()) t.title,
    };

    testWidgets('Import asks first, and "Cancel" changes nothing', (
      tester,
    ) async {
      final store = _diskStore();
      addTask(store, 'Mine');
      final files = FakeFiles()..picked = (name: 'old.json', text: otherFile());
      await openSettings(tester, store, tab: SettingsTab.data, files: files);
      await tapIn(tester, keyed('settings-import'));
      expect(find.text('Replace everything in Grove?'), findsOneWidget);
      expect(
        find.text(
          'This file has 2 tasks, 1 events, 0 notes and 0 lists.\n'
          'Import replaces ALL your data with the data in this file.\n'
          'Grove saves a copy of your data first, in the data folder.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(taskTitles(store), {'Mine'});
      expect(keyed('settings-data-message'), findsNothing);
      expect(settingsView, findsOneWidget);
    });

    testWidgets('Import replaces the data and keeps a copy of the old', (
      tester,
    ) async {
      final store = _diskStore();
      addTask(store, 'Mine');
      final files = FakeFiles()..picked = (name: 'old.json', text: otherFile());
      await openSettings(tester, store, tab: SettingsTab.data, files: files);
      await tapIn(tester, keyed('settings-import'));
      await tester.tap(find.text('Replace Everything'));
      await tester.pump();
      await endToast(tester);
      expect(taskTitles(store), {'From the file 1', 'From the file 2'});
      expect(
        message(tester),
        'Imported old.json. Your old data is in before-import.sqlite in the '
        'data folder.',
      );
      expect(
        File('${store.dataDir}${Platform.pathSeparator}before-import.sqlite')
            .existsSync(),
        isTrue,
      );
    });

    testWidgets('Import: a wrong file changes nothing', (tester) async {
      final store = _diskStore();
      addTask(store, 'Mine');
      final files = FakeFiles()..picked = (name: 'x.json', text: '{"a": 1}');
      await openSettings(tester, store, tab: SettingsTab.data, files: files);
      await tapIn(tester, keyed('settings-import'));
      expect(find.text('Replace everything in Grove?'), findsNothing);
      expect(
        message(tester),
        'This is not a Grove export file. Nothing was changed.',
      );
      expect(
        tester.getSemantics(keyed('settings-data-message')).label,
        startsWith('Problem: '),
      );
      expect(taskTitles(store), {'Mine'});
    });

    testWidgets('Import: no folder for the copy, so nothing changes', (
      tester,
    ) async {
      final store = plannerStore();
      addTask(store, 'Mine');
      final files = FakeFiles()..picked = (name: 'old.json', text: otherFile());
      await openSettings(tester, store, tab: SettingsTab.data, files: files);
      await tapIn(tester, keyed('settings-import'));
      await tester.tap(find.text('Replace Everything'));
      await tester.pumpAndSettle();
      expect(
        message(tester),
        'Grove cannot find its data folder. Nothing was changed.',
      );
      expect(taskTitles(store), {'Mine'});
    });

    testWidgets('Import: a closed file window does nothing', (tester) async {
      final store = _diskStore();
      final files = FakeFiles();
      await openSettings(tester, store, tab: SettingsTab.data, files: files);
      await tapIn(tester, keyed('settings-import'));
      expect(files.opened, 1);
      expect(find.text('Replace everything in Grove?'), findsNothing);
      expect(keyed('settings-data-message'), findsNothing);
    });
  });
  group('updates', () {
    AppStore updateStore(FakeReleases releases) => makeStore(
      prefs: MemoryPrefs()..set('appearance.motion', false),
      releases: releases,
    );

    testWidgets('a copy with no check has no Updates section', (tester) async {
      await openSettings(tester, plannerStore(), tab: SettingsTab.data);
      expect(keyed('settings-updates-version'), findsNothing);
      expect(keyed('settings-updates-check'), findsNothing);
    });

    testWidgets('the section shows the version and turns the check off', (
      tester,
    ) async {
      final store = updateStore(FakeReleases());
      await openSettings(tester, store, tab: SettingsTab.data);
      expect(
        tester.widget<Text>(keyed('settings-updates-version')).data,
        'Grove ${GroveCore.version}',
      );
      expect(store.checksForUpdates, isTrue);
      await tapIn(tester, keyed('settings-updates-switch'));
      expect(store.checksForUpdates, isFalse);
      expect(store.prefs.getBool('updates.check'), isFalse);
    });

    testWidgets('Check now says when this is the newest version', (
      tester,
    ) async {
      final releases = FakeReleases(release(GroveCore.version));
      final store = updateStore(releases);
      await openSettings(tester, store, tab: SettingsTab.data);
      await tapIn(tester, keyed('settings-updates-check'));
      expect(releases.asked, 1);
      expect(
        tester.widget<Text>(keyed('settings-updates-message')).data,
        'Grove ${GroveCore.version} is the newest version.',
      );
    });

    testWidgets('Check now finds a new version and the card shows', (
      tester,
    ) async {
      final store = updateStore(FakeReleases(release('9.9.9')));
      await openSettings(tester, store, tab: SettingsTab.data);
      await tapIn(tester, keyed('settings-updates-check'));
      expect(
        tester.widget<Text>(keyed('settings-updates-message')).data,
        'Grove 9.9.9 is here.',
      );
      expect(store.availableUpdate?.version.toString(), '9.9.9');
    });

    testWidgets('Check now with no network says so', (tester) async {
      final store = updateStore(FakeReleases()..fails = true);
      await openSettings(tester, store, tab: SettingsTab.data);
      await tapIn(tester, keyed('settings-updates-check'));
      expect(
        tester.widget<Text>(keyed('settings-updates-message')).data,
        'Grove could not reach GitHub. Try again later.',
      );
    });
  });
}
