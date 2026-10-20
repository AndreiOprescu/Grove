import 'package:flutter_test/flutter_test.dart';

import 'dart:math';

import 'package:grove/core/parsing/markdown_edit.dart';
import 'package:grove/core/parsing/markdown_spans.dart';
import 'package:grove/core/parsing/note_parser.dart';
import 'package:grove/core/parsing/reference_parser.dart';

// Port of Tests/GroveCoreTests/MarkdownEditTests.swift and the "Make task"
// part of TaskMarkTests.swift.
// Text is written with the caret as `|`, or a selection between `‹` and `›`.

(String, Utf16Range) parse(String marked) {
  final open = marked.indexOf('‹'), close = marked.indexOf('›');
  if (open >= 0) {
    final text = marked.replaceAll('‹', '').replaceAll('›', '');
    return (text, Utf16Range(open, close - open - 1));
  }
  final bar = marked.indexOf('|');
  return (marked.replaceAll('|', ''), Utf16Range(bar, 0));
}

String apply(String text, TextEdit e) =>
    text.replaceRange(e.range.location, e.range.end, e.replacement);

/// Applies an edit and writes the result with the new selection marked.
/// Null when the edit does nothing.
String? run(String marked, TextEdit? Function(String, Utf16Range) op) {
  final (text, sel) = parse(marked);
  final e = op(text, sel);
  if (e == null) return null;
  final out = apply(text, e);
  final s = e.selection;
  if (s.length == 0) return out.replaceRange(s.location, s.location, '|');
  final closed = out.replaceRange(s.end, s.end, '›');
  return closed.replaceRange(s.location, s.location, '‹');
}

String? enter(String s) => run(s, (t, r) => MarkdownEdit.enter(t, r));
String? tab(String s) => run(s, (t, r) => MarkdownEdit.indent(t, r));
String? backTab(String s) =>
    run(s, (t, r) => MarkdownEdit.indent(t, r, outdent: true));
String? wrap(String marker, String s) =>
    run(s, (t, r) => MarkdownEdit.toggleWrap(marker, t, r));
String? line(LineStyle style, String s) =>
    run(s, (t, r) => MarkdownEdit.toggleLine(style, t, r));

String? inline(
  InlineFormat format,
  String s, {
  HighlightColor color = HighlightColor.yellow,
}) => run(s, (t, r) => MarkdownEdit.toggleInline(format, t, r, color: color));

/// Backspace, or forward delete, of one character at the caret. A selection is deleted whole.
String? del(String marked, {bool forward = false}) {
  final (text, sel) = parse(marked);
  final change = sel.length > 0
      ? sel
      : (forward
            ? Utf16Range(sel.location, 1)
            : Utf16Range(sel.location - 1, 1));
  return run(
    marked,
    (t, r) => MarkdownEdit.deletion(text, change, selection: sel),
  );
}

String? typed(String marked, String ch, {bool pull = true}) =>
    run(marked, (t, r) => MarkdownEdit.typed(t, r, ch, pull: pull));

/// Each shown character with the formats on it, read back from the spans.
List<(String, Set<String>)> shown(String text) {
  final spans = MarkdownSpans.scan(text);
  final marks = <int>{};
  for (final s in spans) {
    final t = s.kind.type;
    if (t == SpanType.syntax ||
        t == SpanType.emptyPair ||
        t == SpanType.headingMark ||
        t == SpanType.quoteMark) {
      for (var i = s.range.location; i < s.range.end; i++) {
        marks.add(i);
      }
    }
  }
  String? key(SpanKind k) => switch (k.type) {
    SpanType.bold => 'b',
    SpanType.italic => 'i',
    SpanType.underline => 'u',
    SpanType.strike => 's',
    SpanType.highlight => 'h:${k.color!.name}',
    SpanType.code => 'c',
    SpanType.linkWords => 'l:${k.url}',
    _ => null,
  };
  return [
    for (var i = 0; i < text.length; i++)
      if (!marks.contains(i))
        (
          text[i],
          {
            for (final s in spans)
              if (key(s.kind) != null &&
                  s.range.location <= i &&
                  i < s.range.end)
                key(s.kind)!,
          },
        ),
  ];
}

