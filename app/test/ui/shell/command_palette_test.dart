// The command palette (PLAN §5.5 item 11) and the two buttons at the top
// right: "Search" and the gear. Swift: Sources/Grove/Shared/
// CommandPalette.swift.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/shell/command_palette.dart';
import 'package:grove/ui/shell/left_dock.dart';
import 'package:grove/ui/shell/screen_switch.dart';
import 'package:grove/ui/shell/top_buttons.dart';
import 'package:grove/ui/theme/panel.dart';

import '../settings/settings_support.dart';

final palette = find.byType(CommandPalette);
final field = keyed('palette-field');
final searchButton = keyed('search-button');
final gear = keyed('settings-button');

Finder row(String id) => keyed('palette-row-$id');
Finder command(PaletteCommandId id) => row('command-${id.name}');

/// Ctrl (or `modifier`) and K.
Future<void> pressPaletteKey(
  WidgetTester tester, {
  LogicalKeyboardKey modifier = LogicalKeyboardKey.controlLeft,
}) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

Future<void> type(WidgetTester tester, String text) async {
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
}

/// Return on a real keyboard and "Go" on the keyboard of a phone.
Future<void> pressReturn(WidgetTester tester) async {
  await tester.testTextInput.receiveAction(TextInputAction.go);
  await tester.pumpAndSettle();
}

/// The ids of the rows that are drawn as the chosen one.
List<String> chosenRows(WidgetTester tester) => [
  for (final element
      in find
          .descendant(
            of: palette,
            matching: find.byWidgetPredicate(
              (w) =>
                  w is DecoratedBox &&
                  w.decoration is BoxDecoration &&
                  (w.decoration as BoxDecoration).color != null &&
                  w.child is SizedBox &&
                  (w.child! as SizedBox).height == CommandPalette.rowHeight,
            ),
          )
          .evaluate())
    (element.findAncestorWidgetOfExactType<GestureDetector>()!.key!
            as ValueKey<String>)
        .value
        .replaceFirst('palette-row-', ''),
];

bool fieldHasFocus(WidgetTester tester) =>
    tester.widget<TextField>(field).focusNode!.hasFocus;

