import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/event.dart';
import 'package:grove/core/model/goal.dart';
import 'package:grove/core/model/link.dart';
import 'package:grove/core/model/note.dart';
import 'package:grove/core/model/recurrence.dart';
import 'package:grove/core/model/task.dart';
import 'package:grove/data/data.dart';

import 'goal_repo_test.dart' show block, monday, sunday;
import 'helpers.dart';

/// A small world that touches every table.
void fill(Repos r) {
  const day = DayKey('2026-10-05');
  r.lists.save(ListItem(id: 'L1', name: 'Home', emoji: '🌿'));
  r.notes.save(
    Note(
      id: 'N1',
      title: 'Garden ideas',
      body: 'Plant #herbs and see [[Water plants|T1]]',
    ),
  );
  r.notes.save(
    Note(
      id: 'N2',
      title: 'Monday',
      body: 'Daily',
      kind: NoteKind.daily,
      date: day,
      mood: 3,
    ),
  );
  r.tasks.save(
    TaskItem(
      id: 'T1',
      title: 'Water plants',
      summary: 'every other day',
      notes: 'Use rain water',
      listId: 'L1',
      bucket: TaskBucket.day,
      planDate: day,
      estimateMin: 20,
      recurrence: RecurrenceRule(freq: Freq.weekly, weekdays: [1, 4]),
      sourceNoteId: 'N1',
    ),
  );
  r.tasks.save(TaskItem(id: 'T2', title: 'Fill the can', parentId: 'T1'));
  r.tags.setTaskTags('T1', ['garden']);
  r.tags.setNoteTags('N1', ['herbs']);
  r.events.save(
    EventItem(
      id: 'E1',
      title: 'Stand-up',
      start: const WallTime(day: day, minute: 570),
      end: const WallTime(day: day, minute: 600),
      recurrence: RecurrenceRule(freq: Freq.daily),
    ),
  );
  r.events.addExdate('E1', day.adding(days: 1));
  r.events.save(
    EventItem(
      id: 'E2',
      title: 'Water plants',
      start: const WallTime(day: day, minute: 660),
      end: const WallTime(day: day, minute: 680),
      kind: EventKind.block,
      taskId: 'T1',
    ),
  );
  r.links.addManual(
    const ItemRef(ItemType.note, 'N1'),
    const ItemRef(ItemType.task, 'T1'),
  );
  r.settings.set('welcome.shown', '1');
  r.db.execute(
    'INSERT INTO attachments (id, mime, data, width, height, created_at) '
    'VALUES (?, ?, ?, ?, ?, ?)',
    [
      'A1',
      'image/png',
      Uint8List.fromList([0, 1, 2, 255, 254]),
      4,
      3,
      '2026-10-05T08:00:00',
    ],
  );
}

Map<String, dynamic> decode(String text) =>
    jsonDecode(text) as Map<String, dynamic>;

/// The file as JSON, changed by [edit], back to text.
String edited(Repos r, void Function(Map<String, dynamic> tables) edit) {
  final obj = decode(DataExport.export(r.db));
  edit(obj['tables'] as Map<String, dynamic>);
  return jsonEncode(obj);
}

Repos keeper() {
  final r = makeRepos();
  r.tasks.save(TaskItem(id: 'KEEP', title: 'Keep me'));
  return r;
}

void expectRefused(String data, Repos r) {
  expect(() => DataExport.importData(data, r), throwsA(isA<ExportFailure>()));
  expect(r.tasks.get('KEEP')?.title, 'Keep me');
  expect(r.search.search('Keep').length, 1);
}

