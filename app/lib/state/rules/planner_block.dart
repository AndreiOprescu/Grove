import '../../core/model/day_key.dart';
import '../../core/model/event.dart';
import '../../core/planner/planner_math.dart';

/// What the grid draws. Built from an event (and its task, if any).
class PlannerBlock {
  const PlannerBlock({
    required this.id,
    required this.title,
    this.summary = '',
    required this.day,
    required this.startMinute,
    required this.endMinute,
    required this.kind,
    this.taskId,
    required this.isDone,
    required this.color,
    required this.isRecurring,
    this.hasNote = false,
    this.priority = 0,
    this.goalId,
  });

  /// The event id.
  final String id;
  final String title;

  /// The short description of the task, if any.
  final String summary;
  final DayKey day;
  final int startMinute;
  final int endMinute;
  final EventKind kind;
  final String? taskId;
  final bool isDone;
  final String color;
  final bool isRecurring;
  final bool hasNote;

  /// The priority of the block's task, 0 to 3. 0 for a block with no task.
  final int priority;

  /// The goal this block belongs to, or null. A goal block has no task;
  /// [isDone] comes from the event's `doneAt`.
  final String? goalId;

  Span get span => Span(id: id, start: startMinute, end: endMinute);
  int get length => endMinute - startMinute;
  bool get isTaskBlock => taskId != null;
  bool get isGoalBlock => goalId != null;

  List<Object?> get _props => [
    id,
    title,
    summary,
    day,
    startMinute,
    endMinute,
    kind,
    taskId,
    isDone,
    color,
    isRecurring,
    hasNote,
    priority,
    goalId,
  ];

  @override
  bool operator ==(Object other) {
    if (other is! PlannerBlock) return false;
    final a = _props, b = other._props;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_props);

  @override
  String toString() =>
      'PlannerBlock($id, $title, $day $startMinute-$endMinute)';
}

/// One block's new place, used by moves, resizes and ripple.
class BlockEdit {
  const BlockEdit({
    required this.id,
    required this.day,
    required this.start,
    required this.end,
  });

  final String id;
  final DayKey day;
  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is BlockEdit &&
      other.id == id &&
      other.day == day &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(id, day, start, end);

  @override
  String toString() => 'BlockEdit($id, $day, $start, $end)';
}

/// Numbers the planner screen and the store share.
abstract final class PlannerLimits {
  /// The height of one hour on the grid, in points: the smallest and the largest zoom.
  static const minHourHeight = 36.0;
  static const maxHourHeight = 160.0;
  static const defaultHourHeight = 64.0;

  /// The lengths, in minutes, in the "Duration" entry of a block's menu.
  static const durationChoices = [15, 30, 45, 60, 90, 120, 180, 240];
}
