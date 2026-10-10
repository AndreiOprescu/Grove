// Port of Tests/GroveTests/AtDateStoreTests.swift.
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final tomorrow = DayKey.today().adding(days: 1);

String when(DayKey day, int? start, int? end) =>
    AtDatePlanner.whenLabel(day, start: start, end: end);

List<EventItem> on(AppStore s, DayKey day) =>
    s.eventItems(DayRange.single(day));

void main() {
  group('a plain line', () {
    test('a plain line makes an hour long event linked to the note', () {
      final s = makeStore();
      final n = s.newNote(title: 'Ideas');
      final line = s.addToPlanner(line: 'Call Sam @tomorrow 3pm', inNote: n.id);
      final e = on(s, tomorrow).first;
      expect(e.title, 'Call Sam');
      expect(e.kind, EventKind.event);
      expect(e.allDay, isFalse);
      expect(e.start, WallTime(day: tomorrow, minute: 900));
      expect(e.end, WallTime(day: tomorrow, minute: 960));
      expect(e.notes, '[[Ideas|${n.id}]]');
      expect(
        [for (final l in s.linkedItems(ItemRef(ItemType.note, n.id))) l.ref],
        [ItemRef(ItemType.event, e.id)],
      );
      expect(line, '[[Call Sam|${e.id}]] · ${when(tomorrow, 900, 960)}');
    });

    test('a length in the token is used', () {
      final s = makeStore();
      final n = s.newNote(title: 'Ideas');
      expect(
        s.addToPlanner(line: 'Workshop @tomorrow 9am for 2h', inNote: n.id),
        isNotNull,
      );
      final e = on(s, tomorrow).first;
      expect(e.start.minute, 540);
      expect(e.end.minute, 660);
    });

    test('a day with no time makes an all-day event', () {
      final s = makeStore();
      final n = s.newNote(title: 'Ideas');
      final line = s.addToPlanner(line: 'Holiday @tomorrow', inNote: n.id);
      final e = on(s, tomorrow).first;
      expect(e.allDay, isTrue);
      expect(e.start.day, tomorrow);
      expect(line, '[[Holiday|${e.id}]] · ${when(tomorrow, null, null)}');
    });

    test('a list marker stays on the line', () {
      final s = makeStore();
      final n = s.newNote(title: 'Ideas');
      final line = s.addToPlanner(line: '- Lunch @tomorrow 12pm', inNote: n.id);
      expect(line, startsWith('- [[Lunch|'));
    });
  });

  group('a check box', () {
    test('an open box makes a task with a half hour block', () {
      final s = makeStore();
      final n = s.newNote(title: 'Ideas');
      final line = s.addToPlanner(
        line: '- [ ] Write report @tomorrow 9am',
        inNote: n.id,
      );
      final t = s.repos.tasks.all().first;
      expect(t.title, 'Write report');
      expect(t.bucket, TaskBucket.day);
      expect(t.planDate, tomorrow);
      expect(t.estimateMin, 30);
      expect(t.notes, 'From [[Ideas|${n.id}]]');
      final block = s.blocksOfTask(t.id).first;
      expect(block.start, WallTime(day: tomorrow, minute: 540));
      expect(block.end, WallTime(day: tomorrow, minute: 570));
      expect(
        line,
        '- [ ] Write report · ${when(tomorrow, 540, 570)} ⟦t:${t.id}⟧',
      );
      // A task makes no plain event.
      expect(
        s.repos.events.all().where((e) => e.kind == EventKind.event),
        isEmpty,
      );
    });

    test('the block takes the typed length and the task keeps it', () {
      final s = makeStore();
      final n = s.newNote(title: 'Ideas');
      expect(
        s.addToPlanner(
          line: '- [ ] Write report @tomorrow 9am for 2h',
          inNote: n.id,
        ),
        isNotNull,
      );
      final t = s.repos.tasks.all().first;
      expect(t.estimateMin, 120);
      expect(s.blocksOfTask(t.id).first.end.minute, 660);
    });

    test('a box with a day and no time is planned for the day without a '
        'block', () {
      final s = makeStore();
      final n = s.newNote(title: 'Ideas');
      final line = s.addToPlanner(
        line: '- [ ] Write report @tomorrow',
        inNote: n.id,
      );
      final t = s.repos.tasks.all().first;
      expect(t.bucket, TaskBucket.day);
      expect(t.planDate, tomorrow);
      expect(s.blocksOfTask(t.id), isEmpty);
      expect(
        line,
        '- [ ] Write report · ${when(tomorrow, null, null)} ⟦t:${t.id}⟧',
      );
    });

    test('other quick add words still work on the box', () {
      final s = makeStore();
      final n = s.newNote(title: 'Ideas');
      expect(
        s.addToPlanner(
          line: '- [ ] Write report #work !1 @tomorrow 9am',
          inNote: n.id,
        ),
        isNotNull,
      );
      final t = s.repos.tasks.all().first;
      expect(t.title, 'Write report');
      expect(t.priority, 1);
      expect(t.planDate, tomorrow); // the @ day wins
      expect(s.blocksOfTask(t.id).length, 1);
    });

    test('a box that already has a task is planned, not copied', () {
      final s = makeStore();
      final n = s.newNote(title: 'Ideas');
      final t = s.quickAdd('Write report')!;
      final line = s.addToPlanner(
        line: '- [ ] Write report @tomorrow 9am ⟦t:${t.id}⟧',
        inNote: n.id,
      );
      expect(s.repos.tasks.all().length, 1);
      expect(s.task(t.id)?.planDate, tomorrow);
      expect(s.blocksOfTask(t.id).length, 1);
      expect(
        line,
        '- [ ] Write report · ${when(tomorrow, 540, 570)} ⟦t:${t.id}⟧',
      );
    });

    test('a task that has a block moves it', () {
      final s = makeStore();
      final n = s.newNote(title: 'Ideas');
      final t = s.quickAdd('Write report')!;
      s.schedule(taskId: t.id, day: DayKey.today(), start: 600, length: 45);
      expect(
        s.addToPlanner(
          line: '- [ ] Write report @tomorrow 14:00 ⟦t:${t.id}⟧',
          inNote: n.id,
        ),
        isNotNull,
      );
      final blocks = s.blocksOfTask(t.id);
      expect(blocks.length, 1);
      expect(blocks[0].start, WallTime(day: tomorrow, minute: 840));
      // Keeps its 45 minutes.
      expect(blocks[0].end, WallTime(day: tomorrow, minute: 885));
    });

    test('a day with no time takes the old block away', () {
      final s = makeStore();
      final n = s.newNote(title: 'Ideas');
      final t = s.quickAdd('Write report')!;
      s.schedule(taskId: t.id, day: DayKey.today(), start: 600, length: 45);
      expect(
        s.addToPlanner(
          line: '- [ ] Write report @tomorrow ⟦t:${t.id}⟧',
          inNote: n.id,
        ),
        isNotNull,
      );
      expect(s.task(t.id)?.planDate, tomorrow);
      expect(s.blocksOfTask(t.id), isEmpty);
    });

    test('extra blocks of the task are removed when one is moved', () {
      final s = makeStore();
      final n = s.newNote(title: 'Ideas');
      final t = s.quickAdd('Write report')!;
      s.schedule(taskId: t.id, day: DayKey.today(), start: 600, length: 45);
      s.repos.events.save(
        s.blockEvent(
          t,
          day: DayKey.today().adding(days: 5),
          start: 900,
          end: 945,
        ),
      );
      expect(
        s.addToPlanner(
          line: '- [ ] Write report @tomorrow 14:00 ⟦t:${t.id}⟧',
          inNote: n.id,
        ),
        isNotNull,
      );
      expect(
        [for (final b in s.blocksOfTask(t.id)) b.start],
        [WallTime(day: tomorrow, minute: 840)],
      );
    });

    test('a mark whose task is gone makes a new task', () {
      final s = makeStore();
      final n = s.newNote(title: 'Ideas');
      final line = s.addToPlanner(
        line:
            '- [ ] Write report @tomorrow 9am '
            '⟦t:00000000-0000-0000-0000-000000000000⟧',
        inNote: n.id,
      )!;
      final t = s.repos.tasks.all().first;
      expect(line, endsWith('⟦t:${t.id}⟧'));
      expect(line, isNot(contains('0000-0000')));
    });
  });

  group('the day', () {
    test('a time alone uses the day of a daily note', () {
      final s = makeStore();
      final day = DayKey.today().adding(days: 5);
      final d = s.dailyNote(day);
      expect(s.addToPlanner(line: 'Standup @10:00', inNote: d.id), isNotNull);
      expect(on(s, day).length, 1);
    });

    test('a time alone in a plain note uses today', () {
      final s = makeStore();
      final n = s.newNote(title: 'Ideas');
      expect(s.addToPlanner(line: 'Standup @10:00', inNote: n.id), isNotNull);
      expect(on(s, DayKey.today()).length, 1);
    });
  });

  group('refused lines', () {
    test('a ticked box is refused and nothing changes', () {
      final s = makeStore();
      final n = s.newNote(title: 'Ideas');
      expect(
        s.addToPlanner(line: '- [x] Write report @tomorrow 9am', inNote: n.id),
        isNull,
      );
      expect(s.repos.tasks.all(), isEmpty);
      expect(on(s, tomorrow), isEmpty);
      expect(s.undoName, anyOf(isNull, 'New Note'));
    });

    test('a line with no token or no note is refused', () {
      final s = makeStore();
      final n = s.newNote(title: 'Ideas');
      expect(s.addToPlanner(line: 'Call Sam tomorrow', inNote: n.id), isNull);
      expect(
        s.addToPlanner(line: 'Call Sam @tomorrow 3pm', inNote: 'missing'),
        isNull,
      );
      expect(s.repos.events.all(), isEmpty);
    });

    test('the new line has nothing left to add', () {
      final s = makeStore();
      final n = s.newNote(title: 'Ideas');
      final line = s.addToPlanner(
        line: '- [ ] Write report @tomorrow 9am',
        inNote: n.id,
      )!;
      expect(s.addToPlanner(line: line, inNote: n.id), isNull);
    });
  });

  group('undo', () {
    test('one undo takes back an event and all its links', () {
      final s = makeStore();
      final n = s.newNote(title: 'Ideas');
      expect(
        s.addToPlanner(line: 'Call Sam @tomorrow 3pm', inNote: n.id),
        isNotNull,
      );
      expect(s.undoName, 'Add to Planner');
      s.undo();
      expect(on(s, tomorrow), isEmpty);
      expect(s.linkedItems(ItemRef(ItemType.note, n.id)), isEmpty);
    });

    test('one undo takes back a task and its block', () {
      final s = makeStore();
      final n = s.newNote(title: 'Ideas');
      expect(
        s.addToPlanner(line: '- [ ] Write report @tomorrow 9am', inNote: n.id),
        isNotNull,
      );
      s.undo();
      expect(s.repos.tasks.all(), isEmpty);
      expect(on(s, tomorrow), isEmpty);
      s.redo();
      expect(s.repos.tasks.all().length, 1);
      expect(on(s, tomorrow).length, 1);
    });
  });
}
