import '../model/day_key.dart';
import '../model/routine.dart';

/// Where a routine stands on one day.
class RoutineStatus {
  const RoutineStatus({
    required this.due,
    required this.daysLeft,
    required this.fraction,
    required this.label,
  });

  /// The day it is due next.
  final DayKey due;

  /// Days from today to [due]. Below 0 when it is late.
  final int daysLeft;

  /// How full the bar is: 0 on the day it was done, 1 on the due day and
  /// after.
  final double fraction;

  /// "3 days left", "1 day left", "Due today", "Late 2 days".
  final String label;

  bool get late => daysLeft < 0;
}

/// The rules of a routine: a task that comes back a set time after the day
/// it was last done.
abstract final class RoutineRules {
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// The day after [last] when the routine is due again. Months are calendar
  /// months: the day is clamped to the length of the month.
  static DayKey dueDay(DayKey last, RoutineRule rule) => switch (rule.unit) {
    RoutineUnit.days => last.adding(days: rule.every),
    RoutineUnit.weeks => last.adding(days: 7 * rule.every),
    RoutineUnit.months => _addMonths(last, rule.every),
  };

  static DayKey _addMonths(DayKey date, int months) {
    final total = date.month - 1 + months;
    final y = date.year + total ~/ 12, m = total % 12 + 1;
    final last = DayKey.ymd(y, m, 1).daysInMonth;
    return DayKey.ymd(y, m, date.day < last ? date.day : last);
  }

  /// The day the clock started: the latest done day, or [since] (the day the
  /// routine was turned on) when that is later. So a routine turned on again
  /// does not start late because of an old history.
  static DayKey lastDone(DayKey since, Iterable<DayKey> doneDays) {
    var last = since;
    for (final day in doneDays) {
      if (day > last) last = day;
    }
    return last;
  }

  static RoutineStatus status(RoutineRule rule, DayKey last, DayKey today) {
    final due = dueDay(last, rule);
    final total = last.daysUntil(due);
    final left = today.daysUntil(due);
    final gone = total - left;
    final fraction = total <= 0 ? 1.0 : (gone / total).clamp(0.0, 1.0);
    return RoutineStatus(
      due: due,
      daysLeft: left,
      fraction: fraction.toDouble(),
      label: leftLabel(left),
    );
  }

  static String leftLabel(int daysLeft) {
    if (daysLeft == 0) return 'Due today';
    if (daysLeft > 0) {
      return daysLeft == 1 ? '1 day left' : '$daysLeft days left';
    }
    final late = -daysLeft;
    return late == 1 ? 'Late 1 day' : 'Late $late days';
  }

  /// Late first, then the least time left, then by title.
  static int compare(int aLeft, String aTitle, int bLeft, String bTitle) {
    final byLeft = aLeft.compareTo(bLeft);
    if (byLeft != 0) return byLeft;
    return aTitle.toLowerCase().compareTo(bTitle.toLowerCase());
  }

  /// "12 Nov".
  static String shortDate(DayKey day) => '${day.day} ${_months[day.month - 1]}';

  /// "Done 6 times, last on 12 Nov", "Done once, last on 12 Nov" or
  /// "Not done yet".
  static String historyLabel(Iterable<DayKey> doneDays) {
    final days = doneDays.toList();
    if (days.isEmpty) return 'Not done yet';
    var last = days.first;
    for (final day in days) {
      if (day > last) last = day;
    }
    final times = days.length == 1 ? 'once' : '${days.length} times';
    return 'Done $times, last on ${shortDate(last)}';
  }

  /// "Every day", "Every 2 weeks", "Every month".
  static String stepLabel(RoutineRule rule) {
    final one = switch (rule.unit) {
      RoutineUnit.days => 'day',
      RoutineUnit.weeks => 'week',
      RoutineUnit.months => 'month',
    };
    return rule.every == 1 ? 'Every $one' : 'Every ${rule.every} ${one}s';
  }
}
