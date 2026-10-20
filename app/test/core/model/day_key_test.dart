// Port of DayKeyTests in Tests/GroveCoreTests/DatabaseTests.swift.
import 'package:grove/core/model/day_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('weekday and week start', () {
    const fri = DayKey('2026-10-02');
    expect(fri.weekdayIndex, 5);
    expect(fri.weekStart(), const DayKey('2026-09-28'));
    expect(fri.weekStart(mondayFirst: false), const DayKey('2026-09-27'));
    expect(const DayKey('2026-10-04').weekdayIndex, 7);
    expect(const DayKey('2026-10-04').weekStart(), const DayKey('2026-09-28'));
  });

  test('adding days crosses months', () {
    expect(
      const DayKey('2026-10-31').adding(days: 1),
      const DayKey('2026-11-01'),
    );
    expect(
      const DayKey('2026-03-01').adding(days: -1),
      const DayKey('2026-02-28'),
    );
    expect(const DayKey('2026-10-02').daysUntil(const DayKey('2026-10-09')), 7);
  });

  test('adding days across a daylight saving change stays on whole days', () {
    // Europe moves clocks back on 2026-10-25 and forward on 2026-03-29.
    expect(
      const DayKey('2026-10-24').adding(days: 2),
      const DayKey('2026-10-26'),
    );
    expect(const DayKey('2026-03-28').daysUntil(const DayKey('2026-03-30')), 2);
  });

  test('parse rejects bad dates', () {
    expect(DayKey.parse('2026-02-30'), isNull);
    expect(DayKey.parse('2026-1-1'), isNull);
    expect(DayKey.parse('hello'), isNull);
    expect(DayKey.parse('2026-02-28'), const DayKey('2026-02-28'));
  });

  test('wall time round trip', () {
    final w = WallTime.parse('2026-10-02T14:05');
    expect(w?.minute, 14 * 60 + 5);
    expect(w?.string, '2026-10-02T14:05');
    expect(WallTime.parse('2026-10-02T25:00'), isNull);
    expect(
      const WallTime(day: DayKey('2026-10-02'), minute: 1440).string,
      '2026-10-02T24:00',
    );
  });

  test('week number', () {
    expect(const DayKey('2026-10-02').weekOfYear, 40);
    // ISO weeks at year edges.
    expect(const DayKey('2027-01-01').weekOfYear, 53);
    expect(const DayKey('2025-12-29').weekOfYear, 1);
  });

  test('days in month and ranges', () {
    expect(const DayKey('2028-02-10').daysInMonth, 29);
    expect(const DayKey('2026-02-10').daysInMonth, 28);
    expect(
      const DayKey('2026-09-29').rangeThrough(const DayKey('2026-10-01')),
      const [DayKey('2026-09-29'), DayKey('2026-09-30'), DayKey('2026-10-01')],
    );
    expect(
      const DayKey('2026-10-02').rangeThrough(const DayKey('2026-10-01')),
      isEmpty,
    );
  });

  test('day keys and wall times compare by their text', () {
    expect(const DayKey('2026-09-30') < const DayKey('2026-10-01'), isTrue);
    expect(
      const WallTime(
        day: DayKey('2026-10-01'),
        minute: 600,
      ).compareTo(const WallTime(day: DayKey('2026-10-01'), minute: 60)),
      greaterThan(0),
    );
  });

  test('a day key from a date uses its calendar day', () {
    expect(
      DayKey.fromDate(DateTime(2026, 10, 2, 23, 59)),
      const DayKey('2026-10-02'),
    );
    expect(DayKey.ymd(2026, 1, 5).string, '2026-01-05');
  });
}
