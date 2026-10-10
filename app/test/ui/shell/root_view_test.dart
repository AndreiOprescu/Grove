// The app shell on a desktop window and on a phone: the screen switch, the
// left dock, the theme menu, the shortcuts, the message and the background.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/app.dart';
import 'package:grove/ui/shell/appearance_button.dart';
import 'package:grove/ui/shell/left_dock.dart';
import 'package:grove/ui/shell/root_view.dart';
import 'package:grove/ui/shell/screen_switch.dart';
import 'package:grove/ui/shell/shell_model.dart';
import 'package:grove/ui/theme/ambient_background.dart';
import 'package:grove/ui/theme/grove_theme.dart';
import 'package:grove/ui/theme/theme_spec.dart';

import '../support.dart';

Finder screenButton(Screen s) => find.byKey(ValueKey('screen-${s.name}'));
Finder dockButton(LeftPane p) => find.byKey(ValueKey('dock-${p.name}'));
Finder content(Screen s) => find.byKey(ValueKey('content-${s.name}'));
Finder pane(LeftPane p) => find.byKey(ValueKey('pane-${p.name}'));

GroveTheme themeOf(WidgetTester tester) =>
    GroveTheme.of(tester.element(find.byType(RootView)));

void main() {
  group('on a desktop window', () {
    testWidgets('the screen switch sits at the top with five words', (
      tester,
    ) async {
      await pumpApp(tester, still(), size: desktopSize);
      expect(find.byType(ScreenSwitch), findsOneWidget);
      expect(find.byType(PhoneNavBar), findsNothing);
      for (final s in Screen.values) {
        expect(
          find.descendant(of: screenButton(s), matching: find.text(s.title)),
          findsOneWidget,
        );
      }
      expect(content(Screen.today), findsOneWidget);
      expect(tester.getTopLeft(find.byType(ScreenSwitch)).dy, lessThan(10));
    });

    testWidgets('a click on a screen name opens that screen', (tester) async {
      final m = still();
      await pumpApp(tester, m, size: desktopSize);
      await tester.tap(screenButton(Screen.notes));
      await tester.pumpAndSettle();
      expect(m.screen, Screen.notes);
      expect(content(Screen.notes), findsOneWidget);
      expect(content(Screen.today), findsNothing);
    });

    testWidgets('a narrow window shows the switch with pictures only', (
      tester,
    ) async {
      await pumpApp(tester, still(), size: const Size(800, 620));
      expect(find.byType(ScreenSwitch), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ScreenSwitch),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the dock is on Today and the Planner only', (tester) async {
      final m = still();
      await pumpApp(tester, m, size: desktopSize);
      expect(find.byType(LeftDock), findsOneWidget);
      for (final p in LeftPane.values) {
        expect(dockButton(p), findsOneWidget);
      }
      m.screen = Screen.planner;
      await tester.pumpAndSettle();
      expect(dockButton(LeftPane.tasks), findsOneWidget);
      for (final s in [Screen.calendar, Screen.notes, Screen.garden]) {
        m.screen = s;
        await tester.pumpAndSettle();
        expect(dockButton(LeftPane.tasks), findsNothing, reason: s.name);
      }
    });

    testWidgets('a dock button opens its panel beside the screen', (
      tester,
    ) async {
      final m = still(screen: Screen.planner);
      await pumpApp(tester, m, size: desktopSize);
      expect(pane(LeftPane.tasks), findsNothing);
      final wide = tester.getSize(content(Screen.planner)).width;

      await tester.tap(dockButton(LeftPane.tasks));
      await tester.pumpAndSettle();
      expect(m.leftPane, LeftPane.tasks);
      expect(tester.getSize(pane(LeftPane.tasks)).width, LeftPane.plannerWidth);
      // the panel pushes the screen aside
      expect(tester.getSize(content(Screen.planner)).width, lessThan(wide));
      expect(
        tester.getTopLeft(pane(LeftPane.tasks)).dx,
        lessThan(tester.getTopLeft(content(Screen.planner)).dx),
      );

      await tester.tap(dockButton(LeftPane.goals));
      await tester.pumpAndSettle();
      expect(pane(LeftPane.goals), findsOneWidget);
      expect(pane(LeftPane.tasks), findsNothing);

      await tester.tap(dockButton(LeftPane.goals));
      await tester.pumpAndSettle();
      expect(m.leftPane, isNull);
      expect(pane(LeftPane.goals), findsNothing);
      expect(tester.getSize(content(Screen.planner)).width, wide);
    });

    testWidgets('an open panel does not show on the Calendar', (tester) async {
      final m = still(screen: Screen.calendar, leftPane: LeftPane.notes);
      await pumpApp(tester, m, size: desktopSize);
      expect(pane(LeftPane.notes), findsNothing);
      m.screen = Screen.today;
      await tester.pumpAndSettle();
      expect(pane(LeftPane.notes), findsOneWidget);
    });

    testWidgets('the buttons say what they are', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(
        tester,
        still(screen: Screen.planner, leftPane: LeftPane.goals),
        size: desktopSize,
      );
      expect(
        tester.getSemantics(screenButton(Screen.planner)),
        isSemantics(label: 'Planner', isButton: true, isSelected: true),
      );
      expect(
        tester.getSemantics(screenButton(Screen.notes)),
        isSemantics(label: 'Notes', isButton: true, isSelected: false),
      );
      expect(
        tester.getSemantics(dockButton(LeftPane.goals)),
        isSemantics(label: 'Goals', isButton: true, isSelected: true),
      );
      expect(find.byTooltip('Hide goals'), findsOneWidget);
      expect(find.byTooltip('Show notes'), findsOneWidget);
      handle.dispose();
    });
  });

  group('on a phone', () {
    testWidgets('the screens are in a bar at the bottom', (tester) async {
      final m = still();
      await pumpApp(tester, m, size: phoneSize);
      expect(find.byType(PhoneNavBar), findsOneWidget);
      expect(find.byType(ScreenSwitch), findsNothing);
      final bar = tester.getRect(find.byType(PhoneNavBar));
      expect(bar.bottom, greaterThan(phoneSize.height - 40));
      expect(tester.takeException(), isNull);

      await tester.tap(screenButton(Screen.garden));
      await tester.pumpAndSettle();
      expect(m.screen, Screen.garden);
      expect(content(Screen.garden), findsOneWidget);
    });

    testWidgets('a nav button is big enough for a finger', (tester) async {
      await pumpApp(tester, still(), size: phoneSize);
      for (final s in Screen.values) {
        final size = tester.getSize(screenButton(s));
        expect(size.height, greaterThanOrEqualTo(44), reason: s.name);
        expect(size.width, greaterThanOrEqualTo(44), reason: s.name);
      }
    });

    testWidgets('an open panel takes the place of the screen', (tester) async {
      final m = still(screen: Screen.planner);
      await pumpApp(tester, m, size: phoneSize);
      expect(content(Screen.planner), findsOneWidget);
      await tester.tap(dockButton(LeftPane.notes));
      await tester.pumpAndSettle();
      expect(pane(LeftPane.notes), findsOneWidget);
      expect(content(Screen.planner), findsNothing);
      await tester.tap(dockButton(LeftPane.notes));
      await tester.pumpAndSettle();
      expect(content(Screen.planner), findsOneWidget);
    });

    testWidgets('the shell keeps clear of the notch and the home bar', (
      tester,
    ) async {
      tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
      addTearDown(tester.view.resetPadding);
      await pumpApp(tester, still(), size: phoneSize);
      expect(
        tester.getTopLeft(find.byType(LeftDock)).dy,
        greaterThanOrEqualTo(47),
      );
      expect(
        tester.getRect(find.byType(PhoneNavBar)).bottom,
        lessThanOrEqualTo(phoneSize.height - 34),
      );
    });
  });

  group('shortcuts', () {
    Future<void> press(
      WidgetTester tester,
      LogicalKeyboardKey modifier,
      LogicalKeyboardKey key,
    ) async {
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
    }

    testWidgets('Ctrl with a number opens a screen', (tester) async {
      final m = still();
      await pumpApp(tester, m, size: desktopSize);
      const ctrl = LogicalKeyboardKey.controlLeft;
      await press(tester, ctrl, LogicalKeyboardKey.digit1);
      expect(m.screen, Screen.planner);
      await press(tester, ctrl, LogicalKeyboardKey.digit3);
      expect(m.screen, Screen.calendar);
      await press(tester, ctrl, LogicalKeyboardKey.digit4);
      expect(m.screen, Screen.notes);
      await press(tester, ctrl, LogicalKeyboardKey.digit5);
      expect(m.screen, Screen.garden);
      await press(tester, ctrl, LogicalKeyboardKey.keyT);
      expect(m.screen, Screen.today);
      await press(tester, ctrl, LogicalKeyboardKey.digit2);
      expect((m.screen, m.leftPane), (Screen.planner, LeftPane.tasks));
    });

    testWidgets('on a Mac the key is Command', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final m = still();
      await pumpApp(tester, m, size: desktopSize);
      await press(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.digit3,
      );
      expect(m.screen, Screen.today);
      await press(
        tester,
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.digit3,
      );
      expect(m.screen, Screen.calendar);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('themes', () {
    testWidgets('the menu at the top right switches the theme live', (
      tester,
    ) async {
      final m = still();
      await pumpApp(tester, m, size: desktopSize);
      expect(themeOf(tester).kind, ThemeId.grove);
      await tester.tap(find.byType(AppearanceButton));
      await tester.pumpAndSettle();
      for (final s in ThemeSpec.all) {
        expect(find.text(s.name), findsOneWidget);
      }
      for (final mode in AppearanceMode.values) {
        expect(find.text(mode.label), findsOneWidget);
      }
      expect(find.text('Motion'), findsOneWidget);

      await tester.tap(find.text('Vintage'));
      await tester.pumpAndSettle();
      expect(m.themeId, ThemeId.vintage);
      expect(themeOf(tester).kind, ThemeId.vintage);
      expect(
        themeOf(tester),
        GroveTheme.make(ThemeId.vintage, Brightness.light),
      );
    });

    testWidgets('the menu sets light or dark and the motion switch', (
      tester,
    ) async {
      final m = still();
      await pumpApp(tester, m, size: desktopSize);
      await tester.tap(find.byType(AppearanceButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(m.appearance, AppearanceMode.dark);
      expect(themeOf(tester).brightness, Brightness.dark);

      await tester.tap(find.byType(AppearanceButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Motion'));
      await tester.pump();
      expect(m.motionSetting, isTrue);
      expect(find.text('Motion on'), findsOneWidget);
      m.setMotion(false);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('the menu works on a phone too', (tester) async {
      final m = still();
      await pumpApp(tester, m, size: phoneSize);
      await tester.tap(find.byType(AppearanceButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Minimal'));
      await tester.pumpAndSettle();
      expect(m.themeId, ThemeId.minimal);
      expect(tester.takeException(), isNull);
    });

    testWidgets('System follows the device', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final m = still(appearance: AppearanceMode.system);
      await pumpApp(tester, m, size: desktopSize);
      expect(themeOf(tester).brightness, Brightness.dark);
      m.setAppearance(AppearanceMode.light);
      await tester.pumpAndSettle();
      expect(themeOf(tester).brightness, Brightness.light);
      m.setAppearance(AppearanceMode.system);
      await tester.pumpAndSettle();
      expect(themeOf(tester).brightness, Brightness.dark);
    });

    testWidgets('every theme draws on both sizes with no error', (
      tester,
    ) async {
      for (final size in [desktopSize, phoneSize]) {
        for (final id in ThemeId.values) {
          for (final mode in [AppearanceMode.light, AppearanceMode.dark]) {
            final m = still(
              themeId: id,
              appearance: mode,
              screen: Screen.planner,
              leftPane: LeftPane.tasks,
            );
            await pumpApp(tester, m, size: size);
            expect(tester.takeException(), isNull, reason: '$id $mode $size');
            expect(themeOf(tester).kind, id);
          }
        }
      }
    });
  });

  group('the background', () {
    testWidgets('Futuristic has the grid, Vintage the paper', (tester) async {
      final m = still();
      await pumpApp(tester, m, size: desktopSize);
      expect(find.byType(AmbientBackground), findsOneWidget);
      expect(find.byType(BackgroundGrid), findsNothing);
      expect(find.byType(PaperTexture), findsNothing);
      m.setTheme(ThemeId.futuristic);
      await tester.pumpAndSettle();
      expect(find.byType(BackgroundGrid), findsOneWidget);
      expect(find.byType(PaperTexture), findsNothing);
      m.setTheme(ThemeId.vintage);
      await tester.pumpAndSettle();
      expect(find.byType(BackgroundGrid), findsNothing);
      expect(find.byType(PaperTexture), findsOneWidget);
    });

    testWidgets('with motion off nothing moves', (tester) async {
      await pumpApp(tester, still(), size: desktopSize);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('with motion on the blobs move, and stop when the window is '
        'not in front', (tester) async {
      final m = LocalShellModel();
      await pumpApp(tester, m, size: desktopSize);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isTrue);

      m.setMotion(false);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('the device setting "reduce motion" stops the blobs', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpApp(tester, LocalShellModel(), size: desktopSize);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('the message', () {
    testWidgets('shows at the bottom and goes away', (tester) async {
      final m = still();
      await pumpApp(tester, m, size: desktopSize);
      m.showToast('Saved');
      await tester.pumpAndSettle();
      expect(find.text('Saved'), findsOneWidget);
      expect(
        tester.getCenter(find.text('Saved')).dy,
        greaterThan(desktopSize.height - 80),
      );
      await tester.pump(const Duration(milliseconds: 2300));
      await tester.pumpAndSettle();
      expect(find.text('Saved'), findsNothing);
    });
  });

  group('the app', () {
    testWidgets('makes its own model when none is given', (tester) async {
      await tester.pumpWidget(const GroveApp());
      expect(find.byType(RootView), findsOneWidget);
      // take the app down so its moving background stops
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a screen made by a feature takes the place of the stand-in', (
      tester,
    ) async {
      await pumpApp(
        tester,
        still(screen: Screen.planner, leftPane: LeftPane.tasks),
        size: desktopSize,
        screenBuilder: (context, screen) =>
            screen == Screen.planner ? const Text('real planner') : null,
        paneBuilder: (context, pane) =>
            pane == LeftPane.tasks ? const Text('real tasks') : null,
      );
      expect(find.text('real planner'), findsOneWidget);
      expect(find.text('real tasks'), findsOneWidget);
    });
  });
}
