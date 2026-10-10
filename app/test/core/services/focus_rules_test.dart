// Port of Tests/GroveCoreTests/FocusRulesTests.swift.
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/event.dart';
import 'package:grove/core/services/focus_rules.dart';

void main() {
  final t0 = DateTime.fromMillisecondsSinceEpoch(1800000000 * 1000);
  DateTime plus(double seconds) =>
      t0.add(Duration(microseconds: (seconds * 1e6).round()));

  test('remaining counts whole seconds and rounds up', () {
    expect(FocusRules.remaining(until: plus(90), now: t0), 90);
    expect(FocusRules.remaining(until: plus(89.2), now: t0), 90);
    expect(FocusRules.remaining(until: plus(0.1), now: t0), 1);
  });

  test('remaining never goes below zero', () {
    expect(FocusRules.remaining(until: t0, now: t0), 0);
    expect(FocusRules.remaining(until: plus(-30), now: t0), 0);
  });

  test('clock shows minutes and seconds', () {
    expect(FocusRules.clock(0), '0:00');
    expect(FocusRules.clock(7), '0:07');
    expect(FocusRules.clock(1447), '24:07');
    expect(FocusRules.clock(3599), '59:59');
  });

  test('clock shows hours from one hour', () {
    expect(FocusRules.clock(3600), '1:00:00');
    expect(FocusRules.clock(3725), '1:02:05');
    expect(FocusRules.clock(-5), '0:00');
  });

  test('progress goes from zero to one', () {
    final end = plus(600);
    double p(DateTime now) =>
        FocusRules.progress(start: t0, end: end, now: now);
    expect(p(t0), 0);
    expect(p(plus(150)), 0.25);
    expect(p(end), 1);
    expect(p(plus(699)), 1);
    expect(p(plus(-5)), 0);
  });

  test('progress of an empty span is one', () {
    expect(FocusRules.progress(start: t0, end: t0, now: t0), 1);
  });

  test('the end of a block is its wall clock time', () {
    final end = FocusRules.endDate(
      const WallTime(day: DayKey('2026-10-05'), minute: 13 * 60 + 30),
    );
    expect([end.year, end.month, end.day], [2026, 10, 5]);
    expect([end.hour, end.minute], [13, 30]);
  });

  test('a block can be focused only before it ends', () {
    const day = DayKey('2026-10-05');
    final block = EventItem(
      title: 'Write',
      start: const WallTime(day: day, minute: 600),
      end: const WallTime(day: day, minute: 660),
      kind: EventKind.block,
    );
    final inside = FocusRules.endDate(const WallTime(day: day, minute: 630));
    final after = FocusRules.endDate(const WallTime(day: day, minute: 661));
    expect(FocusRules.canStart(block, now: inside), isTrue);
    expect(FocusRules.canStart(block, now: after), isFalse);
    // The very end is too late.
    expect(
      FocusRules.canStart(block, now: FocusRules.endDate(block.end)),
      isFalse,
    );
  });
}
