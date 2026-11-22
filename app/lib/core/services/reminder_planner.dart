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
  /// for a due time, `routine-<task id>-<due day>` for a routine. The same thing at the same time always has the same id.
  final String id;
  final String title;
  final String body;

  /// When it shows, in local time.
  final WallTime fireAt;

  /// The day to open on a click.
  final DayKey day;

  /// What to open on a click. A block opens its task. Null: the click opens
  /// the planner on [day] (a bedtime reminder).
  final ItemRef? ref;

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
      ..sort(_byTime);
    return future.take(limit).toList();
  }

  /// The minute of the due day a routine reminds: 09:00.
  static const routineMinute = 9 * 60;

  /// One reminder for each routine, at 09:00 on its due day. A routine that
  /// is late, or whose 09:00 has passed, has none: Grove reminds one time.
  /// [due] holds the task id, its title and the day it is due.
  static List<Reminder> routines({
    required List<({String id, String title, DayKey due})> due,
    required WallTime now,
    int limit = ReminderPlanner.limit,
  }) {
    final out = <Reminder>[
      for (final r in due)
        if (WallTime(day: r.due, minute: routineMinute).compareTo(now) > 0)
          Reminder(
            id: 'routine-${r.id}-${r.due.string}',
            title: r.title,
            body: 'Due today',
            fireAt: WallTime(day: r.due, minute: routineMinute),
            day: r.due,
            ref: ItemRef(ItemType.task, r.id),
          ),
    ]..sort(_byTime);
    return out.take(limit).toList();
  }

  /// Two lists in one, in time order; the same time sorts by id. Plan the
  /// others with `limit - bedtime.length`, so the total stays at [limit].
  static List<Reminder> joined(List<Reminder> a, List<Reminder> b) =>
      [...a, ...b]..sort(_byTime);

  static int _byTime(Reminder a, Reminder b) {
    final byTime = a.fireAt.compareTo(b.fireAt);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
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
