// Port of Tests/GroveTests/EditorViewTests.swift: drives the real editor the
// way the keyboard would. The text rules themselves are tested in
// test/core/parsing.
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/link.dart';
import 'package:grove/state/state.dart' hide MotionRules;
import 'package:grove/ui/editor/editor_tools.dart';
import 'package:grove/ui/editor/markdown_controller.dart';
import 'package:grove/ui/editor/rich_text_field.dart';
import 'package:grove/ui/theme/grove_theme.dart';

import '../tasks/tasks_support.dart' show pumpPane;

const id = '11111111-2222-3333-4444-555555555555';
const gone = '99999999-2222-3333-4444-555555555555';

/// What the editor under test wrote, and the handles to drive it.
class Rig {
  Rig(this.controller, this.focus);

  final MarkdownController controller;
  final FocusNode focus;
  String text = '';
  final told = <String>[];
  final opened = <String?>[];

  /// The web addresses the editor sent to the browser.
  final links = <Uri>[];
}

EditorServices oneTask(Rig rig) => EditorServices(
  suggest: (_) => const [
    MentionSuggestion(
      ref: ItemRef(ItemType.task, 'T1'),
      title: 'Buy milk',
      kind: 'Task',
    ),
  ],
  title: (id) => id == 'T1' ? 'Buy milk' : null,
  isLive: (id) => id != gone,
  notify: rig.told.add,
  open: (id, title) => rig.opened.add(id),
);

Future<Rig> makeRig(
  WidgetTester tester,
  String text, {
  EditorServices Function(Rig rig)? services,
  ThemeId themeId = ThemeId.grove,
  Size size = const Size(500, 400),
  Alignment alignment = Alignment.topLeft,
  ImagePicker? pickImages,
  LinkOpener? openLink,
  // Wraps the editor, as the app does with `EditorTools`.
  Widget Function(Widget child)? around,
}) async {
  final controller = MarkdownController(text: text);
  final focus = FocusNode();
  addTearDown(controller.dispose);
  addTearDown(focus.dispose);
  final rig = Rig(controller, focus)..text = text;
  var shown = text;
  await pumpPane(
    tester,
    StatefulBuilder(
      builder: (context, setState) => Align(
        alignment: alignment,
        child: SizedBox(
          width: 400,
          // As high as its text, as in a page that scrolls.
          child: SingleChildScrollView(
            child: (around ?? (child) => child)(
              RichTextField(
                text: shown,
                controller: controller,
                focusNode: focus,
                services: (services ?? oneTask)(rig),
                placeholder: 'Write here',
                pickImages: pickImages,
                openLink: openLink,
                onChanged: (value) => setState(() {
                  shown = value;
                  rig.text = value;
                }),
              ),
            ),
          ),
        ),
      ),
    ),
    size: size,
    themeId: themeId,
  );
  focus.requestFocus();
  await tester.pump();
  return rig;
}

/// What the keyboard sends: the new text with the caret.
Future<void> send(WidgetTester tester, String text, int caret) async {
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret),
    ),
  );
  await tester.pump();
}

/// Types `typed` at the caret, as one change.
Future<void> type(WidgetTester tester, Rig rig, String typed) async {
  final value = rig.controller.value;
  final s = value.selection;
  await send(
    tester,
    value.text.replaceRange(s.start, s.end, typed),
    s.start + typed.length,
  );
}

Future<void> caret(WidgetTester tester, Rig rig, int offset, [int? end]) async {
  rig.controller.selection = TextSelection(
    baseOffset: offset,
    extentOffset: end ?? offset,
  );
  await tester.pump();
}

/// The key that deletes the letter in front of the caret.
Future<void> backspace(WidgetTester tester, Rig rig) async {
  final value = rig.controller.value;
  final at = value.selection.start;
  await send(tester, value.text.replaceRange(at - 1, at, ''), at - 1);
}

/// What the keyboard of a phone sends while a word is not done yet.
Future<void> compose(WidgetTester tester, String text, int from, int to) async {
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: to),
      composing: TextRange(start: from, end: to),
    ),
  );
  await tester.pump();
}

/// Command-Z on a Mac, Ctrl-Z elsewhere; with Shift for redo.
Future<void> undoKey(WidgetTester tester, {bool redo = false}) async {
  final apple =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;
  final command = apple
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(command);
  if (redo) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
  if (redo) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(command);
  await tester.pump();
}

/// A click of a mouse, with a frame between the press and the release.
Future<void> click(WidgetTester tester, Finder target) async {
  final gesture = await tester.startGesture(
    tester.getCenter(target),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 80));
  await gesture.up();
  await tester.pump();
}