void main() {
  group('return continues a list', () {
    test('return continues lists', () {
      const table = [
        ('- one|', '- one\n- |'),
        ('* one|', '* one\n* |'),
        ('1. one|', '1. one\n2. |'),
        ('9. nine|', '9. nine\n10. |'),
        ('- [x] done|', '- [x] done\n- [ ] |'),
        ('- [ ] todo|', '- [ ] todo\n- [ ] |'),
        ('  - nested|', '  - nested\n  - |'),
        ('> quote|', '> quote\n> |'),
        ('- one|two', '- one\n- |two'),
        ('intro\n- one|', 'intro\n- one\n- |'),
      ];
      for (final (input, want) in table) {
        expect(enter(input), want, reason: 'input: $input');
      }
    });

    test('return on an empty item leaves the list', () {
      expect(enter('- |'), '|');
      expect(enter('1. |'), '|');
      expect(enter('- [ ] |'), '|');
      expect(enter('> |'), '|');
      expect(enter('a\n- |'), 'a\n|');
    });

    test('return on an empty nested item moves it one level out', () {
      expect(enter('  - |'), '- |');
      expect(enter('    1. |'), '  1. |');
    });

    test('return leaves other lines alone', () {
      expect(enter('hello|'), isNull);
      expect(enter('# Title|'), isNull);
      expect(enter('|'), isNull);
      expect(enter('- ‹one›'), isNull); // a selection gets the normal new line
      expect(enter('|- one'), isNull); // caret before the marker
    });
  });

  group('tab', () {
    test('tab indents list items', () {
      expect(tab('- a|'), '  - a|');
      expect(tab('1. a|'), '  1. a|');
      expect(tab('- [ ] a|'), '  - [ ] a|');
      expect(tab('|- a'), '  |- a');
    });

    test('back tab moves items out', () {
      expect(backTab('  - a|'), '- a|');
      expect(backTab('    - a|'), '  - a|');
      expect(backTab(' - a|'), '- a|');
      expect(backTab('- a|'), isNull);
    });

    test('tab on plain text does nothing', () {
      expect(tab('hello|'), isNull);
      expect(backTab('  hello|'), isNull);
    });

    test('tab indents every list line in a selection', () {
      expect(tab('‹- a\n- b›'), '‹  - a\n  - b›');
      expect(tab('‹- a\nplain›'), '‹  - a\nplain›');
      expect(backTab('‹  - a\n  - b›'), '‹- a\n- b›');
      // Triple-click selects the line with its newline; the next line stays.
      expect(tab('‹- a\n›- b'), '‹  - a\n›- b');
    });
  });

  group('bold, italic and code', () {
    test('wraps a selection', () {
      expect(wrap('**', 'say ‹word› now'), 'say **‹word›** now');
      expect(wrap('*', 'say ‹word› now'), 'say *‹word›* now');
      expect(wrap('`', '‹x›'), '`‹x›`');
    });

    test('wrap at a caret makes a pair and puts the caret inside', () {
      expect(wrap('**', 'say |'), 'say **|**');
      expect(wrap('*', '|'), '*|*');
    });

    test('wrap again removes the markers', () {
      expect(wrap('**', 'say **‹word›** now'), 'say ‹word› now');
      expect(wrap('*', '*‹x›*'), '‹x›');
      expect(wrap('`', '`‹x›`'), '‹x›');
      expect(wrap('**', '**|**'), '|');
      expect(
        wrap('**', '‹**x**›'),
        '‹x›',
      ); // the markers are inside the selection
    });

    test('bold and italic do not mistake each other', () {
      expect(wrap('*', '**‹x›**'), '***‹x›***'); // bold is not italic
      expect(wrap('*', '***‹x›***'), '**‹x›**'); // removes only the italic
      expect(wrap('**', '***‹x›***'), '*‹x›*'); // removes only the bold
      expect(wrap('**', '*‹x›*'), '***‹x›***');
    });

    test('wrap does not touch a list marker before the selection', () {
      expect(wrap('*', '* ‹item›'), '* *‹item›*');
    });
  });

  group('line styles', () {
    test('adds line styles', () {
      expect(line(LineStyle.bullet, 'one|'), '- one|');
      expect(line(LineStyle.numbered, 'one|'), '1. one|');
      expect(line(LineStyle.checklist, 'one|'), '- [ ] one|');
      expect(line(const LineStyle.heading(2), 'Title|'), '## Title|');
      expect(line(LineStyle.quote, 'wise|'), '> wise|');
    });

    test('toggling the same style removes it', () {
      expect(line(LineStyle.bullet, '- one|'), 'one|');
      expect(line(LineStyle.numbered, '3. one|'), 'one|');
      expect(line(LineStyle.checklist, '- [x] one|'), 'one|');
      expect(line(const LineStyle.heading(2), '## Title|'), 'Title|');
      expect(line(LineStyle.quote, '> wise|'), 'wise|');
    });

    test('a different style replaces the old one', () {
      expect(line(LineStyle.numbered, '- one|'), '1. one|');
      expect(line(LineStyle.checklist, '- one|'), '- [ ] one|');
      expect(line(LineStyle.bullet, '- [ ] one|'), '- one|');
      expect(line(const LineStyle.heading(2), '# Title|'), '## Title|');
      expect(line(LineStyle.bullet, '## Title|'), '- Title|');
    });

    test('line styles keep indentation', () {
      expect(line(LineStyle.bullet, '  one|'), '  - one|');
      expect(line(LineStyle.numbered, '  - one|'), '  1. one|');
      expect(line(LineStyle.bullet, '  - one|'), '  one|');
    });

    test('line styles apply to every line of a selection', () {
      expect(line(LineStyle.numbered, '‹a\nb\nc›'), '‹1. a\n2. b\n3. c›');
      expect(line(LineStyle.bullet, '‹- a\n- b›'), '‹a\nb›');
      // Not all had it: add to all.
      expect(line(LineStyle.bullet, '‹- a\nb›'), '‹- a\n- b›');
      // Empty lines are skipped.
      expect(line(LineStyle.bullet, '‹a\n\nb›'), '‹- a\n\n- b›');
      expect(line(LineStyle.numbered, '‹a\n\nb›'), '‹1. a\n\n2. b›');
    });

    test('line style on an empty line adds the marker', () {
      expect(line(LineStyle.bullet, '|'), '- |');
      expect(line(const LineStyle.heading(1), 'x\n|'), 'x\n# |');
    });
  });

  group('checkbox', () {
    test('clicking a checkbox flips it', () {
      String? flip(String text, int at) {
        final e = MarkdownEdit.toggleCheckbox(text, at);
        return e == null ? null : apply(text, e);
      }

      expect(flip('- [ ] a', 3), '- [x] a');
      expect(flip('- [x] a', 0), '- [ ] a');
      expect(flip('- [X] a', 6), '- [ ] a');
      expect(flip('x\n  - [ ] a', 5), 'x\n  - [x] a');
      expect(flip('- a', 0), isNull);
      expect(flip('plain', 2), isNull);
    });
  });

  group('mentions', () {
    test('finds the open mention before the caret', () {
      final (t1, s1) = parse('see [[Bu|');
      final a = MarkdownEdit.mentionTrigger(t1, s1.location)!;
      expect(a.query, 'Bu');
      expect(a.range, const Utf16Range(4, 4));

      final (t2, s2) = parse('see [[|');
      expect(MarkdownEdit.mentionTrigger(t2, s2.location)?.query, '');

      // Only the text before the caret counts.
      final (t3, s3) = parse('[[Bu|y milk');
      expect(MarkdownEdit.mentionTrigger(t3, s3.location)?.query, 'Bu');

      final (t4, s4) = parse('a\n[[two words|');
      expect(MarkdownEdit.mentionTrigger(t4, s4.location)?.query, 'two words');
    });

    test('no trigger when the mention is closed or broken', () {
      for (final marked in [
        'see [Bu|',
        '[[a]] b|',
        '[[a\n|',
        'plain|',
        '[[a]|',
      ]) {
        final (t, s) = parse(marked);
        expect(
          MarkdownEdit.mentionTrigger(t, s.location),
          isNull,
          reason: 'input: $marked',
        );
      }
    });

    test('inserting a mention replaces what was typed', () {
      const text = 'see [[Bu';
      final trigger = MarkdownEdit.mentionTrigger(text, 8)!;
      const id = '11111111-2222-3333-4444-555555555555';
      final edit = MarkdownEdit.insertMention(
        title: 'Buy milk',
        id: id,
        replacing: trigger.range,
      );
      final out = apply(text, edit);
      expect(out, 'see [[Buy milk|$id]]');
      expect(edit.selection, Utf16Range(out.length, 0));
    });

    test('inserted mention is read back by the parser', () {
      const id = '11111111-2222-3333-4444-555555555555';
      final edit = MarkdownEdit.insertMention(
        title: 'Plan [draft] | v2',
        id: id,
        replacing: const Utf16Range(0, 0),
      );
      final found = ReferenceParser.mentions(edit.replacement).first;
      expect(found.id, id);
      expect(found.title, 'Plan draft v2');
    });
  });

  group('images', () {
    const imageId = '11111111-2222-3333-4444-555555555555';
    String image(String marked) => run(
      marked,
      (t, r) => MarkdownEdit.insertImage(
        id: imageId,
        alt: 'shot',
        text: t,
        selection: r,
      ),
    )!;
    final markup = ReferenceParser.imageMarkup(id: imageId, alt: 'shot');

    test('image goes on a line of its own', () {
      expect(image('hello|'), 'hello\n$markup\n|');
      expect(image('|'), '$markup\n|');
      expect(image('ab|cd'), 'ab\n$markup\n|cd');
      expect(image('a\n|'), 'a\n$markup\n|');
    });

    test('image before an existing line break reuses it', () {
      expect(image('a\n|\nb'), 'a\n$markup\n|b');
    });

    test('image replaces a selection', () {
      expect(image('a ‹old› b'), 'a \n$markup\n| b');
    });

    test('removing an image takes its line too', () {
      const other = '99999999-2222-3333-4444-555555555555';
      final otherMarkup = ReferenceParser.imageMarkup(id: other, alt: 'other');
      String remove(String text) => MarkdownEdit.removeImage(imageId, text);
      expect(remove('a\n$markup\nb'), 'a\nb');
      expect(remove('$markup\nb'), 'b');
      expect(remove('a\n$markup'), 'a');
      expect(remove(markup), '');
      // Other text on the line stays.
      expect(remove('see $markup here'), 'see  here');
      // Other images stay.
      expect(remove('$markup\n$otherMarkup'), otherMarkup);
      expect(remove('no image'), 'no image');
    });
  });

  group('make task', () {
    const id = '11111111-2222-3333-4444-555555555555';

    test('a plain line becomes a check box with a mark', () {
      const text = 'Call Sam about the trip';
      final target = MarkdownEdit.taskTarget(text, const Utf16Range(5, 0))!;
      expect(target.title, 'Call Sam about the trip');
      final edit = MarkdownEdit.taskLine(target, text, taskId: 'T1');
      expect(edit.replacement, '- [ ] Call Sam about the trip ⟦t:T1⟧');
      expect(edit.range, const Utf16Range(0, 23));
      // The caret stays before the hidden mark.
      expect(
        edit.selection,
        Utf16Range('- [ ] Call Sam about the trip'.length, 0),
      );
    });

    test('a selection names the task and the whole line stays', () {
      const text = 'I need to call Sam about the trip';
      final sel = Utf16Range(text.indexOf('call Sam'), 'call Sam'.length);
      final target = MarkdownEdit.taskTarget(text, sel)!;
      expect(target.title, 'call Sam');
      expect(
        MarkdownEdit.taskLine(target, text, taskId: 'T1').replacement,
        '- [ ] I need to call Sam about the trip ⟦t:T1⟧',
      );
    });

    test('a bullet becomes a check box and keeps its indent', () {
      const text = 'intro\n  - Pack the bags';
      final target = MarkdownEdit.taskTarget(text, const Utf16Range(12, 0))!;
      expect(target.title, 'Pack the bags');
      final edit = MarkdownEdit.taskLine(target, text, taskId: 'T1');
      expect(edit.replacement, '  - [ ] Pack the bags ⟦t:T1⟧');
      expect(edit.range, const Utf16Range(6, 17));
    });

    test('a heading loses its hashes', () {
      const text = '## Book flights';
      final target = MarkdownEdit.taskTarget(text, const Utf16Range(0, 0))!;
      expect(
        MarkdownEdit.taskLine(target, text, taskId: 'T1').replacement,
        '- [ ] Book flights ⟦t:T1⟧',
      );
    });

    test('a check box keeps its box', () {
      const text = '- [x] Done already';
      final target = MarkdownEdit.taskTarget(text, const Utf16Range(8, 0))!;
      expect(
        MarkdownEdit.taskLine(target, text, taskId: 'T1').replacement,
        '- [x] Done already ⟦t:T1⟧',
      );
    });

    test(
      'no target for an empty line, several lines or a task that exists',
      () {
        expect(
          MarkdownEdit.taskTarget('one\n\ntwo', const Utf16Range(4, 0)),
          isNull,
        );
        expect(
          MarkdownEdit.taskTarget('- [ ] \nnext', const Utf16Range(2, 0)),
          isNull,
        );
        expect(
          MarkdownEdit.taskTarget('one\ntwo', const Utf16Range(1, 5)),
          isNull,
        );
        expect(
          MarkdownEdit.taskTarget(
            '- [ ] Buy milk ⟦t:T1⟧',
            const Utf16Range(8, 0),
          ),
          isNull,
        );
      },
    );

    test(
      'the line is found when it is the last one or has a Windows break',
      () {
        final last = MarkdownEdit.taskTarget(
          'a\nLast line',
          const Utf16Range(11, 0),
        )!;
        expect(last.title, 'Last line');
        expect(last.line, const Utf16Range(2, 9));
        final crlf = MarkdownEdit.taskTarget(
          'First\r\nSecond',
          const Utf16Range(1, 0),
        )!;
        expect(crlf.line, const Utf16Range(0, 5));
      },
    );

    test('the new line is a readable check box with a task', () {
      const text = 'Call Sam';
      final target = MarkdownEdit.taskTarget(text, const Utf16Range(0, 0))!;
      final edit = MarkdownEdit.taskLine(target, text, taskId: id);
      expect(NoteParser.checkboxes(edit.replacement), [
        const NoteCheckbox(
          line: 0,
          checked: false,
          text: 'Call Sam',
          taskId: id,
        ),
      ]);
    });
  });

  group('line prefix', () {
    test('reads each kind of line start', () {
      expect(MarkdownEdit.prefix('  - [x] a')?.kind, PrefixKind.checklist);
      expect(MarkdownEdit.prefix('  - [x] a')?.checked, isTrue);
      expect(MarkdownEdit.prefix('  - [x] a')?.length, 8);
      expect(MarkdownEdit.prefix('12. a')?.number, 12);
      expect(MarkdownEdit.prefix('### a')?.level, 3);
      expect(MarkdownEdit.prefix('> a')?.kind, PrefixKind.quote);
      expect(MarkdownEdit.prefix('plain'), isNull);
    });
  });
  group('formats on a selection', () {
    const b = InlineFormat.bold;
    test('wraps the selected words in each mark', () {
      expect(inline(b, 'say ‹word› now'), 'say **‹word›** now');
      expect(inline(InlineFormat.italic, 'a ‹b c› d'), 'a *‹b c›* d');
      expect(inline(InlineFormat.strike, 'a ‹b c› d'), 'a ~~‹b c›~~ d');
      expect(inline(InlineFormat.underline, 'a ‹b c› d'), 'a <u>‹b c›</u> d');
      expect(inline(InlineFormat.highlight, 'a ‹b c› d'), 'a ==‹b c›== d');
      expect(inline(InlineFormat.code, 'a ‹b c› d'), 'a `‹b c›` d');
    });

    test('spaces at the edges stay outside the marks', () {
      expect(inline(b, 'say‹ word ›now'), 'say‹ **word** ›now');
    });

    test('a second press takes the format off', () {
      expect(inline(b, 'say **‹word›** now'), 'say ‹word› now');
      expect(inline(b, '‹**x**›'), '‹x›');
      expect(inline(InlineFormat.strike, '~~‹x›~~'), '‹x›');
    });

    test('a mixed selection gets the format everywhere', () {
      expect(inline(b, '‹**a** b›'), '**‹a b›**');
    });

    test('taking it off part of a format splits it', () {
      expect(inline(b, '**a ‹b› c**'), '**a** ‹b› **c**');
    });

    test('touching formats merge', () {
      expect(inline(b, '**a**‹ b ›**c**'), '**a‹ b ›c**');
      expect(inline(b, '**a**‹b›'), '**a‹b›**');
    });

    test('each line gets its own marks, line starts stay', () {
      expect(inline(b, '‹one\ntwo›'), '**‹one**\n**two›**');
      expect(inline(b, '- ‹a\n- b›'), '- **‹a**\n- **b›**');
    });

    test('formats that cross are written so they read back', () {
      expect(inline(InlineFormat.strike, '**a ‹b** c›'), '**a ~~‹b~~** ~~c›~~');
    });

    test('a highlight changes colour, the same colour takes it off', () {
      expect(
        inline(InlineFormat.highlight, '==‹hi›==', color: HighlightColor.green),
        '=={green}‹hi›==',
      );
      expect(inline(InlineFormat.highlight, '==‹hi›=='), '‹hi›');
      expect(
        inline(
          InlineFormat.highlight,
          '=={pink}‹hi›==',
          color: HighlightColor.pink,
        ),
        '‹hi›',
      );
    });

    test('a selection of only spaces does nothing', () {
      expect(inline(b, 'a‹ ›b'), isNull);
    });

    test('formats read back as asked after many presses', () {
      final rnd = Random(7);
      const formats = [
        InlineFormat.bold,
        InlineFormat.italic,
        InlineFormat.underline,
        InlineFormat.strike,
        InlineFormat.highlight,
      ];
      String keyOf(InlineFormat f, HighlightColor c) => switch (f) {
        InlineFormat.bold => 'b',
        InlineFormat.italic => 'i',
        InlineFormat.underline => 'u',
        InlineFormat.strike => 's',
        InlineFormat.highlight => 'h:${c.name}',
        InlineFormat.code => 'c',
      };
      var done = 0;
      for (var round = 0; round < 40; round++) {
        var text = List.generate(
          4 + rnd.nextInt(4),
          (_) => ['ab', 'cd', 'e', 'fgh', 'ij'][rnd.nextInt(5)],
        ).join(' ');
        for (var step = 0; step < 8; step++) {
          final before = shown(text);
          final a = rnd.nextInt(text.length + 1);
          final z = rnd.nextInt(text.length + 1);
          final sel = Utf16Range(a < z ? a : z, (a - z).abs());
          if (sel.length == 0) continue;
          final f = formats[rnd.nextInt(formats.length)];
          final c = HighlightColor.values[rnd.nextInt(4)];
          final e = MarkdownEdit.toggleInline(f, text, sel, color: c);
          if (e == null) continue;
          final out = apply(text, e);
          final after = shown(out);
          final why = '"$text" $sel $f $c -> "$out"';
          expect(
            after.map((u) => u.$1).join(),
            before.map((u) => u.$1).join(),
            reason: why,
          );
          // Which shown letters were picked, by their place among the shown letters.
          final picked = <int>{};
          var n = 0;
          final spans = MarkdownSpans.scan(text);
          final marks = <int>{
            for (final s in spans)
              if (s.kind.type == SpanType.syntax ||
                  s.kind.type == SpanType.emptyPair)
                for (var i = s.range.location; i < s.range.end; i++) i,
          };
          for (var i = 0; i < text.length; i++) {
            if (marks.contains(i)) continue;
            if (sel.location <= i && i < sel.end) picked.add(n);
            n += 1;
          }
          final key = keyOf(f, c);
          final letters = [
            for (final i in picked)
              if (before[i].$1.trim().isNotEmpty) i,
          ];
          if (letters.isEmpty) continue;
          final on = after[letters.first].$2.contains(key);
          for (var i = 0; i < before.length; i++) {
            if (before[i].$1.trim().isEmpty) continue;
            if (letters.contains(i)) {
              expect(after[i].$2.contains(key), on, reason: why);
              final others = after[i].$2.where((k) => k[0] != key[0]).toSet();
              final had = before[i].$2.where((k) => k[0] != key[0]).toSet();
              expect(others, had, reason: why);
            } else {
              expect(after[i].$2, before[i].$2, reason: why);
            }
          }
          text = out;
          done += 1;
        }
      }
      expect(done, greaterThan(100));
    });
  });

  group('formats at a caret', () {
    const b = InlineFormat.bold;
    test('a caret in a word works on the whole word', () {
      expect(inline(b, 'say wo|rd now'), 'say **wo|rd** now');
      expect(inline(b, '**wo|rd**'), 'wo|rd');
    });

    test('at the edge of a format the caret steps out', () {
      expect(inline(b, '**word|** x'), '**word**| x');
      expect(inline(b, 'x **|word**'), 'x |**word**');
    });

    test('just outside a format the caret steps in', () {
      expect(inline(b, '**word**| x'), '**word|** x');
    });

    test('in the middle beside a space the format splits', () {
      expect(inline(b, '**a |b**'), '**a** |**b**');
    });

    test('anywhere else an empty pair goes in with the caret inside', () {
      expect(inline(b, 'say |'), 'say **|**');
      expect(inline(InlineFormat.italic, 'say |'), 'say *|*');
      expect(inline(InlineFormat.underline, 'say |'), 'say <u>|</u>');
      expect(inline(InlineFormat.strike, 'say |'), 'say ~~|~~');
      expect(inline(InlineFormat.highlight, 'say |'), 'say ==|==');
      expect(
        inline(InlineFormat.highlight, 'say |', color: HighlightColor.green),
        'say =={green}|==',
      );
      expect(inline(InlineFormat.code, 'say |'), 'say `|`');
    });

    test('a second press takes the empty pair away', () {
      expect(inline(b, 'say **|**'), 'say |');
      expect(inline(InlineFormat.strike, 'say ~~|~~'), 'say |');
    });

    test('another highlight colour at an edge starts after it', () {
      expect(
        inline(InlineFormat.highlight, '==hi|==', color: HighlightColor.green),
        '==hi===={green}|==',
      );
    });
  });

  group('headings', () {
    String? heading(int level, String s) =>
        run(s, (t, r) => MarkdownEdit.setHeading(level, t, r));

    test('sets, changes and takes off the heading mark', () {
      expect(heading(2, '|Title'), '## |Title');
      expect(heading(3, '# |Title'), '### |Title');
      expect(heading(0, '## |Title'), '|Title');
      expect(heading(1, '> |wise'), '# |wise');
      expect(heading(1, '‹a\nb›'), '‹# a\n# b›');
    });

    test('lists and lines already right are left alone', () {
      expect(heading(2, '- |item'), isNull);
      expect(heading(0, '|plain'), isNull);
      expect(heading(2, '## |same'), isNull);
    });
  });

  group('clear formats', () {
    String? clear(String s) => run(s, (t, r) => MarkdownEdit.clearInline(t, r));

    test('takes off every format and the heading or quote mark', () {
      expect(
        clear('‹**a** ~~b~~ ==c== [d](https://x.y) `e` <u>f</u>›'),
        '‹a b c d e f›',
      );
      expect(clear('## ‹**Title**›'), '‹Title›');
      expect(clear('> ‹*wise*›'), '‹wise›');
    });

    test('list and checklist marks stay', () {
      expect(clear('- [ ] ‹**buy**›'), '- [ ] ‹buy›');
      expect(clear('1. ‹*one*›'), '1. ‹one›');
    });

    test('a caret clears its whole line', () {
      expect(clear('**a** b|\n*c*'), 'a b|\n*c*');
    });

    test('nothing to clear does nothing', () {
      expect(clear('‹plain›'), isNull);
    });
  });

  group('links', () {
    String? link(String s, String url, {String? words}) =>
        run(s, (t, r) => MarkdownEdit.setLink(url, t, r, words: words));
    String? unlink(String s) => run(s, (t, r) => MarkdownEdit.removeLink(t, r));

    test('the selected words become a link', () {
      expect(
        link('see ‹docs› now', 'https://a.b'),
        'see [docs](https://a.b)| now',
      );
      expect(
        link('‹**big** news›', 'https://a.b'),
        '[**big** news](https://a.b)|',
      );
    });

    test('an address without a scheme gets https', () {
      expect(link('‹docs›', 'a.b/c'), '[docs](https://a.b/c)|');
    });

    test('at a caret the words or the address go in', () {
      expect(
        link('see |', 'https://a.b', words: 'docs'),
        'see [docs](https://a.b)|',
      );
      expect(link('|', 'https://a.b'), '[https://a.b](https://a.b)|');
    });

    test('a caret in a link changes its address', () {
      expect(
        link('[do|cs](https://old.x) z', 'https://a.b'),
        '[docs](https://a.b)| z',
      );
    });

    test('an address with a space is refused', () {
      expect(link('‹docs›', 'https://a b'), isNull);
      expect(link('‹docs›', ''), isNull);
    });

    test('remove keeps the words', () {
      expect(unlink('see [do|cs](https://a.b) now'), 'see do|cs now');
      expect(unlink('‹[a](https://a.b) and [b](https://c.d)›'), '‹a and b›');
      expect(unlink('no |link'), isNull);
    });

    test('the link at a place', () {
      const text = 'a [b](https://c.d) e';
      expect(MarkdownEdit.linkAt(text, 3)?.kind.url, 'https://c.d');
      expect(MarkdownEdit.linkAt(text, 0), isNull);
    });
  });

  group('divider', () {
    String? divider(String s) =>
        run(s, (t, r) => MarkdownEdit.insertDivider(t, r));

    test('goes on a line of its own, the caret on the next line', () {
      expect(divider('a|'), 'a\n---\n|');
      expect(divider('|'), '---\n|');
      expect(divider('a|\nb'), 'a\n---\n|b');
      expect(divider('a\n|'), 'a\n---\n|');
    });
  });

  group('deleting around marks', () {
    test('deleting the last letter of a format takes its marks', () {
      expect(del('**a|**'), '|');
      expect(del('x **a**| y'), 'x | y');
      expect(del('|**a** b', forward: true), '| b');
      expect(del('x **‹a›** y'), 'x | y');
    });

    test('a key on a mark deletes the nearest letter instead', () {
      expect(del('**ab**|'), '**a|**');
      expect(del('|**ab**', forward: true), '**|b**');
    });

    test('a range keeps the marks of a format that keeps letters', () {
      expect(del('**a‹b** c›'), '**a|**');
    });

    test('an empty pair goes whole', () {
      expect(del('a ****|'), 'a |');
    });

    test('normal deletes are left to the editor', () {
      expect(del('ab|'), isNull);
      expect(del('**ab|**'), isNull);
    });

    test('backspace at the start of a line takes the line mark', () {
      expect(del('## |Title'), '|Title');
      expect(del('> |q'), '|q');
      expect(del('  - |a'), '- |a');
      expect(del('- |a'), '|a');
      expect(del('- [ ] |buy ⟦t:ID⟧'), '|buy ⟦t:ID⟧');
    });

    test(
      'backspace at the start of a plain line joins it to the line before',
      () {
        // A plain join is the editor's own work.
        expect(del('a\n|b'), isNull);
        expect(del('a\n**|b**'), 'a|**b**');
        expect(del('- [ ] a ⟦t:ID⟧\n|b'), '- [ ] a|b ⟦t:ID⟧');
      },
    );

    test('backspace at the very start does nothing', () {
      expect(del('|a'), '|a');
      expect(del('**|a**'), '**|a**');
    });

    test('a task mark still stays', () {
      expect(del('- [ ] a ⟦t:ID⟧|'), '- [ ] | ⟦t:ID⟧');
    });
  });

  group('typing beside marks', () {
    test('a space at the end of a format goes outside it', () {
      expect(typed('**a|**', ' '), '**a** |');
      expect(typed('~~**a|**~~', ' '), '~~**a**~~ |');
    });

    test('the next letter pulls the format forward', () {
      expect(typed('**a** |', 'b'), '**a b|**');
      expect(typed('**a**  |', 'b'), '**a  b|**');
      expect(typed('- [ ] **a** | ⟦t:ID⟧', 'b'), '- [ ] **a b|** ⟦t:ID⟧');
    });

    test('no pull when asked, or when words follow', () {
      expect(typed('**a** |', 'b', pull: false), isNull);
      expect(typed('**a** | x', 'b'), isNull);
    });

    test('other typing is left to the editor', () {
      expect(typed('`a|`', ' '), isNull);
      expect(typed('**a|**', 'b'), isNull);
      expect(typed('a |', 'b'), isNull);
    });
  });

  group('keepingTaskMarks', () {
    const id = 'T1';
    final mark = NoteParser.marker(id);

    test('a box that lost its mark gets it back', () {
      expect(
        MarkdownEdit.keepingTaskMarks('a\n- [ ] buy $mark', 'a\n- [ ] buy'),
        'a\n- [ ] buy $mark',
      );
      expect(
        MarkdownEdit.keepingTaskMarks('- [x] buy $mark', '- [ ] buy'),
        '- [ ] buy $mark',
      );
    });

    test(
      'a box with other words, or a line that is no box, stays as it is',
      () {
        expect(
          MarkdownEdit.keepingTaskMarks('- [ ] buy milk $mark', '- [ ] buy'),
          '- [ ] buy',
        );
        expect(MarkdownEdit.keepingTaskMarks('- [ ] buy $mark', 'buy'), 'buy');
      },
    );

    test('a mark that the text still has elsewhere is not put twice', () {
      expect(
        MarkdownEdit.keepingTaskMarks(
          '- [ ] buy $mark',
          '- [ ] buy\n- [ ] buy $mark',
        ),
        '- [ ] buy\n- [ ] buy $mark',
      );
    });

    test('a box that has its own mark keeps it', () {
      final other = NoteParser.marker('T2');
      expect(
        MarkdownEdit.keepingTaskMarks('- [ ] buy $mark', '- [ ] buy $other'),
        '- [ ] buy $other',
      );
    });
  });
}
