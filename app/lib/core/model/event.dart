import 'day_key.dart';
import 'ids.dart';
import 'recurrence.dart';

enum EventKind { event, block }

/// A calendar event, a task time-block (an event with [taskId] set) or a
/// goal block ([goalId] set). Same fields as the Swift `EventItem`.
class EventItem {
  EventItem({
    String? id,
    required this.title,
    required this.start,
    required this.end,
    this.allDay = false,
    this.kind = EventKind.event,
    this.taskId,
    this.color = 'accent2',
    this.location = '',
    this.notes = '',
    this.recurrence,
    this.seriesId,
    this.originalDate,
    this.goalId,
    this.doneAt,
    String? createdAt,
    String? updatedAt,
  }) : id = id ?? newId(),
       createdAt = createdAt ?? updatedAt ?? Stamp.now(),
       updatedAt = updatedAt ?? createdAt ?? Stamp.now();

  final String id;
  final String title;
  final WallTime start;
  final WallTime end;
  final bool allDay;
  final EventKind kind;
  final String? taskId;
  final String color;
  final String location;
  final String notes;
  final RecurrenceRule? recurrence;

  /// Set on a detached occurrence of a series.
  final String? seriesId;

  /// Which occurrence it replaces.
  final DayKey? originalDate;

  /// Set on a block that belongs to a goal (it has no task).
  final String? goalId;

  /// When a goal block was ticked done; null = planned.
  final String? doneAt;
  final String createdAt;
  final String updatedAt;

  int get durationMinutes => start.day == end.day
      ? end.minute - start.minute
      : end.minute + 1440 * start.day.daysUntil(end.day) - start.minute;

  EventItem copyWith({
    String? id,
    String? title,
    WallTime? start,
    WallTime? end,
    bool? allDay,
    EventKind? kind,
    Object? taskId = keep,
    String? color,
    String? location,
    String? notes,
    Object? recurrence = keep,
    Object? seriesId = keep,
    Object? originalDate = keep,
    Object? goalId = keep,
    Object? doneAt = keep,
    String? createdAt,
    String? updatedAt,
  }) => EventItem(
    id: id ?? this.id,
    title: title ?? this.title,
    start: start ?? this.start,
    end: end ?? this.end,
    allDay: allDay ?? this.allDay,
    kind: kind ?? this.kind,
    taskId: identical(taskId, keep) ? this.taskId : taskId as String?,
    color: color ?? this.color,
    location: location ?? this.location,
    notes: notes ?? this.notes,
    recurrence: identical(recurrence, keep)
        ? this.recurrence
        : recurrence as RecurrenceRule?,
    seriesId: identical(seriesId, keep) ? this.seriesId : seriesId as String?,
    originalDate: identical(originalDate, keep)
        ? this.originalDate
        : originalDate as DayKey?,
    goalId: identical(goalId, keep) ? this.goalId : goalId as String?,
    doneAt: identical(doneAt, keep) ? this.doneAt : doneAt as String?,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  List<Object?> get _props => [
    id,
    title,
    start,
    end,
    allDay,
    kind,
    taskId,
    color,
    location,
    notes,
    recurrence,
    seriesId,
    originalDate,
    goalId,
    doneAt,
    createdAt,
    updatedAt,
  ];

  @override
  bool operator ==(Object other) =>
      other is EventItem && sameList(other._props, _props);

  @override
  int get hashCode => Object.hashAll(_props);

  @override
  String toString() => 'EventItem($id, $title, $start–$end)';
}
