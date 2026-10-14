import '../../core/model/day_key.dart';
import '../../core/model/goal_subtask.dart';
import '../../core/parsing/quick_add_parser.dart';
import '../../core/planner/planner_math.dart';

/// What a goal shows of its subtasks in the Goals panel. Plain functions, so
/// tests can check them.
abstract final class GoalSubtaskRules {
  /// How many subtasks a closed goal shows.
  static const closedCount = 3;

  /// The subtasks that the goal shows. A subtask that is planned in a block
  /// and done there is not in it: the block keeps it.
  static List<GoalSubtaskItem> inGoal(List<GoalSubtaskItem> all) => [
    for (final s in all)
      if (!(s.isPlanned && s.isDone)) s,
  ];

  /// The subtasks under a closed goal: the first ones that are not done, in
  /// list order. A done subtask shows only in the open goal.
  static List<GoalSubtaskItem> closed(List<GoalSubtaskItem> all) =>
      all.where((s) => !s.isDone).take(closedCount).toList();

  /// The line under them, for what a closed goal does not show: "+2 more",
  /// "2 done" or "+2 more · 2 done". Null when it shows every subtask.
  static String? moreLine(List<GoalSubtaskItem> all) {
    final mine = inGoal(all);
    final done = mine.where((s) => s.isDone).length;
    final hidden = mine.length - done - closedCount;
    final parts = [if (hidden > 0) '+$hidden more', if (done > 0) '$done done'];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// The mark on a subtask that is planned in a block: the day and the start
  /// of the block. "Today 10:00", "Tue 14:00" for one of the next six days,
  /// "12 Oct 10:00" for any other day.
  static String planMark(WallTime start, {required DayKey today}) {
    final day = start.day;
    final away = today.daysUntil(day);
    final name = away == 0
        ? 'Today'
        : away > 0 && away < 7
        ? QuickAddParser.weekdayShort[day.weekdayIndex]
        : '${day.day} ${QuickAddParser.monthShort[day.month]}';
    return '$name ${PlannerMath.clock(start.minute)}';
  }
}
