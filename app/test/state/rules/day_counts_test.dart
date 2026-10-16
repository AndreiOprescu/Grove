import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

// The 3 bars of the Persona screen: good, okay and rough days.

void main() {
  test('counts each mood; a missing mood is 0', () {
    final c = DayCounts.from({3: 6, 1: 2});
    expect(c.of(Mood.sun), 6);
    expect(c.of(Mood.cloud), 0);
    expect(c.of(Mood.rain), 2);
    expect(c.total, 8);
  });

  test('the biggest count fills its bar; the others are a part of it', () {
    final c = DayCounts.from({3: 6, 2: 3, 1: 0});
    expect(c.fill(Mood.sun), 1);
    expect(c.fill(Mood.cloud), 0.5);
    expect(c.fill(Mood.rain), 0);
  });

  test('no days gives empty bars, not a crash', () {
    const c = DayCounts.empty;
    expect(c.total, 0);
    for (final m in Mood.values) {
      expect(c.fill(m), 0);
    }
  });

  test('this month runs from the 1st to the last day of the month', () {
    expect(
      DaySpan.month.range(const DayKey('2026-10-16')),
      const DayRange(DayKey('2026-10-01'), DayKey('2026-10-31')),
    );
    expect(
      DaySpan.month.range(const DayKey('2026-12-05')),
      const DayRange(DayKey('2026-12-01'), DayKey('2026-12-31')),
    );
    expect(
      DaySpan.month.range(const DayKey('2028-02-10')),
      const DayRange(DayKey('2028-02-01'), DayKey('2028-02-29')),
    );
    expect(DaySpan.all.range(const DayKey('2026-10-16')), isNull);
  });

  test('a stored name gives the span back; anything else is this month', () {
    expect(DaySpan.fromName('all'), DaySpan.all);
    expect(DaySpan.fromName('month'), DaySpan.month);
    expect(DaySpan.fromName(null), DaySpan.month);
    expect(DaySpan.fromName('year'), DaySpan.month);
  });
}
