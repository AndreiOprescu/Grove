// Port of Tests/GroveTests/NotesRulesTests.swift.
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

Note note(
  String title, {
  NoteKind kind = NoteKind.note,
  bool pinned = false,
  String body = '',
}) => Note(title: title, body: body, kind: kind, pinned: pinned);

void main() {
  test('daily title', () {
    expect(
      NotesRules.dailyTitle(const DayKey('2026-10-02')),
      'Friday, 2 October 2026',
    );
    expect(
      NotesRules.dailyTitle(const DayKey('2026-12-31')),
      'Thursday, 31 December 2026',
    );
  });

  test('weekly title', () {
    expect(
      NotesRules.weeklyTitle(const DayKey('2026-09-28')),
      'Week 40 · 28 Sep – 4 Oct',
    );
    expect(
      NotesRules.weeklyTitle(const DayKey('2026-10-26')),
      'Week 44 · 26 Oct – 1 Nov',
    );
  });

  test('week numbers follow the calendar week', () {
    // Belongs to week 1 of 2025.
    expect(NotesRules.weekNumber(const DayKey('2024-12-30')), 1);
    expect(NotesRules.weekNumber(const DayKey('2026-01-05')), 2);
    expect(NotesRules.weekNumber(const DayKey('2026-12-28')), 53);
  });

  test('templates', () {
    expect(
      NotesRules.template(NoteKind.daily),
      '## Plan\n\n## Notes\n\n## Reflection\n',
    );
    expect(
      NotesRules.template(NoteKind.weekly),
      '## Goals\n\n## Notes\n\n## Review\n',
    );
    expect(NotesRules.template(NoteKind.note), '');
  });

  test('filters', () {
    final a = note('A', kind: NoteKind.daily);
    final b = note('B', kind: NoteKind.weekly);
    final c = note('C', pinned: true);
    final d = note('D');
    final all = [a, b, c, d];
    List<String> none(String _) => const [];
    List<String> names(NoteFilter f, List<String> Function(String) tagsOf) => [
      for (final n in NotesRules.filter(all, f, tagsOf: tagsOf)) n.title,
    ];
    expect(NotesRules.filter(all, NoteFilter.all, tagsOf: none).length, 4);
    expect(names(NoteFilter.daily, none), ['A']);
    expect(names(NoteFilter.weekly, none), ['B']);
    expect(names(NoteFilter.pinned, none), ['C']);
    // Any letter case.
    expect(
      names(
        const NoteFilter.tag('work'),
        (id) => id == d.id ? const ['Work'] : const [],
      ),
      ['D'],
    );
  });

  test('preview skips headings and marks', () {
    expect(
      NotesRules.preview(
        '## Plan\n\nCall **Sam** about '
        '[[Trip|2D6F1B1C-0000-4000-8000-000000000000]]\nmore',
      ),
      'Call Sam about Trip',
    );
    expect(NotesRules.preview('# Only a heading\n\n'), '');
    expect(NotesRules.preview('- [ ] Pack bags ⟦t:A⟧'), 'Pack bags');
    expect(NotesRules.preview('![pic](grove-image:X)\nHello'), 'Hello');
  });

  test('preview drops the new marks and divider lines', () {
    expect(
      NotesRules.preview('---\n~~Old~~ <u>new</u> ==plan=='),
      'Old new plan',
    );
    expect(
      NotesRules.preview('> read [the docs](https://a.b) *now*'),
      'read the docs now',
    );
    expect(NotesRules.preview('a == b'), 'a == b');
  });

  test('preview is short', () {
    final long = 'word ' * 60;
    expect(NotesRules.preview(long).runes.length, lessThanOrEqualTo(91));
  });

  test('copy titles', () {
    expect(NotesRules.copyTitle('Ideas', existing: {'Ideas'}), 'Ideas copy');
    expect(
      NotesRules.copyTitle('Ideas', existing: {'Ideas', 'Ideas copy'}),
      'Ideas copy 2',
    );
    expect(
      NotesRules.copyTitle(
        'Ideas',
        existing: {'Ideas', 'Ideas copy', 'Ideas copy 2'},
      ),
      'Ideas copy 3',
    );
  });

  test('new titles do not repeat', () {
    expect(NotesRules.untitled(existing: {}), 'Untitled');
    expect(
      NotesRules.untitled(existing: {'Untitled', 'untitled 2'}),
      'Untitled 3',
    );
  });

  group('an empty daily note', () {
    const template = '## Plan\n\n## Notes\n\n## Reflection\n';
    Note daily(String body, {int? mood, bool pinned = false}) => Note(
      title: 'Friday',
      body: body,
      kind: NoteKind.daily,
      date: const DayKey('2026-10-02'),
      mood: mood,
      pinned: pinned,
    );

    test('the template, blank lines and spaces are empty', () {
      expect(
        NotesRules.isEmptyDaily(daily(template), template: template),
        isTrue,
      );
      expect(NotesRules.isEmptyDaily(daily(''), template: template), isTrue);
      expect(
        NotesRules.isEmptyDaily(
          daily('  ## Notes  \n\n   '),
          template: template,
        ),
        isTrue,
      );
    });

    test('a line of its own, a mood or a pin is not empty', () {
      expect(
        NotesRules.isEmptyDaily(
          daily('${template}A good day'),
          template: template,
        ),
        isFalse,
      );
      expect(
        NotesRules.isEmptyDaily(
          daily(template, mood: Mood.sun.value),
          template: template,
        ),
        isFalse,
      );
      expect(
        NotesRules.isEmptyDaily(
          daily(template, pinned: true),
          template: template,
        ),
        isFalse,
      );
    });

    test('the first template counts when the person has their own', () {
      expect(
        NotesRules.isEmptyDaily(daily(template), template: '# My day\n'),
        isTrue,
      );
      expect(
        NotesRules.isEmptyDaily(daily('# My day\n'), template: '# My day\n'),
        isTrue,
      );
    });

    test('a note that is not a daily note is never empty', () {
      expect(
        NotesRules.isEmptyDaily(note('Idea'), template: template),
        isFalse,
      );
    });
  });
}
