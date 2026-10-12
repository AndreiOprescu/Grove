import 'day_key.dart';
import 'ids.dart';

/// A subtask of a goal. It belongs to the goal, not to one block, so every
/// block of the goal has the same list. The subtasks of one block are
/// another thing (`BlockSubtaskItem`).
class GoalSubtaskItem {
  GoalSubtaskItem({
    String? id,
    required this.goalId,
    required this.title,
    this.doneAt,
    this.sort = 0,
    String? createdAt,
    String? updatedAt,
  }) : id = id ?? newId(),
       createdAt = createdAt ?? updatedAt ?? Stamp.now(),
       updatedAt = updatedAt ?? createdAt ?? Stamp.now();

  final String id;

  /// The goal that this subtask is in.
  final String goalId;
  final String title;

  /// When it was ticked, or null for an open subtask.
  final String? doneAt;
  final double sort;
  final String createdAt;
  final String updatedAt;

  bool get isDone => doneAt != null;

  GoalSubtaskItem copyWith({
    String? id,
    String? goalId,
    String? title,
    Object? doneAt = keep,
    double? sort,
    String? createdAt,
    String? updatedAt,
  }) => GoalSubtaskItem(
    id: id ?? this.id,
    goalId: goalId ?? this.goalId,
    title: title ?? this.title,
    doneAt: identical(doneAt, keep) ? this.doneAt : doneAt as String?,
    sort: sort ?? this.sort,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  List<Object?> get _props => [
    id,
    goalId,
    title,
    doneAt,
    sort,
    createdAt,
    updatedAt,
  ];

  @override
  bool operator ==(Object other) =>
      other is GoalSubtaskItem && sameList(other._props, _props);

  @override
  int get hashCode => Object.hashAll(_props);
}
