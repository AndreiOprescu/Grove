// Port of Tests/GroveTests/AllTasksTests.swift (the rules part).
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

TaskItem task(String title, TaskBucket bucket, {String? day, String? week}) =>
    TaskItem(
      title: title,
      bucket: bucket,
      planDate: day == null ? null : DayKey(day),
      planWeek: week == null ? null : DayKey(week),
    );

void main() {
  const inbox = TaskBucket.inbox;
  const someday = TaskBucket.someday;
  const dayB = TaskBucket.day;
  const weekB = TaskBucket.week;

  test('no day yet runs inbox then weeks then someday', () {
    final input = [
      task('later A', someday),
      task('week 12 Oct', weekB, week: '2026-10-12'),
      task('inbox 1', inbox),
      task('week 5 Oct', weekB, week: '2026-10-05'),
      task('inbox 2', inbox),
      task('later B', someday),
    ];
    final split = AllTasksRules.split(input);
    expect(titles(split.noDay), [
      'inbox 1',
      'inbox 2',
      'week 5 Oct',
      'week 12 Oct',
      'later A',
      'later B',
    ]);
    expect(split.byDay, isEmpty);
  });

  test('tasks of the same week keep their list order', () {
    final input = [
      task('b', weekB, week: '2026-10-05'),
      task('a', weekB, week: '2026-10-05'),
      task('first', weekB, week: '2026-09-28'),
    ];
    expect(titles(AllTasksRules.split(input).noDay), ['first', 'b', 'a']);
  });

  test('by day runs earliest first with past days on top', () {
    final input = [
      task('next week', dayB, day: '2026-10-12'),
      task('today', dayB, day: '2026-10-04'),
      task('last week', dayB, day: '2026-09-28'),
    ];
    final split = AllTasksRules.split(input);
    expect(titles(split.byDay), ['last week', 'today', 'next week']);
    expect(split.noDay, isEmpty);
  });

  test('tasks on the same day keep their list order', () {
    final input = [
      task('b', dayB, day: '2026-10-05'),
      task('first', dayB, day: '2026-10-04'),
      task('a', dayB, day: '2026-10-05'),
      task('c', dayB, day: '2026-10-05'),
    ];
    expect(titles(AllTasksRules.split(input).byDay), ['first', 'b', 'a', 'c']);
  });

  test('a day task with no date has no day yet', () {
    final split = AllTasksRules.split([
      task('odd', dayB),
      task('dated', dayB, day: '2026-10-04'),
    ]);
    expect(titles(split.noDay), ['odd']);
    expect(titles(split.byDay), ['dated']);
  });

  group('unscheduled list (overdue first, then tasks with no day)', () {
    final today = d('2026-10-09');

    test('overdue is open day tasks before today, earliest first', () {
      final input = [
        task('yesterday', dayB, day: '2026-10-08'),
        task('long ago', dayB, day: '2026-09-20'),
        task('also yesterday', dayB, day: '2026-10-08'),
      ];
      final r = AllTasksRules.unscheduled(input, today: today);
      expect(titles(r.overdue), ['long ago', 'yesterday', 'also yesterday']);
      expect(r.unscheduled, isEmpty);
    });

    test('a task planned for today or later is in neither list', () {
      final input = [
        task('today', dayB, day: '2026-10-09'),
        task('tomorrow', dayB, day: '2026-10-10'),
        task('next month', dayB, day: '2026-11-01'),
      ];
      final r = AllTasksRules.unscheduled(input, today: today);
      expect(r.overdue, isEmpty);
      expect(r.unscheduled, isEmpty);
    });

    test('unscheduled is inbox then weeks then someday, and an undated day '
        'task', () {
      final input = [
        task('later', someday),
        task('week', weekB, week: '2026-10-12'),
        task('inbox', inbox),
        task('odd', dayB),
      ];
      final r = AllTasksRules.unscheduled(input, today: today);
      expect(titles(r.unscheduled), ['inbox', 'odd', 'week', 'later']);
      expect(r.overdue, isEmpty);
    });

    test('a week task from a past week is unscheduled, not overdue', () {
      final r = AllTasksRules.unscheduled([
        task('old week', weekB, week: '2026-09-21'),
      ], today: today);
      expect(r.overdue, isEmpty);
      expect(titles(r.unscheduled), ['old week']);
    });

    test('each task is in at most one of the two lists', () {
      final input = [
        task('a', dayB, day: '2026-10-01'),
        task('b', inbox),
        task('c', dayB, day: '2026-10-20'),
        task('d', someday),
      ];
      final r = AllTasksRules.unscheduled(input, today: today);
      expect(titles(r.overdue), ['a']);
      expect(titles(r.unscheduled), ['b', 'd']);
    });
  });
}
