// The menus of the Mac app (PLAN §5.8, Swift: the `.commands` of
// Sources/Grove/GroveApp.swift): the same lines, the same keys. The keys
// work on each system; the menu bar is on a Mac.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/calendar/event_editor.dart';
import 'package:grove/ui/shell/app_menus.dart';
import 'package:grove/ui/shell/shell_model.dart';
import 'package:grove/ui/theme/theme_spec.dart';

import '../settings/settings_support.dart';

const ctrl = LogicalKeyboardKey.controlLeft;
const command = LogicalKeyboardKey.metaLeft;
const shift = LogicalKeyboardKey.shiftLeft;
const alt = LogicalKeyboardKey.altLeft;

/// `key` with the keys of `held` down. The key "+" has no place of its own
/// on a keyboard: it is the key of "=".
Future<void> press(
  WidgetTester tester,
  List<LogicalKeyboardKey> held,
  LogicalKeyboardKey key,
) async {
  for (final h in held) {
    await tester.sendKeyDownEvent(h);
  }
  await tester.sendKeyEvent(
    key,
    physicalKey: key == LogicalKeyboardKey.add
        ? PhysicalKeyboardKey.equal
        : null,
  );
  for (final h in held.reversed) {
    await tester.sendKeyUpEvent(h);
  }
  await tester.pumpAndSettle();
}

