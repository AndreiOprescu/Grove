import '../../core/model/day_key.dart';
import '../../core/model/task.dart';

/// The order of the Planner screen's task list, which shows every open task.
/// Plain functions, so tests can check them.
abstract final class AllTasksRules {
  /// Splits tasks (already in list order) into the two parts of the list.
  /// `noDay`: inbox, then week tasks (earliest week first), then someday.
  /// A day task with no date counts as inbox.
  /// `byDay`: tasks with a day, earliest day first, so late ones are on top.
  /// Tasks that tie keep the order they came in.
  static ({List<TaskItem> noDay, List<TaskItem> byDay}) split(
    List<TaskItem> tasks,
  ) {
    final noDay = <({int group, String week, int index, TaskItem task})>[];
    final byDay = <({DayKey day, int index, TaskItem task})>[];
    for (var i = 0; i < tasks.length; i++) {
      final t = tasks[i];
      final d = t.planDate;
      if (t.bucket == TaskBucket.day && d != null) {
        byDay.add((day: d, index: i, task: t));
      } else {
        noDay.add((
          group: _group(t.bucket),
          week: t.planWeek?.string ?? '',
          index: i,
          task: t,
        ));
      }
    }
    noDay.sort((a, b) {
      if (a.group != b.group) return a.group.compareTo(b.group);
      final week = a.week.compareTo(b.week);
      return week != 0 ? week : a.index.compareTo(b.index);
    });
    byDay.sort((a, b) {
      final day = a.day.compareTo(b.day);
      return day != 0 ? day : a.index.compareTo(b.index);
    });
    return (
      noDay: [for (final x in noDay) x.task],
      byDay: [for (final x in byDay) x.task],
    );
  }

  /// The tasks the Planner screen's side list offers for dragging onto the
  /// calendar (tasks already on a day are left out).
  /// `overdue`: tasks planned for a day before [today], earliest day first.
  /// `unscheduled`: tasks with no day, in the order of `split(...).noDay`.
  /// A task planned for [today] or a later day is in neither list.
  /// A week task is never overdue.
  static ({List<TaskItem> overdue, List<TaskItem> unscheduled}) unscheduled(
    List<TaskItem> tasks, {
    required DayKey today,
  }) {
    final parts = split(tasks);
    return (
      overdue: [
        for (final t in parts.byDay)
          if ((t.planDate ?? today) < today) t,
      ],
      unscheduled: parts.noDay,
    );
  }

  static int _group(TaskBucket bucket) => switch (bucket) {
    TaskBucket.inbox || TaskBucket.day => 0,
    TaskBucket.week => 1,
    TaskBucket.someday => 2,
  };
}
