// Port of the model parts of TaskColorTests.swift, DatabaseTests.swift, SmokeTests.swift.
import 'package:grove/core/grove_core.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/event.dart';
import 'package:grove/core/model/goal.dart';
import 'package:grove/core/model/ids.dart';
import 'package:grove/core/model/note.dart';
import 'package:grove/core/model/recurrence.dart';
import 'package:grove/core/model/task.dart';
import 'package:grove/core/model/task_color.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('version is set', () {
    expect(GroveCore.version, isNotEmpty);
  });

  group('task colour', () {
    test('there are eight different colours', () {
      expect(TaskColor.names.length, 8);
      expect(TaskColor.names.toSet().length, 8);
    });

    test('a task has no colour at first', () {
      expect(TaskItem(title: 'x').color, '');
    });

    test('no colour and the eight names are valid', () {
      expect(TaskColor.isValid(''), isTrue);
      for (final name in TaskColor.names) {
        expect(TaskColor.isValid(name), isTrue);
      }
      expect(TaskColor.isValid('mauve'), isFalse);
      expect(TaskColor.isValid('Red'), isFalse);
    });
  });

  group('task', () {
    test('defaults match the Swift app', () {
      final t = TaskItem(title: 'x');
      expect(t.priority, 0);
      expect(t.status, TaskStatus.open);
      expect(t.bucket, TaskBucket.inbox);
      expect(t.estimateMin, 30);
      expect(t.isDone, isFalse);
      expect(t.completedAt, isNull);
      expect(t.createdAt, t.updatedAt);
    });

    test('copyWith changes one field and can clear a nullable one', () {
      final t = TaskItem(
        id: 'T1',
        title: 'x',
        bucket: TaskBucket.day,
        planDate: const DayKey('2026-10-02'),
      );
      final moved = t.copyWith(planDate: null, bucket: TaskBucket.inbox);
      expect(moved.planDate, isNull);
      expect(moved.bucket, TaskBucket.inbox);
      expect(moved.title, 'x');
      expect(t.planDate, const DayKey('2026-10-02'));
      expect(t.copyWith(), t);
      expect(t.copyWith(status: TaskStatus.done).isDone, isTrue);
    });

    test('equal values are equal', () {
      final a = TaskItem(id: 'T1', title: 'x');
      expect(a.copyWith(), a);
      expect(a.copyWith().hashCode, a.hashCode);
      expect(a.copyWith(color: 'teal') == a, isFalse);
    });
  });

  group('event', () {
    test('event duration', () {
      final e = EventItem(
        title: 'x',
        start: const WallTime(day: DayKey('2026-10-02'), minute: 660),
        end: const WallTime(day: DayKey('2026-10-02'), minute: 750),
      );
      expect(e.durationMinutes, 90);
    });

    test('an event over midnight counts the minutes of both days', () {
      final e = EventItem(
        title: 'x',
        start: const WallTime(day: DayKey('2026-10-02'), minute: 1380),
        end: const WallTime(day: DayKey('2026-10-03'), minute: 60),
      );
      expect(e.durationMinutes, 120);
    });

    test('defaults match the Swift app', () {
      final e = EventItem(
        title: 'x',
        start: const WallTime(day: DayKey('2026-10-02'), minute: 0),
        end: const WallTime(day: DayKey('2026-10-02'), minute: 60),
      );
      expect(e.kind, EventKind.event);
      expect(e.color, 'accent2');
      expect(e.allDay, isFalse);
      expect(e.taskId, isNull);
      expect(e.goalId, isNull);
    });
  });

  group('goal and note', () {
    test('goal defaults', () {
      final g = GoalItem(title: 'Read');
      expect(g.kind, GoalKind.hours);
      expect(g.targetMin, 300);
      expect(g.targetCount, 3);
      expect(g.color, '');
    });

    test('note defaults', () {
      final n = Note(title: 'n');
      expect(n.kind, NoteKind.note);
      expect(n.pinned, isFalse);
      expect(n.mood, isNull);
    });
  });

  group('recurrence rule', () {
    test('interval is at least one', () {
      expect(RecurrenceRule(freq: Freq.daily, interval: 0).interval, 1);
    });

    test('JSON matches the Swift encoding and round trips', () {
      final r = RecurrenceRule(
        freq: Freq.weekly,
        interval: 2,
        weekdays: const [1, 3],
        until: const DayKey('2026-12-31'),
      );
      expect(RecurrenceRule.fromJson(r.json()), r);
      // Swift's JSONEncoder leaves out nil fields.
      expect(
        RecurrenceRule(freq: Freq.daily).json(),
        '{"freq":"daily","interval":1}',
      );
    });

    test('JSON written by the Swift app reads back', () {
      final r = RecurrenceRule.fromJson(
        '{"interval":1,"freq":"monthly","count":5,"until":"2027-01-01"}',
      );
      expect(r?.freq, Freq.monthly);
      expect(r?.count, 5);
      expect(r?.until, const DayKey('2027-01-01'));
      expect(RecurrenceRule.fromJson(null), isNull);
      expect(RecurrenceRule.fromJson('not json'), isNull);
      expect(RecurrenceRule.fromJson('{"freq":"hourly","interval":1}'), isNull);
    });
  });

  test('new ids look like Swift UUID strings and differ', () {
    final a = newId(), b = newId();
    expect(
      RegExp(
        r'^[0-9A-F]{8}-[0-9A-F]{4}-4[0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12}$',
      ).hasMatch(a),
      isTrue,
    );
    expect(a, isNot(b));
  });

  test('stamps are local seconds without a zone', () {
    expect(
      RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$').hasMatch(Stamp.now()),
      isTrue,
    );
    expect(
      Stamp.fromDate(DateTime(2026, 10, 2, 8, 5, 9)),
      '2026-10-02T08:05:09',
    );
  });
}
