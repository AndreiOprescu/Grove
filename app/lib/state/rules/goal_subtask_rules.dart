import '../../core/model/goal_subtask.dart';

/// What a closed goal shows of its subtasks in the Goals panel. Plain
/// functions, so tests can check them.
abstract final class GoalSubtaskRules {
  /// How many subtasks a closed goal shows.
  static const closedCount = 3;

  /// The subtasks under a closed goal: the first ones that are not done, in
  /// list order. A done subtask shows only in the open goal.
  static List<GoalSubtaskItem> closed(List<GoalSubtaskItem> all) =>
      all.where((s) => !s.isDone).take(closedCount).toList();

  /// The line under them, for what a closed goal does not show: "+2 more",
  /// "2 done" or "+2 more · 2 done". Null when it shows every subtask.
  static String? moreLine(List<GoalSubtaskItem> all) {
    final done = all.where((s) => s.isDone).length;
    final hidden = all.length - done - closedCount;
    final parts = [if (hidden > 0) '+$hidden more', if (done > 0) '$done done'];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
