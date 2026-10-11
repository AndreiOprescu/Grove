// Ports of Tests/GroveTests/TaskFormatTests.swift and of the view tests of
// Tests/GroveTests/TaskLookTests.swift.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/tasks/task_format.dart';
import 'package:grove/ui/theme/grove_theme.dart';
import 'package:grove/ui/theme/named_colors.dart';

import '../../state/support.dart';

void main() {
  final today = d('2026-10-02');

  test('near days have names', () {
    expect(TaskFormat.dayLabel(today, today: today), 'Today');
    expect(TaskFormat.dayLabel(d('2026-10-03'), today: today), 'Tomorrow');
    expect(TaskFormat.dayLabel(d('2026-10-01'), today: today), 'Yesterday');
  });

  test('other days show weekday, day and month', () {
    final text = TaskFormat.dayLabel(d('2026-10-09'), today: today);
    expect(text, 'Fri 9 Oct');
    expect(['Today', 'Tomorrow', 'Yesterday'], isNot(contains(text)));
  });

  test('date label never uses relative names', () {
    expect(TaskFormat.dateLabel(d('2026-10-01')), isNot('Yesterday'));
    expect(TaskFormat.dateLabel(d('2026-10-01')), contains('1'));
  });

  test('week label names its Monday', () {
    final text = TaskFormat.weekLabel(d('2026-10-05'));
    expect(text, startsWith('Week of '));
    expect(text, contains('5'));
    expect(text, isNot(contains('Mon')));
  });

  test('plan label says where a task lives', () {
    expect(
      TaskFormat.planLabel(
        TaskItem(title: 'a', bucket: TaskBucket.day, planDate: d('2026-10-03')),
        today: today,
      ),
      'Tomorrow',
    );
    expect(
      TaskFormat.planLabel(
        TaskItem(
          title: 'b',
          bucket: TaskBucket.week,
          planWeek: d('2026-10-05'),
        ),
        today: today,
      ),
      TaskFormat.weekLabel(d('2026-10-05')),
    );
    expect(
      TaskFormat.planLabel(
        TaskItem(title: 'c', bucket: TaskBucket.someday),
        today: today,
      ),
      'Someday',
    );
    expect(TaskFormat.planLabel(TaskItem(title: 'd'), today: today), isNull);
  });

  test('due day in the past is late', () {
    final due = TaskFormat.due('2026-10-01', today: today, nowMinute: 600);
    expect(due.late, isTrue);
    expect(due.text, 'due Yesterday');
  });

  test('due time today is late only after it passed', () {
    expect(
      TaskFormat.due('2026-10-02T09:00', today: today, nowMinute: 600).late,
      isTrue,
    );
    final early = TaskFormat.due(
      '2026-10-02T09:00',
      today: today,
      nowMinute: 500,
    );
    expect(early.late, isFalse);
    expect(early.text, 'due Today 09:00');
  });

  test('due in the future is not late', () {
    expect(
      TaskFormat.due('2026-10-05', today: today, nowMinute: 1200).late,
      isFalse,
    );
  });

  test('every chip kind has an icon of its own', () {
    expect(ChipKind.values.map(TaskFormat.icon).toSet().length, 8);
  });

  test('the place of a new task has a short name', () {
    expect(
      TaskFormat.placeLabel(
        TaskItem(title: 'a', bucket: TaskBucket.day, planDate: today),
        today: today,
      ),
      'Today',
    );
    expect(
      TaskFormat.placeLabel(
        TaskItem(title: 'a', bucket: TaskBucket.week, planWeek: today),
        today: today,
      ),
      'this week',
    );
    expect(
      TaskFormat.placeLabel(
        TaskItem(title: 'a', bucket: TaskBucket.someday),
        today: today,
      ),
      'Someday',
    );
    expect(TaskFormat.placeLabel(TaskItem(title: 'a'), today: today), 'Inbox');
  });

  // TaskLookTests
  test('low is green, medium is yellow, high is red, none has no border', () {
    expect(TaskFormat.priorityTone(0), isNull);
    expect(TaskFormat.priorityTone(1), PriorityTone.green);
    expect(TaskFormat.priorityTone(2), PriorityTone.yellow);
    expect(TaskFormat.priorityTone(3), PriorityTone.red);
    expect(TaskFormat.priorityTone(7), isNull);
    expect(TaskFormat.priorityTone(-1), isNull);
    expect(PriorityColors.color(1), PriorityColors.low);
    expect(PriorityColors.color(2), PriorityColors.medium);
    expect(PriorityColors.color(3), PriorityColors.high);
    expect(PriorityColors.color(0), isNull);
  });

  test('the border is thick', () {
    expect(PriorityColors.borderWidth, greaterThanOrEqualTo(3));
  });

  test('the colour names have a colour each', () {
    final theme = GroveTheme.make(ThemeId.grove, Brightness.light);
    expect(TaskColor.names.length, 8);
    expect(TaskColor.names.map(theme.color).toSet().length, 8);
  });
}