/// Uses a tool of the row above the text, or of its "…" menu when the row
/// has no room for it.
Future<void> useTool(WidgetTester tester, String label) async {
  final button = find.bySemanticsLabel(label);
  if (button.evaluate().isNotEmpty) {
    await tester.tap(button);
    await tester.pump();
    return;
  }
  await tester.tap(find.bySemanticsLabel('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// The bubble under a link that was clicked.
final linkBubble = find.byKey(const ValueKey('link-bubble'));

/// A button of the bubble.
Finder bubbleButton(String label) =>
    find.descendant(of: linkBubble, matching: find.text(label));

/// The window that makes or changes a link.
final linkDialog = find.byKey(const ValueKey('link-dialog'));

/// A field of the link window: `link-words` or `link-address`.
Finder linkField(String key) => find.byKey(ValueKey(key));

String fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(linkField(key)).controller!.text;

/// Save of the link window. One frame first, so that Save is on after
/// [WidgetTester.enterText].
Future<void> tapSave(WidgetTester tester) async {
  await tester.pump();
  await tester.tap(
    find.descendant(of: linkDialog, matching: find.text('Save')),
  );
  await tester.pumpAndSettle();
}

/// Command-K on a Mac, Ctrl-K elsewhere.
Future<void> linkKey(WidgetTester tester) async {
  final apple =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;
  final command = apple
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(command);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(command);
  await tester.pumpAndSettle();
}

/// Eight tasks for the `[[` list: a list 248 points high.
EditorServices eightTasks(Rig rig) => EditorServices(
  suggest: (_) => [
    for (var i = 0; i < 8; i++)
      MentionSuggestion(
        ref: ItemRef(ItemType.task, 'T$i'),
        title: 'Buy milk $i',
        kind: 'Task',
      ),
  ],
  title: (id) => 'Buy milk',
);

/// A field with the "Show marks" switch off: the marks are hidden.
EditorServices hidingMarks(Rig rig) => EditorServices(showMarks: () => false);

/// A field with the "Show marks" switch on: the marks show dim.
EditorServices showingMarks(Rig rig) => EditorServices(showMarks: () => true);

/// The caret the field draws at `offset`, in the field.
Rect caretRect(WidgetTester tester, int offset) {
  final state = tester.state<EditableTextState>(find.byType(EditableText));
  return state.renderEditable.getLocalRectForCaret(
    TextPosition(offset: offset),
  );
}

/// The pieces of text the editor draws, with their styles.
List<TextSpan> pieces(WidgetTester tester, Rig rig) {
  final span = rig.controller.buildTextSpan(
    context: tester.element(find.byType(EditableText)),
    withComposing: false,
  );
  return [
    for (final child in span.children ?? const <InlineSpan>[])
      if (child is TextSpan) child,
  ];
}

TextSpan pieceWith(WidgetTester tester, Rig rig, String text) =>
    pieces(tester, rig).firstWhere((p) => p.text == text);

void main() {
  group('typing', () {
    testWidgets('typing updates the text', (tester) async {
      final rig = await makeRig(tester, '');
      await type(tester, rig, 'hello');
      expect(rig.text, 'hello');
    });

    testWidgets('Return continues a bullet list', (tester) async {
      final rig = await makeRig(tester, '- one');
      await caret(tester, rig, 5);
      await type(tester, rig, '\n');
      expect(rig.text, '- one\n- ');
      expect(rig.controller.selection.baseOffset, 8);
    });

    testWidgets('Return on an empty bullet ends the list', (tester) async {
      final rig = await makeRig(tester, '- one\n- ');
      await caret(tester, rig, 8);
      await type(tester, rig, '\n');
      expect(rig.text, '- one\n');
    });

    testWidgets('Return in plain text makes a line break', (tester) async {
      final rig = await makeRig(tester, 'one');
      await caret(tester, rig, 3);
      await type(tester, rig, '\n');
      expect(rig.text, 'one\n');
    });

    testWidgets('Tab indents a list item, Shift-Tab takes it back', (
      tester,
    ) async {
      final rig = await makeRig(tester, '- one\n- two');
      await caret(tester, rig, 11);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(rig.text, '- one\n  - two');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(rig.text, '- one\n- two');
    });

    testWidgets('Tab outside a list leaves the text alone', (tester) async {
      final rig = await makeRig(tester, 'plain');
      await caret(tester, rig, 5);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(rig.text, 'plain');
    });
  });

  group('a mention is one unit', () {
    testWidgets('Backspace after a mention deletes the whole mention', (
      tester,
    ) async {
      const text = 'a [[Buy milk|$id]]';
      final rig = await makeRig(tester, text);
      await caret(tester, rig, text.length);
      await send(tester, text.substring(0, text.length - 1), text.length - 1);
      expect(rig.text, 'a ');
      expect(rig.controller.selection.baseOffset, 2);
    });

    testWidgets('a caret that enters a mention moves to the far edge', (
      tester,
    ) async {
      const text = 'a [[Buy milk|$id]] z';
      final rig = await makeRig(tester, text);
      const start = 2;
      const end = 2 + '[[Buy milk|$id]]'.length;
      // moving right from before it jumps over it
      await caret(tester, rig, start);
      await caret(tester, rig, start + 1);
      expect(
        rig.controller.selection,
        const TextSelection.collapsed(offset: end),
      );
      // moving left from after it jumps back over it
      await caret(tester, rig, end);
      await caret(tester, rig, end - 1);
      expect(
        rig.controller.selection,
        const TextSelection.collapsed(offset: start),
      );
    });

    testWidgets('typing inside a mention lands after it', (tester) async {
      const text = '[[Buy milk|$id]]';
      final rig = await makeRig(tester, text);
      await send(tester, text.replaceRange(4, 4, 'x'), 5);
      expect(rig.text, '${text}x');
    });

    testWidgets('the id and the brackets of a mention are not seen', (
      tester,
    ) async {
      final rig = await makeRig(tester, 'a [[Buy milk|$id]] z');
      final theme = GroveTheme.of(tester.element(find.byType(RichTextField)));
      final title = pieceWith(tester, rig, 'Buy milk');
      expect(title.style?.color, theme.accent);
      expect(title.style?.fontWeight, FontWeight.w500);
      for (final hidden in ['[[', '|$id]]']) {
        final piece = pieceWith(tester, rig, hidden);
        expect(piece.style?.fontSize, lessThan(0.1), reason: hidden);
        expect(piece.style?.color?.a, 0, reason: hidden);
      }
    });

    testWidgets('a mention of a thing that is gone is struck out', (
      tester,
    ) async {
      final rig = await makeRig(tester, '[[Old|$gone]]');
      final theme = GroveTheme.of(tester.element(find.byType(RichTextField)));
      final title = pieceWith(tester, rig, 'Old');
      expect(title.style?.color, theme.muted);
      expect(title.style?.decoration, TextDecoration.lineThrough);
    });

    testWidgets('a click on a mention opens it', (tester) async {
      final rig = await makeRig(tester, 'see [[Buy milk|$id]] now');
      final editable = tester.renderObject<RenderBox>(
        find.byType(EditableText),
      );
      final state = tester.state<EditableTextState>(find.byType(EditableText));
      final boxes = state.renderEditable.getBoxesForSelection(
        const TextSelection(baseOffset: 6, extentOffset: 14),
      );
      final middle = editable.localToGlobal(boxes.first.toRect().center);
      await tester.tapAt(middle, kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(rig.opened, [id]);
    });
  });

  group('the look of the text', () {
    testWidgets('each piece keeps its length, so the caret is right', (
      tester,
    ) async {
      const text =
          '# Title\n- one\n- [ ] two ⟦t:$id⟧\n- [x] done\n> said\n'
          '**bold** *it* `code` #tag @fri [[Buy milk|$id]] '
          '![door](grove-image:$id)';
      final rig = await makeRig(tester, text);
      final drawn = pieces(tester, rig).map((p) => p.text!).join();
      expect(drawn.length, text.length);
    });

    testWidgets('bold, italic, code, a quote and a tag each have their look', (
      tester,
    ) async {
      final rig = await makeRig(
        tester,
        'plain **bold** *slant* `code` #tag\n> said',
        services: showingMarks,
      );
      final theme = GroveTheme.of(tester.element(find.byType(EditableText)));
      final plain = pieceWith(tester, rig, 'plain ').style!;
      expect(plain.fontWeight, isNot(FontWeight.w700));
      expect(plain.fontStyle, isNot(FontStyle.italic));
      expect(plain.color, theme.ink);

      expect(pieceWith(tester, rig, 'bold').style!.fontWeight, FontWeight.w700);
      expect(
        pieceWith(tester, rig, 'slant').style!.fontStyle,
        FontStyle.italic,
      );

      final code = pieceWith(tester, rig, 'code').style!;
      expect(code.backgroundColor, theme.surface2);
      expect(code.fontFamily, theme.number(12).fontFamily);
      // the line of the code is as high as the line of the text
      expect(
        code.fontSize! * code.height!,
        closeTo(plain.fontSize! * plain.height!, 1e-9),
      );

      expect(pieceWith(tester, rig, '#tag').style!.color, theme.accent2);

      // a quote: pale words after a mark in the accent colour
      expect(pieceWith(tester, rig, 'said').style!.color, theme.muted);
      final mark = pieces(tester, rig).firstWhere((p) => p.text!.contains('>'));
      expect(mark.style!.color, theme.accent);
      // the marks stay in the text, but pale
      final star = pieces(tester, rig).firstWhere((p) => p.text == '**').style!;
      expect(star.color, theme.muted.withValues(alpha: 0.55));
    });

    testWidgets('a web link and an @date are underlined in the accent colour', (
      tester,
    ) async {
      final rig = await makeRig(tester, 'see https://grove.example/a on @fri');
      final theme = GroveTheme.of(tester.element(find.byType(EditableText)));
      final link = pieceWith(tester, rig, 'https://grove.example/a').style!;
      expect(link.color, theme.accent);
      expect(link.decoration, TextDecoration.underline);
      expect(link.decorationStyle, isNot(TextDecorationStyle.dotted));
      final date = pieceWith(tester, rig, '@fri').style!;
      expect(date.color, theme.accent);
      expect(date.decoration, TextDecoration.underline);
      expect(date.decorationStyle, TextDecorationStyle.dotted);
      // the words around them are plain
      expect(pieceWith(tester, rig, 'see ').style!.decoration, isNull);
    });

    testWidgets('a bullet is drawn as a dot', (tester) async {
      final rig = await makeRig(tester, '- one');
      expect(pieces(tester, rig).first.text, startsWith('•'));
    });

    testWidgets('a check box is drawn as a box, ticked or not', (tester) async {
      final rig = await makeRig(tester, '- [ ] open\n- [x] done');
      final icons = [
        for (final p in pieces(tester, rig))
          if (p.style?.fontFamily == 'MaterialIcons') p.text,
      ];
      expect(icons, [
        String.fromCharCode(Icons.check_box_outline_blank.codePoint),
        String.fromCharCode(Icons.check_box.codePoint),
      ]);
      final done = pieceWith(tester, rig, 'done');
      expect(done.style?.decoration, TextDecoration.lineThrough);
    });

    testWidgets('a click on a check box ticks it', (tester) async {
      final rig = await makeRig(tester, '- [ ] open');
      await caret(tester, rig, 10);
      final editable = tester.renderObject<RenderBox>(
        find.byType(EditableText),
      );
      final state = tester.state<EditableTextState>(find.byType(EditableText));
      final boxes = state.renderEditable.getBoxesForSelection(
        const TextSelection(baseOffset: 3, extentOffset: 4),
      );
      final middle = editable.localToGlobal(boxes.first.toRect().center);
      await tester.tapAt(middle, kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(rig.text, '- [x] open');
      expect(rig.controller.selection.baseOffset, 10);
    });

    testWidgets('a heading has bigger, bold letters on a whole line', (
      tester,
    ) async {
      final rig = await makeRig(tester, '# Big\nsmall');
      final big = pieceWith(tester, rig, 'Big');
      expect(big.style?.fontSize, 20);
      expect(big.style?.fontWeight, FontWeight.w700);
      final line = big.style!.fontSize! * big.style!.height!;
      expect(line, closeTo(line.roundToDouble(), 1e-9));
    });

    testWidgets('a line of plain text is 17 points high', (tester) async {
      await makeRig(tester, 'one\ntwo\nthree');
      expect(tester.getSize(find.byType(EditableText)).height, 51);
    });

    testWidgets('Vintage: every line is 28 points high, a heading too', (
      tester,
    ) async {
      await makeRig(tester, '# Big\ntwo\nthree', themeId: ThemeId.vintage);
      expect(tester.getSize(find.byType(EditableText)).height, 84);
    });

    testWidgets('the placeholder shows only in an empty text', (tester) async {
      final rig = await makeRig(tester, '');
      expect(find.text('Write here'), findsOneWidget);
      await type(tester, rig, 'a');
      expect(find.text('Write here'), findsNothing);
    });
  });

  group('buttons and shortcuts', () {
    testWidgets('bold wraps the selection', (tester) async {
      final rig = await makeRig(tester, 'make this loud');
      await caret(tester, rig, 5, 9);
      await tester.tap(find.bySemanticsLabel('Bold'));
      await tester.pump();
      expect(rig.text, 'make **this** loud');
    });

    testWidgets('the checklist button turns a line into a checklist', (
      tester,
    ) async {
      final rig = await makeRig(tester, 'buy milk');
      await caret(tester, rig, 3);
      await tester.tap(find.bySemanticsLabel('Checklist'));
      await tester.pump();
      expect(rig.text, '- [ ] buy milk');
    });

    testWidgets('the other buttons write their marks', (tester) async {
      final rig = await makeRig(tester, 'word');
      Future<void> press(String label, String expected) async {
        rig.controller.load('word');
        await caret(tester, rig, 0, 4);
        await useTool(tester, label);
        expect(rig.controller.text, expected, reason: label);
      }

      await press('Italic', '*word*');
      await press('Code', '`word`');
      await press('Bullet list', '- word');
      await press('Numbered list', '1. word');
      await press('Quote', '> word');
    });

    testWidgets('Command or Ctrl with B, I and E format the selection', (
      tester,
    ) async {
      final rig = await makeRig(tester, 'word');
      for (final (key, expected) in [
        (LogicalKeyboardKey.keyB, '**word**'),
        (LogicalKeyboardKey.keyI, '*word*'),
        (LogicalKeyboardKey.keyE, '`word`'),
      ]) {
        rig.controller.load('word');
        await caret(tester, rig, 0, 4);
        // The test runs as Android: the key is Ctrl.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(rig.controller.text, expected);
      }
    });

    testWidgets('there is no image button when the app cannot pick one', (
      tester,
    ) async {
      await makeRig(tester, '');
      expect(find.bySemanticsLabel('Add an image'), findsNothing);
      // Not in the "…" menu either.
      await tester.tap(find.bySemanticsLabel('More'));
      await tester.pumpAndSettle();
      expect(find.text('Divider'), findsOneWidget);
      expect(find.text('Add an image'), findsNothing);
    });
  });

  group('images', () {
    testWidgets('a new image goes in as markup and is stored', (tester) async {
      final stored = <ImageToStore>[];
      final rig = await makeRig(
        tester,
        'see',
        services: (rig) => EditorServices(
          storeImage: (image) {
            stored.add(image);
            return id;
          },
        ),
      );
      await caret(tester, rig, 3);
      rig.controller.importImages([
        (
          name: 'door',
          image: (
            mime: 'image/png',
            data: Uint8List.fromList([1, 2, 3]),
            width: 4,
            height: 3,
          ),
        ),
      ]);
      await tester.pump();
      expect(stored, hasLength(1));
      expect(rig.text, contains('![door](grove-image:$id)'));
      // The strip shows a small picture for it.
      expect(find.byKey(const ValueKey('image-$id')), findsOneWidget);
    });

    testWidgets('an image that cannot be read shows a message and changes '
        'nothing', (tester) async {
      final rig = await makeRig(tester, 'see');
      rig.controller.importImages([(name: 'junk', image: null)]);
      await tester.pump();
      expect(rig.text, 'see');
      expect(rig.told, ['junk is not an image Grove can read.']);
    });

    testWidgets('the remove button takes the image out of the text', (
      tester,
    ) async {
      final rig = await makeRig(tester, 'a ![door](grove-image:$id) b');
      await tester.tap(find.bySemanticsLabel('Remove this image'));
      await tester.pump();
      expect(rig.text, isNot(contains('grove-image')));
      expect(find.byKey(const ValueKey('image-$id')), findsNothing);
    });

    testWidgets('the text shows only the name of an image', (tester) async {
      final rig = await makeRig(tester, '![door](grove-image:$id)');
      final theme = GroveTheme.of(tester.element(find.byType(RichTextField)));
      expect(pieceWith(tester, rig, 'door').style?.color, theme.accent2);
      final rest = pieces(tester, rig).where((p) => p.text != 'door');
      for (final piece in rest) {
        expect(piece.style?.fontSize, lessThan(0.1), reason: piece.text);
      }
    });
  });

  group('web links', () {
    const text = 'see https://grove.example/a now';
    final address = Uri.parse('https://grove.example/a');
    const named = 'see [Grove](https://grove.example/a) now';

    /// The middle of the letters `from` to `to` of the text.
    Offset place(WidgetTester tester, int from, int to) {
      final editable = tester.renderObject<RenderBox>(
        find.byType(EditableText),
      );
      final state = tester.state<EditableTextState>(find.byType(EditableText));
      final boxes = state.renderEditable.getBoxesForSelection(
        TextSelection(baseOffset: from, extentOffset: to),
      );
      return editable.localToGlobal(boxes.first.toRect().center);
    }

    /// One click, at `at` of the clock of the pointer.
    Future<void> clickAt(
      WidgetTester tester,
      Offset where, {
      Duration at = Duration.zero,
    }) async {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.down(where, timeStamp: at);
      await gesture.up(timeStamp: at);
      await gesture.removePointer();
      await tester.pump();
    }

    LinkOpener browser(Rig Function() rig, {bool works = true}) => (url) async {
      rig().links.add(url);
      return works;
    };

    /// A click on the link, then Open in its bubble.
    Future<void> openAt(WidgetTester tester, Offset where) async {
      await clickAt(tester, where);
      await tester.tap(bubbleButton('Open'));
      await tester.pump();
    }

    testWidgets('a click on a web link shows a bubble and opens nothing yet', (
      tester,
    ) async {
      late Rig rig;
      rig = await makeRig(tester, text, openLink: browser(() => rig));
      expect(linkBubble, findsNothing);
      await clickAt(tester, place(tester, 4, 27));
      expect(linkBubble, findsOneWidget);
      expect(rig.links, isEmpty);
      // The address with no `https://`; a bare address has no Remove.
      expect(
        find.descendant(of: linkBubble, matching: find.text('grove.example/a')),
        findsOneWidget,
      );
      expect(bubbleButton('Open'), findsOneWidget);
      expect(bubbleButton('Edit'), findsOneWidget);
      expect(bubbleButton('Remove'), findsNothing);
      // The text did not change, and keeps the keyboard.
      expect(rig.text, text);
      expect(rig.focus.hasFocus, isTrue);
    });

    testWidgets('Open in the bubble opens the browser and closes the bubble', (
      tester,
    ) async {
      late Rig rig;
      rig = await makeRig(tester, text, openLink: browser(() => rig));
      await openAt(tester, place(tester, 4, 27));
      expect(rig.links, [address]);
      expect(rig.told, isEmpty);
      expect(linkBubble, findsNothing);
      expect(rig.text, text);
    });

    testWidgets('a tap of a finger shows the bubble too', (tester) async {
      late Rig rig;
      rig = await makeRig(tester, text, openLink: browser(() => rig));
      await tester.tapAt(place(tester, 4, 27));
      await tester.pump();
      expect(linkBubble, findsOneWidget);
      await tester.tap(bubbleButton('Open'));
      await tester.pump();
      expect(rig.links, [address]);
    });

    testWidgets('a click on plain words shows no bubble', (tester) async {
      late Rig rig;
      rig = await makeRig(tester, text, openLink: browser(() => rig));
      await clickAt(tester, place(tester, 0, 3));
      await clickAt(tester, place(tester, 28, 31));
      expect(linkBubble, findsNothing);
      expect(rig.links, isEmpty);
    });

    testWidgets('with no browser the bubble has no Open', (tester) async {
      final rig = await makeRig(tester, text);
      await clickAt(tester, place(tester, 4, 27));
      expect(linkBubble, findsOneWidget);
      expect(bubbleButton('Open'), findsNothing);
      expect(bubbleButton('Edit'), findsOneWidget);
      expect(rig.told, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the editor takes the browser of the app around it', (
      tester,
    ) async {
      late Rig rig;
      rig = await makeRig(
        tester,
        text,
        around: (child) =>
            EditorTools(openLink: browser(() => rig), child: child),
      );
      await openAt(tester, place(tester, 4, 27));
      expect(rig.links, [address]);
    });

    testWidgets('a double click on a link opens nothing', (tester) async {
      late Rig rig;
      rig = await makeRig(tester, text, openLink: browser(() => rig));
      final where = place(tester, 4, 27);
      await clickAt(tester, where, at: const Duration(seconds: 5));
      await clickAt(tester, where, at: const Duration(milliseconds: 5150));
      expect(rig.links, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a drag over a web link shows no bubble', (tester) async {
      late Rig rig;
      rig = await makeRig(tester, text, openLink: browser(() => rig));
      final gesture = await tester.startGesture(
        place(tester, 4, 6),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(place(tester, 20, 22));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(linkBubble, findsNothing);
      expect(rig.links, isEmpty);
    });

    testWidgets('a browser that cannot open the link: Grove says so', (
      tester,
    ) async {
      late Rig rig;
      rig = await makeRig(
        tester,
        text,
        openLink: browser(() => rig, works: false),
      );
      await openAt(tester, place(tester, 4, 27));
      await tester.pump();
      expect(rig.links, [address]);
      expect(rig.told, ['Grove could not open the link.']);
    });

    testWidgets('a browser that fails with an error: Grove says so', (
      tester,
    ) async {
      final rig = await makeRig(
        tester,
        text,
        openLink: (url) async => throw StateError('no browser'),
      );
      await openAt(tester, place(tester, 4, 27));
      await tester.pump();
      expect(rig.told, ['Grove could not open the link.']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the dot at the end of a sentence is not a part of the link', (
      tester,
    ) async {
      late Rig rig;
      rig = await makeRig(
        tester,
        'see https://grove.example/a.',
        openLink: browser(() => rig),
      );
      await openAt(tester, place(tester, 4, 27));
      expect(rig.links, [address]);
    });

    testWidgets('a link with its own words: Open, Edit and Remove', (
      tester,
    ) async {
      late Rig rig;
      rig = await makeRig(tester, named, openLink: browser(() => rig));
      await clickAt(tester, place(tester, 5, 10));
      expect(linkBubble, findsOneWidget);
      expect(
        find.descendant(of: linkBubble, matching: find.text('grove.example/a')),
        findsOneWidget,
      );
      expect(bubbleButton('Open'), findsOneWidget);
      expect(bubbleButton('Edit'), findsOneWidget);
      expect(bubbleButton('Remove'), findsOneWidget);
      await tester.tap(bubbleButton('Open'));
      await tester.pump();
      expect(rig.links, [address]);
      expect(rig.text, named);
    });

    testWidgets('Remove keeps the words as plain text', (tester) async {
      late Rig rig;
      rig = await makeRig(tester, named, openLink: browser(() => rig));
      await clickAt(tester, place(tester, 5, 10));
      await tester.tap(bubbleButton('Remove'));
      await tester.pump();
      expect(rig.text, 'see Grove now');
      expect(linkBubble, findsNothing);
      expect(rig.links, isEmpty);
      expect(rig.focus.hasFocus, isTrue);
      // One step of the undo of the box.
      await undoKey(tester);
      expect(rig.text, named);
    });

    testWidgets('Edit opens the link window with the link filled in', (
      tester,
    ) async {
      late Rig rig;
      rig = await makeRig(tester, named, openLink: browser(() => rig));
      await clickAt(tester, place(tester, 5, 10));
      await tester.tap(bubbleButton('Edit'));
      await tester.pumpAndSettle();
      expect(linkBubble, findsNothing);
      expect(linkDialog, findsOneWidget);
      expect(fieldText(tester, 'link-words'), 'Grove');
      expect(fieldText(tester, 'link-address'), 'https://grove.example/a');
      await tester.enterText(linkField('link-address'), 'grove.example/b');
      await tapSave(tester);
      expect(rig.text, 'see [Grove](https://grove.example/b) now');
      expect(rig.links, isEmpty);
    });

    testWidgets('Edit of a bare address can give it words', (tester) async {
      late Rig rig;
      rig = await makeRig(tester, text, openLink: browser(() => rig));
      await clickAt(tester, place(tester, 4, 27));
      await tester.tap(bubbleButton('Edit'));
      await tester.pumpAndSettle();
      expect(fieldText(tester, 'link-words'), '');
      expect(fieldText(tester, 'link-address'), 'https://grove.example/a');
      await tester.enterText(linkField('link-words'), 'Grove');
      await tapSave(tester);
      expect(rig.text, named);
    });

    testWidgets('Escape closes the bubble', (tester) async {
      late Rig rig;
      rig = await makeRig(tester, named, openLink: browser(() => rig));
      await clickAt(tester, place(tester, 5, 10));
      expect(linkBubble, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(linkBubble, findsNothing);
      expect(rig.focus.hasFocus, isTrue);
      expect(rig.text, named);
    });

    testWidgets('a click somewhere else closes the bubble', (tester) async {
      late Rig rig;
      rig = await makeRig(tester, named, openLink: browser(() => rig));
      await clickAt(tester, place(tester, 5, 10));
      expect(linkBubble, findsOneWidget);
      // On plain words of the text.
      await clickAt(tester, place(tester, 0, 3));
      expect(linkBubble, findsNothing);
      await clickAt(tester, place(tester, 5, 10));
      expect(linkBubble, findsOneWidget);
      // Out of the box.
      await clickAt(tester, const Offset(450, 380));
      expect(linkBubble, findsNothing);
      expect(rig.links, isEmpty);
    });

    testWidgets('typing closes the bubble', (tester) async {
      late Rig rig;
      rig = await makeRig(tester, named, openLink: browser(() => rig));
      await clickAt(tester, place(tester, 5, 10));
      expect(linkBubble, findsOneWidget);
      await type(tester, rig, 'x');
      expect(linkBubble, findsNothing);
    });

    testWidgets('a letter typed right after a link is plain text', (
      tester,
    ) async {
      const linked = 'see [Grove](https://grove.example/a)';
      final rig = await makeRig(tester, linked);
      await caret(tester, rig, linked.length);
      await type(tester, rig, 's');
      expect(rig.text, '${linked}s');
      expect(rig.controller.activeAt().link, isFalse);
    });
  });

  group('the link window', () {
    testWidgets('the key opens it with the selected words; Save is off until '
        'the address is a web address', (tester) async {
      final rig = await makeRig(tester, 'see Grove now');
      await caret(tester, rig, 4, 9);
      await linkKey(tester);
      expect(linkDialog, findsOneWidget);
      expect(fieldText(tester, 'link-words'), 'Grove');
      expect(fieldText(tester, 'link-address'), '');
      // No address: Save does nothing.
      await tapSave(tester);
      expect(linkDialog, findsOneWidget);
      // Only http and https (Q-16).
      for (final bad in [
        'ftp://grove.example',
        'javascript:alert(1)',
        'grove',
      ]) {
        await tester.enterText(linkField('link-address'), bad);
        await tester.pump();
        await tapSave(tester);
        expect(linkDialog, findsOneWidget, reason: bad);
      }
      // A bare host gets https://.
      await tester.enterText(linkField('link-address'), 'grove.example');
      await tapSave(tester);
      expect(linkDialog, findsNothing);
      expect(rig.text, 'see [Grove](https://grove.example) now');
      // The box has the keyboard again, with the caret after the link.
      expect(rig.focus.hasFocus, isTrue);
      expect(
        rig.controller.selection,
        const TextSelection.collapsed(offset: 34),
      );
    });

    testWidgets('Command-K on a Mac', (tester) async {
      final rig = await makeRig(tester, 'see Grove now');
      await caret(tester, rig, 4, 9);
      await linkKey(tester);
      expect(linkDialog, findsOneWidget);
      await tester.enterText(
        linkField('link-address'),
        'https://grove.example',
      );
      await tapSave(tester);
      expect(rig.text, 'see [Grove](https://grove.example) now');
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('the Link tool opens it too', (tester) async {
      final rig = await makeRig(tester, 'see Grove now');
      await caret(tester, rig, 4, 9);
      await useTool(tester, 'Link');
      await tester.pumpAndSettle();
      expect(linkDialog, findsOneWidget);
      expect(fieldText(tester, 'link-words'), 'Grove');
      await tester.enterText(linkField('link-address'), 'grove.example');
      // Return in a field saves.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(linkDialog, findsNothing);
      expect(rig.text, 'see [Grove](https://grove.example) now');
    });

    testWidgets('Cancel changes nothing and puts the selection back', (
      tester,
    ) async {
      final rig = await makeRig(tester, 'see Grove now');
      await caret(tester, rig, 4, 9);
      await linkKey(tester);
      await tester.enterText(linkField('link-address'), 'grove.example');
      await tester.tap(
        find.descendant(of: linkDialog, matching: find.text('Cancel')),
      );
      await tester.pumpAndSettle();
      expect(linkDialog, findsNothing);
      expect(rig.text, 'see Grove now');
      expect(rig.focus.hasFocus, isTrue);
      expect(
        rig.controller.selection,
        const TextSelection(baseOffset: 4, extentOffset: 9),
      );
    });

    testWidgets('no words and no selection: the address is the words', (
      tester,
    ) async {
      final rig = await makeRig(tester, 'see ');
      await caret(tester, rig, 4);
      await linkKey(tester);
      expect(fieldText(tester, 'link-words'), '');
      await tester.enterText(linkField('link-address'), 'grove.example');
      await tapSave(tester);
      expect(rig.text, 'see [https://grove.example](https://grove.example)');
    });

    testWidgets('own words in place of the selected ones', (tester) async {
      final rig = await makeRig(tester, 'see Grove now');
      await caret(tester, rig, 4, 9);
      await linkKey(tester);
      await tester.enterText(linkField('link-words'), 'the home page');
      await tester.enterText(linkField('link-address'), 'grove.example');
      await tapSave(tester);
      expect(rig.text, 'see [the home page](https://grove.example) now');
    });

    testWidgets('in a link it changes the address and keeps the format of '
        'the words', (tester) async {
      const text = 'see [**Gro**ve](https://grove.example/a) now';
      final rig = await makeRig(tester, text);
      await caret(tester, rig, 12);
      await linkKey(tester);
      expect(fieldText(tester, 'link-words'), 'Grove');
      expect(fieldText(tester, 'link-address'), 'https://grove.example/a');
      await tester.enterText(linkField('link-address'), 'grove.example/b');
      await tapSave(tester);
      expect(rig.text, 'see [**Gro**ve](https://grove.example/b) now');
    });

    testWidgets('in a link new words take the place of the old', (
      tester,
    ) async {
      const text = 'see [Grove](https://grove.example/a) now';
      final rig = await makeRig(tester, text);
      await caret(tester, rig, 7);
      await linkKey(tester);
      await tester.enterText(linkField('link-words'), 'Home');
      await tapSave(tester);
      expect(rig.text, 'see [Home](https://grove.example/a) now');
    });

    testWidgets('a new link is one step of undo', (tester) async {
      final rig = await makeRig(tester, 'see Grove now');
      await caret(tester, rig, 4, 9);
      await linkKey(tester);
      await tester.enterText(linkField('link-address'), 'grove.example');
      await tapSave(tester);
      await undoKey(tester);
      expect(rig.text, 'see Grove now');
    });
  });

  group('the picker of the app', () {
    PickedImage picture(String name) => (
      name: name,
      image: (
        mime: 'image/png',
        data: Uint8List.fromList([1, 2, 3]),
        width: 4,
        height: 3,
      ),
    );

    EditorServices keeps(Rig rig) =>
        EditorServices(storeImage: (image) => id, notify: rig.told.add);

    testWidgets('"Add an image" puts the picked pictures in the text', (
      tester,
    ) async {
      var asked = 0;
      final rig = await makeRig(
        tester,
        'see',
        services: keeps,
        pickImages: () async {
          asked += 1;
          return [picture('door')];
        },
      );
      await caret(tester, rig, 3);
      await useTool(tester, 'Add an image');
      await tester.pump();
      await tester.pump();
      expect(asked, 1);
      expect(rig.text, contains('![door](grove-image:$id)'));
      expect(find.byKey(const ValueKey('image-$id')), findsOneWidget);
    });

    testWidgets('the editor takes the picker of the app around it', (
      tester,
    ) async {
      final rig = await makeRig(
        tester,
        '',
        services: keeps,
        around: (child) => EditorTools(
          pickImages: () async => [picture('gate')],
          child: child,
        ),
      );
      await useTool(tester, 'Add an image');
      await tester.pump();
      await tester.pump();
      expect(rig.text, contains('![gate](grove-image:$id)'));
    });

    testWidgets('a closed file window changes nothing', (tester) async {
      final rig = await makeRig(
        tester,
        'see',
        services: keeps,
        pickImages: () async => const [],
      );
      await useTool(tester, 'Add an image');
      await tester.pump();
      await tester.pump();
      expect(rig.text, 'see');
      expect(rig.told, isEmpty);
    });

    testWidgets('a file that is not a picture: Grove says so', (tester) async {
      final rig = await makeRig(
        tester,
        'see',
        services: keeps,
        pickImages: () async => const [(name: 'notes', image: null)],
      );
      await useTool(tester, 'Add an image');
      await tester.pump();
      await tester.pump();
      expect(rig.text, 'see');
      expect(rig.told, ['notes is not an image Grove can read.']);
    });

    testWidgets('a file window that fails: Grove says so', (tester) async {
      final rig = await makeRig(
        tester,
        'see',
        services: keeps,
        pickImages: () async => throw StateError('no window'),
      );
      await useTool(tester, 'Add an image');
      await tester.pump();
      await tester.pump();
      expect(rig.text, 'see');
      expect(rig.told, ['Grove could not open the file window.']);
      expect(tester.takeException(), isNull);
    });
  });

  group('drop', () {
    testWidgets('a dropped task becomes a mention', (tester) async {
      final rig = await makeRig(tester, 'ab');
      rig.controller.dropItem('T1', 1);
      await tester.pump();
      expect(rig.text, 'a[[Buy milk|T1]]b');
    });

    testWidgets('a task that is gone is not dropped', (tester) async {
      final rig = await makeRig(tester, 'ab');
      rig.controller.dropItem('nope', 1);
      await tester.pump();
      expect(rig.text, 'ab');
    });
  });

  group('the [[ list', () {
    testWidgets('typing [[ opens the list and Return picks the row', (
      tester,
    ) async {
      final rig = await makeRig(tester, 'see ');
      await caret(tester, rig, 4);
      await type(tester, rig, '[[bu');
      await tester.pump();
      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.text('Task'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(rig.text, 'see [[Buy milk|T1]]');
      expect(find.text('Task'), findsNothing);
    });

    testWidgets('a line break from a phone keyboard picks the row too', (
      tester,
    ) async {
      final rig = await makeRig(tester, '');
      await type(tester, rig, '[[bu');
      await type(tester, rig, '\n');
      expect(rig.text, '[[Buy milk|T1]]');
    });

    testWidgets('a tap on a row picks it', (tester) async {
      final rig = await makeRig(tester, '');
      await type(tester, rig, '[[');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('mention-T1')));
      await tester.pump();
      expect(rig.text, '[[Buy milk|T1]]');
    });

    testWidgets('the list is under the [[, 300 points wide', (tester) async {
      final rig = await makeRig(tester, 'one\ntwo ');
      await caret(tester, rig, 8);
      await type(tester, rig, '[[');
      await tester.pump();
      final list = tester.getRect(find.byType(MentionListView));
      final field = tester.getRect(find.byType(EditableText));
      expect(list.width, 300);
      // Under the second line (2 x 17 points), with a small gap.
      expect(list.top, closeTo(field.top + 34 + 4, 2));
      expect(list.top, list.top.roundToDouble());
      expect(list.left, greaterThan(field.left));
    });

    testWidgets('Esc closes the list and Return then makes a line break', (
      tester,
    ) async {
      final rig = await makeRig(tester, '');
      await type(tester, rig, '[[bu');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('Task'), findsNothing);
      await type(tester, rig, '\n');
      expect(rig.text, startsWith('[[bu'));
      expect(rig.text, isNot(contains('T1')));
    });

    testWidgets('Esc is kept by the editor only while its list is open', (
      tester,
    ) async {
      final rig = await makeRig(tester, '');
      // no list yet: Esc is not the editor's
      expect(rig.controller.closeList(), isFalse);
      await type(tester, rig, '[[bu');
      expect(rig.controller.closeList(), isTrue);
      expect(rig.controller.closeList(), isFalse);
      // More letters after the same [[ do not open it again.
      await type(tester, rig, 'y');
      expect(rig.controller.mentions.value, isNull);
    });

    testWidgets('the arrow keys move the chosen row', (tester) async {
      final rig = await makeRig(
        tester,
        '',
        services: (rig) => EditorServices(
          suggest: (_) => const [
            MentionSuggestion(
              ref: ItemRef(ItemType.task, 'T1'),
              title: 'Buy milk',
              kind: 'Task',
            ),
            MentionSuggestion(
              ref: ItemRef(ItemType.note, 'N1'),
              title: 'Budget',
              kind: 'Note',
            ),
          ],
        ),
      );
      await type(tester, rig, '[[bu');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(rig.controller.mentions.value?.selected, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(rig.text, '[[Budget|N1]]');
    });

    testWidgets('the mention button types [[ and opens the list', (
      tester,
    ) async {
      final rig = await makeRig(tester, 'a ');
      await caret(tester, rig, 2);
      await useTool(tester, 'Mention');
      await tester.pump();
      expect(rig.text, 'a [[');
      expect(rig.controller.mentions.value, isNotNull);
    });

    testWidgets('the list closes when the text loses the keyboard', (
      tester,
    ) async {
      final rig = await makeRig(tester, '');
      await type(tester, rig, '[[');
      expect(rig.controller.mentions.value, isNotNull);
      rig.focus.unfocus();
      await tester.pump();
      expect(rig.controller.mentions.value, isNull);
    });
  });

  group('tasks and the planner', () {
    testWidgets('a line with words becomes a task line', (tester) async {
      final made = <String>[];
      final rig = await makeRig(
        tester,
        'call the bank',
        services: (rig) => EditorServices(
          makeTask: (words) {
            made.add(words);
            return 'T9';
          },
        ),
      );
      await caret(tester, rig, 4);
      expect(rig.controller.canMakeTask, isTrue);
      rig.controller.makeTask();
      await tester.pump();
      expect(made, ['call the bank']);
      expect(rig.text, '- [ ] call the bank ⟦t:T9⟧');
    });

    testWidgets('a field that is not a note cannot make a task', (
      tester,
    ) async {
      final rig = await makeRig(tester, 'call the bank');
      await caret(tester, rig, 4);
      expect(rig.controller.canMakeTask, isFalse);
    });

    testWidgets('"Add to planner" shows on a line with an @date', (
      tester,
    ) async {
      final sent = <String>[];
      final rig = await makeRig(
        tester,
        'plain\nlunch @fri 1pm',
        services: (rig) => EditorServices(
          addToPlanner: (line) {
            sent.add(line);
            return '[[lunch|E1]] Fri 13:00';
          },
        ),
      );
      await caret(tester, rig, 2);
      expect(find.text('Add to planner'), findsNothing);
      await caret(tester, rig, 12);
      expect(find.text('Add to planner'), findsOneWidget);
      await tester.tap(find.text('Add to planner'));
      await tester.pump();
      expect(sent, ['lunch @fri 1pm']);
      expect(rig.text, 'plain\n[[lunch|E1]] Fri 13:00');
    });
  });

  group('a key next to a unit', () {
    testWidgets('a letter typed in front of a mention stays in front of it', (
      tester,
    ) async {
      const text = 'x [[Buy milk|$id]] y';
      final rig = await makeRig(tester, text);
      await caret(tester, rig, 2);
      await type(tester, rig, '[');
      expect(rig.text, 'x [[[Buy milk|$id]] y');
      expect(rig.controller.selection.baseOffset, 3);
    });

    testWidgets('a letter typed in front of an image stays in front of it', (
      tester,
    ) async {
      const text = 'wow ![cat](grove-image:$id) y';
      final rig = await makeRig(tester, text);
      await caret(tester, rig, 4);
      await type(tester, rig, '!');
      expect(rig.text, 'wow !![cat](grove-image:$id) y');
      expect(rig.controller.selection.baseOffset, 5);
    });

    testWidgets('Backspace in front of an image keeps the image', (
      tester,
    ) async {
      const text = 'wow!![cat](grove-image:$id) y';
      final rig = await makeRig(tester, text);
      await caret(tester, rig, 4);
      await backspace(tester, rig);
      expect(rig.text, 'wow![cat](grove-image:$id) y');
      expect(rig.controller.selection.baseOffset, 3);
    });

    testWidgets('Backspace in front of a mention keeps the mention', (
      tester,
    ) async {
      const text = 'a[[[Buy milk|$id]] y';
      final rig = await makeRig(tester, text);
      await caret(tester, rig, 2);
      await backspace(tester, rig);
      expect(rig.text, 'a[[Buy milk|$id]] y');
      expect(rig.controller.selection.baseOffset, 1);
    });

    testWidgets('Backspace on one of two spaces in front of a task mark '
        'takes that space only', (tester) async {
      const text = '- [ ] buy milk  ⟦t:abc⟧\nnext';
      final rig = await makeRig(tester, text);
      await caret(tester, rig, 15);
      await backspace(tester, rig);
      expect(rig.text, '- [ ] buy milk ⟦t:abc⟧\nnext');
      expect(rig.controller.selection.baseOffset, 14);
    });

    testWidgets('a key far from the caret is still read where it is', (
      tester,
    ) async {
      // What a spelling fix of the keyboard does: the caret is at the end,
      // the change is in the middle.
      final rig = await makeRig(tester, 'aa bb aa');
      await caret(tester, rig, 8);
      await send(tester, 'aa cc aa', 8);
      expect(rig.text, 'aa cc aa');
    });
  });

  group('the keyboard of a phone', () {
    testWidgets('Return at the end of a word that is not done yet goes on '
        'with the list', (tester) async {
      final rig = await makeRig(tester, '- ');
      await compose(tester, '- one', 2, 5);
      expect(rig.text, '- one');
      await send(tester, '- one\n', 6);
      expect(rig.text, '- one\n- ');
      expect(rig.controller.selection.baseOffset, 8);
    });

    testWidgets('Return at the end of a word that is not done yet picks the '
        'row of the list', (tester) async {
      final rig = await makeRig(tester, '');
      await compose(tester, '[[bu', 2, 4);
      expect(find.text('Buy milk'), findsOneWidget);
      await send(tester, '[[bu\n', 5);
      expect(rig.text, '[[Buy milk|T1]]');
    });

    testWidgets('a word that is not done yet is left as the keyboard sends '
        'it', (tester) async {
      final rig = await makeRig(tester, '- one');
      await compose(tester, '- one tw', 6, 8);
      await compose(tester, '- one two', 6, 9);
      expect(rig.text, '- one two');
      expect(rig.controller.value.composing, const TextRange(start: 6, end: 9));
    });
  });

  group('a mouse on the buttons', () {
    testWidgets(
      'a click on a button of the row does not take the keyboard away',
      variant: TargetPlatformVariant.desktop(),
      (tester) async {
        final rig = await makeRig(tester, 'make this loud');
        await caret(tester, rig, 5, 9);
        final focus = <bool>[];
        void heard() => focus.add(rig.focus.hasFocus);
        rig.focus.addListener(heard);
        await click(tester, find.bySemanticsLabel('Bold'));
        rig.focus.removeListener(heard);
        expect(focus, isEmpty);
        expect(rig.focus.hasFocus, isTrue);
        expect(rig.text, 'make **this** loud');
      },
    );

    testWidgets(
      'a click on "Add to planner" does not take the keyboard away',
      variant: TargetPlatformVariant.desktop(),
      (tester) async {
        final rig = await makeRig(
          tester,
          'plain\nlunch @fri 1pm',
          services: (rig) =>
              EditorServices(addToPlanner: (line) => '[[lunch|E1]] Fri 13:00'),
        );
        await caret(tester, rig, 12);
        final focus = <bool>[];
        void heard() => focus.add(rig.focus.hasFocus);
        rig.focus.addListener(heard);
        await click(tester, find.text('Add to planner'));
        rig.focus.removeListener(heard);
        expect(focus, isEmpty);
        expect(rig.focus.hasFocus, isTrue);
        expect(rig.text, 'plain\n[[lunch|E1]] Fri 13:00');
      },
    );
  });

  group('the place of the [[ list', () {
    testWidgets('over the line when the field is at the bottom of the window, '
        'and a click on a row still picks it', (tester) async {
      final rig = await makeRig(
        tester,
        '',
        services: eightTasks,
        alignment: Alignment.bottomLeft,
      );
      await type(tester, rig, '[[');
      await tester.pump();
      final list = tester.getRect(find.byType(MentionListView));
      final field = tester.getRect(find.byType(EditableText));
      expect(list.height, 8 * RichTextField.listRow + 8);
      expect(list.bottom, closeTo(field.top - 4, 1));
      expect(list.top, greaterThanOrEqualTo(8));
      for (var i = 0; i < 8; i++) {
        expect(find.text('Buy milk $i').hitTestable(), findsOneWidget);
      }
      await tester.tap(find.text('Buy milk 3'));
      await tester.pump();
      expect(rig.text, '[[Buy milk 3|T3]]');
    });

    testWidgets('over the line when the keyboard of a phone hides the room '
        'under it', (tester) async {
      tester.view.viewInsets = const FakeViewPadding(bottom: 336);
      addTearDown(tester.view.resetViewInsets);
      final lines = [for (var i = 0; i < 20; i++) 'line $i'].join('\n');
      final rig = await makeRig(
        tester,
        '$lines\n',
        services: eightTasks,
        size: const Size(390, 844),
      );
      await caret(tester, rig, lines.length + 1);
      await type(tester, rig, '[[');
      await tester.pump();
      final list = tester.getRect(find.byType(MentionListView));
      final line = tester.getRect(find.byType(EditableText)).bottom - 17;
      // The keyboard starts at 844 - 336 = 508.
      expect(list.bottom, lessThanOrEqualTo(508 - 8));
      expect(list.bottom, closeTo(line - 4, 1));
      for (var i = 0; i < 8; i++) {
        expect(find.text('Buy milk $i').hitTestable(), findsOneWidget);
      }
    });

    testWidgets('with no room over or under the line, all of it stays in the '
        'window', (tester) async {
      final lines = [for (var i = 0; i < 9; i++) 'line $i'].join('\n');
      final rig = await makeRig(tester, '$lines\n', services: eightTasks);
      await caret(tester, rig, lines.length + 1);
      await type(tester, rig, '[[');
      await tester.pump();
      final list = tester.getRect(find.byType(MentionListView));
      expect(list.top, greaterThanOrEqualTo(8));
      expect(list.bottom, lessThanOrEqualTo(400 - 8));
      for (var i = 0; i < 8; i++) {
        expect(find.text('Buy milk $i').hitTestable(), findsOneWidget);
      }
    });

    testWidgets('not past the right edge of the window', (tester) async {
      final rig = await makeRig(
        tester,
        '',
        services: eightTasks,
        size: const Size(390, 844),
      );
      await type(tester, rig, 'a long line of words that ends far right [[');
      await tester.pump();
      final list = tester.getRect(find.byType(MentionListView));
      expect(list.right, lessThanOrEqualTo(390 - 8));
      expect(list.left, greaterThanOrEqualTo(8));
    });
  });

  group('hidden marks', () {
    bool hidden(TextStyle? style) =>
        style!.fontSize == EditorStyle.hidden.fontSize &&
        style.color == const Color(0x00000000);

    testWidgets('the marks of a format are hidden', (tester) async {
      final rig = await makeRig(
        tester,
        'plain **bold** `code` [a](https://x.io)',
        services: hidingMarks,
      );
      final drawn = pieces(tester, rig);
      for (final p in drawn) {
        if (p.text == '**' || p.text == '`' || p.text == '[') {
          expect(hidden(p.style), isTrue, reason: p.text);
        }
      }
      expect(hidden(pieceWith(tester, rig, '](https://x.io)').style), isTrue);
      expect(pieceWith(tester, rig, 'bold').style!.fontWeight, FontWeight.w700);
      expect(hidden(pieceWith(tester, rig, 'plain ').style), isFalse);
    });

    testWidgets('the mark of a heading is hidden', (tester) async {
      final rig = await makeRig(tester, '## Head', services: hidingMarks);
      expect(hidden(pieceWith(tester, rig, '## ').style), isTrue);
    });

    testWidgets('a quote has a bar in the accent colour', (tester) async {
      final rig = await makeRig(tester, '> said', services: hidingMarks);
      final theme = GroveTheme.of(tester.element(find.byType(EditableText)));
      final mark = pieces(tester, rig).first;
      expect(mark.text, '▎ ');
      expect(mark.style!.color, theme.accent);
    });

    testWidgets('each piece keeps its length', (tester) async {
      const text = '## Head\n**b** *i* `c` [a](https://x.io)\n---\n> q';
      final rig = await makeRig(tester, text, services: hidingMarks);
      final span = rig.controller.buildTextSpan(
        context: tester.element(find.byType(EditableText)),
        withComposing: false,
      );
      var length = 0;
      span.visitChildren((child) {
        if (child is WidgetSpan) length += 1;
        if (child is TextSpan) length += child.text?.length ?? 0;
        return true;
      });
      expect(length, text.length);
    });

    testWidgets('the caret beside hidden marks is as high as beside a letter', (
      tester,
    ) async {
      await makeRig(tester, '**cd** ef\nx', services: hidingMarks);
      final letter = caretRect(tester, 8);
      for (final at in [0, 2, 4, 6]) {
        final rect = caretRect(tester, at);
        expect(rect.height, closeTo(letter.height, 0.5), reason: '$at');
        expect(rect.top, closeTo(letter.top, 0.5), reason: '$at');
      }
      // The line is as high as a line of plain text.
      expect(tester.getSize(find.byType(EditableText)).height, 34);
    });

    testWidgets('the caret at the start of a heading is as high as its line', (
      tester,
    ) async {
      await makeRig(tester, '## Head', services: hidingMarks);
      final letter = caretRect(tester, 5);
      final start = caretRect(tester, 3);
      expect(start.height, closeTo(letter.height, 0.5));
      expect(start.top, closeTo(letter.top, 0.5));
    });

    testWidgets('the arrow keys step over hidden marks', (tester) async {
      final rig = await makeRig(tester, 'a**b**c', services: hidingMarks);
      await caret(tester, rig, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(
        rig.controller.selection,
        const TextSelection.collapsed(offset: 4),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(rig.controller.selection.baseOffset, 1);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(
        rig.controller.selection,
        const TextSelection(baseOffset: 1, extentOffset: 4),
      );
    });

    testWidgets('with "Show marks" on the arrow keys step on each mark', (
      tester,
    ) async {
      final rig = await makeRig(tester, 'a**b**c', services: showingMarks);
      await caret(tester, rig, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(rig.controller.selection.baseOffset, 2);
      final star = pieces(tester, rig).firstWhere((p) => p.text == '**');
      expect(hidden(star.style), isFalse);
    });

    testWidgets('Backspace at the start of a heading takes its mark', (
      tester,
    ) async {
      final rig = await makeRig(tester, 'x\n## Head', services: hidingMarks);
      await caret(tester, rig, 5);
      await backspace(tester, rig);
      expect(rig.text, 'x\nHead');
    });

    testWidgets('a space at the end of bold goes after its marks', (
      tester,
    ) async {
      final rig = await makeRig(tester, '**b**', services: hidingMarks);
      await caret(tester, rig, 3);
      await type(tester, rig, ' ');
      expect(rig.text, '**b** ');
    });

    testWidgets('Bold at a caret, then a letter: a bold letter', (
      tester,
    ) async {
      final rig = await makeRig(tester, 'a ', services: hidingMarks);
      await caret(tester, rig, 2);
      await tester.tap(find.bySemanticsLabel('Bold'));
      await tester.pump();
      await type(tester, rig, 'b');
      expect(rig.text, 'a **b**');
    });

    testWidgets('an empty pair goes when the caret leaves it', (tester) async {
      final rig = await makeRig(tester, 'a b', services: hidingMarks);
      await caret(tester, rig, 2);
      await tester.tap(find.bySemanticsLabel('Bold'));
      await tester.pump();
      expect(rig.text, 'a ****b');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(rig.text, 'a b');
      expect(rig.controller.selection.baseOffset, 1);
    });

    testWidgets('the arrow keys never stop before a bullet, a bar or a box', (
      tester,
    ) async {
      final rig = await makeRig(tester, 'x\n- one\n> q\n- [ ] t');
      final stops = <int>[];
      await caret(tester, rig, 0);
      for (var i = 0; i < 9; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        stops.add(rig.controller.selection.baseOffset);
      }
      expect(stops, [1, 4, 5, 6, 7, 10, 11, 18, 19]);
      stops.clear();
      for (var i = 0; i < 9; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        stops.add(rig.controller.selection.baseOffset);
      }
      expect(stops, [18, 11, 10, 7, 6, 5, 4, 1, 0]);
    });

    testWidgets('a move to the start of a list line rests after the bullet', (
      tester,
    ) async {
      final rig = await makeRig(tester, 'x\n- one');
      await caret(tester, rig, 6);
      // Command and Left on a Mac, Home elsewhere.
      final apple = defaultTargetPlatform == TargetPlatform.macOS;
      if (apple) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
      }
      await tester.pump();
      expect(
        rig.controller.selection,
        const TextSelection.collapsed(offset: 4),
      );
    });

    testWidgets('a word move that ends in hidden marks rests on the letter', (
      tester,
    ) async {
      final rig = await makeRig(tester, 'one **two** x', services: hidingMarks);
      await caret(tester, rig, 0);
      // Alt on a Mac, Ctrl elsewhere, moves by words.
      final apple = defaultTargetPlatform == TargetPlatform.macOS;
      final mod = apple
          ? LogicalKeyboardKey.altLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(mod);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(mod);
      await tester.pump();
      // Never in the middle of hidden marks.
      final at = rig.controller.selection.baseOffset;
      expect(at, greaterThan(3));
      expect(rig.controller.canonical(at), at);
    });
  });

  group('a divider', () {
    testWidgets('is drawn as a line, one line high', (tester) async {
      final rig = await makeRig(tester, 'a\n---\nb', services: hidingMarks);
      final span = rig.controller.buildTextSpan(
        context: tester.element(find.byType(EditableText)),
        withComposing: false,
      );
      expect(span.children!.whereType<WidgetSpan>(), hasLength(1));
      expect(tester.getSize(find.byType(EditableText)).height, 51);
      final theme = GroveTheme.of(tester.element(find.byType(EditableText)));
      final rule = find.byType(EditorDivider);
      // As wide as the text, less the room of the caret.
      expect(tester.getSize(rule).width, closeTo(400, 6));
      expect(tester.widget<EditorDivider>(rule).color, theme.line);
    });

    testWidgets('Vintage: one ruled line high', (tester) async {
      await makeRig(
        tester,
        'a\n---\nb',
        themeId: ThemeId.vintage,
        services: hidingMarks,
      );
      expect(tester.getSize(find.byType(EditableText)).height, 84);
    });

    testWidgets('the caret steps over it as one letter', (tester) async {
      final rig = await makeRig(tester, 'a\n---\nb', services: hidingMarks);
      await caret(tester, rig, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(rig.controller.selection.baseOffset, 5);
    });

    testWidgets('Backspace after it takes all of it', (tester) async {
      final rig = await makeRig(tester, 'a\n---\nb', services: hidingMarks);
      await caret(tester, rig, 6);
      await backspace(tester, rig);
      expect(rig.text, 'a\nb');
    });
  });

  group('"Show marks"', () {
    test('is off at first: the marks are hidden', () {
      expect(EditorServices().showMarks(), isFalse);
      final controller = MarkdownController();
      addTearDown(controller.dispose);
      expect(controller.showMarks, isFalse);
    });

    testWidgets('the text changes as soon as the switch does', (tester) async {
      var show = false;
      final rig = await makeRig(
        tester,
        'plain **bold**',
        services: (rig) => EditorServices(showMarks: () => show),
      );
      final theme = GroveTheme.of(tester.element(find.byType(EditableText)));
      expect(
        pieceWith(tester, rig, '**').style!.fontSize,
        EditorStyle.hidden.fontSize,
      );
      show = true;
      tester.element(find.byType(RichTextField)).markNeedsBuild();
      await tester.pump();
      expect(
        pieceWith(tester, rig, '**').style!.color,
        theme.muted.withValues(alpha: 0.55),
      );
    });
  });

  testWidgets('a new text from outside replaces what the editor shows', (
    tester,
  ) async {
    final controller = MarkdownController(text: 'one');
    addTearDown(controller.dispose);
    final changes = <String>[];
    Future<void> show(String text) => pumpPane(
      tester,
      RichTextField(text: text, controller: controller, onChanged: changes.add),
    );
    await show('one');
    await tester.pumpWidget(const SizedBox());
    expect(controller.text, 'one');
    // The same field with another text.
    final text = ValueNotifier('one');
    addTearDown(text.dispose);
    await pumpPane(
      tester,
      ValueListenableBuilder<String>(
        valueListenable: text,
        builder: (context, value, _) => RichTextField(
          text: value,
          controller: controller,
          onChanged: changes.add,
        ),
      ),
    );
    text.value = 'two';
    await tester.pump();
    expect(controller.text, 'two');
    // A load is not a change the user made.
    expect(changes, isEmpty);
  });

  group('undo and redo', () {
    testWidgets('the keys take back typed words and do them again', (
      tester,
    ) async {
      final rig = await makeRig(tester, 'x ');
      await caret(tester, rig, 2);
      for (final letter in ['h', 'i']) {
        await type(tester, rig, letter);
      }
      expect(rig.text, 'x hi');
      await undoKey(tester);
      expect(rig.text, 'x ');
      await undoKey(tester, redo: true);
      expect(rig.text, 'x hi');
      expect(
        rig.controller.selection,
        const TextSelection.collapsed(offset: 4),
      );
    }, variant: TargetPlatformVariant.desktop());

    testWidgets('Ctrl-Y does again what undo took back, on Windows', (
      tester,
    ) async {
      final rig = await makeRig(tester, '');
      await caret(tester, rig, 0);
      await type(tester, rig, 'a');
      await undoKey(tester);
      expect(rig.text, '');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(rig.text, 'a');
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('a format button is taken back with the selection', (
      tester,
    ) async {
      final rig = await makeRig(tester, 'word');
      await caret(tester, rig, 0, 4);
      await tester.tap(find.bySemanticsLabel('Italic'));
      await tester.pump();
      expect(rig.text, '*word*');
      await undoKey(tester);
      expect(rig.text, 'word');
      expect(
        rig.controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 4),
      );
    }, variant: TargetPlatformVariant.desktop());

    testWidgets('with nothing to undo in the box, the key goes to the app', (
      tester,
    ) async {
      var app = 0;
      final rig = await makeRig(
        tester,
        'one',
        // The undo of the app, as `ShellKeys` has it.
        around: (child) => Focus(
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent ||
                event.logicalKey != LogicalKeyboardKey.keyZ) {
              return KeyEventResult.ignored;
            }
            app += 1;
            return KeyEventResult.handled;
          },
          child: child,
        ),
      );
      await caret(tester, rig, 3);
      await undoKey(tester);
      expect(app, 1);
      await type(tester, rig, '!');
      await undoKey(tester);
      expect((rig.text, app), ('one', 1));
      // Another text from outside: the history of the box starts again.
      await type(tester, rig, '?');
      rig.controller.load('two');
      await tester.pump();
      expect(rig.controller.canUndo, isFalse);
      await undoKey(tester);
      expect((rig.controller.text, app), ('two', 2));
    }, variant: TargetPlatformVariant.desktop());
  });
}
