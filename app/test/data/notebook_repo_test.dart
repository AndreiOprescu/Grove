import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/note.dart';
import 'package:grove/core/model/notebook.dart';
import 'package:grove/core/model/task.dart';
import 'package:grove/data/data.dart';
import 'package:grove/sync/outbox.dart';

import 'helpers.dart';

// Notebooks and their sections (shared migration 14): a note can be in one
// notebook and in one section of it, has an order there, and can be
// archived.

List<String> ids(Iterable<Object> items) => [
  for (final i in items)
    switch (i) {
      final Note n => n.id,
      final Notebook b => b.id,
      final NotebookSection s => s.id,
      _ => '$i',
    },
];

void main() {
  group('migration 14', () {
    test('it is the newest migration', () {
      expect(Migrations.all.length, 14);
      expect(Migrations.all[13], contains('CREATE TABLE notebooks'));
      expect(Migrations.all[13], contains('CREATE TABLE notebook_sections'));
    });

    test('a database of schema 13 keeps its notes and gets the new '
        'columns', () {
      final dir = tempDir('grove-notebooks-14-');
      final path = oldDatabase(
        dir,
        13,
        'INSERT INTO notes (id, title, body, kind, date, pinned, created_at, '
        "updated_at) VALUES ('N1', 'Ideas', 'one', 'note', NULL, 1, "
        "'2026-10-20T09:00:00', '2026-10-21T09:00:00'), ('D1', "
        "'Friday, 2 October 2026', 'x', 'daily', '2026-10-02', 0, "
        "'2026-10-02T09:00:00', '2026-10-02T09:00:00');",
      );
      final db = Database.open(path);
      addTearDown(db.close);
      expect(db.userVersion, 14);
      final cols = db.query(
        'PRAGMA table_info(notes)',
        const [],
        (r) => r.text(1),
      );
      expect(
        cols,
        containsAll(['notebook_id', 'section_id', 'sort_order', 'archived_at']),
      );
      final r = Repos(db);
      final n = r.notes.get('N1')!;
      expect(n.title, 'Ideas');
      expect(n.body, 'one');
      expect(n.pinned, isTrue);
      expect(n.notebookId, isNull);
      expect(n.sectionId, isNull);
      expect(n.sortOrder, 0);
      expect(n.archived, isFalse);
      expect(r.notes.daily(const DayKey('2026-10-02'))?.id, 'D1');
      expect(r.notebooks.all(), isEmpty);
      expect(
        db.query(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND name = 'notes_notebook'",
          const [],
          (r) => r.text(0),
        ),
        ['notes_notebook'],
      );
    });

    test('the new tables sync: they have the sync columns and fill the '
        'outbox', () {
      final r = makeRepos();
      for (final t in ['notebooks', 'notebook_sections']) {
        expect(SyncMigrations.syncedTables, contains(t));
        expect(
          r.db.query('PRAGMA table_info($t)', const [], (r) => r.text(1)),
          containsAll(['deleted', 'user_id', 'updated_at']),
          reason: t,
        );
      }
      // Parents first: a section after its notebook, a note after both.
      final order = SyncMigrations.syncedTables;
      expect(
        order.indexOf('notebooks'),
        lessThan(order.indexOf('notebook_sections')),
      );
      expect(
        order.indexOf('notebook_sections'),
        lessThan(order.indexOf('notes')),
      );
      final b = Notebook(id: 'B1', name: 'Work');
      r.notebooks.save(b);
      r.notebooks.saveSection(
        NotebookSection(id: 'S1', notebookId: 'B1', name: 'Q4'),
      );
      expect(Outbox(r.db).entries().map((e) => e.table), [
        'notebooks',
        'notebook_sections',
      ]);
    });
  });

  group('NotebookRepo', () {
    test('save, read, change, in order of sort_order then name', () {
      final r = makeRepos();
      r.notebooks
        ..save(Notebook(id: 'B', name: 'Work', sortOrder: 2))
        ..save(Notebook(id: 'A', name: 'Home', sortOrder: 1, color: 'green'))
        ..save(Notebook(id: 'C', name: 'Alpha', sortOrder: 2));
      expect(ids(r.notebooks.all()), ['A', 'C', 'B']);
      expect(r.notebooks.get('A')!.color, 'green');
      expect(r.notebooks.get('B')!.color, isNull);
      r.notebooks.save(r.notebooks.get('B')!.copyWith(name: 'Job'));
      expect(r.notebooks.get('B')!.name, 'Job');
      expect(r.notebooks.get('nope'), isNull);
    });

    test('sections of a notebook, in order', () {
      final r = makeRepos();
      r.notebooks
        ..save(Notebook(id: 'B1', name: 'Work'))
        ..save(Notebook(id: 'B2', name: 'Home'))
        ..saveSection(
          NotebookSection(id: 'S2', notebookId: 'B1', name: 'B', sortOrder: 2),
        )
        ..saveSection(
          NotebookSection(id: 'S1', notebookId: 'B1', name: 'A', sortOrder: 1),
        )
        ..saveSection(NotebookSection(id: 'S3', notebookId: 'B2', name: 'C'));
      expect(ids(r.notebooks.sections('B1')), ['S1', 'S2']);
      expect(ids(r.notebooks.sections('B2')), ['S3']);
      expect(r.notebooks.section('S2')!.name, 'B');
      expect(
        () => r.notebooks.saveSection(
          NotebookSection(notebookId: 'nope', name: 'X'),
        ),
        throwsA(anything),
      );
    });

    test('reorder gives each id its place', () {
      final r = makeRepos();
      r.notebooks
        ..save(Notebook(id: 'A', name: 'A'))
        ..save(Notebook(id: 'B', name: 'B'))
        ..save(Notebook(id: 'C', name: 'C'))
        ..reorder(['C', 'A', 'B']);
      expect(ids(r.notebooks.all()), ['C', 'A', 'B']);
      r.notebooks
        ..saveSection(NotebookSection(id: 'S1', notebookId: 'A', name: 'x'))
        ..saveSection(NotebookSection(id: 'S2', notebookId: 'A', name: 'y'))
        ..reorderSections(['S2', 'S1']);
      expect(ids(r.notebooks.sections('A')), ['S2', 'S1']);
    });

    test('deleting a notebook frees its notes and removes its sections', () {
      final r = makeRepos();
      r.notebooks
        ..save(Notebook(id: 'B1', name: 'Work'))
        ..saveSection(NotebookSection(id: 'S1', notebookId: 'B1', name: 'Q4'));
      r.notes.save(Note(id: 'N1', title: 'Plan', notebookId: 'B1'));
      r.notes.save(
        Note(id: 'N2', title: 'Ideas', notebookId: 'B1', sectionId: 'S1'),
      );
      r.notebooks.delete('B1');
      expect(r.notebooks.get('B1'), isNull);
      expect(r.notebooks.section('S1'), isNull);
      for (final id in ['N1', 'N2']) {
        final n = r.notes.get(id)!;
        expect(n.notebookId, isNull, reason: id);
        expect(n.sectionId, isNull, reason: id);
      }
    });

    test('deleting a section keeps its notes in the notebook', () {
      final r = makeRepos();
      r.notebooks
        ..save(Notebook(id: 'B1', name: 'Work'))
        ..saveSection(NotebookSection(id: 'S1', notebookId: 'B1', name: 'Q4'));
      r.notes.save(
        Note(id: 'N1', title: 'Plan', notebookId: 'B1', sectionId: 'S1'),
      );
      r.notebooks.deleteSection('S1');
      expect(r.notebooks.section('S1'), isNull);
      final n = r.notes.get('N1')!;
      expect(n.notebookId, 'B1');
      expect(n.sectionId, isNull);
    });
  });

  group('NoteRepo and notebooks', () {
    test('the new fields are saved and read', () {
      final r = makeRepos();
      r.notebooks
        ..save(Notebook(id: 'B1', name: 'Work'))
        ..saveSection(NotebookSection(id: 'S1', notebookId: 'B1', name: 'Q4'));
      r.notes.save(
        Note(
          id: 'N1',
          title: 'Plan',
          notebookId: 'B1',
          sectionId: 'S1',
          sortOrder: 2.5,
          archivedAt: '2026-10-26T09:00:00',
        ),
      );
      final n = r.notes.get('N1')!;
      expect(n.notebookId, 'B1');
      expect(n.sectionId, 'S1');
      expect(n.sortOrder, 2.5);
      expect(n.archivedAt, '2026-10-26T09:00:00');
      expect(n.archived, isTrue);
    });

    test('all() skips archived notes; archived() has them; daily and weekly '
        'still find them', () {
      final r = makeRepos();
      r.notes.save(Note(id: 'N1', title: 'Kept'));
      r.notes.save(
        Note(id: 'N2', title: 'Old', archivedAt: '2026-10-26T09:00:00'),
      );
      r.notes.save(
        Note(
          id: 'D1',
          title: 'Day',
          kind: NoteKind.daily,
          date: const DayKey('2026-10-02'),
          archivedAt: '2026-10-26T09:00:00',
        ),
      );
      r.notes.save(
        Note(
          id: 'W1',
          title: 'Week',
          kind: NoteKind.weekly,
          date: const DayKey('2026-09-28'),
          archivedAt: '2026-10-26T09:00:00',
        ),
      );
      expect(ids(r.notes.all()), ['N1']);
      expect(ids(r.notes.all(includeArchived: true)).toSet(), {
        'N1',
        'N2',
        'D1',
        'W1',
      });
      expect(ids(r.notes.archived()).toSet(), {'N2', 'D1', 'W1'});
      expect(r.notes.daily(const DayKey('2026-10-02'))?.id, 'D1');
      expect(r.notes.weekly(const DayKey('2026-09-28'))?.id, 'W1');
    });

    test('setArchived and back', () {
      final r = makeRepos();
      r.notes.save(
        Note(id: 'N1', title: 'A', updatedAt: '2026-10-20T09:00:00'),
      );
      r.notes.setArchived('N1', true, at: '2026-10-26T10:00:00');
      expect(r.notes.get('N1')!.archivedAt, '2026-10-26T10:00:00');
      expect(r.notes.all(), isEmpty);
      r.notes.setArchived('N1', false);
      expect(r.notes.get('N1')!.archived, isFalse);
      expect(ids(r.notes.all()), ['N1']);
    });

    test('inNotebook: no section first, then each section in order, then '
        'sort_order', () {
      final r = makeRepos();
      r.notebooks
        ..save(Notebook(id: 'B1', name: 'Work'))
        ..save(Notebook(id: 'B2', name: 'Home'))
        ..saveSection(
          NotebookSection(id: 'S2', notebookId: 'B1', name: 'Z', sortOrder: 1),
        )
        ..saveSection(
          NotebookSection(id: 'S1', notebookId: 'B1', name: 'A', sortOrder: 2),
        );
      r.notes
        ..save(Note(id: 'a', title: 'a', notebookId: 'B1', sectionId: 'S1'))
        ..save(
          Note(
            id: 'b',
            title: 'b',
            notebookId: 'B1',
            sectionId: 'S2',
            sortOrder: 2,
          ),
        )
        ..save(
          Note(
            id: 'c',
            title: 'c',
            notebookId: 'B1',
            sectionId: 'S2',
            sortOrder: 1,
          ),
        )
        ..save(Note(id: 'd', title: 'd', notebookId: 'B1', sortOrder: 5))
        ..save(Note(id: 'e', title: 'e', notebookId: 'B2'))
        ..save(
          Note(
            id: 'f',
            title: 'f',
            notebookId: 'B1',
            archivedAt: '2026-10-26T09:00:00',
          ),
        );
      expect(ids(r.notes.inNotebook('B1')), ['d', 'c', 'b', 'a']);
      expect(ids(r.notes.inNotebook('B2')), ['e']);
    });

    test('move puts a note in a notebook and a section, with an order', () {
      final r = makeRepos();
      r.notebooks
        ..save(Notebook(id: 'B1', name: 'Work'))
        ..saveSection(NotebookSection(id: 'S1', notebookId: 'B1', name: 'Q4'));
      r.notes.save(Note(id: 'N1', title: 'A'));
      r.notes.move('N1', notebookId: 'B1', sectionId: 'S1', sortOrder: 3);
      var n = r.notes.get('N1')!;
      expect((n.notebookId, n.sectionId, n.sortOrder), ('B1', 'S1', 3.0));
      r.notes.move('N1', notebookId: null, sectionId: null, sortOrder: 0);
      n = r.notes.get('N1')!;
      expect((n.notebookId, n.sectionId), (null, null));
    });

    test('notes linked to events and notes with open tasks: one query '
        'each', () {
      final r = makeRepos();
      r.db.execute(
        'INSERT INTO links (src_type, src_id, dst_type, dst_id) VALUES '
        "('note', 'N1', 'event', 'E1'), ('event', 'E2', 'note', 'N2'), "
        "('note', 'N3', 'task', 'T9')",
      );
      expect(r.notes.linkedToEvents(), {'N1', 'N2'});

      r.notes
        ..save(Note(id: 'A', title: 'A'))
        ..save(Note(id: 'B', title: 'B'));
      r.tasks
        ..save(TaskItem(title: 'open', sourceNoteId: 'A'))
        ..save(
          TaskItem(title: 'done', sourceNoteId: 'B', status: TaskStatus.done),
        )
        ..save(TaskItem(title: 'free'));
      expect(r.notes.withOpenTasks(), {'A'});
    });
  });

  group('light reads', () {
    test('allWithoutBodies has every note, archived too, with no body', () {
      final r = makeRepos();
      r.notes
        ..save(Note(id: 'A', title: 'Live', body: 'long text', pinned: true))
        ..save(
          Note(
            id: 'B',
            title: 'Old',
            body: 'x',
            archivedAt: '2026-10-26T09:00:00',
          ),
        );
      final list = r.notes.allWithoutBodies();
      expect(ids(list)..sort(), ['A', 'B']);
      expect(list.map((n) => n.body), everyElement(''));
      expect(list.firstWhere((n) => n.id == 'A').pinned, isTrue);
      expect(list.firstWhere((n) => n.id == 'B').archived, isTrue);
    });

    test('anyLive leaves archived notes out', () {
      final r = makeRepos();
      expect(r.notes.anyLive(), isFalse);
      r.notes.save(
        Note(id: 'B', title: 'Old', archivedAt: '2026-10-26T09:00:00'),
      );
      expect(r.notes.anyLive(), isFalse);
      r.notes.save(Note(id: 'A', title: 'Live'));
      expect(r.notes.anyLive(), isTrue);
    });
  });
}
