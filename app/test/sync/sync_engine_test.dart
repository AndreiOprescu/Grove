import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// A remote that runs a callback each time a push arrived.
class HookRemote extends MemoryRemote {
  Future<void> Function()? afterPush;

  /// Runs when a pull has its rows, before the device gets them.
  void Function()? duringPull;

  @override
  Future<List<RowChange>> pull({required int after, required int limit}) async {
    final page = await super.pull(after: after, limit: limit);
    duringPull?.call();
    return page;
  }

  @override
  Future<void> push(List<RowChange> changes) async {
    await super.push(changes);
    await afterPush?.call();
  }
}

/// One row of every synced table.
void fill(Device d) {
  final r = d.repos;
  final list = ListItem(name: 'Home', emoji: '🌿');
  final note = Note(title: 'Idea', body: 'A plum tree');
  final goal = GoalItem(title: 'Read');
  final task = TaskItem(title: 'Sweep', listId: list.id, sourceNoteId: note.id);
  final sub = TaskItem(title: 'Find the broom', parentId: task.id);
  final event = EventItem(
    title: 'Standup',
    start: at('2026-10-05T09:00'),
    end: at('2026-10-05T09:15'),
  );
  final block = EventItem(
    title: 'Sweep',
    start: at('2026-10-05T10:00'),
    end: at('2026-10-05T11:00'),
    kind: EventKind.block,
    taskId: task.id,
  );
  final goalBlock = EventItem(
    title: 'Read',
    start: at('2026-10-05T14:00'),
    end: at('2026-10-05T15:00'),
    kind: EventKind.block,
    goalId: goal.id,
  );
  r.lists.save(list);
  r.notes.save(note);
  r.goals.upsert(goal);
  r.tasks.save(task);
  r.tasks.save(sub);
  r.events.save(event);
  r.events.save(block);
  r.events.save(goalBlock);
  r.blockSubtasks.save(
    BlockSubtaskItem(eventId: goalBlock.id, title: 'Chapter 3'),
  );
  r.events.addExdate(event.id, DayKey('2026-10-12'));
  r.links.addManual(
    ItemRef(ItemType.note, note.id),
    ItemRef(ItemType.task, task.id),
  );
  r.tags.setTaskTags(task.id, ['chores']);
  r.tags.setNoteTags(note.id, ['garden']);
  r.settings.set('template.daily', '## Plan');
  r.attachments.add(
    mime: 'image/png',
    data: Uint8List.fromList([137, 80, 78, 71, 0, 255]),
    width: 2,
    height: 3,
  );
}

void randomOp(Device d, Random rnd) {
  final r = d.repos;
  T? pick<T>(List<T> xs) => xs.isEmpty ? null : xs[rnd.nextInt(xs.length)];
  final tasks = r.tasks.all();
  final lists = r.lists.all(includeArchived: true);
  final notes = r.notes.all();
  final events = r.events.all();
  final task = pick(tasks);
  final event = pick(events);
  final note = pick(notes);
  switch (rnd.nextInt(14)) {
    case 0 || 1:
      final parent = rnd.nextInt(3) == 0
          ? pick(tasks.where((t) => t.parentId == null).toList())
          : null;
      r.tasks.save(
        TaskItem(
          title: 'T${rnd.nextInt(1000)}',
          listId: rnd.nextBool() ? pick(lists)?.id : null,
          parentId: parent?.id,
        ),
      );
    case 2:
      if (task != null) {
        r.tasks.save(task.copyWith(title: 'E${rnd.nextInt(1000)}'));
      }
    case 3:
      if (task != null) r.tasks.delete(task.id);
    case 4:
      r.lists.save(ListItem(name: 'L${rnd.nextInt(1000)}'));
    case 5:
      final list = pick(lists);
      if (list != null) r.lists.delete(list.id);
    case 6:
      if (task != null) {
        r.tags.setTaskTags(task.id, [
          for (final n in ['red', 'green', 'blue'])
            if (rnd.nextBool()) n,
        ]);
      }
    case 7:
      final day = DayKey('2026-10-0${1 + rnd.nextInt(3)}');
      final old = r.notes.daily(day);
      r.notes.save(
        old == null
            ? Note(
                title: day.string,
                kind: NoteKind.daily,
                date: day,
                body: 'w${rnd.nextInt(1000)}',
              )
            : old.copyWith(body: '${old.body}\nmore${rnd.nextInt(1000)}'),
      );
    case 8:
      r.settings.set('k${rnd.nextInt(3)}', 'v${rnd.nextInt(1000)}');
    case 9:
      if (task != null) {
        r.events.save(
          EventItem(
            title: 'B${rnd.nextInt(1000)}',
            start: at('2026-10-05T09:00'),
            end: at('2026-10-05T10:00'),
            kind: EventKind.block,
            taskId: task.id,
          ),
        );
      }
    case 10:
      if (event != null) r.events.delete(event.id);
    case 11:
      if (event != null) {
        r.events.addExdate(event.id, DayKey('2026-10-1${rnd.nextInt(3)}'));
      }
    case 12:
      if (task != null && note != null) {
        r.links.addManual(
          ItemRef(ItemType.task, task.id),
          ItemRef(ItemType.note, note.id),
        );
        r.tasks.save(task.copyWith(sourceNoteId: note.id));
      }
    case 13:
      if (note != null) {
        if (rnd.nextBool()) {
          r.notes.delete(note.id);
        } else {
          r.tags.setNoteTags(note.id, ['red', 'pink']);
        }
      }
  }
}

