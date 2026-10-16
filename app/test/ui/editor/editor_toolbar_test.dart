// The row of tools above a rich text box: which tools show at each width,
// the "…" menu, the tools that light up, and the tools with a menu.
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/parsing/markdown_spans.dart';
import 'package:grove/state/state.dart' hide MotionRules;
import 'package:grove/ui/editor/markdown_controller.dart';
import 'package:grove/ui/editor/rich_text_field.dart';

import '../tasks/tasks_support.dart' show pumpPane;

/// A rich text box `width` wide, with the keyboard, and what it wrote.
class Box {
  Box(this.controller, this.focus);

  final MarkdownController controller;
  final FocusNode focus;
  String text = '';
  int links = 0;
}

Future<Box> pumpBox(
  WidgetTester tester,
  String text, {
  double width = 780,
  bool link = false,
  bool image = false,
}) async {
  final controller = MarkdownController(text: text);
  final focus = FocusNode();
  addTearDown(controller.dispose);
  addTearDown(focus.dispose);
  final box = Box(controller, focus)..text = text;
  controller.addListener(() => box.text = controller.text);
  await pumpPane(
    tester,
    Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: link
            // The row alone, with a Link tool that only counts its taps
            // (the box itself opens the link window).
            ? TextFieldTapRegion(
                child: Column(
                  children: [
                    EditorToolbar(
                      controller: controller,
                      before: focus.requestFocus,
                      onLink: () => box.links++,
                      onImage: image ? () {} : null,
                    ),
                    TextField(
                      controller: controller,
                      focusNode: focus,
                      maxLines: null,
                    ),
                  ],
                ),
              )
            : RichTextField(
                text: text,
                controller: controller,
                focusNode: focus,
                services: EditorServices(showMarks: () => false),
                pickImages: image ? () async => const [] : null,
                onChanged: (value) => box.text = value,
              ),
      ),
    ),
    size: const Size(900, 600),
  );
  focus.requestFocus();
  await tester.pump();
  return box;
}

Future<void> select(WidgetTester tester, Box box, int from, [int? to]) async {
  box.controller.selection = TextSelection(
    baseOffset: from,
    extentOffset: to ?? from,
  );
  await tester.pump();
}

Finder tool(String label) => find.bySemanticsLabel(label);

/// A tool of the row: there, or not there.
bool shows(String label) => tool(label).evaluate().isNotEmpty;

/// Taps a row of an open menu.
Future<void> pick(WidgetTester tester, String row) async {
  await tester.tap(find.text(row).last);
  await tester.pumpAndSettle();
}

Future<void> openMore(WidgetTester tester) async {
  await tester.tap(tool('More'));
  await tester.pumpAndSettle();
}

/// The names of the tools in the row, left to right.
List<String> rowOrder(WidgetTester tester, List<String> labels) {
  final shown = [
    for (final l in labels)
      if (shows(l)) l,
  ];
  shown.sort(
    (a, b) =>
        tester.getCenter(tool(a)).dx.compareTo(tester.getCenter(tool(b)).dx),
  );
  return shown;
}

const wideOrder = [
  'Undo',
  'Redo',
  'Text size',
  'Bold',
  'Italic',
  'Underline',
  'Strike',
  'Highlight',
  'Code',
  'Bullet list',
  'Numbered list',
  'Checklist',
  'Quote',
  'Indent in',
  'Indent out',
  'Link',
  'Mention',
  'Add an image',
  'Divider',
  'Clear format',
];

