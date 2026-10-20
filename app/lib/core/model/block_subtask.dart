import 'day_key.dart';
import 'ids.dart';

/// A subtask of one goal block. It belongs to the event, not to the goal, so
/// each block has its own list. Same fields as the Swift `BlockSubtaskItem`.
class BlockSubtaskItem {
  BlockSubtaskItem({
    String? id,
    required this.eventId,
    required this.title,
    this.doneAt,
    this.sort = 0,
    String? createdAt,
    String? updatedAt,
  }) : id = id ?? newId(),
       createdAt = createdAt ?? updatedAt ?? Stamp.now(),
       updatedAt = updatedAt ?? createdAt ?? Stamp.now();

  final String id;

  /// The block (an event) that this subtask is in.
  final String eventId;
  final String title;

  /// When it was ticked, or null for an open subtask.
  final String? doneAt;
  final double sort;
  final String createdAt;
  final String updatedAt;

  bool get isDone => doneAt != null;

  BlockSubtaskItem copyWith({
    String? id,
    String? eventId,
    String? title,
    Object? doneAt = keep,
    double? sort,
    String? createdAt,
    String? updatedAt,
  }) => BlockSubtaskItem(
    id: id ?? this.id,
    eventId: eventId ?? this.eventId,
    title: title ?? this.title,
    doneAt: identical(doneAt, keep) ? this.doneAt : doneAt as String?,
    sort: sort ?? this.sort,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  List<Object?> get _props => [
    id,
    eventId,
    title,
    doneAt,
    sort,
    createdAt,
    updatedAt,
  ];

  @override
  bool operator ==(Object other) =>
      other is BlockSubtaskItem && sameList(other._props, _props);

  @override
  int get hashCode => Object.hashAll(_props);
}
