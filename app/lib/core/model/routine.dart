import 'dart:convert';

import 'day_key.dart';
import 'ids.dart';

/// The step of a routine.
enum RoutineUnit { days, weeks, months }

/// How often a routine task is due: every [every] [unit]. The clock starts
/// again on the day the task was last done.
class RoutineRule {
  RoutineRule({int every = 1, this.unit = RoutineUnit.weeks})
    : every = every < 1 ? 1 : (every > maxEvery ? maxEvery : every);

  /// The largest step the panel offers.
  static const maxEvery = 99;

  final int every;
  final RoutineUnit unit;

  /// `{"every":2,"unit":"weeks"}`.
  String json() => jsonEncode({'every': every, 'unit': unit.name});

  /// Reads what [json] wrote. Null for anything else.
  static RoutineRule? fromJson(String? s) {
    if (s == null) return null;
    try {
      final m = jsonDecode(s);
      if (m is! Map<String, Object?>) return null;
      final every = m['every'];
      final unit = RoutineUnit.values.asNameMap()[m['unit']];
      if (every is! int || every < 1 || unit == null) return null;
      return RoutineRule(every: every, unit: unit);
    } on FormatException {
      return null;
    }
  }

  RoutineRule copyWith({int? every, RoutineUnit? unit}) =>
      RoutineRule(every: every ?? this.every, unit: unit ?? this.unit);

  @override
  bool operator ==(Object other) =>
      other is RoutineRule && other.every == every && other.unit == unit;

  @override
  int get hashCode => Object.hash(every, unit);

  @override
  String toString() => json();
}

/// One day a routine task was done. Every one is kept. [eventId] is the
/// planner block that was ticked, or null for a tick in the task list.
class RoutineDone {
  RoutineDone({
    String? id,
    required this.taskId,
    required this.day,
    this.eventId,
    String? doneAt,
  }) : id = id ?? newId(),
       doneAt = doneAt ?? Stamp.now();

  final String id;
  final String taskId;
  final DayKey day;
  final String? eventId;
  final String doneAt;

  RoutineDone copyWith({Object? eventId = keep, String? doneAt}) => RoutineDone(
    id: id,
    taskId: taskId,
    day: day,
    eventId: identical(eventId, keep) ? this.eventId : eventId as String?,
    doneAt: doneAt ?? this.doneAt,
  );

  List<Object?> get _props => [id, taskId, day, eventId, doneAt];

  @override
  bool operator ==(Object other) =>
      other is RoutineDone && sameList(other._props, _props);

  @override
  int get hashCode => Object.hashAll(_props);
}
