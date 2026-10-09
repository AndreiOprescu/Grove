import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/parsing/markdown_edit.dart';
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
}
