import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// The store side of the day menu: a right-click on a day in the Planner or
// the Calendar.

const tue = DayKey('2026-10-20');
const wed = DayKey('2026-10-21');

TaskItem onDay(String id, DayKey day, {TaskStatus status = TaskStatus.open}) =>
    TaskItem(
      id: id,
      title: id,
      bucket: TaskBucket.day,
      planDate: day,
      status: status,
    );

void main() {
  group('a new deadline on a day', () {
    test('opens the card on that day with Deadline on', () {
      final s = makeStore();
      s.newEvent(on: tue, deadline: true);
      final item = s.editingEvent!.item;
      expect(s.editingEvent!.isNew, isTrue);
      expect(item.isDeadline, isTrue);
      expect(item.allDay, isTrue);
      expect(item.start.day, tue);
    });

    test('a deadline with no title is saved as "New Deadline"', () {
      final s = makeStore();
      s.newEvent(on: tue, deadline: true);
      s.saveEvent(s.editingEvent!.item, from: null);
      final saved = s.repos.events.all().single;
      expect(saved.title, 'New Deadline');
      expect(saved.isDeadline, isTrue);
    });

    test('a plain new event is still not a deadline', () {
      final s = makeStore();
      s.newEvent(on: tue);
      expect(s.editingEvent!.item.isDeadline, isFalse);
    });
  });

  group('move the open tasks of a day', () {
    test('open tasks go to the new day, done tasks stay', () {
      final s = makeStore();
      s.repos.tasks.save(onDay('a', tue));
      s.repos.tasks.save(onDay('b', tue));
      s.repos.tasks.save(onDay('done', tue, status: TaskStatus.done));
      s.repos.tasks.save(onDay('other', wed));

      expect(s.moveOpenTasks(from: tue, to: wed), 2);

      expect(s.task('a')!.planDate, wed);
      expect(s.task('b')!.planDate, wed);
      expect(s.task('done')!.planDate, tue);
      expect(s.openTasks(TaskPlacement.day(tue)), isEmpty);
      expect(s.openTasks(TaskPlacement.day(wed)).map((t) => t.id).toSet(), {
        'a',
        'b',
        'other',
      });
    });

    test('a time block keeps its time on the new day', () {
      final s = makeStore();
      final t = onDay('a', tue);
      s.repos.tasks.save(t);
      s.repos.events.save(s.blockEvent(t, day: tue, start: 600, end: 660));

      s.moveOpenTasks(from: tue, to: wed);

      final block = s.blocksOfTask('a').single;
      expect(block.start, const WallTime(day: wed, minute: 600));
      expect(block.end, const WallTime(day: wed, minute: 660));
    });

    test('is one undo step', () {
      final s = makeStore();
      final t = onDay('a', tue);
      s.repos.tasks.save(t);
      s.repos.tasks.save(onDay('b', tue));
      s.repos.events.save(s.blockEvent(t, day: tue, start: 600, end: 660));

      s.moveOpenTasks(from: tue, to: wed);
      expect(s.undoName, 'Move Open Tasks');
      s.undo();

      expect(s.task('a')!.planDate, tue);
      expect(s.task('b')!.planDate, tue);
      expect(s.blocksOfTask('a').single.start.day, tue);
    });

    test('the same day, or a day with no open task, changes nothing', () {
      final s = makeStore();
      s.repos.tasks.save(onDay('a', tue));
      expect(s.moveOpenTasks(from: tue, to: tue), 0);
      expect(s.moveOpenTasks(from: wed, to: tue), 0);
      expect(s.task('a')!.planDate, tue);
      expect(s.undoName, isNull);
    });
  });
}