void main() {
  late MemoryRemote remote;
  late Device a, b;

  setUp(() {
    remote = MemoryRemote();
    a = Device(remote);
    b = Device(remote);
  });

  /// A task that both devices have.
  Future<TaskItem> shared(String title) async {
    final t = TaskItem(title: title);
    a.repos.tasks.save(t);
    await a.sync();
    await b.sync();
    return t;
  }

  group('Push and pull', () {
    test('a sync sends the waiting changes and empties the outbox', () async {
      final t = TaskItem(title: 'Buy milk');
      a.repos.tasks.save(t);

      final report = await a.sync();

      expect(report.pushed, 1);
      expect(a.outbox.count, 0);
      expect(remoteRows(remote, 'tasks'), ['${t.id} saved']);
      expect(remote.rows.single.data['title'], 'Buy milk');
    });

    test('a second device gets every kind of row', () async {
      fill(a);
      await a.sync();
      final report = await b.sync();

      expect(report.pushed, 0);
      expect(report.pulled, greaterThan(12));
      expect(report.skipped, isEmpty);
      for (final table in SyncMigrations.syncedTables) {
        expect(dump(b.db)[table], isNotEmpty, reason: table);
      }
      expectSame([a, b]);
    });

    test('the device does not send back what it pulled', () async {
      fill(a);
      await a.sync();
      await b.sync();
      expect(b.outbox.count, 0);
      final pushes = remote.pushCalls;
      await b.sync();
      expect(remote.pushCalls, pushes);
    });

    test('pulled tasks, events and notes can be found by search', () async {
      fill(a);
      await a.sync();
      await b.sync();
      List<String> found(String q) => [
        for (final h in b.repos.search.search(q)) h.title,
      ];
      expect(found('broom'), ['Find the broom']);
      expect(found('standup'), ['Standup']);
      expect(found('plum'), ['Idea']);
    });

    test('a sync with nothing to do moves nothing', () async {
      fill(a);
      await a.sync();
      final report = await a.sync();
      expect((report.pushed, report.pulled), (0, 0));
    });

    test('a change travels', () async {
      final t = await shared('Buy milk');
      a.later();
      a.repos.tasks.save(t.copyWith(title: 'Buy oat milk'));
      await a.sync();
      await b.sync();
      expect(b.repos.tasks.get(t.id)!.title, 'Buy oat milk');
    });

    test('a delete travels, with everything that hung on the row', () async {
      fill(a);
      await a.sync();
      await b.sync();
      final task = a.repos.tasks.all().firstWhere((t) => t.title == 'Sweep');

      a.later();
      a.repos.tasks.delete(task.id);
      await a.sync();
      await b.sync();

      expect(b.repos.tasks.all(), isEmpty);
      // The block of the task went with it. The goal block has no task: it
      // stays, with its subtask.
      final left = b.repos.events.all();
      expect(left.map((e) => e.title), ['Standup', 'Read']);
      expect(b.repos.blockSubtasks.forEvent(left.last.id).map((s) => s.title), [
        'Chapter 3',
      ]);
      expect(b.repos.search.search('broom'), isEmpty);
      expect(b.outbox.count, 0);
      expectSame([a, b]);
    });

    test('rows come in pages', () async {
      final small = Device(remote, pageSize: 2);
      final other = Device(remote, pageSize: 3);
      for (var i = 0; i < 7; i++) {
        small.repos.tasks.save(TaskItem(title: 'T$i'));
      }
      final sent = await small.sync();
      expect(sent.pushed, 7);
      expect(remote.pushCalls, 4);

      final got = await other.sync();
      expect(got.pulled, 7);
      expectSame([small, other]);
    });

    test('the device remembers how far it pulled', () async {
      fill(a);
      await a.sync();
      await b.sync();
      expect(b.outbox.cursor, remote.lastSeq);
      final pulls = remote.pullCalls;
      final report = await b.sync();
      expect(report.pulled, 0);
      expect(remote.pullCalls, pulls + 1);
    });
  });

  group('Offline', () {
    test(
      'offline: the sync throws, nothing is lost, the next sync works',
      () async {
        a.repos.tasks.save(TaskItem(title: 'Written on the train'));
        remote.offline = true;
        await expectLater(a.sync(), throwsA(isA<RemoteUnavailable>()));
        expect(a.outbox.count, 1);
        expect(a.repos.tasks.all().single.title, 'Written on the train');

        remote.offline = false;
        await a.sync();
        await b.sync();
        expect(b.repos.tasks.all().single.title, 'Written on the train');
      },
    );

    test(
      'a push that stops half way loses nothing and doubles nothing',
      () async {
        for (var i = 0; i < 4; i++) {
          a.repos.tasks.save(TaskItem(title: 'T$i'));
        }
        remote.failPushAfter = 2;
        await expectLater(a.sync(), throwsA(isA<RemoteUnavailable>()));
        expect(a.outbox.count, 4);

        await a.sync();
        await b.sync();
        expect(remote.rows.length, 4);
        expect(b.repos.tasks.all().length, 4);
        expectSame([a, b]);
      },
    );

    test('a pull that stops half way changes nothing', () async {
      for (var i = 0; i < 5; i++) {
        a.repos.tasks.save(TaskItem(title: 'T$i'));
      }
      await a.sync();
      final c = Device(remote, pageSize: 2);
      remote.failPullAfter = 1;
      await expectLater(c.sync(), throwsA(isA<RemoteUnavailable>()));
      expect(c.repos.tasks.all(), isEmpty);
      expect(c.outbox.cursor, 0);

      await c.sync();
      expectSame([a, c]);
    });

    test(
      'a change made while the push is on its way stays in the outbox',
      () async {
        final hooked = HookRemote();
        final d = Device(hooked);
        final t = TaskItem(title: 'First');
        d.repos.tasks.save(t);
        hooked.afterPush = () async {
          hooked.afterPush = null;
          d.repos.tasks.save(t.copyWith(title: 'Second'));
        };

        await d.sync();

        expect(hooked.rows.single.data['title'], 'Second');
        expect(d.outbox.count, 0);
        expect(d.repos.tasks.get(t.id)!.title, 'Second');
      },
    );

    test('two sync calls at the same time are one run', () async {
      a.repos.tasks.save(TaskItem(title: 'T'));
      final first = a.sync();
      final second = a.sync();
      expect(identical(first, second), isTrue);
      await first;
      expect(remote.pushCalls, 1);
      expect(a.engine.isSyncing, isFalse);
    });

    test('after a failed sync a new sync can start', () async {
      remote.offline = true;
      a.repos.tasks.save(TaskItem(title: 'T'));
      await expectLater(a.sync(), throwsA(isA<RemoteUnavailable>()));
      expect(a.engine.isSyncing, isFalse);
      remote.offline = false;
      expect((await a.sync()).pushed, 1);
    });
  });

  group('Last write wins', () {
    test('two devices change the same task: the later change stays', () async {
      final t = await shared('Start');
      a.later();
      a.repos.tasks.save(t.copyWith(title: 'From A'));
      b.later();
      b.repos.tasks.save(t.copyWith(title: 'From B'));

      await settle([a, b]);

      expect(a.repos.tasks.get(t.id)!.title, 'From B');
      expectSame([a, b]);
    });

    test('the later change stays when its device syncs first too', () async {
      final t = await shared('Start');
      a.later();
      a.repos.tasks.save(t.copyWith(title: 'From A'));
      b.later();
      b.repos.tasks.save(t.copyWith(title: 'From B'));

      await settle([b, a]);

      expect(a.repos.tasks.get(t.id)!.title, 'From B');
      expectSame([a, b]);
    });

    test('a later delete wins over a change', () async {
      final t = await shared('Start');
      a.later();
      a.repos.tasks.save(t.copyWith(title: 'From A'));
      b.later();
      b.repos.tasks.delete(t.id);

      await settle([a, b]);

      expect(a.repos.tasks.all(), isEmpty);
      expect(b.repos.tasks.all(), isEmpty);
    });

    test('a later change wins over a delete: the row comes back', () async {
      final t = await shared('Start');
      a.later();
      a.repos.tasks.delete(t.id);
      b.later();
      b.repos.tasks.save(t.copyWith(title: 'Still needed'));

      await settle([a, b]);

      expect(a.repos.tasks.get(t.id)!.title, 'Still needed');
      expectSame([a, b]);
    });

    test(
      'two changes of the same age: both devices end with the same row',
      () async {
        final t = await shared('Start');
        final time = DateTime.now().millisecondsSinceEpoch + 86400000;
        a.outbox.seeClock(time);
        b.outbox.seeClock(time);
        a.repos.tasks.save(t.copyWith(title: 'From A'));
        b.repos.tasks.save(t.copyWith(title: 'From B'));
        expect(
          a.outbox.entry('tasks', t.id)!.stamp,
          b.outbox.entry('tasks', t.id)!.stamp,
        );

        await settle([a, b]);

        expectSame([a, b]);
      },
    );

    test('a change of the same age made while the pull is on its way: the '
        'remote row wins on both devices', () async {
      final hooked = HookRemote();
      final first = Device(hooked), second = Device(hooked);
      final t = TaskItem(title: 'Start');
      first.repos.tasks.save(t);
      await settle([first, second]);

      final time = DateTime.now().millisecondsSinceEpoch + 86400000;
      first.outbox.seeClock(time);
      first.repos.tasks.save(t.copyWith(title: 'From the first'));
      await first.sync();
      hooked.duringPull = () {
        hooked.duringPull = null;
        second.outbox.seeClock(time);
        second.repos.tasks.save(t.copyWith(title: 'From the second'));
      };
      await second.sync();

      expect(second.repos.tasks.get(t.id)!.title, 'From the first');
      await settle([first, second]);
      expectSame([first, second]);
    });

    test('a change is newer than everything the device has seen, also when '
        'its clock is behind', () async {
      final t = await shared('Start');
      // The clock of B is a day ahead.
      b.outbox.seeClock(DateTime.now().millisecondsSinceEpoch + 86400000);
      b.repos.tasks.save(t.copyWith(title: 'From B'));
      await b.sync();
      await a.sync();
      // A changes the task after it saw the change of B.
      a.repos.tasks.save(t.copyWith(title: 'From A, after B'));

      await settle([a, b]);

      expect(b.repos.tasks.get(t.id)!.title, 'From A, after B');
    });

    test('the whole row of the later change wins, not single fields', () async {
      final t = await shared('Start');
      a.later();
      a.repos.tasks.save(t.copyWith(title: 'New title'));
      b.later();
      b.repos.tasks.save(t.copyWith(priority: 1));

      await settle([a, b]);

      final end = a.repos.tasks.get(t.id)!;
      expect((end.title, end.priority), ('Start', 1));
      expectSame([a, b]);
    });
  });

  group('Rows that point at other rows', () {
    test('one device deletes a task, the other changes its subtask: both '
        'rows go, on the remote too', () async {
      final p = TaskItem(title: 'Parent');
      final c = TaskItem(title: 'Child', parentId: p.id);
      a.repos.tasks.save(p);
      a.repos.tasks.save(c);
      await a.sync();
      await b.sync();

      a.later();
      a.repos.tasks.delete(p.id);
      b.later();
      b.repos.tasks.save(c.copyWith(title: 'Child, changed'));
      await settle([b, a]);

      expect(a.repos.tasks.all(), isEmpty);
      expect(b.repos.tasks.all(), isEmpty);
      expect(
        remoteRows(remote, 'tasks'),
        unorderedEquals(['${p.id} gone', '${c.id} gone']),
      );
    });

    test('one device deletes a list, the other puts a task in it: the task '
        'stays, without the list', () async {
      final l = ListItem(name: 'Home');
      final t = TaskItem(title: 'Sweep');
      a.repos.lists.save(l);
      a.repos.tasks.save(t);
      await a.sync();
      await b.sync();

      a.later();
      a.repos.lists.delete(l.id);
      b.later();
      b.repos.tasks.save(t.copyWith(listId: l.id, title: 'Sweep the yard'));
      await settle([b, a]);

      final end = a.repos.tasks.get(t.id)!;
      expect((end.title, end.listId), ('Sweep the yard', null));
      expect(a.repos.lists.all(includeArchived: true), isEmpty);
      expectSame([a, b]);
    });

    test(
      'a deleted task that comes back does not bring its subtasks',
      () async {
        final p = TaskItem(title: 'Parent');
        final c = TaskItem(title: 'Child', parentId: p.id);
        a.repos.tasks.save(p);
        a.repos.tasks.save(c);
        await a.sync();
        await b.sync();

        a.later();
        a.repos.tasks.delete(p.id);
        b.later();
        b.repos.tasks.save(p.copyWith(title: 'Parent, still needed'));
        await settle([a, b]);

        expect(a.repos.tasks.all().map((t) => t.title), [
          'Parent, still needed',
        ]);
        expectSame([a, b]);
      },
    );

    test('a watcher never sees a row before the row it points at', () async {
      final hooked = HookRemote();
      final writer = Device(hooked, pageSize: 1);
      final watcher = Device(hooked);
      final r = writer.repos;
      final p = TaskItem(title: 'Parent');
      final c = TaskItem(title: 'Child', parentId: p.id);
      final g = TaskItem(title: 'Grandchild', parentId: c.id);
      final l = ListItem(name: 'Home');
      r.tasks.save(g.copyWith(parentId: null));
      r.tasks.save(c.copyWith(parentId: null));
      r.tasks.save(p);
      r.tasks.save(c);
      r.tasks.save(g);
      r.events.save(
        EventItem(
          title: 'Block',
          start: at('2026-10-05T09:00'),
          end: at('2026-10-05T10:00'),
          kind: EventKind.block,
          taskId: g.id,
        ),
      );
      r.tags.setTaskTags(g.id, ['x']);
      r.lists.save(l);
      // The parent and the list are saved last. They must still arrive first.
      r.tasks.save(p.copyWith(listId: l.id));

      var looks = 0;
      hooked.afterPush = () async {
        looks++;
        await watcher.sync();
        expect(watcher.outbox.count, 0, reason: 'after push $looks');
      };
      await writer.sync();
      hooked.afterPush = null;

      expect(looks, greaterThan(5));
      await watcher.sync();
      expect(watcher.repos.tasks.all().length, 3);
      expectSame([writer, watcher]);
    });
  });

  group('Two rows that must be one', () {
    test('the same tag made on two devices becomes one tag', () async {
      final ta = TaskItem(title: 'On A');
      final tb = TaskItem(title: 'On B');
      a.repos.tasks.save(ta);
      a.repos.tags.setTaskTags(ta.id, ['home']);
      b.repos.tasks.save(tb);
      b.repos.tags.setTaskTags(tb.id, ['Home', 'garden']);

      await settle([a, b]);

      for (final d in [a, b]) {
        expect(d.repos.tags.all().length, 2);
        expect(d.repos.tags.tagsForTask(ta.id).length, 1);
        expect(d.repos.tags.tagsForTask(tb.id).length, 2);
        expect(
          d.repos.tasks.withTag('home').map((t) => t.title),
          unorderedEquals(['On A', 'On B']),
        );
      }
      expectSame([a, b]);
      expect(
        remoteRows(remote, 'tags').where((r) => r.endsWith('saved')).length,
        2,
      );
    });

    test('the same tag on three devices, in any sync order', () async {
      final c = Device(remote);
      final tasks = <TaskItem>[];
      for (final d in [a, b, c]) {
        final t = TaskItem(title: 'T${tasks.length}');
        d.repos.tasks.save(t);
        d.repos.tags.setTaskTags(t.id, ['home']);
        tasks.add(t);
      }

      await settle([c, a, b]);

      for (final d in [a, b, c]) {
        expect(d.repos.tags.all().length, 1);
        expect(d.repos.tasks.withTag('home').length, 3);
      }
      expectSame([a, b, c]);
    });

    test('a tag link made later with the lost tag is kept', () async {
      final ta = TaskItem(title: 'On A');
      final tb = TaskItem(title: 'On B');
      final tb2 = TaskItem(title: 'On B, later');
      a.repos.tasks.save(ta);
      a.repos.tags.setTaskTags(ta.id, ['home']);
      b.repos.tasks.save(tb);
      b.repos.tags.setTaskTags(tb.id, ['home']);
      // B sends its tag. Only A pulls and makes the two tags one.
      await b.sync();
      await a.sync();
      // B does not know that yet and uses its own tag again.
      b.later();
      b.repos.tasks.save(tb2);
      b.repos.tags.setTaskTags(tb2.id, ['home']);

      await settle([b, a]);

      for (final d in [a, b]) {
        expect(d.repos.tags.all().length, 1);
        expect(d.repos.tasks.withTag('home').length, 3);
      }
      expectSame([a, b]);
    });

    Note daily(Device d, String body, {String day = '2026-10-05'}) {
      final n = Note(
        title: 'Monday',
        kind: NoteKind.daily,
        date: DayKey(day),
        body: body,
      );
      d.repos.notes.save(n);
      return n;
    }

    test('the same daily note written on two devices becomes one note with '
        'both texts', () async {
      final na = daily(a, 'Written on A');
      final nb = daily(b, 'Written on B');

      await settle([a, b]);

      final kept = a.repos.notes.all().single;
      final first = na.id.compareTo(nb.id) < 0 ? na : nb;
      final second = identical(first, na) ? nb : na;
      expect(kept.id, first.id);
      expect(kept.body, '${first.body}\n\n${second.body}');
      expect(b.repos.search.search('written').single.title, 'Monday');
      expectSame([a, b]);
    });

    test(
      'a daily note with the same text on both devices is not doubled',
      () async {
        daily(a, '## Plan');
        daily(b, '## Plan');
        await settle([a, b]);
        expect(a.repos.notes.all().single.body, '## Plan');
        expectSame([a, b]);
      },
    );

    test('an empty daily note adds nothing to the other one', () async {
      daily(a, '');
      daily(b, 'Only B wrote');
      await settle([a, b]);
      expect(a.repos.notes.all().single.body, 'Only B wrote');
      expectSame([a, b]);
    });

    test('two daily notes of different days stay two notes', () async {
      daily(a, 'Monday');
      daily(b, 'Tuesday', day: '2026-10-06');
      await settle([a, b]);
      expect(a.repos.notes.all().length, 2);
      expectSame([a, b]);
    });

    test('what pointed at the lost note points at the kept note', () async {
      final made = <TaskItem>[];
      for (final (i, d) in [a, b].indexed) {
        final n = daily(d, 'Text $i');
        final t = TaskItem(title: 'From note $i', sourceNoteId: n.id);
        d.repos.tasks.save(t);
        d.repos.tags.setNoteTags(n.id, ['tag$i']);
        d.repos.links.addManual(
          ItemRef(ItemType.note, n.id),
          ItemRef(ItemType.task, t.id),
        );
        d.repos.links.addManual(
          ItemRef(ItemType.task, t.id),
          ItemRef(ItemType.note, n.id),
        );
        made.add(t);
      }

      await settle([a, b]);

      for (final d in [a, b]) {
        final kept = d.repos.notes.all().single;
        final ref = ItemRef(ItemType.note, kept.id);
        expect(d.repos.tasks.all().map((t) => t.sourceNoteId), [
          kept.id,
          kept.id,
        ]);
        expect(
          d.repos.tags.tagsForNote(kept.id),
          unorderedEquals(['tag0', 'tag1']),
        );
        expect(d.repos.links.outgoing(ref).length, 2);
        expect(d.repos.links.backlinks(ref).length, 2);
      }
      expectSame([a, b]);
    });
  });

  group('A row that comes back with a new id', () {
    // Each case runs two times: the old id is the smaller one, then the
    // larger one. The result must not depend on that.
    for (final (oldId, newId) in [('AAAA', 'BBBB'), ('BBBB', 'AAAA')]) {
      test('a daily note is deleted and written again ($oldId then $newId): '
          'the new note stays', () async {
        final old = Note(
          id: oldId,
          title: 'Monday',
          kind: NoteKind.daily,
          date: DayKey('2026-10-05'),
          body: 'Old text',
        );
        a.repos.notes.save(old);
        await settle([a, b]);

        a.later();
        a.repos.notes.delete(old.id);
        a.repos.notes.save(
          Note(
            id: newId,
            title: 'Monday',
            kind: NoteKind.daily,
            date: DayKey('2026-10-05'),
            body: 'New text',
          ),
        );
        // B gets the delete and the new note in one pull.
        await settle([a, b]);

        for (final d in [a, b]) {
          final kept = d.repos.notes.all().single;
          expect(kept.id, newId);
          expect(kept.body, contains('New text'));
        }
        expectSame([a, b]);
        expect(
          remoteRows(remote, 'notes'),
          unorderedEquals(['$oldId gone', '$newId saved']),
        );
      });

      test('a tag is deleted and made again ($oldId then $newId): the new '
          'tag and its tasks stay', () async {
        final t = TaskItem(title: 'Sweep');
        final later = TaskItem(title: 'Mop');
        a.repos.tasks.save(t);
        a.db.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
          oldId,
          'home',
        ]);
        a.db.execute('INSERT INTO task_tags (task_id, tag_id) VALUES (?, ?)', [
          t.id,
          oldId,
        ]);
        await settle([a, b]);
        expect(b.repos.tasks.withTag('home').single.title, 'Sweep');

        a.later();
        a.db.execute('DELETE FROM tags WHERE id = ?', [oldId]);
        a.db.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
          newId,
          'home',
        ]);
        a.repos.tasks.save(later);
        a.db.execute('INSERT INTO task_tags (task_id, tag_id) VALUES (?, ?)', [
          later.id,
          newId,
        ]);
        await settle([a, b]);

        for (final d in [a, b]) {
          expect(d.repos.tags.all().single.id, newId);
          expect(d.repos.tasks.withTag('home').single.title, 'Mop');
        }
        expectSame([a, b]);
      });
    }

    test('two notes become one and a task of the lost note changes: a '
        'third device takes the change', () async {
      final c = Device(remote);
      Note monday(String id) => Note(
        id: id,
        title: 'Monday',
        kind: NoteKind.daily,
        date: DayKey('2026-10-05'),
        body: 'From $id',
      );
      final t = TaskItem(title: 'From the note', sourceNoteId: 'BBBB');
      a.repos.notes.save(monday('AAAA'));
      b.repos.notes.save(monday('BBBB'));
      b.repos.tasks.save(t);
      await b.sync();
      await c.sync();
      expect(c.repos.tasks.get(t.id)!.sourceNoteId, 'BBBB');

      // A makes the two notes one. Then it changes the task.
      await a.sync();
      expect(a.repos.tasks.get(t.id)!.sourceNoteId, 'AAAA');
      a.later();
      a.repos.tasks.save(
        a.repos.tasks.get(t.id)!.copyWith(title: 'Changed on A'),
      );
      await a.sync();

      // C gets the kept note, the task and the delete of its note in one pull.
      await c.sync();
      final end = c.repos.tasks.get(t.id)!;
      expect((end.title, end.sourceNoteId), ('Changed on A', 'AAAA'));

      await settle([a, b, c]);
      expect(a.repos.tasks.get(t.id)!.title, 'Changed on A');
      expectSame([a, b, c]);
    });

    test('a note that two devices know gets a twin and a new text in the '
        'same pull: no text is lost', () async {
      final c = Device(remote);
      final first = Note(
        id: 'AAAA',
        title: 'Monday',
        kind: NoteKind.daily,
        date: DayKey('2026-10-05'),
        body: 'From A',
      );
      a.repos.notes.save(first);
      await settle([a, c]);
      // B is offline and writes the note of the same day.
      b.repos.notes.save(
        Note(
          id: 'BBBB',
          title: 'Monday',
          kind: NoteKind.daily,
          date: DayKey('2026-10-05'),
          body: 'From B',
        ),
      );
      remote.offline = true;
      await expectLater(b.sync(), throwsA(isA<RemoteUnavailable>()));
      remote.offline = false;
      // The remote gets the note of B first, then the new text of A.
      await remote.push([
        for (final e in b.outbox.entries())
          RowChange(
            table: e.table,
            key: e.key,
            stamp: e.stamp,
            deleted: false,
            data: {
              'id': 'BBBB',
              'title': 'Monday',
              'kind': 'daily',
              'date': '2026-10-05',
              'body': 'From B',
              'created_at': '2026-10-05T08:00:00',
              'updated_at': '2026-10-05T08:00:00',
            },
          ),
      ]);
      a.later();
      a.repos.notes.save(first.copyWith(body: 'From A, with more'));
      await a.sync();

      await c.sync();

      expect(c.repos.notes.all().single.body, 'From A, with more\n\nFrom B');
      await settle([a, b, c]);
      expect(a.repos.notes.all().single.body, 'From A, with more\n\nFrom B');
      expectSame([a, b, c]);
    });
  });

  group('A pull between two pages of a push', () {
    test('a list is deleted and its task changed: the watcher does not undo '
        'the change', () async {
      final hooked = HookRemote();
      final writer = Device(hooked, pageSize: 1);
      final watcher = Device(hooked);
      final l = ListItem(name: 'Home');
      final t = TaskItem(title: 'Sweep', listId: l.id);
      writer.repos.lists.save(l);
      writer.repos.tasks.save(t);
      await settle([writer, watcher]);

      writer.later();
      writer.repos.lists.delete(l.id);
      writer.repos.tasks.save(
        writer.repos.tasks.get(t.id)!.copyWith(title: 'Sweep the yard'),
      );
      hooked.afterPush = () async {
        await watcher.sync();
        expect(watcher.outbox.count, 0);
      };
      await writer.sync();
      hooked.afterPush = null;
      await settle([writer, watcher]);

      final end = watcher.repos.tasks.get(t.id)!;
      expect((end.title, end.listId), ('Sweep the yard', null));
      expect(watcher.repos.lists.all(includeArchived: true), isEmpty);
      expectSame([writer, watcher]);
    });

    test('a task is deleted with its subtask: the watcher sends nothing '
        'back', () async {
      final hooked = HookRemote();
      final writer = Device(hooked, pageSize: 1);
      final watcher = Device(hooked);
      fill(writer);
      await settle([writer, watcher]);
      final task = writer.repos.tasks.all().firstWhere(
        (t) => t.title == 'Sweep',
      );

      writer.later();
      writer.repos.tasks.delete(task.id);
      writer.repos.notes.delete(writer.repos.notes.all().single.id);
      final pushes = hooked.pushCalls;
      await writer.sync();
      final writerPushes = hooked.pushCalls - pushes;
      hooked.afterPush = null;
      await watcher.sync();

      expect(writerPushes, greaterThan(4));
      expect(watcher.outbox.count, 0);
      expectSame([writer, watcher]);
    });
  });

  group('Many devices', () {
    for (var seed = 1; seed <= 25; seed++) {
      test(
        'random offline work on three devices ends the same (seed $seed)',
        () async {
          final rnd = Random(seed);
          final devices = [a, b, Device(remote, pageSize: 3)];
          for (var step = 0; step < 90; step++) {
            final d = devices[rnd.nextInt(3)];
            if (rnd.nextInt(4) > 0) d.later();
            randomOp(d, rnd);
            if (rnd.nextInt(7) == 0) await devices[rnd.nextInt(3)].sync();
          }

          await settle(devices);
          expectSame(devices);

          // A new device gets the same data and has nothing to repair.
          final fresh = Device(remote);
          final report = await fresh.sync();
          expect(report.skipped, isEmpty);
          expect(fresh.outbox.count, 0);
          expectSame([a, fresh]);
        },
      );
    }
  });

  group('Rows this app cannot use', () {
    test('a row of a table this app does not know is skipped', () async {
      final t = TaskItem(title: 'Known');
      a.repos.tasks.save(t);
      await a.sync();
      await remote.push([
        const RowChange(
          table: 'holograms',
          key: 'h1',
          stamp: 5,
          deleted: false,
          data: {'id': 'h1'},
        ),
      ]);

      final report = await b.sync();

      expect(report.pulled, 2);
      expect(b.repos.tasks.all().single.title, 'Known');
      expect(b.outbox.cursor, remote.lastSeq);
    });

    test('a column this app does not know is ignored', () async {
      final t = TaskItem(title: 'Known');
      a.repos.tasks.save(t);
      await a.sync();
      final row = remote.rows.single;
      await remote.push([
        RowChange(
          table: 'tasks',
          key: row.key,
          stamp: row.stamp + 1,
          deleted: false,
          data: {...row.data, 'title': 'From the future', 'hologram': 1},
        ),
      ]);

      await b.sync();

      expect(b.repos.tasks.get(t.id)!.title, 'From the future');
    });

    test(
      'a row that cannot be saved is skipped and named in the report',
      () async {
        final t = TaskItem(title: 'Good');
        a.repos.tasks.save(t);
        await a.sync();
        await remote.push([
          const RowChange(
            table: 'tasks',
            key: 'bad',
            stamp: 5,
            deleted: false,
            data: {'id': 'bad', 'title': null},
          ),
        ]);

        final report = await b.sync();

        expect(report.skipped.single, startsWith('tasks bad:'));
        expect(b.repos.tasks.all().single.title, 'Good');
        expect(b.outbox.cursor, remote.lastSeq);
        expect(b.outbox.count, 0);
      },
    );
  });
}
