// Port of `TaskFormat` in Sources/Grove/Tasks/TaskFormat.swift and of
// `QuickAddField.label(for:)`. The priority colours are in
// ../theme/named_colors.dart.
import 'package:flutter/material.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/task.dart';
import 'package:grove/core/parsing/quick_add_parser.dart';
import 'package:grove/core/planner/planner_math.dart';
import 'package:grove/state/state.dart' hide MotionRules;

/// The colour of a task's outline. Low is green, medium is yellow, high is
/// red.
enum PriorityTone { green, yellow, red }

/// Small text helpers for the task list.
abstract final class TaskFormat {
  /// "Today", "Tomorrow", "Yesterday", else "Fri 9 Oct".
  static String dayLabel(DayKey day, {DayKey? today}) =>
      switch ((today ?? DayKey.today()).daysUntil(day)) {
        0 => 'Today',
        1 => 'Tomorrow',
        -1 => 'Yesterday',
        _ => dateLabel(day),
      };

  /// "Fri 9 Oct" for any day. Used where "Yesterday" would read oddly.
  static String dateLabel(DayKey day) => NotesRules.shortDay(day);

  /// "Week of 5 Oct" for a week task. `monday` is the stored week.
  static String weekLabel(DayKey monday) =>
      'Week of ${NotesRules.shortDate(monday)}';

  /// Where a task is planned: the day, "Week of 5 Oct" or "Someday". null
  /// for the inbox.
  static String? planLabel(TaskItem task, {DayKey? today}) {
    final day = task.planDate;
    final week = task.planWeek;
    return switch (task.bucket) {
      TaskBucket.day => day == null ? null : dayLabel(day, today: today),
      TaskBucket.week => week == null ? null : weekLabel(week),
      TaskBucket.someday => 'Someday',
      TaskBucket.inbox => null,
    };
  }

  /// The short name of the place a new task went to.
  static String placeLabel(TaskItem task, {DayKey? today}) {
    final day = task.planDate;
    return switch (task.bucket) {
      TaskBucket.day => day == null ? 'Day' : dayLabel(day, today: today),
      TaskBucket.week => 'this week',
      TaskBucket.someday => 'Someday',
      TaskBucket.inbox => 'Inbox',
    };
  }

  /// The text for a due value ("YYYY-MM-DD" or "YYYY-MM-DDTHH:MM") and
  /// whether it is late.
  static ({String text, bool late}) due(
    String value, {
    DayKey? today,
    required int nowMinute,
  }) {
    final now = today ?? DayKey.today();
    final day = DayKey(value.length > 10 ? value.substring(0, 10) : value);
    var text = 'due ${dayLabel(day, today: now)}';
    var late = day < now;
    final time = WallTime.parse(value);
    if (time != null) {
      text += ' ${PlannerMath.clock(time.minute)}';
      if (day == now) late = time.minute < nowMinute;
    }
    return (text: text, late: late);
  }

  /// null when the priority is not 1, 2 or 3: no outline.
  static PriorityTone? priorityTone(int priority) => switch (priority) {
    1 => PriorityTone.green,
    2 => PriorityTone.yellow,
    3 => PriorityTone.red,
    _ => null,
  };

  /// The icon of a label under the quick-add field.
  static IconData icon(ChipKind kind) => switch (kind) {
    ChipKind.date => Icons.calendar_today_outlined,
    ChipKind.time => Icons.schedule,
    ChipKind.duration => Icons.hourglass_empty,
    ChipKind.repeats => Icons.repeat,
    ChipKind.due => Icons.flag_outlined,
    ChipKind.list => Icons.folder_outlined,
    ChipKind.tag => Icons.tag,
    ChipKind.priority => Icons.priority_high,
  };
}
