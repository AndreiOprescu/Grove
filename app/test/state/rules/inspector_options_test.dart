// Port of Tests/GroveTests/InspectorOptionsTests.swift.
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

void main() {
  test('every preset reads back as itself', () {
    for (final p in RepeatPreset.values) {
      if (p == RepeatPreset.custom) continue;
      expect(RepeatPreset.of(p.rule), p, reason: '$p');
    }
  });

  test('no rule is none', () {
    expect(RepeatPreset.of(null), RepeatPreset.none);
    expect(RepeatPreset.none.rule, isNull);
  });

  test('preset rules', () {
    expect(RepeatPreset.daily.rule, RecurrenceRule(freq: Freq.daily));
    expect(
      RepeatPreset.weekdays.rule,
      RecurrenceRule(freq: Freq.weekly, weekdays: [1, 2, 3, 4, 5]),
    );
    expect(
      RepeatPreset.biweekly.rule,
      RecurrenceRule(freq: Freq.weekly, interval: 2),
    );
  });

  test('other rules are custom and keep their details', () {
    const custom = RepeatPreset.custom;
    expect(
      RepeatPreset.of(RecurrenceRule(freq: Freq.daily, interval: 3)),
      custom,
    );
    expect(
      RepeatPreset.of(RecurrenceRule(freq: Freq.weekly, weekdays: [2, 4])),
      custom,
    );
    expect(
      RepeatPreset.of(
        RecurrenceRule(freq: Freq.daily, until: const DayKey('2027-01-01')),
      ),
      custom,
    );
    expect(
      RepeatPreset.of(RecurrenceRule(freq: Freq.monthly, count: 5)),
      custom,
    );
  });

  test('estimate choices always hold the current value once', () {
    expect(
      InspectorOptions.estimates(including: 30).where((m) => m == 30).length,
      1,
    );
    final odd = InspectorOptions.estimates(including: 37);
    expect(odd, contains(37));
    expect(odd, [...odd]..sort());
    expect(InspectorOptions.estimates(including: 30), isNot(contains(37)));
  });

  test('estimate choices follow the fifteen minute grid', () {
    final list = InspectorOptions.estimates(including: 30);
    expect(list.every((m) => m % 15 == 0), isTrue);
    expect(list.first, 15);
  });

  test('due dates read and write', () {
    const day = DayKey('2026-10-05');
    expect(InspectorOptions.dueDay('2026-10-05'), day);
    expect(InspectorOptions.dueDay('2026-10-05T14:30'), day);
    expect(InspectorOptions.dueDay(null), isNull);
    expect(
      InspectorOptions.dueString(day, keepingTimeOf: '2026-10-01T14:30'),
      '2026-10-05T14:30',
    );
    expect(
      InspectorOptions.dueString(day, keepingTimeOf: '2026-10-01'),
      '2026-10-05',
    );
    expect(InspectorOptions.dueString(day), '2026-10-05');
  });

  test('plan buckets map to placements', () {
    const mon = DayKey('2026-10-05'), wed = DayKey('2026-10-07');
    expect(
      InspectorOptions.placement(bucket: TaskBucket.inbox, date: wed),
      TaskPlacement.inbox,
    );
    expect(
      InspectorOptions.placement(bucket: TaskBucket.someday, date: wed),
      TaskPlacement.someday,
    );
    expect(
      InspectorOptions.placement(bucket: TaskBucket.day, date: wed),
      const TaskPlacement.day(wed),
    );
    expect(
      InspectorOptions.placement(bucket: TaskBucket.week, date: wed),
      const TaskPlacement.week(mon),
    );
  });
}
