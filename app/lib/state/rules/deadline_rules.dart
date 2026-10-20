import '../../core/model/day_key.dart';
import '../../core/model/event.dart';
import '../../core/parsing/at_date.dart';
import '../../core/planner/planner_math.dart';
import 'calendar_rules.dart';

/// The Deadlines panel in three parts.
class DeadlineSections {
  const DeadlineSections({
    required this.missed,
    required this.coming,
    required this.done,
  });

  /// Due time passed and not ticked. The oldest first.
  final List<EventItem> missed;

  /// Due later. The soonest first.
  final List<EventItem> coming;

  /// Ticked done. The newest tick first.
  final List<EventItem> done;

  bool get isEmpty => missed.isEmpty && coming.isEmpty && done.isEmpty;
}

/// The small rules behind deadlines: an event with `isDeadline` set. It is due
/// at its end and is ticked done with `doneAt`. Plain functions, so tests can
/// check them.
abstract final class DeadlineRules {
  /// When [e] is due: its end. An all-day deadline is due at the end of its
  /// last day.
  static DateTime due(EventItem e) =>
      e.allDay ? e.end.day.adding(days: 1).date : EventDraft.date(e.end);

  /// The deadlines of [events] in their three parts. Plain events and
  /// repeating events stay out.
  static DeadlineSections sections(
    Iterable<EventItem> events, {
    required DateTime now,
  }) {
    final missed = <EventItem>[], coming = <EventItem>[], done = <EventItem>[];
    for (final e in events) {
      if (!e.isDeadline || e.recurrence != null) continue;
      if (e.doneAt != null) {
        done.add(e);
      } else if (due(e).isAfter(now)) {
        coming.add(e);
      } else {
        missed.add(e);
      }
    }
    int byDue(EventItem a, EventItem b) => due(a).compareTo(due(b));
    missed.sort(byDue);
    coming.sort(byDue);
    done.sort((a, b) => b.doneAt!.compareTo(a.doneAt!));
    return DeadlineSections(missed: missed, coming: coming, done: done);
  }

  /// How long before the due time [e] was ticked. Minus means late. Null
  /// when it is not ticked.
  static Duration? margin(EventItem e) {
    final at = DateTime.tryParse(e.doneAt ?? '');
    return at == null ? null : due(e).difference(at);
  }

  /// "Done 2d 3h early", "Done 40m late" or "Done just on time". Null when
  /// [e] is not ticked.
  static String? marginText(EventItem e) {
    final m = margin(e);
    if (m == null) return null;
    if (m.inMinutes == 0) return 'Done just on time';
    return m.isNegative ? 'Done ${span(-m)} late' : 'Done ${span(m)} early';
  }

  /// A length in the planner's style: "40m", "3h 5m", "2d 3h". From one day
  /// up, the minutes do not count.
  static String span(Duration d) {
    final days = d.inDays, hours = d.inHours % 24;
    if (days == 0) return PlannerMath.duration(d.inMinutes);
    return hours == 0 ? '${days}d' : '${days}d ${hours}h';
  }

  /// When [e] is due, and for one not ticked how long is left or how late it
  /// is: "Today 17:00 · in 5h", "Thu 22 Oct · missed by 2d".
  static String dueText(EventItem e, {required DateTime now}) {
    final at = due(e);
    final day = e.end.day;
    final today = DayKey.fromDate(now);
    final String when;
    if (day == today || day == today.adding(days: 1)) {
      final word = day == today ? 'Today' : 'Tomorrow';
      when = e.allDay ? word : '$word ${PlannerMath.clock(e.end.minute)}';
    } else {
      when = AtDatePlanner.whenLabel(
        day,
        start: e.allDay ? null : e.end.minute,
      );
    }
    if (e.doneAt != null) return when;
    final left = at.difference(now);
    return left.isNegative
        ? '$when · missed by ${span(-left)}'
        : '$when · in ${span(left)}';
  }
}
