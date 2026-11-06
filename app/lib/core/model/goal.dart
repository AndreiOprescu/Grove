import 'day_key.dart';
import 'ids.dart';

/// What a goal counts each week: the hours of its blocks, or how many blocks
/// there are.
enum GoalKind { hours, sessions }

/// A habit has a weekly target and never ends. A project can finish: it has a
/// goal map, and its root square is its finish line (ADR 0008).
enum GoalType { habit, project }

/// A piece of work the user drags into a day as a time block. Progress is
/// never stored on the goal; it is worked out from its blocks.
class GoalItem {
  GoalItem({
    String? id,
    required this.title,
    this.notes = '',
    this.color = '',
    this.targetMin = 300,
    this.sort = 0,
    this.archived = false,
    this.kind = GoalKind.hours,
    this.targetCount = 3,
    this.type = GoalType.habit,
    this.doneWhen = '',
    this.workMinutes,
    this.dueDay,
    this.why = '',
    String? createdAt,
    String? updatedAt,
  }) : id = id ?? newId(),
       createdAt = createdAt ?? updatedAt ?? Stamp.now(),
       updatedAt = updatedAt ?? createdAt ?? Stamp.now();

  final String id;
  final String title;
  final String notes;

  /// One of `TaskColor.names`, or "" for none.
  final String color;

  /// Minutes per week for an hours goal. 300 = 5 hours.
  final int targetMin;
  final double sort;
  final bool archived;
  final String createdAt;
  final String updatedAt;
  final GoalKind kind;

  /// Sessions per week for a sessions goal.
  final int targetCount;

  final GoalType type;

  /// For a project: how the user knows it is done. Empty for none.
  final String doneWhen;

  /// For a project: how much work the user thinks it needs, or null.
  final int? workMinutes;

  /// For a project: the day it should be done by, or null.
  final DayKey? dueDay;

  /// For a project: why it matters. Empty for none.
  final String why;

  bool get isProject => type == GoalType.project;

  GoalItem copyWith({
    String? id,
    String? title,
    String? notes,
    String? color,
    int? targetMin,
    double? sort,
    bool? archived,
    GoalKind? kind,
    int? targetCount,
    GoalType? type,
    String? doneWhen,
    Object? workMinutes = keep,
    Object? dueDay = keep,
    String? why,
    String? createdAt,
    String? updatedAt,
  }) => GoalItem(
    id: id ?? this.id,
    title: title ?? this.title,
    notes: notes ?? this.notes,
    color: color ?? this.color,
    targetMin: targetMin ?? this.targetMin,
    sort: sort ?? this.sort,
    archived: archived ?? this.archived,
    kind: kind ?? this.kind,
    targetCount: targetCount ?? this.targetCount,
    type: type ?? this.type,
    doneWhen: doneWhen ?? this.doneWhen,
    workMinutes: identical(workMinutes, keep)
        ? this.workMinutes
        : workMinutes as int?,
    dueDay: identical(dueDay, keep) ? this.dueDay : dueDay as DayKey?,
    why: why ?? this.why,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  List<Object?> get _props => [
    id,
    title,
    notes,
    color,
    targetMin,
    sort,
    archived,
    createdAt,
    updatedAt,
    kind,
    targetCount,
    type,
    doneWhen,
    workMinutes,
    dueDay,
    why,
  ];

  @override
  bool operator ==(Object other) =>
      other is GoalItem && sameList(other._props, _props);

  @override
  int get hashCode => Object.hashAll(_props);
}
