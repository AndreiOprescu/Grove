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
      expect(noteTitles(s.notes(filter: NoteFilter.pinned)), ['A']);
      s.undo();
      expect(s.notes(filter: NoteFilter.pinned), isEmpty);
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
      expect(noteTitles(s.notes(filter: const NoteFilter.tag('Home'))), ['A']);
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
      s.noteFilter = NoteFilter.pinned;
      s.openNote(n.id);
      expect(s.noteFilter, NoteFilter.all);
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
}
