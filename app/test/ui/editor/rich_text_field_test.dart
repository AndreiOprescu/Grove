// Port of Tests/GroveTests/EditorViewTests.swift: drives the real editor the
// way the keyboard would. The text rules themselves are tested in
// test/core/parsing.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/link.dart';
import 'package:grove/state/state.dart' hide MotionRules;
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
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          child: RichTextField(
            text: shown,
            controller: controller,
            focusNode: focus,
            services: (services ?? oneTask)(rig),
            placeholder: 'Write here',
            onChanged: (value) => setState(() {
              shown = value;
              rig.text = value;
            }),
          ),
        ),
      ),
    ),
    size: const Size(500, 400),
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
        await tester.tap(find.bySemanticsLabel(label));
        await tester.pump();
        expect(rig.controller.text, expected, reason: label);
      }

      await press('Italic', '*word*');
      await press('Code', '`word`');
      await press('Bullet list', '- word');
      await press('Numbered list', '1. word');
      await press('Heading', '## word');
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
      await tester.tap(find.bySemanticsLabel('Mention'));
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
}
