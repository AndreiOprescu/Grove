// Port of Tests/GroveTests/NoteStoreTests.swift.
import 'package:flutter_test/flutter_test.dart';

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
}
