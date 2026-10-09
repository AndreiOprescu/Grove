import 'day_key.dart';
import 'ids.dart';

/// What a goal counts each week: the hours of its blocks, or how many blocks
/// there are.
enum GoalKind { hours, sessions }

/// A recurring piece of work with a weekly target and no date.
/// The user drags it into a day as a time block. Progress is never stored on
/// the goal; it is worked out from its blocks.
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
  ];

  @override
  bool operator ==(Object other) =>
      other is GoalItem && sameList(other._props, _props);

  @override
  int get hashCode => Object.hashAll(_props);
}
