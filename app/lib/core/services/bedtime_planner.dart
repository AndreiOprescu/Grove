import '../model/day_key.dart';
import '../sleep/sleep_night.dart';
import '../sleep/sleep_stats.dart';
import 'reminder_planner.dart';

/// One "plan tomorrow" notification before bedtime.
class BedtimeReminder {
  const BedtimeReminder({
    required this.id,
    required this.title,
    required this.body,
    required this.fireAt,
    required this.day,
  });

  /// `bed-<night>`: one per night, so a new time replaces the old one.
  final String id;
  final String title;
  final String body;

  /// When it shows, in local time.
  final WallTime fireAt;

  /// The day to open on a click: the day after the night.
  final DayKey day;

  /// The same, in the list of reminders. A click opens the planner on [day].
  Reminder get reminder => Reminder(
    id: id,
    title: title,
    body: body,
    fireAt: fireAt,
    day: day,
    ref: null,
  );

  @override
  bool operator ==(Object other) =>
      other is BedtimeReminder &&
      other.id == id &&
      other.title == title &&
      other.body == body &&
      other.fireAt == fireAt &&
      other.day == day;

  @override
  int get hashCode => Object.hash(id, title, body, fireAt, day);

  @override
  String toString() => 'BedtimeReminder($id, $title, $fireAt)';
}

/// Works out the bedtime reminders: some time before the usual bedtime,
/// Grove asks to look at the next day. No system calls here.
abstract final class BedtimePlanner {
  static const leadChoices = [60, 90, 120];
  static const defaultLead = 90;

  /// - [now]: the time now. A reminder at this time or before it is left out.
  /// - [lead]: minutes before bedtime, one of [leadChoices].
  /// - [nights]: the sleep nights Grove has seen.
  /// - [sleepLine], [wakeLine]: the planner lines of a day, or null.
  /// - [plannedCount]: timed events and blocks on a day.
  /// - [nextAlarm]: the next alarm of this device. It moves the bedtime of
  ///   the night before it earlier when it leaves too little sleep.
  static List<BedtimeReminder> plan({
    required WallTime now,
    required int lead,
    required bool enabled,
    required Map<DayKey, SleepNight> nights,
    required int? Function(DayKey) sleepLine,
    required int? Function(DayKey) wakeLine,
    required int Function(DayKey) plannedCount,
    DateTime? nextAlarm,
  }) {
    if (!enabled || !leadChoices.contains(lead)) return const [];

    final out = <BedtimeReminder>[];
    for (var i = -1; i <= 6; i++) {
      final night = now.day.adding(days: i);
      final next = night.adding(days: 1);
      final bedtime = BedtimePlanner.bedtime(
        night: night,
        nights: nights,
        sleepLine: sleepLine(night),
        wakeLine: wakeLine(next),
        nextAlarm: nextAlarm,
      );
      final fireAt = ReminderPlanner.shifted(bedtime, by: -lead);
      if (fireAt.compareTo(now) <= 0) continue;

      final (title, body) = _words(
        night: night,
        planned: plannedCount(next),
        lead: lead,
        today: fireAt.day == next,
      );
      out.add(
        BedtimeReminder(
          id: 'bed-${night.string}',
          title: title,
          body: body,
          fireAt: fireAt,
          day: next,
        ),
      );
    }
    out.sort((a, b) {
      final byTime = a.fireAt.compareTo(b.fireAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    return out;
  }

  /// When [night] usually starts, made earlier when [nextAlarm] leaves too
  /// little sleep. [sleepLine] is the line of [night], [wakeLine] the one of
  /// the next day.
  static WallTime bedtime({
    required DayKey night,
    required Map<DayKey, SleepNight> nights,
    required int? sleepLine,
    required int? wakeLine,
    DateTime? nextAlarm,
  }) {
    final usual = SleepStats.usualBedtime(
      night: night,
      nights: nights,
      sleepLine: sleepLine,
    );
    if (nextAlarm == null) return usual;
    return SleepStats.withAlarm(
      bedtime: usual,
      length: SleepStats.usualLength(
        night: night,
        nights: nights,
        sleepLine: sleepLine,
        wakeLine: wakeLine,
      ),
      alarm: nextAlarm,
      night: night,
    );
  }

  static String _leadText(int lead) => switch (lead) {
    60 => 'about an hour',
    90 => 'about 1½ hours',
    _ => 'about ${lead ~/ 60} hours',
  };

  /// The words for [night]. The variant comes from the date, so a refresh
  /// never changes them.
  static (String, String) _words({
    required DayKey night,
    required int planned,
    required int lead,
    required bool today,
  }) {
    final d = today ? 'today' : 'tomorrow';
    final day = today ? 'Today' : 'Tomorrow';
    final l = _leadText(lead);
    final pick = _hash(night.string);

    if (planned <= 0) {
      final variants = [
        (
          'Plan $d 🌙',
          'Bedtime is in $l. A few minutes now make the morning easier.',
        ),
        (
          '$day is still open',
          'Bedtime is in $l. Pick what matters most for $d and sleep easy.',
        ),
        (
          'A calm start for $d',
          'Bedtime is in $l. Sketch $d now and wake up knowing where to '
              'begin.',
        ),
        (
          'Wind down with a plan',
          'Bedtime is in $l. Jot down what $d should hold.',
        ),
      ];
      return variants[pick % variants.length];
    }

    final things = planned == 1 ? '1 thing' : '$planned things';
    final variants = [
      ("Check $d's plan", '$day has $things planned. A quick look before bed?'),
      (
        '$day is taking shape',
        'You have $things planned for $d. Bedtime is in $l.',
      ),
      (
        'A look at $d 🌙',
        '$day has $things waiting. A quick check now helps you sleep easy.',
      ),
    ];
    return variants[pick % variants.length];
  }

  /// A hash that is the same on every run and every device.
  static int _hash(String text) {
    var h = 0;
    for (final c in text.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }
}
