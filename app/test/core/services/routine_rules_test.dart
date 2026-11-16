import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/routine.dart';
import 'package:grove/core/services/routine_rules.dart';

DayKey d(String s) => DayKey(s);

void main() {
  group('RoutineRule', () {
    test('json goes there and back', () {
      final r = RoutineRule(every: 2, unit: RoutineUnit.weeks);
      expect(r.json(), '{"every":2,"unit":"weeks"}');
      expect(RoutineRule.fromJson(r.json()), r);
    });

    test('bad json reads as null', () {
      for (final s in [
        null,
        '',
        'x',
        '[]',
        '{"every":0,"unit":"days"}',
        '{"every":"2","unit":"days"}',
        '{"every":2,"unit":"years"}',
      ]) {
        expect(RoutineRule.fromJson(s), isNull, reason: '$s');
      }
    });

    test('the step is at least 1', () {
      expect(RoutineRule(every: 0).every, 1);
      expect(RoutineRule(every: -3).every, 1);
    });
  });

  group('dueDay', () {
    test('days and weeks add days', () {
      expect(
        RoutineRules.dueDay(
          d('2026-11-10'),
          RoutineRule(every: 3, unit: RoutineUnit.days),
        ),
        d('2026-11-13'),
      );
      expect(
        RoutineRules.dueDay(
          d('2026-11-10'),
          RoutineRule(every: 2, unit: RoutineUnit.weeks),
        ),
        d('2026-11-24'),
      );
    });

    test('months are calendar months, the day clamped to the month', () {
      final monthly = RoutineRule(every: 1, unit: RoutineUnit.months);
      expect(RoutineRules.dueDay(d('2026-11-12'), monthly), d('2026-12-12'));
      expect(RoutineRules.dueDay(d('2026-01-31'), monthly), d('2026-02-28'));
      expect(
        RoutineRules.dueDay(
          d('2026-11-30'),
          RoutineRule(every: 3, unit: RoutineUnit.months),
        ),
        d('2027-02-28'),
      );
    });
  });

  group('lastDone', () {
    test('the latest done day, or the start day with none', () {
      expect(RoutineRules.lastDone(d('2026-11-01'), const []), d('2026-11-01'));
      expect(
        RoutineRules.lastDone(d('2026-11-01'), [
          d('2026-11-05'),
          d('2026-11-03'),
        ]),
        d('2026-11-05'),
      );
    });

    test(
      'a start after the history wins: a routine turned on again starts fresh',
      () {
        expect(
          RoutineRules.lastDone(d('2026-11-10'), [d('2026-10-01')]),
          d('2026-11-10'),
        );
      },
    );
  });

  group('status', () {
    final weekly = RoutineRule(every: 1, unit: RoutineUnit.weeks);

    test('the bar fills as time runs out', () {
      final s = RoutineRules.status(weekly, d('2026-11-10'), d('2026-11-10'));
      expect(s.fraction, 0);
      expect(s.label, '7 days left');
      expect(s.late, isFalse);
      expect(s.due, d('2026-11-17'));

      final mid = RoutineRules.status(weekly, d('2026-11-10'), d('2026-11-14'));
      expect(mid.fraction, closeTo(4 / 7, 1e-9));
      expect(mid.label, '3 days left');

      final one = RoutineRules.status(weekly, d('2026-11-10'), d('2026-11-16'));
      expect(one.label, '1 day left');
    });

    test('full on the due day', () {
      final s = RoutineRules.status(weekly, d('2026-11-10'), d('2026-11-17'));
      expect(s.fraction, 1);
      expect(s.label, 'Due today');
      expect(s.late, isFalse);
      expect(s.daysLeft, 0);
    });

    test('after the due day it stays full and says how late', () {
      final s = RoutineRules.status(weekly, d('2026-11-10'), d('2026-11-18'));
      expect(s.fraction, 1);
      expect(s.label, 'Late 1 day');
      expect(s.late, isTrue);
      final s3 = RoutineRules.status(weekly, d('2026-11-10'), d('2026-11-20'));
      expect(s3.label, 'Late 3 days');
      expect(s3.daysLeft, -3);
    });
  });

  test('order: late first, then the least time left, then the title', () {
    final rows = [
      (title: 'b', daysLeft: 3),
      (title: 'a', daysLeft: 3),
      (title: 'late', daysLeft: -2),
      (title: 'today', daysLeft: 0),
    ];
    rows.sort(
      (x, y) => RoutineRules.compare(x.daysLeft, x.title, y.daysLeft, y.title),
    );
    expect(rows.map((r) => r.title), ['late', 'today', 'a', 'b']);
  });

  test('the history line', () {
    expect(RoutineRules.historyLabel(const []), 'Not done yet');
    expect(
      RoutineRules.historyLabel([d('2026-11-12')]),
      'Done once, last on 12 Nov',
    );
    expect(
      RoutineRules.historyLabel([
        d('2026-10-01'),
        d('2026-11-12'),
        d('2026-11-01'),
      ]),
      'Done 3 times, last on 12 Nov',
    );
  });

  test('the step label', () {
    expect(
      RoutineRules.stepLabel(RoutineRule(every: 1, unit: RoutineUnit.days)),
      'Every day',
    );
    expect(
      RoutineRules.stepLabel(RoutineRule(every: 2, unit: RoutineUnit.weeks)),
      'Every 2 weeks',
    );
    expect(
      RoutineRules.stepLabel(RoutineRule(every: 1, unit: RoutineUnit.months)),
      'Every month',
    );
  });
}
