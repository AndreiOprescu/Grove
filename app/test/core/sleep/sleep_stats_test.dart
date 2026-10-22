import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/sleep/sleep_night.dart';
import 'package:grove/core/sleep/sleep_stats.dart';

/// A Monday.
const night = DayKey('2026-10-05');
const next = DayKey('2026-10-06');

WallTime w(DayKey day, int hour, [int minute = 0]) =>
    WallTime(day: day, minute: hour * 60 + minute);

/// The time [minutes] after 12:00 on [day].
WallTime afterNoon(DayKey day, int minutes) {
  final total = 720 + minutes;
  return WallTime(
    day: day.adding(days: total ~/ 1440),
    minute: total % 1440,
  );
}

/// A night [daysBefore] days before [night], asleep [bed] minutes after
/// noon, for [length] minutes.
MapEntry<DayKey, SleepNight> n(int daysBefore, int bed, [int length = 480]) {
  final d = night.adding(days: -daysBefore);
  final asleep = afterNoon(d, bed);
  final woke = afterNoon(d, bed + length);
  return MapEntry(
    d,
    SleepNight(
      night: d,
      asleep: asleep,
      woke: woke,
      sources: const ['android'],
      parts: {'android': NightPart(asleep: asleep, woke: woke)},
    ),
  );
}

WallTime bed(List<MapEntry<DayKey, SleepNight>> list, {int? sleepLine}) =>
    SleepStats.usualBedtime(
      night: night,
      nights: Map.fromEntries(list),
      sleepLine: sleepLine,
    );

int length(
  List<MapEntry<DayKey, SleepNight>> list, {
  int? sleepLine,
  int? wakeLine,
}) => SleepStats.usualLength(
  night: night,
  nights: Map.fromEntries(list),
  sleepLine: sleepLine,
  wakeLine: wakeLine,
);

void main() {
  group('measures', () {
    test('bedtime counts minutes after noon on the evening day', () {
      expect(SleepStats.bedtimeMinutes(night, w(night, 23, 50)), 710);
      expect(SleepStats.bedtimeMinutes(night, w(next, 0, 20)), 740);
    });

    test('length is the minutes between asleep and woke', () {
      expect(n(1, 660, 455).value.length, 455);
    });
  });

  group('usualBedtime', () {
    test('the 4 latest same weekdays give the median', () {
      final t = bed([
        n(7, 600),
        n(14, 620),
        n(21, 640),
        n(28, 700),
        n(35, 0),
        n(1, 300),
        n(2, 300),
        n(3, 300),
      ]);
      // Middle two of 600, 620, 640, 700: (620 + 640) / 2 = 630 → 22:30.
      expect(t, w(night, 22, 30));
    });

    test('the median of an even count is rounded', () {
      // (601 + 610) / 2 = 605.5 → 606.
      expect(bed([n(7, 601), n(14, 610)]), afterNoon(night, 606));
    });

    test('the median works across midnight', () {
      expect(bed([n(7, 710), n(14, 730)]), w(next, 0, 0));
      expect(bed([n(7, 740), n(14, 760)]), w(next, 0, 30));
    });

    test('same weekdays older than 56 days do not count', () {
      final t = bed([n(56, 600), n(63, 700), n(1, 650), n(2, 650)]);
      // Only one same weekday in range, two recent nights: fall to the line.
      expect(t, w(night, 23));
    });

    test('one same weekday falls back to the last 14 nights', () {
      final t = bed([n(7, 600), n(1, 650), n(3, 660), n(13, 670), n(15, 0)]);
      // Nights 1..14: 650, 660, 600 (day 7), 670 → 655.
      expect(t, afterNoon(night, 655));
    });

    test('the night itself and later nights do not count', () {
      final t = bed([n(0, 0), n(-7, 0), n(7, 600), n(14, 620)]);
      expect(t, afterNoon(night, 610));
    });

    test('too few nights fall back to the sleep line', () {
      expect(bed([n(1, 600), n(2, 600)], sleepLine: 22 * 60), w(night, 22));
    });

    test('a sleep line before noon is after midnight', () {
      expect(bed([], sleepLine: 30), w(next, 0, 30));
    });

    test('no nights and no line give 23:00', () {
      expect(bed([]), w(night, 23));
    });
  });

  group('usualLength', () {
    test('the 4 latest same weekdays give the median', () {
      expect(
        length([n(7, 600, 420), n(14, 600, 440), n(21, 600, 500), n(1, 0, 1)]),
        440,
      );
    });

    test('falls back to the last 14 nights', () {
      expect(length([n(1, 600, 400), n(2, 600, 410), n(3, 600, 600)]), 410);
    });

    test('falls back to the wake line minus the sleep line', () {
      expect(length([], sleepLine: 23 * 60, wakeLine: 7 * 60), 480);
      expect(length([], sleepLine: 22 * 60, wakeLine: 6 * 60 + 30), 510);
      expect(length([], sleepLine: 30, wakeLine: 7 * 60), 390);
    });

    test('no lines, or lines in the wrong order, give 480', () {
      expect(length([]), 480);
      expect(length([], sleepLine: 23 * 60), 480);
      expect(length([], wakeLine: 7 * 60), 480);
      expect(length([], sleepLine: 9 * 60, wakeLine: 7 * 60), 480);
    });
  });

  group('withAlarm', () {
    WallTime alarmed(DateTime? alarm, {int length = 480}) =>
        SleepStats.withAlarm(
          bedtime: w(night, 23),
          length: length,
          alarm: alarm,
          night: night,
        );

    test('an early alarm moves bedtime earlier', () {
      expect(alarmed(DateTime(2026, 10, 6, 6)), w(night, 22));
      expect(alarmed(DateTime(2026, 10, 6, 6, 30, 40)), w(night, 22, 30));
    });

    test('a late alarm keeps the usual bedtime', () {
      expect(alarmed(DateTime(2026, 10, 6, 8)), w(night, 23));
    });

    test('an alarm outside 00:00 to 14:00 the next day is left out', () {
      expect(alarmed(DateTime(2026, 10, 6, 14)), w(night, 23));
      expect(alarmed(DateTime(2026, 10, 5, 22)), w(night, 23));
      expect(alarmed(DateTime(2026, 10, 7, 5)), w(night, 23));
    });

    test('no alarm keeps the usual bedtime', () {
      expect(alarmed(null), w(night, 23));
    });
  });
}
