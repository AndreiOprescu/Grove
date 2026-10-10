// Port of Tests/GroveTests/MenuBarTests.swift.
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const day = DayKey('2026-10-05');

PlannerBlock block(
  String id,
  String title,
  int start,
  int end, {
  bool done = false,
  bool task = false,
}) => PlannerBlock(
  id: id,
  title: title,
  day: day,
  startMinute: start,
  endMinute: end,
  kind: task ? EventKind.block : EventKind.event,
  taskId: task ? 'T-$id' : null,
  isDone: done,
  color: 'accent',
  isRecurring: false,
);

NowNext make(List<PlannerBlock> blocks, int minute) =>
    NowNextRules.make(blocks: blocks, minute: minute);

void main() {
  group('the Now and Next lines', () {
    test('a block that is running is now', () {
      expect(make([block('a', 'Standup', 540, 600)], 560).now, 'Now: Standup');
    });

    test('the start minute counts and the end minute does not', () {
      final blocks = [block('a', 'Standup', 540, 600)];
      expect(make(blocks, 540).now, 'Now: Standup');
      expect(make(blocks, 599).now, 'Now: Standup');
      expect(make(blocks, 600).now, 'Nothing planned right now');
      expect(make(blocks, 539).now, 'Nothing planned right now');
    });

    test('the next block shows how long it takes', () {
      expect(
        make([block('a', 'Write report', 600, 660)], 575).next,
        'Next: Write report in 25 min',
      );
    });

    test('long waits use hours and minutes', () {
      final b = [block('a', 'Gym', 1080, 1140)];
      expect(make(b, 1020).next, 'Next: Gym in 1 h');
      expect(make(b, 990).next, 'Next: Gym in 1 h 30 min');
      expect(make(b, 1079).next, 'Next: Gym in 1 min');
    });

    test('the next block is the earliest one that starts later', () {
      final blocks = [
        block('c', 'Late', 900, 960),
        block('b', 'Soon', 620, 650),
        block('a', 'Now', 540, 600),
      ];
      final r = make(blocks, 560);
      expect(r.now, 'Now: Now');
      expect(r.next, 'Next: Soon in 1 h');
    });

    test('when blocks overlap, now is the one that started last', () {
      final blocks = [
        block('a', 'Long', 540, 700),
        block('b', 'Short', 600, 630),
      ];
      expect(make(blocks, 610).now, 'Now: Short');
    });

    test('nothing else today when the day is over', () {
      final r = make([block('a', 'Standup', 540, 600)], 700);
      expect(r.now, 'Nothing planned right now');
      expect(r.next, 'Nothing else today');
    });

    test('an empty day has both quiet lines', () {
      expect(
        make(const [], 700),
        const NowNext(
          now: 'Nothing planned right now',
          next: 'Nothing else today',
        ),
      );
    });

    test('a block of a done task is left out', () {
      final blocks = [
        block('a', 'Write report', 540, 600, done: true, task: true),
        block('b', 'Call', 620, 650),
      ];
      final r = make(blocks, 560);
      expect(r.now, 'Nothing planned right now');
      expect(r.next, 'Next: Call in 1 h');
    });
  });

  group('the menu bar window on a real store', () {
    test('quick add from the menu bar goes to today', () {
      final s = makeStore();
      final t = s.menuBarAdd('Buy milk')!;
      expect(t.planDate, DayKey.today());
      expect(t.bucket, TaskBucket.day);
      expect(titles(s.repos.tasks.forDay(DayKey.today())), ['Buy milk']);
    });

    test('a date in the text still wins', () {
      final s = makeStore();
      final t = s.menuBarAdd('Dentist tomorrow')!;
      expect(t.planDate, DayKey.today().adding(days: 1));
    });

    test('empty text adds nothing', () {
      final s = makeStore();
      expect(s.menuBarAdd('   '), isNull);
      expect(s.repos.tasks.all(), isEmpty);
    });

    test('the lines cover the blocks of today', () {
      final s = makeStore();
      final today = DayKey.today();
      s.repos.events.save(
        EventItem(
          id: 'E1',
          title: 'Standup',
          start: WallTime(day: today, minute: 540),
          end: WallTime(day: today, minute: 600),
          color: 'accent3',
        ),
      );
      final lines = s.menuBarLines(minute: 560);
      expect(lines.now, 'Now: Standup');
      expect(lines.next, 'Nothing else today');
    });
  });
}
