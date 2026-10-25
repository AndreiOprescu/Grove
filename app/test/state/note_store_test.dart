// Port of Tests/GroveTests/NoteStoreTests.swift.
import 'package:flutter_test/flutter_test.dart';

import '../data/helpers.dart' show tempDir;
import 'support.dart';

const friday = DayKey('2026-10-02');

List<String> noteTitles(Iterable<Note> notes) => [
  for (final n in notes) n.title,
];

List<String> linkTitles(AppStore s, ItemRef ref) => [
  for (final l in s.linkedItems(ref)) l.title,
];

void main() {
  group('daily and weekly notes', () {
    test('a daily note is made once from the template', () {
      final s = makeStore();
      final a = s.dailyNote(friday);
      final b = s.dailyNote(friday);
      expect(a.id, b.id);
      expect(a.kind, NoteKind.daily);
      expect(a.date, friday);
      expect(a.title, 'Friday, 2 October 2026');
      expect(a.body, '## Plan\n\n## Notes\n\n## Reflection\n');
      expect(s.repos.notes.all().length, 1);
      expect(s.undoName, isNull); // opening a day is not an edit
    });

    test('a weekly note uses the Monday', () {
      final s = makeStore();
      final w = s.weeklyNote(friday);
      expect(w.kind, NoteKind.weekly);
      expect(w.date, const DayKey('2026-09-28'));
      expect(w.title, 'Week 40 · 28 Sep – 4 Oct');
      // The Sunday is in the same week.
      expect(s.weeklyNote(const DayKey('2026-10-04')).id, w.id);
    });

    test('opening the daily note shows it', () {
      final s = makeStore();
      s.openDailyNote(friday);
      expect(s.screen, Screen.notes);
      expect(s.selectedNoteId, s.dailyNote(friday).id);
    });
  });

  group('making, editing, deleting', () {
    test('new notes get fresh titles and undo removes them', () {
      final s = makeStore();
      final a = s.newNote();
      final b = s.newNote();
      expect(a.title, 'Untitled');
      expect(b.title, 'Untitled 2');
      expect(s.selectedNoteId, b.id);
      expect(s.screen, Screen.notes);
      s.undo();
      expect(s.note(b.id), isNull);
      expect(s.note(a.id), isNotNull);
    });

    test('typing makes one undo step', () {
      final s = makeStore();
      final n = s.newNote();
      final t0 = DateTime.now();
      s.setNoteBody(n.id, 'a', now: t0);
      s.setNoteBody(n.id, 'ab', now: t0.add(const Duration(seconds: 1)));
      s.setNoteBody(n.id, 'abc', now: t0.add(const Duration(seconds: 2)));
      expect(s.note(n.id)?.body, 'abc');
      s.undo();
      expect(s.note(n.id)?.body, '');
      s.redo();
      expect(s.note(n.id)?.body, 'abc');
    });

    test('saving the same text changes nothing', () {
      final s = makeStore();
      final n = s.newNote();
      s.setNoteBody(n.id, '', now: DateTime.now());
      expect(s.undoName, 'New Note');
    });

    test('renaming a note', () {
      final s = makeStore();
      final n = s.newNote();
      s.renameNote(n.id, to: '  Trip ideas ');
      expect(s.note(n.id)?.title, 'Trip ideas');
      s.renameNote(n.id, to: '   '); // an empty name is refused
      expect(s.note(n.id)?.title, 'Trip ideas');
      s.undo();
      expect(s.note(n.id)?.title, 'Untitled');
    });

    test('a daily note keeps its title', () {
      final s = makeStore();
      final d = s.dailyNote(friday);
      s.renameNote(d.id, to: 'Other');
      expect(s.note(d.id)?.title, 'Friday, 2 October 2026');
    });

    test('renaming updates the mentions', () {
      final s = makeStore();
      final a = s.newNote(title: 'Alpha');
      final b = s.newNote(title: 'Beta');
      s.setNoteBody(b.id, 'See [[Alpha]]', now: DateTime.now());
      s.renameNote(a.id, to: 'Gamma');
      expect(s.note(b.id)?.body, 'See [[Gamma|${a.id}]]');
    });

    test('deleting a note can be undone', () {
      final s = makeStore();
      final a = s.newNote(title: 'Alpha');
      final b = s.newNote(title: 'Beta');
      s.setNoteBody(a.id, 'See [[Beta]]', now: DateTime.now());
      final ref = ItemRef(ItemType.note, b.id);
      expect(linkTitles(s, ref), ['Alpha']);
      s.deleteNote(b.id);
      expect(s.note(b.id), isNull);
      expect(s.selectedNoteId, isNot(b.id));
      s.undo();
      expect(s.note(b.id)?.title, 'Beta');
      expect(linkTitles(s, ref), ['Alpha']); // the link is back
    });
  });

  group('links and tags', () {
    test('a body makes links and tags', () {
      final s = makeStore();
      final a = s.newNote(title: 'Alpha');
      final b = s.newNote(title: 'Beta');
      s.setNoteBody(
        a.id,
        'Call about [[Beta]] #work #Plan',
        now: DateTime.now(),
      );
      expect(s.note(a.id)?.body, 'Call about [[Beta|${b.id}]] #work #Plan');
      expect(s.noteTags(a.id), ['Plan', 'work']);
      final back = s.linkedItems(ItemRef(ItemType.note, b.id));
      expect(back.length, 1);
      expect(back[0].ref, ItemRef(ItemType.note, a.id));
      expect(back[0].title, 'Alpha');
    });

    test('undo brings the old tags back', () {
      final s = makeStore();
      final n = s.newNote();
      s.setNoteBody(
        n.id,
        '#one',
        now: DateTime.now().subtract(const Duration(seconds: 300)),
      );
      s.setNoteBody(n.id, '#two', now: DateTime.now());
      expect(s.noteTags(n.id), ['two']);
      s.undo();
      expect(s.noteTags(n.id), ['one']);
    });

    test('a task that mentions a note is a backlink', () {
      final s = makeStore();
      final n = s.newNote(title: 'Trip');
      final t = TaskItem(title: 'Book flights');
      s.repos.tasks.save(t);
      s.setNotes(t.id, 'Details are in [[Trip]]');
      final items = s.linkedItems(ItemRef(ItemType.note, n.id));
      expect([for (final i in items) i.title], ['Book flights']);
      expect(items[0].ref.type, ItemType.task);
    });
  });

  group('the list', () {
    test('pinned notes come first', () {
      final s = makeStore();
      final a = s.newNote(title: 'A');
      s.newNote(title: 'B');
      s.togglePin(a.id);
      expect(s.notes().first.id, a.id);
      expect(noteTitles(s.notes(section: NoteSection.pinned)), ['A']);
      s.undo();
      expect(s.notes(section: NoteSection.pinned), isEmpty);
    });

    test('the list searches titles and text', () {
      final s = makeStore();
      final a = s.newNote(title: 'Groceries');
      s.newNote(title: 'Other');
      s.setNoteBody(a.id, 'buy oat milk', now: DateTime.now());
      expect(noteTitles(s.notes(query: 'milk')), ['Groceries']);
      expect(noteTitles(s.notes(query: 'other')), ['Other']);
      expect(s.notes(query: 'nothing here'), isEmpty);
    });

    test('filtering by tag', () {
      final s = makeStore();
      final a = s.newNote(title: 'A');
      s.newNote(title: 'B');
      s.setNoteBody(a.id, '#home', now: DateTime.now());
      expect(noteTitles(s.notes(section: const NoteSection.tag('Home'))), [
        'A',
      ]);
      expect(s.allNoteTags(), ['home']);
    });

    test('duplicating a note', () {
      final s = makeStore();
      final a = s.newNote(title: 'Ideas');
      s.setNoteBody(a.id, '- [ ] one ⟦t:T1⟧', now: DateTime.now());
      s.togglePin(a.id);
      s.duplicateNote(a.id);
      final copy = s.note(s.selectedNoteId!)!;
      expect(copy.id, isNot(a.id));
      expect(copy.title, 'Ideas copy');
      expect(copy.kind, NoteKind.note);
      expect(copy.pinned, isFalse);
      // The hidden task marker stays with the first note.
      expect(copy.body, '- [ ] one');
    });
  });

  group('opening', () {
    test('a mention of a note opens the notes screen', () {
      final s = makeStore();
      final n = s.newNote(title: 'Trip');
      s.screen = Screen.planner;
      s.selectedNoteId = null;
      s.open(ItemRef(ItemType.note, n.id));
      expect(s.screen, Screen.notes);
      expect(s.selectedNoteId, n.id);
    });

    test('opening a note the list hides resets the filter', () {
      final s = makeStore();
      final n = s.newNote(title: 'Trip');
      s.noteSection = NoteSection.pinned;
      s.openNote(n.id);
      expect(s.noteSection, NoteSection.all);
    });
  });

  group('an empty daily note is not kept', () {
    test('it goes when its last editor goes', () {
      final s = makeStore();
      final n = s.dailyNote(friday);
      s.noteShown(n.id);
      s.noteShown(n.id);
      s.noteHidden(n.id);
      expect(s.note(n.id), isNotNull); // one editor still shows it
      s.selectedNoteId = n.id;
      s.noteHidden(n.id);
      expect(s.note(n.id), isNull);
      expect(s.selectedNoteId, isNull);
      expect(s.undoName, isNull); // Grove made it, so this is not an edit
    });

    test('a note with text, a mood or a pin stays', () {
      final s = makeStore();
      final a = s.dailyNote(friday);
      s.setNoteBody(a.id, '${a.body}A good day');
      final b = s.dailyNote(friday.adding(days: 1));
      s.togglePin(b.id);
      for (final id in [a.id, b.id]) {
        s.noteShown(id);
        s.noteHidden(id);
        expect(s.note(id), isNotNull);
      }
    });

    test('a note of the person stays, also with no text', () {
      final s = makeStore();
      final n = s.newNote();
      s.noteShown(n.id);
      s.noteHidden(n.id);
      expect(s.note(n.id), isNotNull);
    });

    test('a mood taken away from a note with nothing else deletes it, and '
        'undo brings it back', () {
      final s = makeStore(clock: const WallTime(day: friday, minute: 600));
      s.setTodayMood(Mood.sun);
      final n = s.existingDailyNote(friday)!;
      expect(n.mood, Mood.sun.value);
      s.setTodayMood(Mood.sun);
      expect(s.existingDailyNote(friday), isNull);
      s.undo();
      expect(s.existingDailyNote(friday)!.mood, Mood.sun.value);
    });

    test('a mood taken away in an open editor keeps the note', () {
      final s = makeStore();
      final n = s.dailyNote(friday);
      s.noteShown(n.id);
      s.setMood(n.id, Mood.sun);
      s.setMood(n.id, Mood.sun);
      expect(s.note(n.id), isNotNull);
      s.noteHidden(n.id);
      expect(s.note(n.id), isNull);
    });

    test('the sweep takes empty notes that did not change for a day', () {
      final s = makeStore(clock: const WallTime(day: friday, minute: 600));
      final old = s.dailyNote(friday);
      final full = s.dailyNote(friday.adding(days: 1));
      s.setNoteBody(full.id, 'A good day');
      s.clockOverride = WallTime(day: friday.adding(days: 1), minute: 300);
      final fresh = s.dailyNote(friday.adding(days: 2));
      final shown = s.dailyNote(friday.adding(days: 3));
      s.noteShown(shown.id);

      // 19 hours later: nothing is old enough
      s.forgetEmptyDailyNotes();
      expect(s.note(old.id), isNotNull);

      s.clockOverride = WallTime(day: friday.adding(days: 1), minute: 660);
      s.forgetEmptyDailyNotes();
      expect(s.note(old.id), isNull);
      expect(s.note(full.id), isNotNull);
      expect(s.note(fresh.id), isNotNull); // a sync can still bring its text
      expect(s.note(shown.id), isNotNull);
    });

    test('the start sweeps the empty notes', () {
      final dir = tempDir('grove-empty-notes').path;
      final first = AppStore.open(dataDir: dir, prefs: MemoryPrefs());
      final n = Note(
        title: NotesRules.dailyTitle(friday),
        body: NotesRules.template(NoteKind.daily),
        kind: NoteKind.daily,
        date: friday,
        createdAt: '2026-01-01T09:00:00',
        updatedAt: '2026-01-01T09:00:00',
      );
      first.repos.notes.save(n, touch: false);
      first.dispose();
      first.repos.db.close();

      final s = AppStore.open(dataDir: dir, prefs: MemoryPrefs());
      addTearDown(() {
        s.dispose();
        s.repos.db.close();
      });
      expect(s.note(n.id), isNull);
    });
  });

  group('sections of the sidebar', () {
    EventItem meeting(AppStore s) {
      final e = EventItem(
        title: 'Team sync',
        start: WallTime(day: friday, minute: 600),
        end: WallTime(day: friday, minute: 660),
      );
      s.repos.events.save(e);
      return e;
    }

    test('the section starts at All, and a note list follows it', () {
      final s = makeStore();
      expect(s.noteSection, NoteSection.all);
      final a = s.newNote(title: 'Plain');
      final d = s.dailyNote(friday);
      expect(noteTitles(s.notes()).toSet(), {'Plain', d.title});
      s.noteSection = NoteSection.daily;
      expect(s.notes(section: s.noteSection).map((n) => n.id), [d.id]);
      expect(s.notes(section: NoteSection.inbox).map((n) => n.id), [a.id]);
    });

    test('the inbox leaves out meeting notes and notes in a notebook', () {
      final s = makeStore();
      final plain = s.newNote(title: 'Plain');
      final m = s.createMeetingNote(meeting(s))!;
      final b = s.newNotebook('Work');
      final inBook = s.newNote(title: 'In book');
      expect(s.note(inBook.id)!.notebookId, b.id);
      expect(s.notes(section: NoteSection.inbox).map((n) => n.id), [plain.id]);
      expect(s.notes(section: NoteSection.meetings).map((n) => n.id), [m.id]);
      expect(s.notes(section: NoteSection.notebook(b.id)).map((n) => n.id), [
        inBook.id,
      ]);
    });

    test('with tasks: only notes with a task that is not done', () {
      final s = makeStore();
      final a = s.newNote(title: 'A');
      final b = s.newNote(title: 'B');
      s.newNote(title: 'C');
      s.repos.tasks.save(TaskItem(title: 'open', sourceNoteId: a.id));
      s.repos.tasks.save(
        TaskItem(title: 'done', sourceNoteId: b.id, status: TaskStatus.done),
      );
      expect(noteTitles(s.notes(section: NoteSection.withTasks)), ['A']);
    });

    test('a search narrows inside the section', () {
      final s = makeStore();
      s.newNotebook('Work');
      final a = s.newNote(title: 'Milk plan');
      s.newNote(title: 'Other');
      s.noteSection = NoteSection.all;
      s.newNote(title: 'Milk outside');
      expect(
        noteTitles(
          s.notes(section: NoteSection.notebook(a.notebookId!), query: 'milk'),
        ),
        ['Milk plan'],
      );
    });

    test('counts for the sidebar', () {
      final s = makeStore();
      s.newNote(title: 'Plain');
      s.createMeetingNote(meeting(s));
      final old = s.newNote(title: 'Old');
      s.archiveNote(old.id);
      final b = s.newNotebook('Work');
      s.newNote(title: 'In book');
      final c = s.sectionCounts();
      expect(c[NoteSection.all], 3);
      expect(c[NoteSection.inbox], 1);
      expect(c[NoteSection.meetings], 1);
      expect(c[NoteSection.archive], 1);
      expect(c[NoteSection.withTasks], 0);
      expect(c[NoteSection.notebook(b.id)], 1);
    });

    test('opening a note the section hides goes to All, or to the archive '
        'for an archived note', () {
      final s = makeStore();
      final a = s.newNote(title: 'A');
      final old = s.newNote(title: 'Old');
      s.archiveNote(old.id);
      s.noteSection = NoteSection.pinned;
      s.openNote(a.id);
      expect(s.noteSection, NoteSection.all);
      s.openNote(old.id);
      expect(s.noteSection, NoteSection.archive);
      expect(s.selectedNoteId, old.id);
    });
  });

  group('notebooks', () {
    test('a new notebook is listed and selected; blank names get a fresh '
        'one', () {
      final s = makeStore();
      final b = s.newNotebook('  Work ');
      expect(b.name, 'Work');
      expect(s.noteSection, NoteSection.notebook(b.id));
      final c = s.newNotebook('');
      expect(c.name, 'Notebook');
      expect(s.newNotebook(' ').name, 'Notebook 2');
      expect(s.notebooks().map((x) => x.name), [
        'Work',
        'Notebook',
        'Notebook 2',
      ]);
      s.undo();
      expect(s.notebooks(), hasLength(2));
    });

    test('rename a notebook and a section; an empty name is refused', () {
      final s = makeStore();
      final b = s.newNotebook('Work');
      s.renameNotebook(b.id, 'Job');
      s.renameNotebook(b.id, '  ');
      expect(s.notebook(b.id)!.name, 'Job');
      final sec = s.newSection(b.id, 'Q4')!;
      s.renameSection(sec.id, 'Q1');
      s.renameSection(sec.id, '');
      expect(s.notebookSections(b.id).single.name, 'Q1');
      s.undo();
      expect(s.notebookSections(b.id).single.name, 'Q4');
      expect(s.newSection('nope', 'X'), isNull);
    });

    test('a new note in a notebook section goes in the notebook, and in the '
        'section when one is given', () {
      final s = makeStore();
      final b = s.newNotebook('Work');
      final sec = s.newSection(b.id, 'Q4')!;
      final a = s.newNote(title: 'A');
      final c = s.newNote(title: 'C', sectionId: sec.id);
      expect((a.notebookId, a.sectionId), (b.id, null));
      expect((c.notebookId, c.sectionId), (b.id, sec.id));
      expect(s.noteSection, NoteSection.notebook(b.id));
      // A section of another notebook is not taken.
      final other = s.newNotebook('Home');
      final d = s.newNote(title: 'D', sectionId: sec.id);
      expect((d.notebookId, d.sectionId), (other.id, null));
    });

    test('move and reorder: the order goes between the neighbours, and the '
        'edit time stays', () {
      final s = makeStore(clock: WallTime(day: friday, minute: 600));
      final b = s.newNotebook('Work');
      s.noteSection = NoteSection.all;
      final x = s.newNote(title: 'X');
      final y = s.newNote(title: 'Y');
      final z = s.newNote(title: 'Z');
      final before = s.note(x.id)!.updatedAt;
      s.clockOverride = WallTime(day: friday.adding(days: 1), minute: 600);
      for (final n in [x, y, z]) {
        s.moveNote(n.id, notebookId: b.id);
      }
      List<String> order() => [
        for (final n in s.notes(section: NoteSection.notebook(b.id))) n.title,
      ];
      expect(order(), ['X', 'Y', 'Z']);
      expect(s.note(x.id)!.updatedAt, before);
      s.reorderInNotebook(z.id, 0);
      expect(order(), ['Z', 'X', 'Y']);
      s.reorderInNotebook(z.id, 1);
      expect(order(), ['X', 'Z', 'Y']);
      s.undo();
      expect(order(), ['Z', 'X', 'Y']);
      // Into a section, at a place.
      final sec = s.newSection(b.id, 'Q4')!;
      s.moveNote(x.id, notebookId: b.id, sectionId: sec.id);
      s.moveNote(y.id, notebookId: b.id, sectionId: sec.id, index: 0);
      expect(
        [
          for (final g in s.groupedNotes(section: NoteSection.notebook(b.id)))
            [g.label, noteTitles(g.notes)],
        ],
        [
          [
            '',
            ['Z'],
          ],
          [
            'Q4',
            ['Y', 'X'],
          ],
        ],
      );
      // Out of the notebook.
      s.moveNote(z.id, notebookId: null);
      expect(s.note(z.id)!.notebookId, isNull);
      expect(noteTitles(s.notes(section: NoteSection.inbox)), ['Z']);
    });

    test('notebooks and sections can be put in order', () {
      final s = makeStore();
      final a = s.newNotebook('A');
      final b = s.newNotebook('B');
      final c = s.newNotebook('C');
      s.reorderNotebook(c.id, 0);
      expect(s.notebooks().map((x) => x.name), ['C', 'A', 'B']);
      final s1 = s.newSection(a.id, 'One')!;
      s.newSection(a.id, 'Two');
      s.reorderSection(s1.id, 1);
      expect(s.notebookSections(a.id).map((x) => x.name), ['Two', 'One']);
      expect(b.id, isNotEmpty);
    });

    test('deleting a notebook frees its notes, and undo brings it all '
        'back', () {
      final s = makeStore();
      final b = s.newNotebook('Work');
      final sec = s.newSection(b.id, 'Q4')!;
      final a = s.newNote(title: 'A');
      final c = s.newNote(title: 'C', sectionId: sec.id);
      s.deleteNotebook(b.id);
      expect(s.notebook(b.id), isNull);
      expect(s.notebookSections(b.id), isEmpty);
      expect(s.noteSection, NoteSection.all);
      for (final id in [a.id, c.id]) {
        expect(s.note(id)!.notebookId, isNull);
        expect(s.note(id)!.sectionId, isNull);
      }
      expect(s.undoName, 'Delete Notebook');
      s.undo();
      expect(s.notebook(b.id)!.name, 'Work');
      expect(s.notebookSections(b.id).single.id, sec.id);
      expect(s.note(a.id)!.notebookId, b.id);
      expect(
        (s.note(c.id)!.notebookId, s.note(c.id)!.sectionId),
        (b.id, sec.id),
      );
      s.redo();
      expect(s.notebook(b.id), isNull);
    });

    test('deleting a section keeps its notes in the notebook; undo puts them '
        'back', () {
      final s = makeStore();
      final b = s.newNotebook('Work');
      final sec = s.newSection(b.id, 'Q4')!;
      final c = s.newNote(title: 'C', sectionId: sec.id);
      s.deleteSection(sec.id);
      expect(s.notebookSections(b.id), isEmpty);
      expect((s.note(c.id)!.notebookId, s.note(c.id)!.sectionId), (b.id, null));
      s.undo();
      expect(s.note(c.id)!.sectionId, sec.id);
    });

    test('duplicating a note keeps it in its notebook and section, right '
        'after it', () {
      final s = makeStore();
      final b = s.newNotebook('Work');
      final a = s.newNote(title: 'A');
      s.newNote(title: 'B');
      s.duplicateNote(a.id);
      expect(noteTitles(s.notes(section: NoteSection.notebook(b.id))), [
        'A',
        'A copy',
        'B',
      ]);
    });
  });

  group('archive', () {
    test('archiving keeps the note selected and shows the archive; '
        'unarchiving brings it back to All', () {
      final s = makeStore();
      final a = s.newNote(title: 'A');
      s.newNote(title: 'B');
      s.selectedNoteId = a.id;
      s.noteSection = NoteSection.inbox;
      s.archiveNote(a.id);
      expect(s.note(a.id)!.archived, isTrue);
      expect(s.selectedNoteId, a.id);
      expect(s.noteSection, NoteSection.archive);
      expect(noteTitles(s.notes()), ['B']);
      expect(noteTitles(s.notes(section: NoteSection.archive)), ['A']);
      expect(s.undoName, 'Archive Note');
      s.undo();
      expect(s.note(a.id)!.archived, isFalse);
      s.redo();
      s.unarchiveNote(a.id);
      expect(s.note(a.id)!.archived, isFalse);
      expect(s.selectedNoteId, a.id);
      expect(s.noteSection, NoteSection.all);
    });

    test('a note that is not selected is archived in place', () {
      final s = makeStore();
      final a = s.newNote(title: 'A');
      final b = s.newNote(title: 'B');
      s.noteSection = NoteSection.inbox;
      s.selectedNoteId = b.id;
      s.archiveNote(a.id);
      expect(s.noteSection, NoteSection.inbox);
      expect(s.selectedNoteId, b.id);
    });

    test('an archived daily note is still the note of its day', () {
      final s = makeStore();
      final d = s.dailyNote(friday);
      s.setNoteBody(d.id, '${d.body}text');
      s.archiveNote(d.id);
      expect(s.dailyNote(friday).id, d.id);
    });
  });

  group('date groups', () {
    test('the list in groups, by the clock of the store', () {
      // Wednesday 21 October 2026.
      final s = makeStore(
        clock: WallTime(day: const DayKey('2026-10-21'), minute: 900),
      );
      final today = s.newNote(title: 'Today');
      s.clockOverride = WallTime(day: const DayKey('2026-10-20'), minute: 600);
      s.newNote(title: 'Yesterday');
      s.clockOverride = WallTime(day: const DayKey('2026-10-02'), minute: 600);
      s.newNote(title: 'Early');
      s.clockOverride = WallTime(day: const DayKey('2026-10-21'), minute: 900);
      expect(s.note(today.id)!.updatedAt, startsWith('2026-10-21'));
      expect(
        [
          for (final g in s.groupedNotes()) [g.label, noteTitles(g.notes)],
        ],
        [
          [
            'Today',
            ['Today'],
          ],
          [
            'Yesterday',
            ['Yesterday'],
          ],
          [
            'October',
            ['Early'],
          ],
        ],
      );
    });
  });
}
