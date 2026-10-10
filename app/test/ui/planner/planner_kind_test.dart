// Port of Tests/GroveTests/PlannerKindTests.swift: the days each top tab
// shows, and where Previous and Next go.
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/ui/planner/planner_kind.dart';

DayKey d(String s) => DayKey.parse(s)!;

void main() {
  final today = d('2026-10-09');

  test('today shows only today', () {
    final days = PlannerKind.today.days(
      selected: d('2026-10-07'),
      today: today,
      sundayFirst: false,
    );
    expect(days, [today]);
  });

  test('the week has 7 days and starts on Monday', () {
    final days = PlannerKind.week.days(
      selected: d('2026-10-07'),
      today: today,
      sundayFirst: false,
    );
    expect(days.length, 7);
    expect(days.first, d('2026-10-05'));
    expect(days.last, d('2026-10-11'));
  });

  test('the week starts on Sunday when the setting says so', () {
    final days = PlannerKind.week.days(
      selected: d('2026-10-07'),
      today: today,
      sundayFirst: true,
    );
    expect(days.first, d('2026-10-04'));
    expect(days.last, d('2026-10-10'));
  });

  test('a Sunday belongs to the week before it with Monday first', () {
    final days = PlannerKind.week.days(
      selected: d('2026-10-11'),
      today: today,
      sundayFirst: false,
    );
    expect(days.first, d('2026-10-05'));
    expect(days.last, d('2026-10-11'));
  });

  test('the month is its grid of 42 days', () {
    final days = PlannerKind.month.days(
      selected: d('2026-10-07'),
      today: today,
      sundayFirst: false,
    );
    expect(days.length, 42);
    expect(days.first, d('2026-09-28'));
    expect(days.last, d('2026-11-08'));
    final sunday = PlannerKind.month.days(
      selected: d('2026-10-07'),
      today: today,
      sundayFirst: true,
    );
    expect(sunday.first, d('2026-09-27'));
  });

  test('the week steps by 7 days', () {
    expect(PlannerKind.week.moved(d('2026-10-07'), by: 1), d('2026-10-14'));
    expect(PlannerKind.week.moved(d('2026-10-07'), by: -1), d('2026-09-30'));
  });

  test('the month steps by one month and keeps the last day', () {
    expect(PlannerKind.month.moved(d('2026-01-31'), by: 1), d('2026-02-28'));
    expect(PlannerKind.month.moved(d('2026-01-15'), by: -1), d('2025-12-15'));
  });

  test('today does not move', () {
    expect(PlannerKind.today.moved(today, by: 1), today);
    expect(PlannerKind.today.moved(today, by: -1), today);
  });
}
