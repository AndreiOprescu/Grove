import '../model/day_key.dart';
import '../model/event.dart';
import '../model/link.dart';
import '../model/task.dart';
import '../planner/planner_math.dart';

/// One notification to ask the system for (PLAN §5.6).
class Reminder {
  const Reminder({
    required this.id,
    required this.title,
    required this.body,
    required this.fireAt,
    required this.day,
    required this.ref,
  });

  /// `ev-<event id>-<start>` for an event or a block, `due-<task id>-<due>`
  /// for a due time. The same thing at the same time always has the same id.
  final String id;
  final String title;
  final String body;

  /// When it shows, in local time.
  final WallTime fireAt;

  /// The day to open on a click.
  final DayKey day;

  /// What to open on a click. A block opens its task.
  final ItemRef ref;

  @override
  bool operator ==(Object other) =>
      other is Reminder &&
      other.id == id &&
      other.title == title &&
      other.body == body &&
      other.fireAt == fireAt &&
      other.day == day &&
      other.ref == ref;

  @override
  int get hashCode => Object.hash(id, title, body, fireAt, day, ref);

  @override
  String toString() => 'Reminder($id, $title, $fireAt)';
}

/// Works out which reminders to schedule. No system calls here, so a test can
/// check every rule.
abstract final class ReminderPlanner {
  /// The system keeps 64 pending notifications. Grove uses at most 60.
  static const limit = 60;
  static const leadChoices = [0, 5, 10, 15];
  static const defaultLead = 5;

  /// - [events]: events and blocks of the coming days, repeating events
  ///   already split into days.
  /// - [dueTasks]: tasks that have a due date. Only a due date with a time
  ///   reminds.
  /// - [finishedTaskIds]: tasks that are done or cancelled. Their blocks do
  ///   not remind.
  /// - [now]: the time now. A reminder at this time or before it is left out.
  /// - [lead]: minutes before the start.
  static List<Reminder> plan({
    required List<EventItem> events,
    required List<TaskItem> dueTasks,
    required Set<String> finishedTaskIds,
    required WallTime now,
    required int lead,
    int limit = ReminderPlanner.limit,
  }) {
    final all = <Reminder>[];

    for (final e in events) {
      if (e.allDay) continue;
      final taskId = e.taskId;
      if (taskId != null && finishedTaskIds.contains(taskId)) continue;
      all.add(
        Reminder(
          id: 'ev-${e.id}-${e.start.string}',
          title: e.title,
          body:
              '${PlannerMath.clock(e.start.minute)} – '
              '${PlannerMath.clock(e.end.minute)}',
          fireAt: shifted(e.start, by: -lead),
          day: e.start.day,
          ref: taskId != null
              ? ItemRef(ItemType.task, taskId)
              : ItemRef(ItemType.event, e.id),
        ),
      );
    }

    for (final t in dueTasks) {
      if (t.status != TaskStatus.open) continue;
      final text = t.due;
      final due = text == null ? null : WallTime.parse(text);
      if (due == null) continue;
      all.add(
        Reminder(
          id: 'due-${t.id}-${due.string}',
          title: t.title,
          body: 'Due ${PlannerMath.clock(due.minute)}',
          fireAt: shifted(due, by: -lead),
          day: due.day,
          ref: ItemRef(ItemType.task, t.id),
        ),
      );
    }

    final future = all.where((r) => r.fireAt.compareTo(now) > 0).toList()
      ..sort((a, b) {
        final byTime = a.fireAt.compareTo(b.fireAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    return future.take(limit).toList();
  }

  /// [time] moved by some minutes, over midnight too.
  static WallTime shifted(WallTime time, {required int by}) {
    final total = time.minute + by;
    final days = (total / 1440).floor();
    return WallTime(
      day: time.day.adding(days: days),
      minute: total - days * 1440,
    );
  }
}