void main() {
  group('the file', () {
    test('names its format and holds every table', () {
      final r = makeRepos();
      fill(r);
      final obj = decode(DataExport.export(r.db));
      expect(obj['format'], 'grove-export');
      expect(obj['version'], 1);
      expect(obj['schema'], r.db.userVersion);
      final tables = obj['tables'] as Map<String, dynamic>;
      expect(tables.keys.toSet(), DataExport.tables.toSet());
      expect((tables['tasks'] as List).length, 2);
      expect((tables['events'] as List).length, 2);
      expect((tables['notes'] as List).length, 2);
      expect((tables['event_exdates'] as List).length, 1);
      expect((tables['attachments'] as List).length, 1);
    });

    test('the search index is not in the file', () {
      final r = makeRepos();
      fill(r);
      final tables = decode(DataExport.export(r.db))['tables'] as Map;
      expect(tables.containsKey('search'), isFalse);
    });

    test(
      'the sync columns are not in the file, so the Mac app can read it',
      () {
        final r = makeRepos();
        fill(r);
        final tables = decode(DataExport.export(r.db))['tables'] as Map;
        for (final name in DataExport.tables) {
          for (final row in tables[name] as List) {
            final keys = (row as Map).keys;
            expect(keys, isNot(contains('deleted')), reason: name);
            expect(keys, isNot(contains('user_id')), reason: name);
          }
        }
        final list = (tables['lists'] as List).first as Map;
        expect(list.keys, isNot(contains('updated_at')));
        final task = (tables['tasks'] as List).first as Map;
        expect(task.keys, contains('updated_at'));
      },
    );

    test('the file has the same rows and columns as a Mac export', () {
      final mac = decode(
        File('test/fixtures/mac_export_v6.json').readAsStringSync(),
      );
      final r = makeRepos();
      DataExport.importData(jsonEncode(mac), r);
      final ours = decode(DataExport.export(r.db));
      expect(ours['schema'], mac['schema']);
      final a = mac['tables'] as Map<String, dynamic>;
      final b = ours['tables'] as Map<String, dynamic>;
      expect(b.keys.toSet(), a.keys.toSet());
      for (final name in a.keys) {
        final macRows = a[name] as List;
        final ourRows = b[name] as List;
        expect(ourRows.length, macRows.length, reason: name);
        for (var i = 0; i < macRows.length; i++) {
          final want = macRows[i] as Map;
          final got = ourRows[i] as Map;
          expect(got.keys.toSet(), want.keys.toSet(), reason: name);
          for (final key in want.keys) {
            // Swift writes 0 for a real 0.0. Compare numbers by value.
            final w = want[key], g = got[key];
            if (w is num && g is num) {
              expect(g.toDouble(), w.toDouble(), reason: '$name.$key');
            } else {
              expect(g, w, reason: '$name.$key');
            }
          }
        }
      }
    });

    test('the keys are sorted and slashes are not escaped', () {
      final r = makeRepos();
      r.notes.save(Note(id: 'N', title: 'a/b'));
      final text = DataExport.export(r.db);
      expect(text, contains('"a/b"'));
      expect(text.indexOf('"exportedAt"'), lessThan(text.indexOf('"format"')));
      expect(text.indexOf('"format"'), lessThan(text.indexOf('"tables"')));
    });

    test('the file tells what is inside without changing anything', () {
      final r = makeRepos();
      fill(r);
      final s = DataExport.summary(DataExport.export(r.db));
      expect(
        s,
        const ExportSummary(tasks: 2, events: 2, notes: 2, lists: 1, images: 1),
      );
    });

    test('the suggested file name has the day', () {
      expect(
        DataExport.suggestedFileName(const DayKey('2026-10-04')),
        'grove-export-2026-10-04.json',
      );
    });
  });

  group('JSON from the Mac app', () {
    late Repos r;
    setUp(() {
      r = makeRepos();
      DataExport.importData(
        File('test/fixtures/mac_export_v6.json').readAsStringSync(),
        r,
      );
    });

    test('imports every item', () {
      expect(r.tasks.all().length, 2);
      expect(r.events.all().length, 3);
      expect(r.notes.all().length, 2);
      expect(r.lists.all().single.emoji, '🌿');
      expect(r.goals.get('G1')?.targetMin, 360);
      expect(r.attachments.get('A1')?.data, [0, 1, 2, 255, 254]);
    });

    test('keeps the details', () {
      final t = r.tasks.get('T1')!;
      expect(t.recurrence, RecurrenceRule(freq: Freq.weekly, weekdays: [1, 4]));
      expect(t.summary, 'every other day');
      expect(t.planDate, const DayKey('2026-10-05'));
      expect(r.tasks.get('T2')?.parentId, 'T1');
      expect(r.tasks.get('T2')?.color, 'teal');
      expect(r.events.get('E3')?.goalId, 'G1');
      expect(r.events.get('E3')?.doneAt, '2026-10-05T21:30:00');
      expect(r.events.exdates('E1'), [const DayKey('2026-10-06')]);
      expect(r.notes.daily(const DayKey('2026-10-05'))?.mood, 3);
      expect(r.tags.tagsForTask('T1'), ['garden']);
      expect(r.tags.tagsForNote('N1'), ['herbs']);
      expect(r.settings.get('welcome.shown'), '1');
      expect(
        r.links.backlinks(const ItemRef(ItemType.task, 'T1')),
        contains(const ItemRef(ItemType.note, 'N1')),
      );
    });

    test('search works after the import', () {
      expect(r.search.search('rain').map((h) => h.ref), [
        const ItemRef(ItemType.task, 'T1'),
      ]);
    });

    test('the imported rows are not deleted and have no user', () {
      expect(
        r.db.query(
          'SELECT COUNT(*) FROM tasks WHERE deleted = 0 AND user_id IS NULL',
          const [],
          (x) => x.asInt(0),
        ),
        [2],
      );
    });
  });

  group('round trip', () {
    test('import gives back everything that was exported', () {
      final a = makeRepos();
      fill(a);
      final b = makeRepos();
      DataExport.importData(DataExport.export(a.db), b);
      expect(b.tasks.all().toSet(), a.tasks.all().toSet());
      expect(b.events.all().toSet(), a.events.all().toSet());
      expect(b.notes.all().toSet(), a.notes.all().toSet());
      expect(b.lists.all(), a.lists.all());
      expect(b.tags.tagsForTask('T1'), ['garden']);
      expect(b.tags.tagsForNote('N1'), ['herbs']);
      expect(b.events.exdates('E1'), [const DayKey('2026-10-06')]);
      expect(
        b.links.backlinks(const ItemRef(ItemType.task, 'T1')),
        contains(const ItemRef(ItemType.note, 'N1')),
      );
      expect(b.settings.get('welcome.shown'), '1');
      expect(b.attachments.get('A1')?.data, [0, 1, 2, 255, 254]);
      expect(b.attachments.get('A1')?.width, 4);
    });

    test('a task keeps its repeat rule and its parent', () {
      final a = makeRepos();
      fill(a);
      final b = makeRepos();
      DataExport.importData(DataExport.export(a.db), b);
      expect(
        b.tasks.get('T1')?.recurrence,
        RecurrenceRule(freq: Freq.weekly, weekdays: [1, 4]),
      );
      expect(b.tasks.get('T2')?.parentId, 'T1');
      expect(b.events.get('E2')?.taskId, 'T1');
    });

    test('search works after an import', () {
      final a = makeRepos();
      fill(a);
      final b = makeRepos();
      DataExport.importData(DataExport.export(a.db), b);
      expect(b.search.search('garden').map((h) => h.ref), [
        const ItemRef(ItemType.note, 'N1'),
      ]);
      expect(b.search.search('rain').map((h) => h.ref), [
        const ItemRef(ItemType.task, 'T1'),
      ]);
    });

    test('import replaces what was there', () {
      final a = makeRepos();
      fill(a);
      final b = makeRepos();
      b.tasks.save(TaskItem(id: 'OLD', title: 'Old task'));
      b.notes.save(Note(id: 'OLDN', title: 'Old note'));
      DataExport.importData(DataExport.export(a.db), b);
      expect(b.tasks.get('OLD'), isNull);
      expect(b.notes.get('OLDN'), isNull);
      expect(b.search.search('Old'), isEmpty);
      expect(b.tasks.all().length, 2);
    });

    test('importing twice changes nothing', () {
      final a = makeRepos();
      fill(a);
      DataExport.importData(DataExport.export(a.db), a);
      expect(a.tasks.all().length, 2);
      expect(a.events.all().length, 2);
      expect(a.attachments.count(), 1);
    });

    test('a task colour comes back from an export file', () {
      final a = makeRepos();
      a.tasks.save(TaskItem(id: 'T1', title: 'Paint', color: 'pink'));
      final b = makeRepos();
      DataExport.importData(DataExport.export(a.db), b);
      expect(b.tasks.get('T1')?.color, 'pink');
    });

    test('a file from before colours still imports', () {
      final b = makeRepos();
      const old =
          '{"format":"grove-export","version":1,"schema":3,"tables":{"tasks":['
          '{"id":"T1","title":"Old","notes":"","summary":"","priority":2,'
          '"status":"open","bucket":"inbox","estimate_min":30,"sort":0,'
          '"created_at":"2026-10-01T08:00:00",'
          '"updated_at":"2026-10-01T08:00:00"}]}}';
      DataExport.importData(old, b);
      expect(b.tasks.get('T1')?.color, '');
      expect(b.tasks.get('T1')?.priority, 2);
    });

    test('a missing table is the same as an empty one', () {
      final a = makeRepos();
      fill(a);
      final data = edited(a, (t) => t.remove('settings'));
      final b = keeper();
      DataExport.importData(data, b);
      expect(b.tasks.get('KEEP'), isNull);
      expect(b.tasks.all().length, 2);
      expect(b.settings.get('welcome.shown'), isNull);
    });
  });

  group('goals in the file', () {
    void fillGoals(Repos r) {
      r.goals.upsert(
        GoalItem(
          id: 'G1',
          title: 'Read',
          notes: 'Novels',
          color: 'blue',
          targetMin: 360,
          sort: 1,
        ),
      );
      r.goals.upsert(
        GoalItem(
          id: 'G2',
          title: 'Run',
          targetMin: 180,
          sort: 2,
          archived: true,
          kind: GoalKind.sessions,
          targetCount: 4,
        ),
      );
      block(r, goal: 'G1', day: monday, to: 690, done: true, id: 'E1');
      block(r, goal: 'G1', day: monday.adding(days: 1), id: 'E2');
      r.tasks.save(TaskItem(id: 'T1', title: 'Write'));
    }

    test('goals and their blocks come back from an export file', () {
      final a = makeRepos();
      fillGoals(a);
      final b = makeRepos();
      DataExport.importData(DataExport.export(a.db), b);
      expect(
        b.goals.all(includeArchived: true),
        a.goals.all(includeArchived: true),
      );
      expect(b.goals.get('G1')?.notes, 'Novels');
      expect(b.goals.get('G2')?.archived, isTrue);
      expect(b.goals.get('G2')?.kind, GoalKind.sessions);
      expect(b.goals.get('G2')?.targetCount, 4);
      expect(b.events.get('E1')?.goalId, 'G1');
      expect(b.goals.minutes('G1', from: monday, to: sunday), 150);
      expect(b.goals.sessions('G1', from: monday, to: sunday), 2);
    });

    test('the file holds the goals table', () {
      final a = makeRepos();
      fillGoals(a);
      expect(DataExport.tables, contains('goals'));
      final tables = decode(DataExport.export(a.db))['tables'] as Map;
      expect((tables['goals'] as List).length, 2);
      expect(((tables['events'] as List).first as Map)['goal_id'], 'G1');
    });

    test('importing replaces the goals that were there', () {
      final a = makeRepos();
      fillGoals(a);
      final b = makeRepos();
      b.goals.upsert(GoalItem(id: 'OLD', title: 'Old goal'));
      DataExport.importData(DataExport.export(a.db), b);
      expect(b.goals.get('OLD'), isNull);
      expect(b.goals.all(includeArchived: true).length, 2);
    });

    test('a file with goals but no kind imports them as hour goals', () {
      final a = makeRepos();
      fillGoals(a);
      final obj = decode(DataExport.export(a.db));
      for (final row in (obj['tables'] as Map)['goals'] as List) {
        (row as Map)
          ..remove('kind')
          ..remove('target_count');
      }
      obj['schema'] = 5;
      final b = makeRepos();
      DataExport.importData(jsonEncode(obj), b);
      final goals = b.goals.all(includeArchived: true);
      expect(goals.length, 2);
      expect(
        goals.every((g) => g.kind == GoalKind.hours && g.targetCount == 3),
        isTrue,
      );
      expect(b.goals.get('G2')?.targetMin, 180);
    });

    test('an old file without goals still imports', () {
      final a = makeRepos();
      fillGoals(a);
      final obj = decode(DataExport.export(a.db));
      final tables = obj['tables'] as Map;
      tables.remove('goals');
      for (final row in tables['events'] as List) {
        (row as Map)
          ..remove('goal_id')
          ..remove('done_at');
      }
      obj['schema'] = 4;
      final b = makeRepos();
      b.goals.upsert(GoalItem(id: 'OLD', title: 'Old goal'));
      DataExport.importData(jsonEncode(obj), b);
      expect(b.goals.all(includeArchived: true), isEmpty);
      final e = b.events.get('E1')!;
      expect(e.goalId, isNull);
      expect(e.doneAt, isNull);
      expect(e.title, 'Block');
      expect(b.tasks.get('T1')?.title, 'Write');
    });
  });

  group('bad files change nothing', () {
    test('text that is not JSON is refused', () {
      expectRefused('not a file', keeper());
    });

    test('another kind of JSON is refused', () {
      expectRefused(
        '{"format":"something-else","version":1,"schema":3,"tables":{}}',
        keeper(),
      );
    });

    test('a JSON list is refused', () {
      expectRefused('[1, 2]', keeper());
    });

    test('a newer file format is refused', () {
      expectRefused(
        '{"format":"grove-export","version":99,"schema":3,"tables":{}}',
        keeper(),
      );
    });

    test('a file from a newer schema is refused', () {
      final r = keeper();
      expectRefused(
        '{"format":"grove-export","version":1,'
        '"schema":${r.db.userVersion + 1},"tables":{}}',
        r,
      );
    });

    test('a table that does not exist is refused', () {
      expectRefused(
        '{"format":"grove-export","version":1,"schema":1,'
        '"tables":{"sqlite_master":[{"name":"x"}]}}',
        keeper(),
      );
    });

    test('a column that does not exist is refused', () {
      final a = makeRepos();
      fill(a);
      final data = edited(
        a,
        (t) =>
            (t['lists'] as List).cast<Map<String, dynamic>>().first['shape'] =
                1,
      );
      expectRefused(data, keeper());
    });

    test('a broken row stops the import and keeps the old data', () {
      // A task with no title breaks the NOT NULL rule half way through.
      final a = makeRepos();
      fill(a);
      final data = edited(a, (t) {
        t['tasks'] = [
          {'id': 'BAD'},
        ];
      });
      expectRefused(data, keeper());
    });

    test('a row that points at nothing is refused', () {
      // A task in a list that is not in the file breaks the link rule at the end.
      final a = makeRepos();
      fill(a);
      final data = edited(a, (t) => t['lists'] = <Object>[]);
      expectRefused(data, keeper());
    });

    test('a damaged picture is refused', () {
      final a = makeRepos();
      fill(a);
      final data = edited(
        a,
        (t) =>
            (t['attachments'] as List)
                    .cast<Map<String, dynamic>>()
                    .first['data'] =
                '***not base64***',
      );
      expectRefused(data, keeper());
    });

    test('a table that is not a list of rows is refused', () {
      expectRefused(
        '{"format":"grove-export","version":1,"schema":1,'
        '"tables":{"tasks":{"id":"x"}}}',
        keeper(),
      );
    });

    test('an empty row is refused', () {
      expectRefused(
        '{"format":"grove-export","version":1,"schema":1,'
        '"tables":{"tags":[{}]}}',
        keeper(),
      );
    });

    test('a failure has a plain message', () {
      expect(
        ExportFailure.notAGroveFile.message,
        'This is not a Grove export file.',
      );
      expect(
        const ExportFailure.badData('Why.').message,
        'The file has a problem. Why.',
      );
    });
  });
}
