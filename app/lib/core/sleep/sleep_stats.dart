import '../model/day_key.dart';
import '../services/reminder_planner.dart';
import 'sleep_night.dart';

/// The usual bedtime and length of sleep, from the nights Grove has seen.
///
/// Each asks in this order: the 4 latest nights on the same weekday in the
/// last 56 days (needs 2), then the last 14 nights (needs 3), then the
/// planner lines, then a default. The value is the median.
abstract final class SleepStats {
  static const sameWeekdays = 4;
  static const sameWeekdaySpan = 56;
  static const recentSpan = 14;
  static const defaultBedtime = 23 * 60;
  static const defaultLength = 480;

  /// Minutes after 12:00 on [night]: 23:50 is 710, 00:20 the next day 740.
  static int bedtimeMinutes(DayKey night, WallTime asleep) =>
      SleepNightRules.minutesBetween(WallTime(day: night, minute: 720), asleep);

  /// When [night] usually starts: on [night] or just after midnight.
  /// [sleepLine] is a minute of [night]; one before 12:00 is after midnight.
  static WallTime usualBedtime({
    required DayKey night,
    required Map<DayKey, SleepNight> nights,
    int? sleepLine,
  }) {
    final m = _usual(night, nights, (n) => bedtimeMinutes(n.night, n.asleep));
    if (m != null) return _afterNoon(night, m);
    if (sleepLine != null) return _line(night, sleepLine);
    return WallTime(day: night, minute: defaultBedtime);
  }

  /// How long [night] usually lasts, in minutes. [wakeLine] is a minute of
  /// the next day.
  static int usualLength({
    required DayKey night,
    required Map<DayKey, SleepNight> nights,
    int? sleepLine,
    int? wakeLine,
  }) {
    final m = _usual(night, nights, (n) => n.length);
    if (m != null) return m;
    if (sleepLine != null && wakeLine != null) {
      final wake = WallTime(day: night.adding(days: 1), minute: wakeLine);
      final length = SleepNightRules.minutesBetween(
        _line(night, sleepLine),
        wake,
      );
      if (length > 0) return length;
    }
    return defaultLength;
  }

  /// [bedtime], made earlier when an [alarm] between 00:00 and 14:00 the
  /// next day leaves less than [length] minutes of sleep.
  static WallTime withAlarm({
    required WallTime bedtime,
    required int length,
    DateTime? alarm,
    required DayKey night,
  }) {
    if (alarm == null) return bedtime;
    final next = night.adding(days: 1);
    if (DayKey.fromDate(alarm) != next || alarm.hour >= 14) return bedtime;
    final rings = WallTime(day: next, minute: alarm.hour * 60 + alarm.minute);
    final latest = ReminderPlanner.shifted(rings, by: -length);
    return latest.compareTo(bedtime) < 0 ? latest : bedtime;
  }

  static int? _usual(
    DayKey night,
    Map<DayKey, SleepNight> nights,
    int Function(SleepNight) value,
  ) {
    final before = nights.values.where((n) => n.night < night).toList()
      ..sort((a, b) => b.night.compareTo(a.night));

    final same = before
        .where(
          (n) =>
              n.night.weekdayIndex == night.weekdayIndex &&
              n.night.daysUntil(night) <= sameWeekdaySpan,
        )
        .take(sameWeekdays)
        .toList();
    if (same.length >= 2) return _median(same.map(value));

    final recent = before
        .where((n) => n.night.daysUntil(night) <= recentSpan)
        .toList();
    if (recent.length >= 3) return _median(recent.map(value));
    return null;
  }

  static int _median(Iterable<int> values) {
    final sorted = values.toList()..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return ((sorted[mid - 1] + sorted[mid]) / 2).round();
  }

  static WallTime _afterNoon(DayKey night, int minutes) =>
      ReminderPlanner.shifted(WallTime(day: night, minute: 720), by: minutes);

  /// A sleep line on [night]; one before 12:00 is after midnight.
  static WallTime _line(DayKey night, int minute) => WallTime(
    day: minute < 720 ? night.adding(days: 1) : night,
    minute: minute,
  );
}