void main() {
  setUp(() => EditorToolbar.lastHighlight = HighlightColor.yellow);

  group('the tools at each width', () {
    testWidgets('780: every tool in its group, and no "…"', (tester) async {
      await pumpBox(tester, 'word', link: true, image: true);
      expect(rowOrder(tester, wideOrder), wideOrder);
      expect(shows('More'), isFalse);
      expect(shows('Highlight colour'), isTrue);
    });

    testWidgets('780 with no picker: no image tool, and Link is there', (
      tester,
    ) async {
      await pumpBox(tester, 'word');
      // Every rich text box can make a link.
      expect(shows('Link'), isTrue);
      expect(shows('Add an image'), isFalse);
      expect(shows('Clear format'), isTrue);
      expect(shows('More'), isFalse);
    });

    testWidgets('340: the short row, and "…" holds the rest', (tester) async {
      final box = await pumpBox(tester, 'word', width: 340, link: true);
      expect(rowOrder(tester, [...wideOrder, 'More']), [
        'Undo',
        'Text size',
        'Bold',
        'Italic',
        'Underline',
        'Highlight',
        'Bullet list',
        'Checklist',
        'Link',
        'More',
      ]);
      expect(tester.takeException(), isNull);
      await select(tester, box, 0, 4);
      await openMore(tester);
      for (final row in [
        'Redo',
        'Strike',
        'Code',
        'Numbered list',
        'Quote',
        'Indent in',
        'Indent out',
        'Mention',
        'Divider',
        'Clear format',
      ]) {
        expect(find.text(row), findsOneWidget, reason: row);
      }
      expect(find.text('Bold'), findsNothing);
      await pick(tester, 'Code');
      expect(box.text, '`word`');
      expect(box.focus.hasFocus, isTrue);
    });

    testWidgets('300: the link goes into "…" too', (tester) async {
      final box = await pumpBox(tester, 'word', width: 300, link: true);
      expect(shows('Checklist'), isTrue);
      expect(shows('Link'), isFalse);
      expect(shows('More'), isTrue);
      expect(tester.takeException(), isNull);
      await openMore(tester);
      await pick(tester, 'Link');
      expect(box.links, 1);
    });

    testWidgets('a row in "…" shows a tick when its format is on', (
      tester,
    ) async {
      final box = await pumpBox(tester, '~~gone~~', width: 300);
      await select(tester, box, 4);
      await openMore(tester);
      final row = find.ancestor(
        of: find.text('Strike'),
        matching: find.byType(Row),
      );
      expect(
        find.descendant(of: row.first, matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
      final code = find.ancestor(
        of: find.text('Code'),
        matching: find.byType(Row),
      );
      expect(
        find.descendant(of: code.first, matching: find.byIcon(Icons.check)),
        findsNothing,
      );
    });
  });

  group('tools light up', () {
    testWidgets('Bold is on in bold words, and off outside', (tester) async {
      final box = await pumpBox(tester, 'a **bold** b');
      await select(tester, box, 6);
      expect(tester.getSemantics(tool('Bold')), isSemantics(isToggled: true));
      expect(
        tester.getSemantics(tool('Italic')),
        isSemantics(isToggled: false),
      );
      await select(tester, box, 0);
      expect(tester.getSemantics(tool('Bold')), isSemantics(isToggled: false));
    });

    testWidgets('Text size shows the size of the line', (tester) async {
      final box = await pumpBox(tester, '## Title\nplain');
      await select(tester, box, 5);
      expect(
        tester.getSemantics(tool('Text size')),
        isSemantics(value: 'Medium heading'),
      );
      await select(tester, box, 12);
      expect(
        tester.getSemantics(tool('Text size')),
        isSemantics(value: 'Normal text'),
      );
    });

    testWidgets('Highlight is on, and its menu ticks the colour', (
      tester,
    ) async {
      final box = await pumpBox(tester, '=={green}leaf==');
      await select(tester, box, 11);
      expect(
        tester.getSemantics(tool('Highlight')),
        isSemantics(isToggled: true),
      );
      await tester.tap(tool('Highlight colour'));
      await tester.pumpAndSettle();
      final green = find.ancestor(
        of: find.text('Green'),
        matching: find.byType(Row),
      );
      expect(
        find.descendant(of: green.first, matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
    });
  });

  group('tools with a menu', () {
    testWidgets('Text size sets the size of the line', (tester) async {
      final box = await pumpBox(tester, 'word');
      await select(tester, box, 2);
      await tester.tap(tool('Text size'));
      await tester.pumpAndSettle();
      for (final row in [
        'Normal text',
        'Big heading',
        'Medium heading',
        'Small heading',
      ]) {
        expect(find.text(row), findsOneWidget, reason: row);
      }
      await pick(tester, 'Big heading');
      expect(box.text, '# word');
      await tester.tap(tool('Text size'));
      await tester.pumpAndSettle();
      await pick(tester, 'Small heading');
      expect(box.text, '### word');
      await tester.tap(tool('Text size'));
      await tester.pumpAndSettle();
      await pick(tester, 'Normal text');
      expect(box.text, 'word');
    });

    testWidgets('Highlight uses the last colour; the arrow picks another', (
      tester,
    ) async {
      final box = await pumpBox(tester, 'one two');
      await select(tester, box, 0, 3);
      await tester.tap(tool('Highlight'));
      await tester.pump();
      expect(box.text, '==one== two');

      await select(tester, box, 8, 11);
      await tester.tap(tool('Highlight colour'));
      await tester.pumpAndSettle();
      for (final row in ['Yellow', 'Green', 'Blue', 'Pink', 'No highlight']) {
        expect(find.text(row), findsOneWidget, reason: row);
      }
      await pick(tester, 'Blue');
      expect(box.text, '==one== =={blue}two==');
      expect(EditorToolbar.lastHighlight, HighlightColor.blue);

      // The main part now gives blue.
      box.controller.load('three');
      await select(tester, box, 0, 5);
      await tester.tap(tool('Highlight'));
      await tester.pump();
      expect(box.controller.text, '=={blue}three==');

      await select(tester, box, 10);
      await tester.tap(tool('Highlight colour'));
      await tester.pumpAndSettle();
      await pick(tester, 'No highlight');
      expect(box.controller.text, 'three');
    });

    testWidgets('the selection stays while a menu is open', (tester) async {
      final box = await pumpBox(tester, 'one two');
      await select(tester, box, 4, 7);
      await tester.tap(tool('Text size'));
      await tester.pumpAndSettle();
      expect(
        box.controller.selection,
        const TextSelection(baseOffset: 4, extentOffset: 7),
      );
      await pick(tester, 'Big heading');
      expect(box.text, '# one two');
      expect(box.focus.hasFocus, isTrue);
    });

    testWidgets(
      'a click in a menu does not take the keyboard from the text',
      variant: TargetPlatformVariant.desktop(),
      (tester) async {
        final box = await pumpBox(tester, 'one two');
        await select(tester, box, 4, 7);
        final heard = <bool>[];
        void listen() => heard.add(box.focus.hasFocus);
        box.focus.addListener(listen);
        await tester.tap(tool('Text size'), kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        await tester.tap(
          find.text('Big heading').last,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        box.focus.removeListener(listen);
        expect(heard, isEmpty);
        expect(box.text, '# one two');
      },
    );
  });

  group('the other tools', () {
    testWidgets('Undo and Redo are grey with nothing to take back', (
      tester,
    ) async {
      final box = await pumpBox(tester, 'word');
      expect(tester.getSemantics(tool('Undo')), isSemantics(isEnabled: false));
      expect(tester.getSemantics(tool('Redo')), isSemantics(isEnabled: false));
      await select(tester, box, 0, 4);
      await tester.tap(tool('Bold'));
      await tester.pump();
      expect(box.text, '**word**');
      expect(tester.getSemantics(tool('Undo')), isSemantics(isEnabled: true));
      await tester.tap(tool('Undo'));
      await tester.pump();
      expect(box.text, 'word');
      expect(tester.getSemantics(tool('Redo')), isSemantics(isEnabled: true));
      await tester.tap(tool('Redo'));
      await tester.pump();
      expect(box.text, '**word**');
    });

    testWidgets('Divider puts a line under the text', (tester) async {
      final box = await pumpBox(tester, 'above');
      await select(tester, box, 5);
      await tester.tap(tool('Divider'));
      await tester.pump();
      expect(box.text, startsWith('above\n---'));
    });

    testWidgets('Clear format takes every format off', (tester) async {
      final box = await pumpBox(tester, '**a** ~~b~~ <u>c</u>');
      await select(tester, box, 0, box.controller.text.length);
      await tester.tap(tool('Clear format'));
      await tester.pump();
      expect(box.text, 'a b c');
    });

    testWidgets('Indent in and out move a list item', (tester) async {
      final box = await pumpBox(tester, '- one\n- two');
      await select(tester, box, 9);
      await tester.tap(tool('Indent in'));
      await tester.pump();
      expect(box.text, '- one\n  - two');
      await tester.tap(tool('Indent out'));
      await tester.pump();
      expect(box.text, '- one\n- two');
    });

    testWidgets('the tips use plain words and name the key', (tester) async {
      await pumpBox(tester, '');
      final mod =
          defaultTargetPlatform == TargetPlatform.macOS ||
              defaultTargetPlatform == TargetPlatform.iOS
          ? '⌘'
          : 'Ctrl+';
      expect(find.byTooltip('Bold  ${mod}B'), findsOneWidget);
      expect(find.byTooltip('Mention a task, event or note'), findsOneWidget);
      expect(find.byTooltip('Underline'), findsOneWidget);
    });
  });
}
