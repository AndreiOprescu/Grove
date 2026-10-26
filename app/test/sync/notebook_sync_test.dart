import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// Notebooks and their sections (shared schema 14) sync like every other row.
// A note keeps its notebook, section, place and archive time on every device.

void main() {
  late MemoryRemote remote;
  late Device a, b;

  setUp(() {
    remote = MemoryRemote();
    a = Device(remote);
    b = Device(remote);
  });

  group('The schema', () {
    test('the tables are synced and exported, before the notes', () {
      const tables = SyncMigrations.syncedTables;
      final notes = tables.indexOf('notes');
      expect(tables.indexOf('notebooks'), lessThan(notes));
      expect(
        tables.indexOf('notebook_sections'),
        greaterThan(tables.indexOf('notebooks')),
      );
      expect(tables.indexOf('notebook_sections'), lessThan(notes));
      expect(DataExport.tables, tables);
      expect(SyncMigrations.addedColumns['notebooks'], {'deleted', 'user_id'});
      expect(SyncMigrations.addedColumns['notebook_sections'], {
        'deleted',
        'user_id',
      });
    });

    test('the SQL for Supabase has both tables and the note columns', () {
      final sql = supabaseSql(RemoteSchema.read(a.db));
      expect(sql, contains('create table if not exists public."notebooks" ('));
      expect(
        sql,
        contains('create table if not exists public."notebook_sections" ('),
      );
      for (final c in [
        'notebook_id',
        'section_id',
        'sort_order',
        'archived_at',
      ]) {
        expect(sql, contains(c), reason: c);
      }
    });

    test('a note goes free when its notebook goes, and leaves its section '
        'when the section goes', () {
      final fks = SyncTable.read(a.db, 'notes').foreignKeys.values;
      final toBook = fks.singleWhere((fk) => fk.column == 'notebook_id');
      expect(toBook.parent, 'notebooks');
      expect(toBook.setsNull, isTrue);
      final toSection = fks.singleWhere((fk) => fk.column == 'section_id');
      expect(toSection.parent, 'notebook_sections');
      expect(toSection.setsNull, isTrue);
    });
  });

  group('Two devices', () {
    test('a notebook, its section and a placed, archived note reach the '
        'other device', () async {
      final book = Notebook(name: 'Work', color: 'green', sortOrder: 1);
      a.repos.notebooks.save(book);
      final sec = NotebookSection(notebookId: book.id, name: 'Q4');
      a.repos.notebooks.saveSection(sec);
      final note = Note(
        title: 'Plan',
        notebookId: book.id,
        sectionId: sec.id,
        sortOrder: 2.5,
      );
      a.repos.notes.save(note);
      a.repos.notes.setArchived(note.id, true, at: '2026-10-26T09:00:00');
      await settle([a, b]);
      expectSame([a, b]);
      expect(b.repos.notebooks.all().single.name, 'Work');
      expect(b.repos.notebooks.all().single.color, 'green');
      expect(b.repos.notebooks.sections(book.id).single.name, 'Q4');
      final got = b.repos.notes.get(note.id)!;
      expect(
        (got.notebookId, got.sectionId, got.sortOrder),
        (book.id, sec.id, 2.5),
      );
      expect(got.archivedAt, '2026-10-26T09:00:00');
      expect(b.repos.notes.all(), isEmpty);
      expect(b.repos.notes.archived().single.id, note.id);
    });

    test('deleting a notebook on one device frees the note on both', () async {
      final book = Notebook(name: 'Work');
      a.repos.notebooks.save(book);
      final sec = NotebookSection(notebookId: book.id, name: 'Q4');
      a.repos.notebooks.saveSection(sec);
      final note = Note(title: 'Plan', notebookId: book.id, sectionId: sec.id);
      a.repos.notes.save(note);
      await settle([a, b]);
      b.later();
      b.repos.notebooks.delete(book.id);
      await settle([a, b]);
      expectSame([a, b]);
      expect(a.repos.notebooks.all(), isEmpty);
      expect(a.repos.notebooks.sections(book.id), isEmpty);
      final got = a.repos.notes.get(note.id)!;
      expect((got.notebookId, got.sectionId), (null, null));
    });

    test('a note moved into a notebook the other device deleted ends up '
        'free', () async {
      final book = Notebook(name: 'Work');
      a.repos.notebooks.save(book);
      final note = Note(title: 'Plan');
      a.repos.notes.save(note);
      await settle([a, b]);
      a.later();
      a.repos.notebooks.delete(book.id);
      b.later();
      b.repos.notes.move(note.id, notebookId: book.id, sortOrder: 1);
      await settle([a, b]);
      expectSame([a, b]);
      expect(a.repos.notes.get(note.id)!.notebookId, isNull);
    });
  });
}
