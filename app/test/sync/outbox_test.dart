import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../data/helpers.dart';
import 'support.dart';

void main() {
  late Device d;
  Repos r() => d.repos;

  setUp(() => d = Device(MemoryRemote()));

  group('What the outbox writes down', () {
    test('a new database has an empty outbox', () {
      expect(d.outbox.count, 0);
      expect(d.outbox.cursor, 0);
      expect(d.db.syncVersion, SyncMigrations.all.length);
    });

    test('a saved task is one waiting change', () {
      final t = TaskItem(title: 'Buy milk');
      r().tasks.save(t);
      final e = d.outbox.entries().single;
      expect(e.table, 'tasks');
      expect(e.key, t.id);
      expect(e.deleted, isFalse);
      expect(e.stamp, greaterThan(0));
    });

    test('a second save keeps one change and makes it newer', () {
      final t = TaskItem(title: 'Buy milk');
      r().tasks.save(t);
      final first = d.outbox.entries().single;
      r().tasks.save(t.copyWith(title: 'Buy oat milk'));
      final second = d.outbox.entries().single;
      expect(second.stamp, greaterThan(first.stamp));
      expect(second.seq, greaterThan(first.seq));
    });

    test('a delete is a waiting change that says "gone"', () {
      final t = TaskItem(title: 'Buy milk');
      r().tasks.save(t);
      d.clearOutbox();
      r().tasks.delete(t.id);
      expect(d.waiting, ['tasks gone']);
      expect(d.outbox.entries().single.key, t.id);
    });

    test('a deleted task takes its subtasks, blocks and links with it', () {
      final p = TaskItem(title: 'Parent');
      final c = TaskItem(title: 'Child', parentId: p.id);
      final block = EventItem(
        title: 'Block',
        start: at('2026-10-05T09:00'),
        end: at('2026-10-05T10:00'),
        kind: EventKind.block,
        taskId: p.id,
      );
      final n = Note(title: 'N');
      r().tasks.save(p);
      r().tasks.save(c);
      r().events.save(block);
      r().notes.save(n);
      r().links.addManual(
        ItemRef(ItemType.task, p.id),
        ItemRef(ItemType.note, n.id),
      );
      d.clearOutbox();

      r().tasks.delete(p.id);

      expect(
        d.waiting,
        unorderedEquals([
          'tasks gone',
          'tasks gone',
          'events gone',
          'links gone',
        ]),
      );
      expect(d.outbox.entry('tasks', c.id)?.deleted, isTrue);
      expect(d.outbox.entry('events', block.id)?.deleted, isTrue);
    });

    test('a deleted list changes the tasks that were in it', () {
      final l = ListItem(name: 'Home');
      final t = TaskItem(title: 'Sweep', listId: l.id);
      r().lists.save(l);
      r().tasks.save(t);
      d.clearOutbox();

      r().lists.delete(l.id);

      expect(d.waiting, unorderedEquals(['lists gone', 'tasks saved']));
    });

    test('tags of a task use a key with two parts', () {
      final t = TaskItem(title: 'Sweep');
      r().tasks.save(t);
      d.clearOutbox();

      r().tags.setTaskTags(t.id, ['home']);

      final tag = r().tags.all().single;
      expect(d.waiting, unorderedEquals(['tags saved', 'task_tags saved']));
      final key = SyncSchema.key([t.id, tag.id]);
      expect(d.outbox.entry('task_tags', key), isNotNull);
      expect(SyncSchema.keyParts(key), [t.id, tag.id]);
    });

    test('a skipped date of a series is saved and removed', () {
      final e = EventItem(
        title: 'Run',
        start: at('2026-10-05T07:00'),
        end: at('2026-10-05T08:00'),
      );
      r().events.save(e);
      d.clearOutbox();

      r().events.addExdate(e.id, DayKey('2026-10-12'));
      expect(d.waiting, ['event_exdates saved']);
      r().events.removeExdate(e.id, DayKey('2026-10-12'));
      expect(d.waiting, ['event_exdates gone']);
    });

    test('a setting with the same value again is no change', () {
      r().settings.set('k', 'v');
      expect(d.waiting, ['settings saved']);
      d.clearOutbox();
      r().settings.set('k', 'v');
      expect(d.waiting, isEmpty);
      r().settings.set('k', 'w');
      expect(d.waiting, ['settings saved']);
    });

    test('goals, notes, lists and images are written down too', () {
      r().goals.upsert(GoalItem(title: 'Read'));
      r().notes.save(Note(title: 'Idea'));
      r().lists.save(ListItem(name: 'Work'));
      r().attachments.add(
        mime: 'image/png',
        data: Uint8List.fromList([1, 2, 3]),
        width: 1,
        height: 1,
      );
      expect(d.waiting, [
        'goals saved',
        'notes saved',
        'lists saved',
        'attachments saved',
      ]);
    });

    test('every change is newer than the one before, also in the same '
        'millisecond', () {
      for (var i = 0; i < 50; i++) {
        r().tasks.save(TaskItem(title: 'T$i'));
      }
      final stamps = [for (final e in d.outbox.entries()) e.stamp];
      expect(stamps.toSet().length, 50);
      expect(stamps, [...stamps]..sort());
    });

    test('the clock never goes back after it saw a later time', () {
      final future = DateTime.now().millisecondsSinceEpoch + 3600000;
      d.outbox.seeClock(future);
      r().tasks.save(TaskItem(title: 'T'));
      expect(d.outbox.entries().single.stamp, future + 1);
      d.outbox.seeClock(5);
      expect(d.outbox.clock, future + 1);
    });

    test('an import replaces everything: old rows gone, new rows saved', () {
      final other = makeRepos();
      final kept = TaskItem(title: 'From the file');
      other.tasks.save(kept);
      final file = DataExport.export(other.db);
      other.db.close();

      final old = TaskItem(title: 'Old');
      r().tasks.save(old);
      d.clearOutbox();
      DataExport.importData(file, r());

      expect(d.outbox.entry('tasks', old.id)?.deleted, isTrue);
      expect(d.outbox.entry('tasks', kept.id)?.deleted, isFalse);
    });

    test('the search index and the outbox are not in the outbox', () {
      r().tasks.save(TaskItem(title: 'T'));
      expect(d.outbox.entries().map((e) => e.table).toSet(), {'tasks'});
    });
  });

  group('The outbox and the schema', () {
    test('rows from before the outbox are put in it, with the lowest rank', () {
      final dir = tempDir('grove-outbox-');
      final path = join(dir, 'o.sqlite');
      var db = Database.open(path);
      final t = TaskItem(title: 'Old');
      Repos(db).tasks.save(t);
      // Take the database back to sync schema 1.
      final triggers = db.query(
        "SELECT name FROM sqlite_master WHERE type = 'trigger' "
        "AND name LIKE 'sync!_%' ESCAPE '!'",
        const [],
        (x) => x.text(0),
      );
      expect(triggers.length, SyncMigrations.syncedTables.length * 3);
      for (final name in triggers) {
        db.executeScript('DROP TRIGGER $name');
      }
      db.executeScript('''
        DROP TABLE outbox;
        DELETE FROM sync_meta WHERE key <> 'schema';
        UPDATE sync_meta SET value = '1' WHERE key = 'schema';
      ''');
      db.close();

      db = Database.open(path);
      final e = Outbox(db).entries().single;
      expect((e.table, e.key, e.stamp, e.deleted), ('tasks', t.id, 0, false));
      Repos(db).tasks.save(t.copyWith(title: 'New'));
      expect(Outbox(db).entries().single.stamp, greaterThan(0));
      db.close();
    });

    test('opening again keeps the outbox and the place in the pull', () {
      final dir = tempDir('grove-outbox-');
      final path = join(dir, 'o.sqlite');
      var db = Database.open(path);
      Repos(db).tasks.save(TaskItem(title: 'T'));
      Outbox(db).cursor = 42;
      db.close();
      db = Database.open(path);
      expect(Outbox(db).count, 1);
      expect(Outbox(db).cursor, 42);
      db.close();
    });

    test('a new column is watched after the next open', () {
      final dir = tempDir('grove-outbox-');
      final path = join(dir, 'o.sqlite');
      var db = Database.open(path);
      final t = TaskItem(title: 'T');
      Repos(db).tasks.save(t);
      db.executeScript(
        "ALTER TABLE tasks ADD COLUMN extra TEXT NOT NULL DEFAULT ''",
      );
      db.close();

      db = Database.open(path);
      db.execute('DELETE FROM outbox');
      db.execute("UPDATE tasks SET extra = 'x' WHERE id = ?", [t.id]);
      expect(Outbox(db).count, 1);
      db.close();
    });

    test('a change to a sync-only column is no change', () {
      final t = TaskItem(title: 'T');
      r().tasks.save(t);
      d.clearOutbox();
      d.db.execute("UPDATE tasks SET user_id = 'u' WHERE id = ?", [t.id]);
      expect(d.outbox.count, 0);
    });

    test('only tags and dated notes have a rule that two rows cannot share '
        'a value', () {
      // The engine joins two such rows into one (see SyncEngine). A new rule
      // of this kind needs the same care, so this test must fail first.
      final found = <String>{};
      for (final table in SyncMigrations.syncedTables) {
        final indexes = d.db.query(
          'PRAGMA index_list($table)',
          const [],
          (x) => (name: x.text(1), unique: x.asBool(2), origin: x.text(3)),
        );
        for (final i in indexes.where((i) => i.unique && i.origin != 'pk')) {
          final cols = d.db.query(
            'PRAGMA index_info(${i.name})',
            const [],
            (x) => x.text(2),
          );
          found.add('$table: ${cols.join(',')}');
        }
      }
      expect(found, {'notes: kind,date', 'tags: name'});
    });

    test('the export file does not hold the outbox', () {
      r().tasks.save(TaskItem(title: 'T'));
      final file = DataExport.export(d.db);
      expect(file, isNot(contains('outbox')));
      expect(file, isNot(contains('sync_meta')));
    });
  });
}
