import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/event.dart';
import 'package:grove/core/model/link.dart';
import 'package:grove/core/model/note.dart';
import 'package:grove/core/model/recurrence.dart';
import 'package:grove/core/model/task.dart';
import 'package:grove/data/data.dart';

import 'helpers.dart';

class _Boom implements Exception {}

void main() {
  group('Database', () {
    test('migrations create the schema', () {
      final db = Database.inMemory();
      expect(db.userVersion, Migrations.all.length);
      final tables = db.query(
        "SELECT name FROM sqlite_master WHERE type IN ('table') ORDER BY name",
        const [],
        (r) => r.text(0),
      );
      for (final t in [
        'tasks',
        'events',
        'notes',
        'lists',
        'links',
        'tags',
        'task_tags',
        'note_tags',
        'settings',
        'event_exdates',
        'search',
        'attachments',
        'goals',
        'block_subtasks',
      ]) {
        expect(tables, contains(t), reason: 'missing table $t');
      }
    });

    test('the shared migrations match the Mac app, seven of them', () {
      // The export file carries this number. The Mac app refuses a higher one.
      expect(Migrations.all.length, 7);
    });

    test('migrations are idempotent', () {
      final dir = tempDir('grove-test-');
      final path = join(dir, 'a.sqlite');
      final first = Repos(Database.open(path));
      first.tasks.save(TaskItem(title: 'keep me'));
      first.db.close();
      final again = Repos(Database.open(path));
      expect(again.tasks.all().map((t) => t.title), ['keep me']);
      again.db.close();
    });

    test('task CRUD', () {
      final r = makeRepos();
      var t = TaskItem(
        title: 'Finish lab report',
        notes: 'use template',
        priority: 3,
        bucket: TaskBucket.day,
        planDate: const DayKey('2026-10-02'),
        due: '2026-10-03',
        estimateMin: 90,
        recurrence: RecurrenceRule(
          freq: Freq.weekly,
          interval: 2,
          weekdays: [1, 3],
        ),
      );
      r.tasks.save(t);
      final got = r.tasks.get(t.id)!;
      expect(got.title, 'Finish lab report');
      expect(got.priority, 3);
      expect(got.planDate, const DayKey('2026-10-02'));
      expect(got.estimateMin, 90);
      expect(
        got.recurrence,
        RecurrenceRule(freq: Freq.weekly, interval: 2, weekdays: [1, 3]),
      );
      t = t.copyWith(
        status: TaskStatus.done,
        completedAt: '2026-10-02T10:00:00',
      );
      r.tasks.save(t);
      expect(r.tasks.get(t.id)?.status, TaskStatus.done);
      expect(r.tasks.all().length, 1);
      r.tasks.delete(t.id);
      expect(r.tasks.get(t.id), isNull);
    });

    test('task queries by bucket', () {
      final r = makeRepos();
      r.tasks.save(
        TaskItem(
          title: 'today',
          bucket: TaskBucket.day,
          planDate: const DayKey('2026-10-02'),
        ),
      );
      r.tasks.save(
        TaskItem(
          title: 'yesterday',
          bucket: TaskBucket.day,
          planDate: const DayKey('2026-10-01'),
        ),
      );
      r.tasks.save(
        TaskItem(
          title: 'week',
          bucket: TaskBucket.week,
          planWeek: const DayKey('2026-09-28'),
        ),
      );
      r.tasks.save(TaskItem(title: 'inbox'));
      r.tasks.save(TaskItem(title: 'later', bucket: TaskBucket.someday));
      expect(r.tasks.forDay(const DayKey('2026-10-02')).map((t) => t.title), [
        'today',
      ]);
      expect(
        r.tasks.overdue(before: const DayKey('2026-10-02')).map((t) => t.title),
        ['yesterday'],
      );
      expect(r.tasks.forWeek(const DayKey('2026-09-28')).map((t) => t.title), [
        'week',
      ]);
      expect(r.tasks.inbox().map((t) => t.title), ['inbox']);
      expect(r.tasks.someday().map((t) => t.title), ['later']);
      expect(
        r.tasks
            .inRange(const DayKey('2026-10-01'), const DayKey('2026-10-02'))
            .length,
        2,
      );
    });

    test('openTopLevel has every open task but no subtasks', () {
      final r = makeRepos();
      final parent = TaskItem(
        title: 'parent',
        bucket: TaskBucket.day,
        planDate: const DayKey('2026-10-02'),
        sort: 2,
      );
      r.tasks.save(parent);
      r.tasks.save(TaskItem(title: 'sub', parentId: parent.id, sort: 3));
      r.tasks.save(TaskItem(title: 'inbox', sort: 1));
      r.tasks.save(
        TaskItem(title: 'someday', bucket: TaskBucket.someday, sort: 4),
      );
      r.tasks.save(TaskItem(title: 'done', status: TaskStatus.done, sort: 5));
      r.tasks.save(
        TaskItem(title: 'cancelled', status: TaskStatus.cancelled, sort: 6),
      );
      r.tasks.save(
        TaskItem(
          title: 'week',
          bucket: TaskBucket.week,
          planWeek: const DayKey('2026-09-28'),
          sort: 0,
        ),
      );
      expect(r.tasks.openTopLevel().map((t) => t.title), [
        'week',
        'inbox',
        'parent',
        'someday',
      ]);
    });

    test('deleting a task cascades to subtasks and blocks', () {
      final r = makeRepos();
      final parent = TaskItem(title: 'parent');
      final child = TaskItem(title: 'child', parentId: parent.id);
      r.tasks.save(parent);
      r.tasks.save(child);
      final block = EventItem(
        title: 'parent',
        start: const WallTime(day: DayKey('2026-10-02'), minute: 600),
        end: const WallTime(day: DayKey('2026-10-02'), minute: 660),
        kind: EventKind.block,
        taskId: parent.id,
      );
      r.events.save(block);
      r.tasks.delete(parent.id);
      expect(r.tasks.get(child.id), isNull);
      expect(r.events.get(block.id), isNull);
    });

    test('saving again does not wipe children', () {
      final r = makeRepos();
      var parent = TaskItem(title: 'parent');
      r.tasks.save(parent);
      r.tasks.save(TaskItem(title: 'child', parentId: parent.id));
      parent = parent.copyWith(title: 'renamed');
      r.tasks.save(parent);
      expect(r.tasks.subtasks(parent.id).length, 1);
    });

    test('events in range and series', () {
      final r = makeRepos();
      final a = EventItem(
        title: 'Dentist',
        start: const WallTime(day: DayKey('2026-10-02'), minute: 840),
        end: const WallTime(day: DayKey('2026-10-02'), minute: 900),
      );
      final b = EventItem(
        title: 'Next week',
        start: const WallTime(day: DayKey('2026-10-09'), minute: 540),
        end: const WallTime(day: DayKey('2026-10-09'), minute: 600),
      );
      final series = EventItem(
        title: 'Standup',
        start: const WallTime(day: DayKey('2026-09-28'), minute: 570),
        end: const WallTime(day: DayKey('2026-09-28'), minute: 585),
        recurrence: RecurrenceRule(freq: Freq.daily),
      );
      for (final e in [a, b, series]) {
        r.events.save(e);
      }
      expect(
        r.events
            .inRange(const DayKey('2026-10-02'), const DayKey('2026-10-02'))
            .map((e) => e.title),
        ['Dentist'],
      );
      expect(
        r.events
            .inRange(const DayKey('2026-10-01'), const DayKey('2026-10-10'))
            .length,
        2,
      );
      expect(r.events.recurringSeries().map((e) => e.title), ['Standup']);
      r.events.addExdate(series.id, const DayKey('2026-10-01'));
      r.events.addExdate(series.id, const DayKey('2026-10-01'));
      expect(r.events.exdates(series.id), [const DayKey('2026-10-01')]);
      r.events.removeExdate(series.id, const DayKey('2026-10-01'));
      expect(r.events.exdates(series.id), isEmpty);
    });

    test('a daily note is unique per day', () {
      final r = makeRepos();
      r.notes.save(
        Note(
          title: 'Fri',
          kind: NoteKind.daily,
          date: const DayKey('2026-10-02'),
        ),
      );
      expect(
        () => r.notes.save(
          Note(
            title: 'Fri again',
            kind: NoteKind.daily,
            date: const DayKey('2026-10-02'),
          ),
        ),
        throwsA(anything),
      );
      expect(r.notes.daily(const DayKey('2026-10-02'))?.title, 'Fri');
      r.notes.save(Note(title: 'Lab 4 — notes', body: 'std dev'));
      expect(r.notes.byTitle('lab 4 — NOTES')?.body, 'std dev');
      expect(r.notes.titles('Lab').length, 1);
    });

    test('note titles treat % and _ as plain letters', () {
      final r = makeRepos();
      r.notes.save(Note(title: '50% off'));
      r.notes.save(Note(title: '500 days'));
      r.notes.save(Note(title: 'a_b'));
      r.notes.save(Note(title: 'axb'));
      expect(r.notes.titles('50%').map((n) => n.title), ['50% off']);
      expect(r.notes.titles('a_').map((n) => n.title), ['a_b']);
    });

    test('tags are case-insensitive and replaceable', () {
      final r = makeRepos();
      final t = TaskItem(title: 'x');
      r.tasks.save(t);
      r.tags.setTaskTags(t.id, ['Home', '#errands']);
      expect(r.tags.tagsForTask(t.id), ['errands', 'Home']);
      r.tags.setTaskTags(t.id, ['home']);
      expect(r.tags.tagsForTask(t.id), ['Home']);
      expect(r.tags.all().length, 2);
      expect(r.tasks.withTag('home').length, 1);
    });

    test('links replace and backlink', () {
      final r = makeRepos();
      const a = ItemRef(ItemType.note, 'A');
      const b = ItemRef(ItemType.note, 'B');
      const t = ItemRef(ItemType.task, 'T');
      r.links.replaceParsed(a, [b, t, b]);
      expect(r.links.backlinks(b).toSet(), {a});
      expect(r.links.outgoing(a).toSet(), {b, t});
      r.links.replaceParsed(a, [t]);
      expect(r.links.backlinks(b), isEmpty);
      r.links.addManual(a, b);
      r.links.replaceParsed(a, []);
      // Manual links survive re-parsing.
      expect(r.links.backlinks(b), [a]);
    });

    test('search finds words and prefixes', () {
      final r = makeRepos();
      r.notes.save(
        Note(title: 'Lab 4', body: 'Error bars must use standard deviation'),
      );
      final t = TaskItem(title: 'Buy oat milk');
      r.tasks.save(t);
      expect(r.search.search('deviation').first.ref.type, ItemType.note);
      expect(r.search.search('stand dev').length, 1);
      expect(r.search.search('oat').first.ref, ItemRef(ItemType.task, t.id));
      expect(r.search.search('oat', types: {ItemType.note}), isEmpty);
      expect(r.search.search('   '), isEmpty);
      r.tasks.delete(t.id);
      expect(r.search.search('oat'), isEmpty);
    });

    test('search ignores accents and quotes', () {
      final r = makeRepos();
      r.notes.save(Note(title: 'Café list', body: 'say "hi"'));
      expect(r.search.search('cafe').length, 1);
      expect(r.search.search('"hi').length, 1);
    });

    test('settings round trip', () {
      final r = makeRepos();
      expect(r.settings.get('theme'), isNull);
      r.settings.set('theme', 'vintage');
      r.settings.set('theme', 'grove');
      expect(r.settings.get('theme'), 'grove');
      r.settings.remove('theme');
      expect(r.settings.get('theme'), isNull);
    });

    test('a transaction rolls back on error', () {
      final r = makeRepos();
      expect(
        () => r.db.transaction(() {
          r.tasks.save(TaskItem(title: 'ghost'));
          throw _Boom();
        }),
        throwsA(isA<_Boom>()),
      );
      expect(r.tasks.all(), isEmpty);
    });

    test('a thousand tasks query is fast', () {
      final r = makeRepos();
      r.db.transaction(() {
        for (var i = 0; i < 1000; i++) {
          final day = const DayKey('2026-10-02').adding(days: i % 30);
          r.tasks.save(
            TaskItem(title: 'Task $i', bucket: TaskBucket.day, planDate: day),
          );
        }
      });
      final clock = Stopwatch()..start();
      final count = r.tasks.forDay(const DayKey('2026-10-05')).length;
      clock.stop();
      expect(count, greaterThan(0));
      expect(clock.elapsedMilliseconds, lessThan(50));
    });
  });

  group('Backup', () {
    test('the daily backup is made once and trimmed', () {
      final dir = tempDir('grove-backup-');
      final r = makeRepos();
      r.tasks.save(TaskItem(title: 'backed up'));
      final folder = join(dir, 'backups');
      expect(
        Backup.runDaily(
          r.db,
          directory: folder,
          today: const DayKey('2026-10-02'),
        ),
        isNotNull,
      );
      expect(
        Backup.runDaily(
          r.db,
          directory: folder,
          today: const DayKey('2026-10-02'),
        ),
        isNull,
      );
      for (var i = 3; i <= 6; i++) {
        Backup.runDaily(
          r.db,
          directory: folder,
          today: DayKey('2026-10-0$i'),
          keep: 3,
        );
      }
      final names = Backup.list(folder)
          .map((p) => p.split(Platform.pathSeparator).last);
      expect(names, [
        'grove-2026-10-06.sqlite',
        'grove-2026-10-05.sqlite',
        'grove-2026-10-04.sqlite',
      ]);
      final copy = Repos(
        Database.open(
          '$folder${Platform.pathSeparator}grove-2026-10-06.sqlite',
        ),
      );
      expect(copy.tasks.all().map((t) => t.title), ['backed up']);
      copy.db.close();
    });

    test('the copy before an import replaces the older one and stays out of '
        'the daily list', () {
      final dir = tempDir('grove-safety-');
      final r = makeRepos();
      r.tasks.save(TaskItem(title: 'first'));
      final one = Backup.safetyCopy(r.db, directory: dir.path);
      r.tasks.save(TaskItem(title: 'second'));
      final two = Backup.safetyCopy(r.db, directory: dir.path);
      expect(one, two);
      expect(two.endsWith('before-import.sqlite'), isTrue);
      expect(Backup.list(dir.path), isEmpty);
      final copy = Repos(Database.open(two));
      expect(copy.tasks.all().map((t) => t.title).toSet(), {'first', 'second'});
      copy.db.close();
    });

    test('the list of a missing folder is empty', () {
      final dir = tempDir('grove-none-');
      expect(Backup.list(join(dir, 'nope')), isEmpty);
    });
  });

  group('Upgrades from an older Mac database', () {
    test('a version 1 database keeps its data', () {
      final dir = tempDir('grove-m2-');
      final path = oldDatabase(
        dir,
        1,
        "INSERT INTO tasks (id, title, created_at, updated_at) VALUES ('t1', "
        "'Old task', '2026-10-01T09:00:00', '2026-10-01T09:00:00');",
      );
      final r = Repos(Database.open(path));
      expect(r.db.userVersion, Migrations.all.length);
      expect(r.tasks.get('t1')?.title, 'Old task');
      expect(r.attachments.count(), 0);
      r.db.close();
    });

    test('a version 2 database keeps its tasks, with no summary', () {
      final dir = tempDir('grove-m3-');
      final path = oldDatabase(
        dir,
        2,
        'INSERT INTO tasks (id, title, notes, created_at, updated_at) VALUES '
        "('t1', 'Old task', 'body', '2026-10-01T09:00:00', "
        "'2026-10-01T09:00:00');",
      );
      final r = Repos(Database.open(path));
      expect(r.db.userVersion, Migrations.all.length);
      final old = r.tasks.get('t1')!;
      expect(old.title, 'Old task');
      expect(old.notes, 'body');
      expect(old.summary, '');
      r.db.close();
    });
  });

  group('Sync columns', () {
    List<String> columns(Database db, String table) =>
        db.query('PRAGMA table_info($table)', const [], (r) => r.text(1));

    test('every synced table gets the sync columns', () {
      final db = Database.inMemory();
      for (final table in DataExport.tables) {
        final cols = columns(db, table);
        expect(cols, contains('deleted'), reason: table);
        expect(cols, contains('user_id'), reason: table);
        expect(cols, contains('updated_at'), reason: table);
      }
      expect(db.syncVersion, SyncMigrations.all.length);
    });

    test('the sync columns do not change the shared schema number', () {
      final db = Database.inMemory();
      expect(db.userVersion, Migrations.all.length);
    });

    test('opening again does not add the sync columns twice', () {
      final dir = tempDir('grove-sync-');
      final path = join(dir, 's.sqlite');
      Database.open(path).close();
      final db = Database.open(path);
      expect(db.syncVersion, SyncMigrations.all.length);
      expect(columns(db, 'tasks').where((c) => c == 'deleted').length, 1);
      db.close();
    });

    test('a new row is not deleted and has no user', () {
      final r = makeRepos();
      final t = TaskItem(title: 'x');
      r.tasks.save(t);
      expect(
        r.db.query('SELECT deleted, user_id FROM tasks WHERE id = ?', [
          t.id,
        ], (row) => (row.asInt(0), row.optText(1))),
        [(0, null)],
      );
    });
  });
}
