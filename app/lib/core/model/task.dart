import 'day_key.dart';
import 'ids.dart';
import 'recurrence.dart';

enum TaskStatus { open, done, cancelled }

enum TaskBucket { inbox, day, week, someday }

/// A to-do item. Same fields as the Swift `TaskItem`.
class TaskItem {
  TaskItem({
    String? id,
    required this.title,
    this.summary = '',
    this.notes = '',
    this.listId,
    this.parentId,
    this.priority = 0,
    this.status = TaskStatus.open,
    this.bucket = TaskBucket.inbox,
    this.planDate,
    this.planWeek,
    this.due,
    this.estimateMin = 30,
    this.recurrence,
    this.sourceNoteId,
    this.sort = 0,
    this.color = '',
    String? createdAt,
    String? updatedAt,
    this.completedAt,
  }) : id = id ?? newId(),
       createdAt = createdAt ?? updatedAt ?? Stamp.now(),
       updatedAt = updatedAt ?? createdAt ?? Stamp.now();

  final String id;
  final String title;

  /// One short line; shows on the planner block.
  final String summary;

  /// The long description (Markdown).
  final String notes;
  final String? listId;
  final String? parentId;

  /// 0 none … 3 high.
  final int priority;
  final TaskStatus status;
  final TaskBucket bucket;

  /// When bucket == day.
  final DayKey? planDate;

  /// Monday, when bucket == week.
  final DayKey? planWeek;

  /// "YYYY-MM-DD" or "YYYY-MM-DDTHH:MM".
  final String? due;
  final int estimateMin;
  final RecurrenceRule? recurrence;
  final String? sourceNoteId;
  final double sort;

  /// One of `TaskColor.names`, or "" for no colour.
  final String color;
  final String createdAt;
  final String updatedAt;
  final String? completedAt;

  bool get isDone => status == TaskStatus.done;

  TaskItem copyWith({
    String? id,
    String? title,
    String? summary,
    String? notes,
    Object? listId = keep,
    Object? parentId = keep,
    int? priority,
    TaskStatus? status,
    TaskBucket? bucket,
    Object? planDate = keep,
    Object? planWeek = keep,
    Object? due = keep,
    int? estimateMin,
    Object? recurrence = keep,
    Object? sourceNoteId = keep,
    double? sort,
    String? color,
    String? createdAt,
    String? updatedAt,
    Object? completedAt = keep,
  }) => TaskItem(
    id: id ?? this.id,
    title: title ?? this.title,
    summary: summary ?? this.summary,
    notes: notes ?? this.notes,
    listId: identical(listId, keep) ? this.listId : listId as String?,
    parentId: identical(parentId, keep) ? this.parentId : parentId as String?,
    priority: priority ?? this.priority,
    status: status ?? this.status,
    bucket: bucket ?? this.bucket,
    planDate: identical(planDate, keep) ? this.planDate : planDate as DayKey?,
    planWeek: identical(planWeek, keep) ? this.planWeek : planWeek as DayKey?,
    due: identical(due, keep) ? this.due : due as String?,
    estimateMin: estimateMin ?? this.estimateMin,
    recurrence: identical(recurrence, keep)
        ? this.recurrence
        : recurrence as RecurrenceRule?,
    sourceNoteId: identical(sourceNoteId, keep)
        ? this.sourceNoteId
        : sourceNoteId as String?,
    sort: sort ?? this.sort,
    color: color ?? this.color,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    completedAt: identical(completedAt, keep)
        ? this.completedAt
        : completedAt as String?,
  );

  List<Object?> get _props => [
    id,
    title,
    summary,
    notes,
    listId,
    parentId,
    priority,
    status,
    bucket,
    planDate,
    planWeek,
    due,
    estimateMin,
    recurrence,
    sourceNoteId,
    sort,
    color,
    createdAt,
    updatedAt,
    completedAt,
  ];

  @override
  bool operator ==(Object other) =>
      other is TaskItem && sameList(other._props, _props);

  @override
  int get hashCode => Object.hashAll(_props);

  @override
  String toString() => 'TaskItem($id, $title)';
}

class ListItem {
  ListItem({
    String? id,
    required this.name,
    this.emoji = '',
    this.color = 'accent',
    this.sort = 0,
    this.archived = false,
  }) : id = id ?? newId();

  final String id;
  final String name;
  final String emoji;
  final String color;
  final int sort;
  final bool archived;

  ListItem copyWith({
    String? id,
    String? name,
    String? emoji,
    String? color,
    int? sort,
    bool? archived,
  }) => ListItem(
    id: id ?? this.id,
    name: name ?? this.name,
    emoji: emoji ?? this.emoji,
    color: color ?? this.color,
    sort: sort ?? this.sort,
    archived: archived ?? this.archived,
  );

  @override
  bool operator ==(Object other) =>
      other is ListItem &&
      other.id == id &&
      other.name == name &&
      other.emoji == emoji &&
      other.color == color &&
      other.sort == sort &&
      other.archived == archived;

  @override
  int get hashCode => Object.hash(id, name, emoji, color, sort, archived);
}

class Tag {
  Tag({String? id, required this.name}) : id = id ?? newId();

  final String id;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is Tag && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}
