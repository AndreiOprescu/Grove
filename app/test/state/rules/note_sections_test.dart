import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

// The sections of the notes sidebar, the date groups and the notebook
// groups (notes redesign, 2026-10-26).

const archivedAt = '2026-10-20T09:00:00';

Note n(
  String id, {
  NoteKind kind = NoteKind.note,
  bool pinned = false,
  String? notebookId,
  String? sectionId,
  double sortOrder = 0,
  String? archived,
  DayKey? date,
  String updatedAt = '2026-10-26T09:00:00',
}) => Note(
  id: id,
  title: id,
  kind: kind,
  pinned: pinned,
  notebookId: notebookId,
  sectionId: sectionId,
  sortOrder: sortOrder,
  archivedAt: archived,
  date: date,
  updatedAt: updatedAt,
);

List<String> idsOf(Iterable<Note> notes) => [for (final x in notes) x.id];

void main() {
  final notes = [
    n('plain'),
    n('pinned', pinned: true),
    n('daily', kind: NoteKind.daily, date: const DayKey('2026-10-26')),
    n('weekly', kind: NoteKind.weekly, date: const DayKey('2026-10-26')),
    n('meeting'),
    n('tasks'),
    n('inBook', notebookId: 'B1'),
    n('inOther', notebookId: 'B2'),
    n('old', archived: archivedAt),
    n('oldPinned', pinned: true, archived: archivedAt),
    n('oldInBook', notebookId: 'B1', archived: archivedAt),
  ];
  const facts = NoteFacts(
    meetingIds: {'meeting', 'oldInBook'},
    openTaskNoteIds: {'tasks', 'old'},
  );
  List<String> pick(NoteSection s) =>
      idsOf(NotesRules.filter(notes, s, facts: facts, tagsOf: (_) => const []));

  group('sections', () {
    test('all is every note that is not archived', () {
      expect(pick(NoteSection.all), [
        'plain',
        'pinned',
        'daily',
        'weekly',
        'meeting',
        'tasks',
        'inBook',
        'inOther',
      ]);
    });

    test('daily, weekly and pinned leave archived notes out', () {
      expect(pick(NoteSection.daily), ['daily']);
      expect(pick(NoteSection.weekly), ['weekly']);
      expect(pick(NoteSection.pinned), ['pinned']);
    });

    test('inbox: plain notes in no notebook that are not meeting notes', () {
      expect(pick(NoteSection.inbox), ['plain', 'pinned', 'tasks']);
    });

    test('meetings: notes linked to an event', () {
      expect(pick(NoteSection.meetings), ['meeting']);
    });

    test('with tasks: notes with an open task', () {
      expect(pick(NoteSection.withTasks), ['tasks']);
    });

    test('archive: archived notes only', () {
      expect(pick(NoteSection.archive), ['old', 'oldPinned', 'oldInBook']);
    });

    test('a notebook: its notes that are not archived', () {
      expect(pick(const NoteSection.notebook('B1')), ['inBook']);
      expect(pick(const NoteSection.notebook('B2')), ['inOther']);
      expect(pick(const NoteSection.notebook('nope')), isEmpty);
    });

    test('a tag still works, and leaves archived notes out', () {
      expect(
        idsOf(
          NotesRules.filter(
            notes,
            const NoteSection.tag('work'),
            facts: facts,
            tagsOf: (id) => id == 'plain' || id == 'old' ? ['Work'] : [],
          ),
        ),
        ['plain'],
      );
    });

    test('sections are values', () {
      expect(
        const NoteSection.notebook('B1'),
        const NoteSection.notebook('B1'),
      );
      expect(
        const NoteSection.notebook('B1'),
        isNot(const NoteSection.notebook('B2')),
      );
      expect(const NoteSection.notebook('B1').notebookId, 'B1');
      expect(NoteSection.all.notebookId, isNull);
      expect(const NoteSection.tag('x').tagName, 'x');
      expect(NoteSection.fixed.first, NoteSection.all);
      expect(NoteSection.fixed, contains(NoteSection.archive));
    });

    test('counts: one pass, every fixed section and each notebook', () {
      final c = NotesRules.counts(notes, facts: facts);
      expect(c[NoteSection.all], 8);
      expect(c[NoteSection.inbox], 3);
      expect(c[NoteSection.daily], 1);
      expect(c[NoteSection.weekly], 1);
      expect(c[NoteSection.pinned], 1);
      expect(c[NoteSection.meetings], 1);
      expect(c[NoteSection.withTasks], 1);
      expect(c[NoteSection.archive], 3);
      expect(c[const NoteSection.notebook('B1')], 1);
      expect(c[const NoteSection.notebook('B2')], 1);
      // A section with nothing in it has 0, not a missing entry.
      expect(
        NotesRules.counts(
          const [],
          facts: const NoteFacts(),
        )[NoteSection.archive],
        0,
      );
    });
  });

  group('date groups', () {
    // Wednesday 21 October 2026. The week starts on Monday 19 October.
    final now = DateTime(2026, 10, 21, 15);
    List<List<Object>> groups(List<Note> list) => [
      for (final g in NotesRules.dateGroups(list, now: now))
        [g.label, idsOf(g.notes)],
    ];

    test('Today, Yesterday, This week, Last week, then months', () {
      final list = [
        n('today', updatedAt: '2026-10-21T08:00:00'),
        n('yesterday', updatedAt: '2026-10-20T23:00:00'),
        n('monday', updatedAt: '2026-10-19T08:00:00'),
        n('lastSunday', updatedAt: '2026-10-18T08:00:00'),
        n('lastMonday', updatedAt: '2026-10-12T08:00:00'),
        n('early', updatedAt: '2026-10-02T08:00:00'),
        n('sept', updatedAt: '2026-09-30T08:00:00'),
        n('lastYear', updatedAt: '2025-12-31T08:00:00'),
      ];
      expect(groups(list), [
        [
          'Today',
          ['today'],
        ],
        [
          'Yesterday',
          ['yesterday'],
        ],
        [
          'This week',
          ['monday'],
        ],
        [
          'Last week',
          ['lastSunday', 'lastMonday'],
        ],
        [
          'October',
          ['early'],
        ],
        [
          'September',
          ['sept'],
        ],
        [
          'December 2025',
          ['lastYear'],
        ],
      ]);
    });

    test('daily and weekly notes go by their day, not their edit time', () {
      final list = [
        n(
          'oldDay',
          kind: NoteKind.daily,
          date: const DayKey('2026-10-02'),
          updatedAt: '2026-10-21T10:00:00',
        ),
        n(
          'thisWeek',
          kind: NoteKind.weekly,
          date: const DayKey('2026-10-19'),
          updatedAt: '2026-10-01T10:00:00',
        ),
        n('edited', updatedAt: '2026-10-21T09:00:00'),
      ];
      expect(groups(list), [
        [
          'Today',
          ['edited'],
        ],
        [
          'This week',
          ['thisWeek'],
        ],
        [
          'October',
          ['oldDay'],
        ],
      ]);
    });

    test('a day later than this week comes first, as Upcoming', () {
      final list = [
        n('today', updatedAt: '2026-10-21T08:00:00'),
        n('friday', kind: NoteKind.daily, date: const DayKey('2026-10-23')),
        n('nextMonth', kind: NoteKind.daily, date: const DayKey('2026-11-02')),
      ];
      expect(groups(list), [
        [
          'Upcoming',
          ['nextMonth'],
        ],
        [
          'Today',
          ['today'],
        ],
        [
          'This week',
          ['friday'],
        ],
      ]);
    });

    test('on a Monday, yesterday is Yesterday, not Last week', () {
      final monday = DateTime(2026, 10, 19, 9);
      final g = NotesRules.dateGroups([
        n('sunday', updatedAt: '2026-10-18T08:00:00'),
        n('saturday', updatedAt: '2026-10-17T08:00:00'),
      ], now: monday);
      expect([for (final x in g) x.label], ['Yesterday', 'Last week']);
    });

    test('within a group the newest day comes first', () {
      final g = NotesRules.dateGroups([
        n('older', updatedAt: '2026-10-02T08:00:00'),
        n('newer', updatedAt: '2026-10-05T08:00:00'),
      ], now: now);
      expect(idsOf(g.single.notes), ['newer', 'older']);
    });
  });

  group('notebook groups', () {
    final sections = [
      NotebookSection(id: 'S2', notebookId: 'B1', name: 'Later', sortOrder: 2),
      NotebookSection(id: 'S1', notebookId: 'B1', name: 'First', sortOrder: 1),
      NotebookSection(id: 'S3', notebookId: 'B1', name: 'Empty', sortOrder: 3),
    ];

    test('notes with no section first, then each section in order', () {
      final g = NotesRules.notebookGroups([
        n('b', notebookId: 'B1', sectionId: 'S1', sortOrder: 2),
        n('a', notebookId: 'B1', sectionId: 'S1', sortOrder: 1),
        n('loose2', notebookId: 'B1', sortOrder: 2),
        n('loose1', notebookId: 'B1', sortOrder: 1),
        n('c', notebookId: 'B1', sectionId: 'S2'),
        // A section that is gone: the note shows with the loose notes.
        n('lost', notebookId: 'B1', sectionId: 'gone', sortOrder: 3),
      ], sections);
      expect(
        [
          for (final x in g) [x.label, x.sectionId, idsOf(x.notes)],
        ],
        [
          [
            '',
            null,
            ['loose1', 'loose2', 'lost'],
          ],
          [
            'First',
            'S1',
            ['a', 'b'],
          ],
          [
            'Later',
            'S2',
            ['c'],
          ],
          ['Empty', 'S3', <String>[]],
        ],
      );
    });
  });

  group('places in an order', () {
    test('between two neighbours, at the start and at the end', () {
      final others = [(id: 'a', order: 1.0), (id: 'b', order: 2.0)];
      expect(NotesRules.placeAt('x', others, 1), {'x': 1.5});
      expect(NotesRules.placeAt('x', others, 0), {'x': 0.0});
      expect(NotesRules.placeAt('x', others, 2), {'x': 3.0});
      expect(NotesRules.placeAt('x', others, 99), {'x': 3.0});
      expect(NotesRules.placeAt('x', const [], 0), {'x': 1.0});
    });

    test('no room between equal neighbours: every item gets a new order', () {
      final others = [(id: 'a', order: 0.0), (id: 'b', order: 0.0)];
      expect(NotesRules.placeAt('x', others, 1), {
        'a': 1.0,
        'x': 2.0,
        'b': 3.0,
      });
    });
  });
}
