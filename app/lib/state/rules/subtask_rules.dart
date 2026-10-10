import 'dart:math';

import '../../core/model/task.dart';
import '../../core/planner/planner_math.dart';

/// The text rules behind the subtask list in the task panel. Plain functions,
/// so tests can check them.
abstract final class SubtaskRules {
  /// The minutes offered in the duration menu of a subtask.
  static const durations = [5, 10, 15, 30, 45, 60, 90, 120];

  /// The menu choices, plus the current value when it is not one of them.
  static List<int> durationsIncluding(int current) =>
      {...durations, current}.where((m) => m > 0).toList()..sort();

  /// "15m" for the collapsed row. Null for no duration.
  static String? chip(int minutes) =>
      minutes > 0 ? PlannerMath.duration(minutes) : null;

  /// "2/4 · 1h 15m": done of total, then the time of all subtasks. Empty when
  /// there are none.
  static String summary(List<TaskItem> subs) {
    if (subs.isEmpty) return '';
    var text = '${subs.where((t) => t.isDone).length}/${subs.length}';
    final minutes = subs.fold(0, (sum, t) => sum + max(0, t.estimateMin));
    if (minutes > 0) text += ' · ${PlannerMath.duration(minutes)}';
    return text;
  }

  /// The section title: "Subtasks  2/4 · 1h 15m".
  static String header(List<TaskItem> subs) {
    final s = summary(subs);
    return s.isEmpty ? 'Subtasks' : 'Subtasks  $s';
  }

  /// The name to save after the user edits a title, or null when nothing
  /// should be saved (empty after trimming, or not different from [current]).
  static String? renamed(String raw, {required String from}) {
    final name = raw.trim();
    return name.isEmpty || name == from ? null : name;
  }
}
