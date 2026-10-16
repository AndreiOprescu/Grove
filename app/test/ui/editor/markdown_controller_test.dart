// The caret model of the editor text and its keys, without a screen.
// What the field draws is tested in rich_text_field_test.dart.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/parsing/markdown_spans.dart';
import 'package:grove/ui/editor/markdown_controller.dart';

MarkdownController make(String text, {bool showMarks = false}) {
  final c = MarkdownController(text: text)..showMarks = showMarks;
  addTearDown(c.dispose);
  return c;
}

/// What a keyboard sends: the new text with the caret.
void send(MarkdownController c, String text, int caret) {
  c.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: caret),
  );
}

/// Types `typed` at the caret.
void type(MarkdownController c, String typed) {
  final s = c.selection;
  send(c, c.text.replaceRange(s.start, s.end, typed), s.start + typed.length);
}

void backspace(MarkdownController c) {
  final at = c.selection.start;
  send(c, c.text.replaceRange(at - 1, at, ''), at - 1);
}

void at(MarkdownController c, int offset) =>
    c.selection = TextSelection.collapsed(offset: offset);

int caretOf(MarkdownController c) => c.selection.baseOffset;

void main() {
  group('hidden marks', () {
    test('the marks of formats, headings and dividers are hidden', () {
      final c = make('a **b** c\n## Head\n---');
      expect(c.hiddenRuns, const [
        Utf16Range(2, 2),
        Utf16Range(5, 2),
        Utf16Range(10, 3),
        Utf16Range(18, 2),
      ]);
    });

    test('marks that touch are one run', () {
      final c = make('***b***');
      expect(c.hiddenRuns, const [Utf16Range(0, 3), Utf16Range(4, 3)]);
    });

    test('with "Show marks" on nothing is hidden', () {
      final c = make('a **b** c', showMarks: true);
      expect(c.hiddenRuns, isEmpty);
    });

    test('the visible index counts only the letters that show', () {
      final c = make('a **b** c');
      expect(
        [for (var i = 0; i <= 9; i++) c.visibleIndex(i)],
        [0, 1, 2, 2, 2, 3, 3, 3, 4, 5],
      );
    });
  });

  group('the canonical caret', () {
    test('rests outside the start and inside the end of a format', () {
      final c = make('x**b**y');
      expect(
        [for (var i = 0; i <= 7; i++) c.canonical(i)],
        [0, 1, 1, 1, 4, 4, 4, 7],
      );
    });

    test('at the start of a heading it rests after the mark', () {
      final c = make('x\n## Head');
      expect([c.canonical(2), c.canonical(3), c.canonical(5)], [5, 5, 5]);
    });

    test('a heading with bold words: after the mark, outside the bold', () {
      final c = make('## **b**');
      expect([for (var i = 0; i <= 5; i++) c.canonical(i)], [3, 3, 3, 3, 3, 3]);
    });

    test('at the end of a link it rests outside the link', () {
      const text = 'see [ab](https://grove.example) c';
      final c = make(text);
      final close = text.indexOf('](');
      final end = text.indexOf(' c');
      expect(c.canonical(close), end);
      expect(c.canonical(end), end);
      expect(c.canonical(4), 4);
      expect(c.canonical(5), 4);
    });

    test('a caret put in hidden marks moves to the canonical place', () {
      final c = make('x**b**y');
      at(c, 2);
      expect(caretOf(c), 1);
      at(c, 6);
      expect(caretOf(c), 4);
    });

    test('with "Show marks" on the caret stays where it is put', () {
      final c = make('x**b**y', showMarks: true);
      at(c, 2);
      expect(caretOf(c), 2);
    });

    test('a selection is left as it is', () {
      final c = make('x**b**y');
      c.selection = const TextSelection(baseOffset: 2, extentOffset: 6);
      expect(c.selection, const TextSelection(baseOffset: 2, extentOffset: 6));
    });
  });

  group('one arrow key', () {
    TextSelection move(
      MarkdownController c,
      int from, {
      bool forward = true,
      bool collapse = true,
      int? base,
    }) => c.moveByCharacter(
      TextSelection(baseOffset: base ?? from, extentOffset: from),
      forward: forward,
      collapse: collapse,
    );

    test('right steps over the marks to the next letter', () {
      final c = make('a**b**c');
      expect(move(c, 0).baseOffset, 1);
      expect(move(c, 1).baseOffset, 4);
      expect(move(c, 4).baseOffset, 7);
    });

    test('left steps back the same way', () {
      final c = make('a**b**c');
      expect(move(c, 7, forward: false).baseOffset, 4);
      expect(move(c, 4, forward: false).baseOffset, 1);
      expect(move(c, 1, forward: false).baseOffset, 0);
    });

    test('a heading line: left at the start of the words goes to the line '
        'before', () {
      final c = make('x\n## Head');
      expect(move(c, 5, forward: false).baseOffset, 1);
      expect(move(c, 1).baseOffset, 5);
    });

    test('a divider is one letter', () {
      final c = make('a\n---\nb');
      expect(move(c, 2).baseOffset, 5);
      expect(move(c, 5, forward: false).baseOffset, 2);
    });

    test('Shift selects one shown letter at a time', () {
      final c = make('a**b**c');
      final one = move(c, 1, collapse: false);
      expect(one, const TextSelection(baseOffset: 1, extentOffset: 4));
      final back = move(c, 4, base: 1, forward: false, collapse: false);
      expect(back, const TextSelection.collapsed(offset: 1));
    });

    test('an arrow on a selection goes to its edge', () {
      final c = make('a**b**c');
      final s = c.moveByCharacter(
        const TextSelection(baseOffset: 0, extentOffset: 6),
        forward: true,
        collapse: true,
      );
      expect(s, const TextSelection.collapsed(offset: 4));
    });
  });

  group('keys beside hidden marks', () {
    test('a space at the end of bold goes after its marks', () {
      final c = make('**b**');
      at(c, 3);
      type(c, ' ');
      expect(c.text, '**b** ');
      expect(caretOf(c), 6);
      type(c, 'x');
      expect(c.text, '**b x**');
    });

    test('after Bold steps out of the format the next letter is plain', () {
      final c = make('**b**');
      at(c, 3);
      c.format(EditorFormat.bold);
      expect(c.text, '**b**');
      type(c, ' ');
      type(c, 'x');
      expect(c.text, '**b** x');
    });

    test('Backspace at the start of a heading takes the mark', () {
      final c = make('x\n## Head');
      at(c, 5);
      backspace(c);
      expect(c.text, 'x\nHead');
      expect(caretOf(c), 2);
    });

    test('Backspace on the last letter of bold takes its marks too', () {
      final c = make('a **b**');
      at(c, 5);
      backspace(c);
      expect(c.text, 'a ');
    });

    test('with "Show marks" on a key deletes the mark it is on', () {
      final c = make('a **b**', showMarks: true);
      at(c, 7);
      backspace(c);
      expect(c.text, 'a **b*');
    });

    test('Backspace after a divider takes all of it', () {
      final c = make('a\n---');
      at(c, 5);
      backspace(c);
      expect(c.text, 'a\n');
    });

    test('Backspace at the start of the line after a divider takes the '
        'divider', () {
      final c = make('a\n---\nb');
      at(c, 6);
      backspace(c);
      expect(c.text, 'a\nb');
      expect(caretOf(c), 2);
    });

    test('a word that the keyboard of a phone has not done yet is left '
        'alone', () {
      final c = make('**b**');
      c.value = const TextEditingValue(
        text: '**b ',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 3, end: 4),
      );
      expect(c.text, '**b ');
    });
  });

  group('an empty format', () {
    test('Bold at a caret puts in an empty pair; typing fills it', () {
      final c = make('a ');
      at(c, 2);
      c.format(EditorFormat.bold);
      expect(c.text, 'a ****');
      expect(caretOf(c), 4);
      type(c, 'b');
      expect(c.text, 'a **b**');
    });

    test('the empty pair goes when the caret leaves it', () {
      final c = make('a ');
      at(c, 2);
      c.format(EditorFormat.bold);
      at(c, 0);
      expect(c.text, 'a ');
      expect(caretOf(c), 0);
    });

    test('an empty italic pair is hidden too, and goes when the caret '
        'leaves', () {
      final c = make('a ');
      at(c, 2);
      c.format(EditorFormat.italic);
      expect(c.text, 'a **');
      expect(c.hiddenRuns, const [Utf16Range(2, 2)]);
      at(c, 1);
      expect(c.text, 'a ');
      expect(caretOf(c), 1);
    });

    test('a space in an empty pair goes before it', () {
      final c = make('a');
      at(c, 1);
      c.format(EditorFormat.bold);
      type(c, ' ');
      expect(c.text, 'a ****');
      expect(caretOf(c), 4);
      type(c, 'b');
      expect(c.text, 'a **b**');
    });

    test('Backspace in an empty pair takes the pair', () {
      final c = make('a');
      at(c, 1);
      c.format(EditorFormat.italic);
      backspace(c);
      expect(c.text, 'a');
      expect(caretOf(c), 1);
    });

    test('Return in an empty pair takes the pair first', () {
      final c = make('a');
      at(c, 1);
      c.format(EditorFormat.bold);
      type(c, '\n');
      expect(c.text, 'a\n');
      expect(caretOf(c), 2);
    });
  });

  group('the format buttons', () {
    test('Bold, Italic and Code wrap the selection', () {
      for (final (f, out) in [
        (EditorFormat.bold, 'make **this** loud'),
        (EditorFormat.italic, 'make *this* loud'),
        (EditorFormat.code, 'make `this` loud'),
      ]) {
        final c = make('make this loud');
        c.selection = const TextSelection(baseOffset: 5, extentOffset: 9);
        c.format(f);
        expect(c.text, out, reason: '$f');
      }
    });

    test('Bold again takes it off', () {
      final c = make('make **this** loud');
      c.selection = const TextSelection(baseOffset: 7, extentOffset: 11);
      c.format(EditorFormat.bold);
      expect(c.text, 'make this loud');
    });
  });
}