/// Runs `body` as on a Mac. The mark of the system is taken away before
/// the test ends, also when `body` fails.
Future<void> onMac(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

/// The lines of a menu as text: the name, then the key the Mac way.
List<String> lines(ShellMenu menu) => [
  for (final node in menu.nodes)
    switch (node) {
      ShellDivider() => '-',
      ShellSub() => '${node.label} ▸',
      ShellEntry() => [node.label, ?node.shortcut].join(' '),
    },
];

/// The menus the system got, by name.
Map<String, PlatformMenu> menuBar(WidgetTester tester) => {
  for (final menu
      in tester
          .widget<PlatformMenuBar>(find.byType(PlatformMenuBar))
          .menus
          .cast<PlatformMenu>())
    menu.label: menu,
};

/// Every line of a menu of the system, also inside a group or a menu.
Iterable<PlatformMenuItem> leaves(PlatformMenuItem item) sync* {
  if (item is PlatformMenu) {
    for (final child in item.menus) {
      yield* leaves(child);
    }
  } else if (item is PlatformMenuItemGroup) {
    for (final child in item.members) {
      yield* leaves(child);
    }
  } else {
    yield item;
  }
}

PlatformMenuItem line(PlatformMenu menu, String label) =>
    leaves(menu).firstWhere((item) => item.label == label);

void main() {
  group('the menus', () {
    test('are those of the Mac app, in its order', () {
      final model = LocalShellModel();
      final menus = shellMenus(model, const ShellCommands());
      expect([for (final m in menus) m.title], ['File', 'Edit', 'View', 'Go']);
      expect(lines(menus[0]), ['New Task ⌘N', 'New Note ⌥⌘N', 'New Event ⇧⌘N']);
      expect(lines(menus[1]), ['Undo ⌘Z', 'Redo ⇧⌘Z']);
      expect(lines(menus[2]), [
        'Today ⌘T',
        'Planner ⌘1',
        'Tasks ⌘2',
        'Notes Panel',
        'Goals Panel',
        'Deadlines Panel',
        'Calendar ⌘3',
        'Notes ⌘4',
        'Garden ⌘5',
        'Persona ⌘6',
        '-',
        'Zoom In ⌘=',
        'Zoom Out ⌘-',
        '-',
        'Theme ▸',
        'Appearance ▸',
        'Motion',
      ]);
      expect(lines(menus[3]), ['Command Palette ⌘K']);
      expect(settingsEntry(const ShellCommands()).shortcut, '⌘,');
      model.dispose();
    });

    test('Theme and Appearance list each choice and mark the one in use', () {
      final model = LocalShellModel()
        ..setTheme(ThemeId.vintage)
        ..setAppearance(AppearanceMode.dark);
      final view = shellMenus(model, const ShellCommands())[2];
      final subs = view.nodes.whereType<ShellSub>().toList();
      expect(
        [for (final e in subs[0].entries) e.label],
        [for (final spec in ThemeSpec.all) spec.name],
      );
      expect(
        [
          for (final e in subs[0].entries)
            if (e.checked == true) e.label,
        ],
        [ThemeSpec.of(ThemeId.vintage).name],
      );
      expect(
        [for (final e in subs[1].entries) e.label],
        ['System', 'Light', 'Dark'],
      );
      expect(
        [
          for (final e in subs[1].entries)
            if (e.checked == true) e.label,
        ],
        ['Dark'],
      );
      // A line of the menu does what its name says.
      subs[0].entries.first.run!();
      expect(model.themeId, ThemeSpec.all.first.id);
      model.dispose();
    });

    test('Undo and Redo say what they take back', () {
      final model = LocalShellModel();
      final edit = shellMenus(
        model,
        ShellCommands(undo: () {}, undoName: 'Add Task'),
      )[1];
      expect(lines(edit), ['Undo Add Task ⌘Z', 'Redo ⇧⌘Z']);
      // Nothing to do again: the line is grey.
      expect(edit.entries.last.run, isNull);
      model.dispose();
    });

    test('a key is Command on a Mac and Ctrl on the others', () {
      const entry = ShellEntry(
        'New Note',
        null,
        key: LogicalKeyboardKey.keyN,
        alt: true,
      );
      final mac = entry.activator(apple: true)!;
      expect(
        (mac.meta, mac.control, mac.alt, mac.shift),
        (true, false, true, false),
      );
      final other = entry.activator(apple: false)!;
      expect((other.meta, other.control, other.alt), (false, true, true));
      expect(const ShellEntry('Motion', null).activator(), isNull);
    });
  });

  group('the keys', () {
    testWidgets('Ctrl and N puts the cursor in the field of a new task', (
      tester,
    ) async {
      final store = plannerStore()..screen = Screen.notes;
      await pumpApp(tester, store);
      final asked = store.quickAddRequest;
      await press(tester, [ctrl], LogicalKeyboardKey.keyN);
      expect(store.quickAddRequest, asked + 1);
      // The task list is on the Today screen.
      expect(store.screen, Screen.today);
    });

    testWidgets('Ctrl, Alt and N makes a note and opens it', (tester) async {
      final store = plannerStore();
      await pumpApp(tester, store);
      final before = store.notes().length;
      await press(tester, [ctrl, alt], LogicalKeyboardKey.keyN);
      expect(store.notes().length, before + 1);
      expect(store.screen, Screen.notes);
      // No task field was asked for: one key runs one line.
      expect(store.quickAddRequest, store.quickAddHandled);
    });

    testWidgets('Ctrl, Shift and N makes an event and opens its card', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpApp(tester, store);
      expect(store.editingEvent, isNull);
      await press(tester, [ctrl, shift], LogicalKeyboardKey.keyN);
      expect(store.editingEvent, isNotNull);
      expect(find.byType(EventEditor), findsOneWidget);
      expect(
        store
            .blocks(DayRange.single(wednesday))
            .where((b) => b.title == 'New event'),
        hasLength(1),
      );
      await endToast(tester);
    });

    testWidgets('Ctrl and comma opens Settings, one window only', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpApp(tester, store);
      await press(tester, [ctrl], LogicalKeyboardKey.comma);
      expect(settingsView, findsOneWidget);
      await press(tester, [ctrl], LogicalKeyboardKey.comma);
      expect(settingsView, findsOneWidget);
    });

    testWidgets('Ctrl with = and with - changes the height of an hour', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpApp(tester, store);
      final start = store.plannerHourHeight;
      await press(tester, [ctrl], LogicalKeyboardKey.equal);
      expect(store.plannerHourHeight, closeTo(start * zoomStep, 0.001));
      await press(tester, [ctrl], LogicalKeyboardKey.minus);
      expect(store.plannerHourHeight, closeTo(start, 0.001));
    });

    testWidgets('the zoom keys work on a screen that has no time grid', (
      tester,
    ) async {
      final store = plannerStore();
      store.screen = Screen.notes;
      await pumpApp(tester, store);
      final start = store.plannerHourHeight;
      await press(tester, [ctrl], LogicalKeyboardKey.equal);
      expect(store.plannerHourHeight, closeTo(start * zoomStep, 0.001));
      store.screen = Screen.garden;
      await tester.pumpAndSettle();
      await press(tester, [ctrl], LogicalKeyboardKey.minus);
      expect(store.plannerHourHeight, closeTo(start, 0.001));
      expect(tester.takeException(), isNull);
    });

    // The grid has the same keys for itself. It takes the key first, so the
    // line of the menu does not run too.
    testWidgets('with the keyboard in the grid one press is one step', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpApp(tester, store);
      await mouseTap(tester, pointAt(tester, wednesday, 14 * 60));
      await endTapWindow(tester);
      final start = store.plannerHourHeight;
      for (final key in [
        LogicalKeyboardKey.equal,
        LogicalKeyboardKey.numpadAdd,
      ]) {
        await press(tester, [ctrl], key);
        expect(
          store.plannerHourHeight,
          closeTo(start * zoomStep, 0.001),
          reason: key.debugName,
        );
        await press(tester, [ctrl], LogicalKeyboardKey.minus);
        expect(
          store.plannerHourHeight,
          closeTo(start, 0.001),
          reason: key.debugName,
        );
      }
    });

    // The keys the grid takes: + is = with Shift on many keyboards, and the
    // number pad has its own + and -.
    testWidgets('the + and the - of the number pad, and the keys with '
        'Shift, zoom from each screen', (tester) async {
      final store = plannerStore();
      store.screen = Screen.notes;
      await pumpApp(tester, store);
      final start = store.plannerHourHeight;
      final zoomIn = [
        ([ctrl], LogicalKeyboardKey.numpadAdd),
        ([ctrl], LogicalKeyboardKey.add),
        ([ctrl, shift], LogicalKeyboardKey.add),
        ([ctrl, shift], LogicalKeyboardKey.equal),
      ];
      final zoomOut = [
        ([ctrl], LogicalKeyboardKey.numpadSubtract),
        ([ctrl, shift], LogicalKeyboardKey.minus),
      ];
      for (final (i, (held, key)) in zoomIn.indexed) {
        final (outHeld, outKey) = zoomOut[i % zoomOut.length];
        final what = '${held.length} held, ${key.debugName}';
        await press(tester, held, key);
        expect(
          store.plannerHourHeight,
          closeTo(start * zoomStep, 0.001),
          reason: what,
        );
        await press(tester, outHeld, outKey);
        expect(store.plannerHourHeight, closeTo(start, 0.001), reason: what);
      }
    });

    testWidgets('a zoom key with no Ctrl, or with Alt, does nothing', (
      tester,
    ) async {
      final store = plannerStore();
      store.screen = Screen.notes;
      await pumpApp(tester, store);
      final start = store.plannerHourHeight;
      await press(tester, [], LogicalKeyboardKey.numpadAdd);
      await press(tester, [shift], LogicalKeyboardKey.equal);
      await press(tester, [ctrl, alt], LogicalKeyboardKey.numpadAdd);
      await press(tester, [ctrl, alt], LogicalKeyboardKey.numpadSubtract);
      await press(tester, [command], LogicalKeyboardKey.numpadAdd);
      expect(store.plannerHourHeight, start);
    });

    testWidgets('a zoom key that is held down zooms again and again', (
      tester,
    ) async {
      final store = plannerStore();
      store.screen = Screen.notes;
      await pumpApp(tester, store);
      final start = store.plannerHourHeight;
      await tester.sendKeyDownEvent(ctrl);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.numpadAdd);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.numpadAdd);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.numpadAdd);
      await tester.sendKeyUpEvent(ctrl);
      await tester.pumpAndSettle();
      expect(
        store.plannerHourHeight,
        closeTo(start * zoomStep * zoomStep, 0.001),
      );
    });

    testWidgets('on a Mac the keys of the number pad zoom with Command', (
      tester,
    ) async {
      await onMac(() async {
        final store = plannerStore();
        store.screen = Screen.notes;
        await pumpApp(tester, store);
        final start = store.plannerHourHeight;
        await press(tester, [ctrl], LogicalKeyboardKey.numpadAdd);
        expect(store.plannerHourHeight, start);
        await press(tester, [command], LogicalKeyboardKey.numpadAdd);
        expect(store.plannerHourHeight, closeTo(start * zoomStep, 0.001));
        await press(tester, [command, shift], LogicalKeyboardKey.minus);
        expect(store.plannerHourHeight, closeTo(start, 0.001));
        await tester.pumpWidget(const SizedBox());
      });
    });

    testWidgets(
      'Ctrl and Z takes a step back, with Shift or Y it comes again',
      (tester) async {
        final store = plannerStore();
        await pumpApp(tester, store);
        int events() => store.blocks(DayRange.single(wednesday)).length;
        store.createFromDraft(
          title: 'Lunch',
          day: wednesday,
          start: 11 * 60,
          end: 12 * 60,
          asEvent: true,
        );
        await tester.pumpAndSettle();
        expect(events(), 1);
        await press(tester, [ctrl], LogicalKeyboardKey.keyZ);
        expect(events(), 0);
        await press(tester, [ctrl, shift], LogicalKeyboardKey.keyZ);
        expect(events(), 1);
        await press(tester, [ctrl], LogicalKeyboardKey.keyZ);
        expect(events(), 0);
        // Redo the Windows way.
        await press(tester, [ctrl], LogicalKeyboardKey.keyY);
        expect(events(), 1);
        await endToast(tester);
      },
    );

    testWidgets('on a Mac the keys are with Command, not with Ctrl', (
      tester,
    ) async {
      await onMac(() async {
        final store = plannerStore();
        await pumpApp(tester, store);
        final before = store.notes().length;
        await press(tester, [ctrl, alt], LogicalKeyboardKey.keyN);
        expect(store.notes().length, before);
        await press(tester, [command, alt], LogicalKeyboardKey.keyN);
        expect(store.notes().length, before + 1);
        await press(tester, [command], LogicalKeyboardKey.comma);
        expect(settingsView, findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });
    });

    testWidgets('while Settings is open the keys of the window do nothing', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpApp(tester, store);
      await press(tester, [ctrl], LogicalKeyboardKey.comma);
      expect(settingsView, findsOneWidget);
      final notes = store.notes().length;
      await press(tester, [ctrl], LogicalKeyboardKey.digit5);
      await press(tester, [ctrl, alt], LogicalKeyboardKey.keyN);
      await press(tester, [ctrl], LogicalKeyboardKey.keyK);
      expect(store.screen, Screen.planner);
      expect(store.notes().length, notes);
      expect(store.paletteOpen, isFalse);
      expect(settingsView, findsOneWidget);
    });

    // As in the Mac app: its Edit menu has the Undo of the store in the
    // place of the Undo of a text field (docs/assumptions.md).
    testWidgets('in a text field the key takes back the step of the store', (
      tester,
    ) async {
      final store = plannerStore();
      store.createFromDraft(
        title: 'Lunch',
        day: wednesday,
        start: 11 * 60,
        end: 12 * 60,
        asEvent: true,
      );
      await pumpApp(tester, store);
      int events() => store.blocks(DayRange.single(wednesday)).length;
      String typed() => tester
          .widget<EditableText>(find.byType(EditableText))
          .controller
          .text;
      // The field of the command palette has the cursor.
      await press(tester, [ctrl], LogicalKeyboardKey.keyK);
      await tester.enterText(keyed('palette-field'), 'fern');
      // A field keeps a step of its text after half a second.
      await tester.pump(const Duration(milliseconds: 600));
      expect((typed(), events()), ('fern', 1));
      await press(tester, [ctrl], LogicalKeyboardKey.keyZ);
      expect((typed(), events()), ('fern', 0));
      await endToast(tester);
    });
  });

  group('Command-K and Command-Z in a text box', () {
    /// The text of the open note.
    final noteBox = find.descendant(
      of: keyed('note-text'),
      matching: find.byType(EditableText),
    );
    final linkDialog = keyed('link-dialog');

    /// Makes a note and puts the cursor in its text.
    Future<void> intoNewNote(
      WidgetTester tester,
      LogicalKeyboardKey modifier,
    ) async {
      await press(tester, [modifier, alt], LogicalKeyboardKey.keyN);
      await tester.tap(noteBox);
      await tester.pumpAndSettle();
    }

    Future<void> cancelLink(WidgetTester tester) async {
      await tester.tap(
        find.descendant(of: linkDialog, matching: find.text('Cancel')),
      );
      await tester.pumpAndSettle();
    }

    for (final mac in [false, true]) {
      final system = mac ? 'on a Mac' : 'off a Mac';
      testWidgets('$system the key opens the palette out of a text box, and '
          'the link window in one', (tester) async {
        Future<void> body() async {
          final key = mac ? command : ctrl;
          final store = plannerStore();
          await pumpApp(tester, store);
          await press(tester, [key], LogicalKeyboardKey.keyK);
          expect(store.paletteOpen, isTrue);
          expect(linkDialog, findsNothing);
          store.paletteOpen = false;
          await tester.pumpAndSettle();

          await intoNewNote(tester, key);
          await press(tester, [key], LogicalKeyboardKey.keyK);
          expect(linkDialog, findsOneWidget);
          expect(store.paletteOpen, isFalse);
          await cancelLink(tester);
          expect(linkDialog, findsNothing);
          expect(store.paletteOpen, isFalse);
          await tester.pumpWidget(const SizedBox());
        }

        mac ? await onMac(body) : await body();
      });
    }

    // The menu bar of a Mac gets a key only when Flutter leaves it (the
    // engine sends Command keys to Flutter first), so the box comes first.
    testWidgets('on a Mac Command-Z in a text box takes back its typing, '
        'not the step of the store', (tester) async {
      await onMac(() async {
        final store = plannerStore();
        await pumpApp(tester, store);
        await intoNewNote(tester, command);
        final notes = store.notes().length;
        final undoName = store.undoName;
        await tester.enterText(noteBox, 'fern');
        await tester.pump();
        String typed() => tester.widget<EditableText>(noteBox).controller.text;
        expect(typed(), 'fern');
        await press(tester, [command], LogicalKeyboardKey.keyZ);
        expect(typed(), '');
        expect(store.notes().length, notes);
        expect(store.undoName, undoName);
        await tester.pumpWidget(const SizedBox());
      });
    });
  });

  group('the menu bar', () {
    testWidgets('a Mac gets the menus of the Mac app', (tester) async {
      await onMac(() async {
        final store = plannerStore();
        await pumpApp(tester, store);
        final bar = menuBar(tester);
        expect(bar.keys.toList(), [
          'Grove',
          'File',
          'Edit',
          'View',
          'Go',
          'Window',
        ]);
        expect(
          [for (final item in leaves(bar['File']!)) item.label],
          ['New Task', 'New Note', 'New Event'],
        );
        final newNote = line(bar['File']!, 'New Note');
        expect(
          newNote.shortcut,
          isA<SingleActivator>()
              .having((a) => a.trigger, 'key', LogicalKeyboardKey.keyN)
              .having((a) => a.meta, 'Command', isTrue)
              .having((a) => a.alt, 'Option', isTrue)
              .having((a) => a.control, 'Ctrl', isFalse),
        );
        expect(
          [
            for (final item in leaves(bar['View']!))
              if (item is! PlatformProvidedMenuItem) item.label,
          ],
          [
            'Today',
            'Planner',
            'Tasks',
            'Notes Panel',
            'Goals Panel',
            'Deadlines Panel',
            'Calendar',
            'Notes',
            'Garden',
            'Persona',
            'Zoom In',
            'Zoom Out',
            for (final spec in ThemeSpec.all)
              spec.id == store.themeId ? '✓ ${spec.name}' : spec.name,
            '✓ System',
            'Light',
            'Dark',
            'Motion',
          ],
        );
        expect(
          [for (final item in leaves(bar['Go']!)) item.label],
          ['Command Palette'],
        );
        // "Settings…" is in the menu of the app, with Command and comma.
        final settings = line(bar['Grove']!, 'Settings…');
        expect(
          (settings.shortcut! as SingleActivator).trigger,
          LogicalKeyboardKey.comma,
        );
        // The lines of the system: About, Hide, Quit, and the Window menu.
        expect(
          [
            for (final item in leaves(bar['Grove']!))
              if (item is PlatformProvidedMenuItem) item.type,
          ],
          containsAll([
            PlatformProvidedMenuItemType.about,
            PlatformProvidedMenuItemType.hide,
            PlatformProvidedMenuItemType.quit,
          ]),
        );
        await tester.pumpWidget(const SizedBox());
      });
    });

    testWidgets('a line that is picked does its work', (tester) async {
      await onMac(() async {
        final store = plannerStore();
        await pumpApp(tester, store);
        final notes = store.notes().length;
        line(menuBar(tester)['File']!, 'New Note').onSelected!();
        await tester.pumpAndSettle();
        expect(store.notes().length, notes + 1);
        line(menuBar(tester)['View']!, 'Garden').onSelected!();
        await tester.pumpAndSettle();
        expect(store.screen, Screen.garden);
        line(menuBar(tester)['Go']!, 'Command Palette').onSelected!();
        await tester.pumpAndSettle();
        expect(store.paletteOpen, isTrue);
        line(menuBar(tester)['Go']!, 'Command Palette').onSelected!();
        await tester.pumpAndSettle();
        expect(store.paletteOpen, isFalse);
        line(menuBar(tester)['Grove']!, 'Settings…').onSelected!();
        await tester.pumpAndSettle();
        expect(settingsView, findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });
    });

    testWidgets('Undo is grey with nothing to undo, then names the step', (
      tester,
    ) async {
      await onMac(() async {
        final store = plannerStore();
        await pumpApp(tester, store);
        expect(line(menuBar(tester)['Edit']!, 'Undo').onSelected, isNull);
        expect(line(menuBar(tester)['Edit']!, 'Redo').onSelected, isNull);
        store.createFromDraft(
          title: 'Lunch',
          day: wednesday,
          start: 11 * 60,
          end: 12 * 60,
          asEvent: true,
        );
        await tester.pumpAndSettle();
        final undo = line(menuBar(tester)['Edit']!, 'Undo ${store.undoName}');
        undo.onSelected!();
        await tester.pumpAndSettle();
        expect(store.blocks(DayRange.single(wednesday)), isEmpty);
        expect(
          line(menuBar(tester)['Edit']!, 'Redo ${store.redoName}').onSelected,
          isNotNull,
        );
        await endToast(tester);
        await tester.pumpWidget(const SizedBox());
      });
    });

    testWidgets('a line of the theme changes the mark', (tester) async {
      await onMac(() async {
        final store = plannerStore();
        await pumpApp(tester, store);
        final other = ThemeSpec.all.firstWhere((s) => s.id != store.themeId);
        line(menuBar(tester)['View']!, other.name).onSelected!();
        await tester.pumpAndSettle();
        expect(store.themeId, other.id);
        expect(
          leaves(menuBar(tester)['View']!).map((item) => item.label),
          contains('✓ ${other.name}'),
        );
        await tester.pumpWidget(const SizedBox());
      });
    });

    testWidgets('while Settings is open a line of the window does nothing', (
      tester,
    ) async {
      await onMac(() async {
        final store = plannerStore();
        await pumpApp(tester, store);
        line(menuBar(tester)['Grove']!, 'Settings…').onSelected!();
        await tester.pumpAndSettle();
        line(menuBar(tester)['View']!, 'Garden').onSelected!();
        await tester.pumpAndSettle();
        expect(store.screen, Screen.planner);
        await tester.pumpWidget(const SizedBox());
      });
    });

    testWidgets('the other systems have no menu bar of the system', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpApp(tester, store);
      expect(find.byType(PlatformMenuBar), findsNothing);
    });
  });
}
