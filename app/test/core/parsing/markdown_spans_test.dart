import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/parsing/markdown_spans.dart';
import 'package:grove/core/parsing/note_parser.dart';

// Port of Tests/GroveCoreTests/MarkdownSpansTests.swift and the span part of
// TaskMarkTests.swift.
void main() {
  const id = '11111111-2222-3333-4444-555555555555';

  String cut(String text, Utf16Range r) => text.substring(r.location, r.end);

  /// The text covered by every span that `pick` accepts, in order.
  List<String> found(
    String text,
    bool Function(SpanKind) pick, {
    Utf16Range? range,
  }) => MarkdownSpans.scan(
    text,
    range: range,
  ).where((s) => pick(s.kind)).map((s) => cut(text, s.range)).toList();

  bool Function(SpanKind) isType(SpanType t) =>
      (k) => k.type == t;
  bool Function(SpanKind) isKind(SpanKind want) =>
      (k) => k == want;

  group('lines', () {
    test('headings', () {
      expect(found('## Title', isType(SpanType.heading)), ['## Title']);
      expect(found('## Title', isKind(SpanKind.headingMark)), ['## ']);
      expect(
        MarkdownSpans.scan('### x')
            .any((s) => s.kind == const SpanKind.heading(3)),
        isTrue,
      );
      expect(found('####### seven', isType(SpanType.heading)), isEmpty);
      expect(found('#nospace', isType(SpanType.heading)), isEmpty);
    });

    test('list marks', () {
      expect(found('- one', isKind(SpanKind.listMark)), ['- ']);
      expect(found('- one', isKind(SpanKind.listPrefix)), ['- ']);
      expect(found('  1. two', isKind(SpanKind.listMark)), ['1. ']);
      expect(found('  1. two', isKind(SpanKind.listPrefix)), ['  1. ']);
      expect(found('* star', isKind(SpanKind.listMark)), ['* ']);
      expect(found('plain', isKind(SpanKind.listMark)), isEmpty);
    });

    test('checklists', () {
      expect(
        found(
          '- [x] done thing',
          isKind(const SpanKind.checkbox(checked: true)),
        ),
        ['[x]'],
      );
      expect(
        found('- [ ] todo', isKind(const SpanKind.checkbox(checked: false))),
        ['[ ]'],
      );
      expect(found('- [X] done thing', isKind(SpanKind.checkedText)), [
        'done thing',
      ]);
      expect(found('- [ ] todo', isKind(SpanKind.checkedText)), isEmpty);
      expect(found('  - [ ] nested', isKind(SpanKind.listPrefix)), [
        '  - [ ] ',
      ]);
      expect(found('- [ ] todo', isType(SpanType.checkbox)), ['[ ]']);
    });

    test('quotes', () {
      expect(found('> wise words', isKind(SpanKind.quote)), ['> wise words']);
      expect(found('> wise words', isKind(SpanKind.quoteMark)), ['> ']);
    });
  });

  group('inline text', () {
    test('bold, italic and code', () {
      expect(found('a **b** c', isKind(SpanKind.bold)), ['b']);
      expect(found('a **b** c', isKind(SpanKind.syntax)), ['**', '**']);
      expect(found('a *b* c', isKind(SpanKind.italic)), ['b']);
      expect(found('use `x` now', isKind(SpanKind.code)), ['x']);
      expect(found('use `x` now', isKind(SpanKind.syntax)), ['`', '`']);
    });

    test('triple stars are bold and italic', () {
      expect(found('***x***', isKind(SpanKind.bold)), ['x']);
      expect(found('***x***', isKind(SpanKind.italic)), ['x']);
      expect(found('***x***', isKind(SpanKind.syntax)), ['***', '***']);
    });

    test('italic can sit inside bold', () {
      expect(found('**a *b* c**', isKind(SpanKind.bold)), ['a *b* c']);
      expect(found('**a *b* c**', isKind(SpanKind.italic)), ['b']);
    });

    test('stars that do not make emphasis are left alone', () {
      expect(found('2 * 3 * 4', isKind(SpanKind.italic)), isEmpty);
      expect(found('a ** b ** c', isKind(SpanKind.bold)), isEmpty);
      expect(found('lone * star', isKind(SpanKind.italic)), isEmpty);
      expect(found('**unclosed', isKind(SpanKind.bold)), isEmpty);
    });

    test('code keeps its content literal', () {
      expect(found('use `**x**` now', isKind(SpanKind.bold)), isEmpty);
      expect(found('`[[A|$id]]`', isType(SpanType.mention)), isEmpty);
    });

    test('emphasis does not cross lines', () {
      expect(found('**a\nb**', isKind(SpanKind.bold)), isEmpty);
    });

    test('list marker star is not italic', () {
      expect(found('* one *two*', isKind(SpanKind.italic)), ['two']);
    });
  });

  group('mentions and images', () {
    test('mention with id hides the brackets and the id', () {
      const text = 'see [[Buy milk|$id]] ok';
      expect(found(text, isType(SpanType.mention)), ['[[Buy milk|$id]]']);
      expect(found(text, isKind(SpanKind.hidden)), ['[[', '|$id]]']);
      final m = MarkdownSpans.scan(text)
          .firstWhere((s) => s.kind.type == SpanType.mention);
      expect(m.kind, const SpanKind.mention(id: id, title: 'Buy milk'));
    });

    test('mention without id still becomes a chip', () {
      const text = 'see [[Buy milk]]';
      expect(found(text, isType(SpanType.mention)), ['[[Buy milk]]']);
      expect(found(text, isKind(SpanKind.hidden)), ['[[', ']]']);
      final m = MarkdownSpans.scan(text)
          .firstWhere((s) => s.kind.type == SpanType.mention);
      expect(m.kind, const SpanKind.mention(title: 'Buy milk'));
    });

    test('emphasis can wrap a mention', () {
      const text = '**[[A|$id]]**';
      expect(found(text, isKind(SpanKind.bold)), ['[[A|$id]]']);
      expect(found(text, isType(SpanType.mention)), ['[[A|$id]]']);
    });

    test('image hides its markup', () {
      const text = '![front door](grove-image:$id)';
      expect(found(text, isType(SpanType.image)), [text]);
      expect(found(text, isKind(SpanKind.hidden)), [
        '![',
        '](grove-image:$id)',
      ]);
      final m = MarkdownSpans.scan(text)
          .firstWhere((s) => s.kind.type == SpanType.image);
      expect(m.kind, const SpanKind.image(id));
    });

    test('image without alt only hides the address', () {
      const text = '![](grove-image:$id)';
      expect(found(text, isKind(SpanKind.hidden)), ['(grove-image:$id)']);
    });

    test('tags and links', () {
      expect(found('call #home now', isKind(SpanKind.tag)), ['#home']);
      expect(found('#home', isKind(SpanKind.tag)), ['#home']);
      expect(found('a#b', isKind(SpanKind.tag)), isEmpty);
      expect(found('# Title', isKind(SpanKind.tag)), isEmpty);
      expect(found('see https://example.com/x, ok', isType(SpanType.link)), [
        'https://example.com/x',
      ]);
      final link = MarkdownSpans.scan('go (https://a.b/c).')
          .firstWhere((s) => s.kind.type == SpanType.link);
      expect(link.kind, const SpanKind.link('https://a.b/c'));
    });

    test('an @date is marked where it can go to the planner', () {
      expect(found('Lunch @fri 12:30 at the cafe', isKind(SpanKind.atDate)), [
        '@fri 12:30',
      ]);
      expect(found('- [ ] Call Sam @tomorrow 3pm', isKind(SpanKind.atDate)), [
        '@tomorrow 3pm',
      ]);
      expect(found('Café ☕\nCall @mon 9am', isKind(SpanKind.atDate)), [
        '@mon 9am',
      ]);
      expect(found('Ask @sam about it', isKind(SpanKind.atDate)), isEmpty);
      expect(found('mail sam@fri.com', isKind(SpanKind.atDate)), isEmpty);
      expect(
        found('Code `@fri 3pm` stays plain', isKind(SpanKind.atDate)),
        isEmpty,
      );
    });
  });

  group('positions', () {
    test('ranges are UTF-16 offsets in the whole text', () {
      const text = 'a\n**b**';
      final bold = MarkdownSpans.scan(text)
          .firstWhere((s) => s.kind == SpanKind.bold);
      expect(bold.range, const Utf16Range(4, 1));
      expect(cut(text, bold.range), 'b');
      // An emoji is two UTF-16 units.
      final emoji = MarkdownSpans.scan('😀 **b**')
          .firstWhere((s) => s.kind == SpanKind.bold);
      expect(emoji.range, const Utf16Range(5, 1));
    });

    test('scanning a range only reads the lines it touches', () {
      const text = '**a**\n**b**\n**c**';
      expect(found(text, isKind(SpanKind.bold)), ['a', 'b', 'c']);
      expect(
        found(text, isKind(SpanKind.bold), range: const Utf16Range(7, 1)),
        ['b'],
      );
      final spans = MarkdownSpans.scan(text, range: const Utf16Range(7, 1));
      expect(
        spans.firstWhere((s) => s.kind == SpanKind.bold).range.location,
        8,
      );
    });

    test('empty text has no spans', () {
      expect(MarkdownSpans.scan(''), isEmpty);
      expect(MarkdownSpans.scan('\n\n'), isEmpty);
    });

    test('a Windows line break ends a line', () {
      expect(found('**a**\r\n**b**', isKind(SpanKind.bold)), ['a', 'b']);
    });
  });

  group('chips behave as one character', () {
    const text = 'a [[B|$id]] c';
    const start = 2, end = 2 + '[[B|$id]]'.length;
    final s = MarkdownSpans.scan(text);

    test('a caret inside a chip moves to its edge', () {
      expect(
        MarkdownSpans.snapped(const Utf16Range(start + 3, 0), s),
        const Utf16Range(end, 0),
      );
      expect(
        MarkdownSpans.snapped(
          const Utf16Range(start + 3, 0),
          s,
          movingForward: false,
        ),
        const Utf16Range(start, 0),
      );
      // The edges are fine as they are.
      expect(
        MarkdownSpans.snapped(const Utf16Range(start, 0), s),
        const Utf16Range(start, 0),
      );
      expect(
        MarkdownSpans.snapped(const Utf16Range(end, 0), s),
        const Utf16Range(end, 0),
      );
    });

    test('a selection grows to whole chips', () {
      expect(
        MarkdownSpans.snapped(const Utf16Range(start + 2, 3), s),
        const Utf16Range(start, end - start),
      );
      expect(
        MarkdownSpans.snapped(const Utf16Range(0, 4), s),
        const Utf16Range(0, end),
      );
    });

    test('deleting part of a chip deletes the whole chip', () {
      const whole = Utf16Range(start, end - start);
      // Backspace after it, then Delete before it.
      expect(MarkdownSpans.expanded(const Utf16Range(end - 1, 1), s), whole);
      expect(MarkdownSpans.expanded(const Utf16Range(start, 1), s), whole);
      expect(
        MarkdownSpans.expanded(const Utf16Range(start - 1, 3), s),
        const Utf16Range(start - 1, end - start + 1),
      );
      expect(
        MarkdownSpans.expanded(const Utf16Range(0, 1), s),
        const Utf16Range(0, 1),
      );
      expect(
        MarkdownSpans.expanded(const Utf16Range(end, 1), s),
        const Utf16Range(end, 1),
      );
    });

    test('typing inside a chip lands after it', () {
      const chip = '[[B|$id]]';
      final cs = MarkdownSpans.scan(chip);
      expect(
        MarkdownSpans.expanded(const Utf16Range(3, 0), cs),
        Utf16Range(chip.length, 0),
      );
      expect(
        MarkdownSpans.expanded(const Utf16Range(0, 0), cs),
        const Utf16Range(0, 0),
      );
    });
  });

  group('task mark', () {
    String mark(String id) => NoteParser.marker(id);
    List<String> marks(String text) => found(text, isKind(SpanKind.taskMark));

    test('the mark is a span with its space', () {
      expect(marks('- [ ] Buy milk ${mark('T1')}'), [' ⟦t:T1⟧']);
    });

    test('a mark is one unit for the caret', () {
      final text = '- [ ] Buy milk ${mark('T1')}';
      final spans = MarkdownSpans.scan(text);
      final at = text.indexOf('⟦');
      // A caret inside the mark moves to an edge.
      final snapped = MarkdownSpans.snapped(Utf16Range(at + 2, 0), spans);
      expect(snapped.length, 0);
      expect([at - 1, text.length], contains(snapped.location));
      // A change that touches the mark takes all of it.
      expect(
        MarkdownSpans.expanded(Utf16Range(at + 1, 1), spans),
        Utf16Range(at - 1, text.length - (at - 1)),
      );
    });

    test('a text without marks has no mark span', () {
      expect(marks('- [ ] Buy milk'), isEmpty);
      expect(marks('⟦t:⟧ and ⟦x:1⟧'), isEmpty);
    });

    test('a mark inside code is plain text', () {
      expect(marks('- [ ] see `${mark('T1')}`'), isEmpty);
    });

    test('the mark does not change the other spans', () {
      final kinds = MarkdownSpans.scan('- [x] Buy milk #home ${mark('T1')}')
          .map((s) => s.kind);
      expect(kinds, contains(SpanKind.listPrefix));
      expect(kinds, contains(SpanKind.tag));
      expect(kinds, contains(SpanKind.checkedText));
      expect(kinds, contains(SpanKind.taskMark));
    });

    MarkDeletion delete(String text, Utf16Range change, {String with_ = ''}) =>
        MarkdownSpans.deletionBesideMark(
          change,
          replacement: with_,
          spans: MarkdownSpans.scan(text),
          text: text,
        );

    test('backspace after the mark deletes the letter before it', () {
      final text = '- [ ] Buy milk ${mark('T1')}';
      final result = delete(text, Utf16Range(text.length - 1, 1));
      // "Buy milk" ends before the space that belongs to the mark.
      final k = text.indexOf('milk') + 3;
      expect(result, MarkDeletion.redirect(Utf16Range(k, 1)));
    });

    test('backspace with nothing to delete does nothing', () {
      final text = '- [ ] ${mark('T1')}';
      expect(
        delete(text, Utf16Range(text.length - 1, 1)),
        MarkDeletion.swallow,
      );
    });

    test('forward delete before the mark deletes the line break', () {
      final text = '- [ ] Buy milk ${mark('T1')}\nNext';
      final start = text.indexOf(' ⟦');
      expect(
        delete(text, Utf16Range(start, 1)),
        MarkDeletion.redirect(Utf16Range(text.indexOf('\n'), 1)),
      );
    });

    test('forward delete at the end of the text does nothing', () {
      final text = '- [ ] Buy milk ${mark('T1')}';
      final start = text.indexOf(' ⟦');
      expect(delete(text, Utf16Range(start, 1)), MarkDeletion.swallow);
    });

    test('other edits are left alone', () {
      final text = '- [ ] Buy milk ${mark('T1')}';
      expect(delete(text, const Utf16Range(8, 1)), MarkDeletion.unchanged);
      expect(
        delete(text, Utf16Range(text.length - 1, 1), with_: 'x'),
        MarkDeletion.unchanged,
      );
      expect(delete(text, const Utf16Range(8, 3)), MarkDeletion.unchanged);
    });
  });
}