void main() {
  group('the buttons at the top right', () {
    testWidgets('a desktop window has "Search" with its key, and a gear', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpApp(tester, store);
      expect(searchButton, findsOneWidget);
      expect(
        find.descendant(of: searchButton, matching: find.text('Search')),
        findsOneWidget,
      );
      // A test runs as an Android device.
      expect(
        find.descendant(of: searchButton, matching: find.text('Ctrl+K')),
        findsOneWidget,
      );
      expect(gear, findsOneWidget);
      // Swift: 16 points from the right edge, 5 from the top.
      expect(tester.getTopRight(gear), const Offset(1100 - 16, 5));
      expect(tester.getRect(searchButton).right, lessThan(1100 - 16 - 26));
      expect(textOffPixels(tester, within: searchButton), isEmpty);
    });

    testWidgets('no part of the top strip covers another', (tester) async {
      // The letters of a test are wider than the real ones: the worst case.
      for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
        debugDefaultTargetPlatformOverride = platform;
        final store = plannerStore();
        await pumpApp(tester, store);
        final dock = tester.getRect(find.byType(LeftDock));
        final screens = tester.getRect(find.byType(ScreenSwitch));
        final search = tester.getRect(searchButton);
        expect(dock.left, platform == TargetPlatform.macOS ? 84 : 16);
        expect(screens.left, greaterThanOrEqualTo(dock.right + 8));
        expect(screens.right, lessThanOrEqualTo(search.left - 8));
        expect(screens.left, screens.left.roundToDouble());
        expect(tester.getRect(gear).right, 1100 - 16);
        await tester.pumpWidget(const SizedBox());
      }
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('in a wide window the screen switch is in the middle', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpApp(tester, store, size: const Size(1440, 900));
      final screens = tester.getRect(find.byType(ScreenSwitch));
      expect(screens.center.dx, 720);
      expect(screens.top, 5);
    });

    testWidgets('a tap on "Search" opens the box with the cursor in it', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpApp(tester, store);
      expect(palette, findsNothing);
      await tester.tap(searchButton);
      await tester.pumpAndSettle();
      expect(store.paletteOpen, isTrue);
      expect(palette, findsOneWidget);
      expect(fieldHasFocus(tester), isTrue);
      expect(find.text(CommandPalette.placeholder), findsOneWidget);
    });

    testWidgets('a tap on the gear opens Settings', (tester) async {
      final store = plannerStore();
      await pumpApp(tester, store);
      await tester.tap(gear);
      await tester.pumpAndSettle();
      expect(settingsView, findsOneWidget);
    });

    testWidgets('a phone has the search picture and no gear', (tester) async {
      final store = plannerStore();
      await pumpApp(tester, store, size: phoneSize);
      expect(searchButton, findsOneWidget);
      expect(
        find.descendant(of: searchButton, matching: find.text('Search')),
        findsNothing,
      );
      expect(gear, findsNothing);
      // Big enough for a finger.
      final size = tester.getSize(searchButton);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
      await tester.tap(searchButton);
      await tester.pumpAndSettle();
      expect(palette, findsOneWidget);
    });

    testWidgets('the top bar fits the narrowest phone', (tester) async {
      final store = plannerStore();
      await pumpApp(tester, store, size: const Size(320, 640));
      expect(tester.takeException(), isNull);
      expect(tester.getRect(searchButton).left, greaterThan(160));
    });

    test('a key is written the way of the system', () {
      expect(KeyNames.of('⌘K', apple: true), '⌘K');
      expect(KeyNames.of('⌘K', apple: false), 'Ctrl+K');
      expect(KeyNames.of('⌥⌘N', apple: false), 'Ctrl+Alt+N');
      expect(KeyNames.of('⇧⌘N', apple: false), 'Ctrl+Shift+N');
      expect(KeyNames.of('⌘,', apple: false), 'Ctrl+,');
    });
  });

  group('the command palette', () {
    testWidgets('Ctrl and K opens it, and closes it', (tester) async {
      final store = plannerStore();
      await pumpApp(tester, store);
      await pressPaletteKey(tester);
      expect(store.paletteOpen, isTrue);
      expect(palette, findsOneWidget);
      expect(fieldHasFocus(tester), isTrue);
      // The first rows are the commands, and the first one is chosen.
      expect(command(PaletteCommandId.newTask), findsOneWidget);
      expect(chosenRows(tester), [store.paletteItems('').first.id]);
      await pressPaletteKey(tester);
      expect(store.paletteOpen, isFalse);
      expect(palette, findsNothing);
    });

    testWidgets('on a Mac the key is Command, and the rows show ⌘', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final store = plannerStore();
      await pumpApp(tester, store);
      await pressPaletteKey(tester);
      expect(store.paletteOpen, isFalse);
      await pressPaletteKey(tester, modifier: LogicalKeyboardKey.metaLeft);
      expect(store.paletteOpen, isTrue);
      expect(
        find.descendant(
          of: command(PaletteCommandId.newTask),
          matching: find.text('⌘N'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: searchButton, matching: find.text('⌘K')),
        findsOneWidget,
      );
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('on Windows the rows show Ctrl', (tester) async {
      final store = plannerStore();
      await pumpApp(tester, store);
      await pressPaletteKey(tester);
      expect(
        find.descendant(
          of: command(PaletteCommandId.newTask),
          matching: find.text('Ctrl+N'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('typing keeps the rows that match', (tester) async {
      final store = plannerStore();
      addTask(store, 'Water the ferns');
      await pumpApp(tester, store);
      await pressPaletteKey(tester);
      await type(tester, 'fern');
      final found = store.paletteItems('fern');
      expect(found, isNotEmpty);
      for (final item in found) {
        expect(row(item.id), findsOneWidget);
      }
      // The task is in the list of the screen under the box too.
      final inBox = find.descendant(
        of: palette,
        matching: find.text('Water the ferns'),
      );
      expect(inBox, findsOneWidget);
      expect(command(PaletteCommandId.newTask), findsNothing);
      // `>` keeps the commands only.
      await type(tester, '>garden');
      expect(command(PaletteCommandId.showGarden), findsOneWidget);
      expect(inBox, findsNothing);
    });

    testWidgets('down and up choose a row, and Return runs it', (tester) async {
      final store = plannerStore();
      await pumpApp(tester, store);
      await pressPaletteKey(tester);
      await type(tester, '>');
      final rows = store.paletteItems('>');
      final garden = rows.indexWhere((r) => r.id == 'command-showGarden');
      expect(garden, greaterThan(1));
      // Up on the first row stays there.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(chosenRows(tester), [rows.first.id]);
      for (var i = 0; i < garden + 1; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(chosenRows(tester), ['command-showGarden']);
      // The chosen row is in view, also when the list had to scroll.
      final list = tester.getRect(keyed('palette-list'));
      final chosen = tester.getRect(command(PaletteCommandId.showGarden));
      expect(chosen.top, greaterThanOrEqualTo(list.top));
      expect(chosen.bottom, lessThanOrEqualTo(list.bottom));
      await pressReturn(tester);
      expect(store.screen, Screen.garden);
      expect(store.paletteOpen, isFalse);
      expect(palette, findsNothing);
    });

    testWidgets('down on the last row stays there', (tester) async {
      final store = plannerStore();
      await pumpApp(tester, store);
      await pressPaletteKey(tester);
      await type(tester, '>');
      final rows = store.paletteItems('>');
      for (var i = 0; i < rows.length + 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      }
      await tester.pumpAndSettle();
      expect(chosenRows(tester), [rows.last.id]);
      final list = tester.getRect(keyed('palette-list'));
      expect(
        tester.getRect(row(rows.last.id)).bottom,
        lessThanOrEqualTo(list.bottom),
      );
    });

    testWidgets('a new text chooses the first row again', (tester) async {
      final store = plannerStore();
      await pumpApp(tester, store);
      await pressPaletteKey(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(chosenRows(tester), [store.paletteItems('')[2].id]);
      await type(tester, '>');
      expect(chosenRows(tester), [store.paletteItems('>').first.id]);
    });

    testWidgets('a tap on a row runs it', (tester) async {
      final store = plannerStore();
      await pumpApp(tester, store);
      await pressPaletteKey(tester);
      await type(tester, '>notes');
      await tester.tap(command(PaletteCommandId.showNotes));
      await tester.pumpAndSettle();
      expect(store.screen, Screen.notes);
      expect(palette, findsNothing);
    });

    testWidgets('Esc closes it', (tester) async {
      final store = plannerStore();
      await pumpApp(tester, store);
      await pressPaletteKey(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(store.paletteOpen, isFalse);
      expect(palette, findsNothing);
    });

    testWidgets('a tap next to the box closes it', (tester) async {
      final store = plannerStore();
      await pumpApp(tester, store);
      await pressPaletteKey(tester);
      await tester.tapAt(const Offset(40, 400));
      await tester.pumpAndSettle();
      expect(store.paletteOpen, isFalse);
      expect(palette, findsNothing);
    });

    testWidgets('a tap in the box leaves the cursor in the field', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpApp(tester, store);
      await pressPaletteKey(tester);
      await tester.tap(find.text('↑↓ choose'));
      await tester.pumpAndSettle();
      expect(store.paletteOpen, isTrue);
      expect(fieldHasFocus(tester), isTrue);
    });

    testWidgets('"Go to date…" keeps the box open and waits for a day', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpApp(tester, store);
      await pressPaletteKey(tester);
      await type(tester, '>go to date');
      await pressReturn(tester);
      expect(store.paletteOpen, isTrue);
      expect(palette, findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text, 'go to ');
      expect(fieldHasFocus(tester), isTrue);
      // As on the Mac: "go to" finds the two commands that start so.
      expect(command(PaletteCommandId.goToDate), findsOneWidget);
      expect(command(PaletteCommandId.goToday), findsOneWidget);
      // "goto" finds no command: the box asks for a day.
      await type(tester, 'goto');
      expect(store.paletteItems('goto'), isEmpty);
      expect(find.text(CommandPalette.typeADay), findsOneWidget);
      // Friday of the week of the test.
      await type(tester, 'go to fri');
      final rows = store.paletteItems('go to fri');
      expect(rows.first.id, 'day-2026-10-09');
      expect(row(rows.first.id), findsOneWidget);
      await pressReturn(tester);
      expect(store.selectedDay, d('2026-10-09'));
      expect(store.paletteOpen, isFalse);
    });

    testWidgets('a text that finds nothing says so', (tester) async {
      final store = plannerStore();
      await pumpApp(tester, store);
      await pressPaletteKey(tester);
      await type(tester, 'zzqqxx');
      expect(store.paletteItems('zzqqxx'), isEmpty);
      expect(find.text(CommandPalette.nothingFound), findsOneWidget);
      // Return with no row does nothing.
      await pressReturn(tester);
      expect(store.paletteOpen, isTrue);
    });

    testWidgets('the box opens empty each time', (tester) async {
      final store = plannerStore();
      await pumpApp(tester, store);
      await pressPaletteKey(tester);
      await type(tester, '>garden');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await pressPaletteKey(tester);
      expect(tester.widget<TextField>(field).controller!.text, '');
      expect(command(PaletteCommandId.newTask), findsOneWidget);
    });

    testWidgets('the box is 560 wide and 90 from the top, on whole pixels', (
      tester,
    ) async {
      final store = plannerStore();
      addTask(store, 'Water the ferns');
      await pumpApp(tester, store);
      await pressPaletteKey(tester);
      final box = tester.getRect(
        find.descendant(of: palette, matching: find.byType(Panel)),
      );
      expect(box.width, CommandPalette.width);
      expect(box.left, (1100 - CommandPalette.width) / 2);
      expect(box.top, CommandPalette.top);
      expect(textOffPixels(tester, within: palette), isEmpty);
      await type(tester, 'fern');
      expect(textOffPixels(tester, within: palette), isEmpty);
      // A window of an odd width.
      await tester.binding.setSurfaceSize(const Size(1101, 621));
      tester.view.physicalSize = const Size(1101, 621);
      await tester.pumpAndSettle();
      final odd = tester.getRect(
        find.descendant(of: palette, matching: find.byType(Panel)),
      );
      expect(odd.left, odd.left.roundToDouble());
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('on a phone the box is as wide as the screen allows', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpApp(tester, store, size: phoneSize);
      await tester.tap(searchButton);
      await tester.pumpAndSettle();
      final box = tester.getRect(
        find.descendant(of: palette, matching: find.byType(Panel)),
      );
      expect(box.left, 12);
      expect(box.width, phoneSize.width - 24);
      expect(box.top, 12);
      expect(tester.takeException(), isNull);
      expect(textOffPixels(tester, within: palette), isEmpty);
    });

    testWidgets('in a low window the list ends inside the window', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpApp(tester, store, size: const Size(800, 400));
      await pressPaletteKey(tester);
      final box = tester.getRect(
        find.descendant(of: palette, matching: find.byType(Panel)),
      );
      expect(box.bottom, lessThanOrEqualTo(400 - 12));
      expect(tester.takeException(), isNull);
    });

    test('the list is as high as its rows, and 360 at most', () {
      expect(CommandPalette.heightFor(1), 60);
      expect(CommandPalette.heightFor(3), 148);
      expect(CommandPalette.heightFor(10), 360);
      expect(CommandPalette.heightFor(10, most: 200), 200);
      // One row is always there.
      expect(CommandPalette.heightFor(10, most: 10), 44);
    });
  });
}
