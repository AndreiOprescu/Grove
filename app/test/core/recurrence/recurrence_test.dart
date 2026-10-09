// Port of RecurrenceTests.swift (RecurrenceTests, OccurrenceTests) and
// RecurrenceEngineTests.swift.
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/event.dart';
import 'package:grove/core/model/recurrence.dart';
import 'package:grove/core/recurrence/recurrence_engine.dart';

List<String> dates(
  RecurrenceRule rule, {
  required String from,
  required String lo,
  required String hi,
  List<String> except = const [],
}) => RecurrenceEngine.occurrences(
  rule: rule,
  seriesStart: DayKey(from),
  from: DayKey(lo),
  to: DayKey(hi),
  exdates: except.map(DayKey.new).toSet(),
).map((d) => d.string).toList();

String? next(String from, RecurrenceRule rule) =>
    RecurrenceEngine.next(after: DayKey(from), rule: rule)?.string;

RecurrenceRule rule(
  Freq freq, {
  int interval = 1,
  List<int>? weekdays,
  String? until,
  int? count,
}) => RecurrenceRule(
  freq: freq,
  interval: interval,
  weekdays: weekdays,
  until: until == null ? null : DayKey(until),
  count: count,
);

void main() {
  // 2026-10-02 is a Friday. 2026-10-05 is a Monday.
  group('occurrences', () {
    test('daily inside a range', () {
      expect(
        dates(
          rule(Freq.daily),
          from: '2026-10-02',
          lo: '2026-10-04',
          hi: '2026-10-07',
        ),
        ['2026-10-04', '2026-10-05', '2026-10-06', '2026-10-07'],
      );
    });

    test('nothing before the start', () {
      expect(
        dates(
          rule(Freq.daily),
          from: '2026-10-02',
          lo: '2026-09-28',
          hi: '2026-10-03',
        ),
        ['2026-10-02', '2026-10-03'],
      );
      expect(
        dates(
          rule(Freq.daily),
          from: '2026-10-02',
          lo: '2026-09-01',
          hi: '2026-09-30',
        ),
        isEmpty,
      );
    });

    test('daily with an interval', () {
      // Every 3 days from the 2nd: 2, 5, 8, 11. A range in the middle keeps the rhythm.
      expect(
        dates(
          rule(Freq.daily, interval: 3),
          from: '2026-10-02',
          lo: '2026-10-06',
          hi: '2026-10-12',
        ),
        ['2026-10-08', '2026-10-11'],
      );
    });

    test('weekly keeps the start weekday', () {
      expect(
        dates(
          rule(Freq.weekly),
          from: '2026-10-02',
          lo: '2026-10-01',
          hi: '2026-10-31',
        ),
        ['2026-10-02', '2026-10-09', '2026-10-16', '2026-10-23', '2026-10-30'],
      );
    });

    test('weekly on chosen weekdays', () {
      // Mon, Wed, Fri. The start (Friday the 2nd) is the first one.
      expect(
        dates(
          rule(Freq.weekly, weekdays: [5, 1, 3]),
          from: '2026-10-02',
          lo: '2026-10-01',
          hi: '2026-10-14',
        ),
        [
          '2026-10-02',
          '2026-10-05',
          '2026-10-07',
          '2026-10-09',
          '2026-10-12',
          '2026-10-14',
        ],
      );
    });

    test('weekly does not start before the start day', () {
      expect(
        dates(
          rule(Freq.weekly, weekdays: [1, 3]),
          from: '2026-10-07',
          lo: '2026-10-05',
          hi: '2026-10-12',
        ),
        ['2026-10-07', '2026-10-12'],
      );
    });

    test('every other week', () {
      final r = rule(Freq.weekly, interval: 2, weekdays: [1]);
      expect(dates(r, from: '2026-10-05', lo: '2026-10-01', hi: '2026-11-10'), [
        '2026-10-05',
        '2026-10-19',
        '2026-11-02',
      ]);
      // Starting the range later gives the same dates.
      expect(dates(r, from: '2026-10-05', lo: '2026-10-20', hi: '2026-11-10'), [
        '2026-11-02',
      ]);
    });

    test('monthly on the 31st skips short months', () {
      expect(
        dates(
          rule(Freq.monthly),
          from: '2026-01-31',
          lo: '2026-01-01',
          hi: '2026-07-31',
        ),
        ['2026-01-31', '2026-03-31', '2026-05-31', '2026-07-31'],
      );
    });

    test('monthly keeps the day', () {
      expect(
        dates(
          rule(Freq.monthly),
          from: '2026-10-15',
          lo: '2026-10-01',
          hi: '2027-01-31',
        ),
        ['2026-10-15', '2026-11-15', '2026-12-15', '2027-01-15'],
      );
      expect(
        dates(
          rule(Freq.monthly, interval: 3),
          from: '2026-10-15',
          lo: '2026-10-01',
          hi: '2027-10-31',
        ),
        ['2026-10-15', '2027-01-15', '2027-04-15', '2027-07-15', '2027-10-15'],
      );
    });

    test('yearly', () {
      expect(
        dates(
          rule(Freq.yearly),
          from: '2026-10-02',
          lo: '2026-01-01',
          hi: '2029-12-31',
        ),
        ['2026-10-02', '2027-10-02', '2028-10-02', '2029-10-02'],
      );
    });

    test('yearly on February 29 only in leap years', () {
      expect(
        dates(
          rule(Freq.yearly),
          from: '2024-02-29',
          lo: '2024-01-01',
          hi: '2033-12-31',
        ),
        ['2024-02-29', '2028-02-29', '2032-02-29'],
      );
    });

    test('until includes the last day', () {
      expect(
        dates(
          rule(Freq.daily, until: '2026-10-04'),
          from: '2026-10-02',
          lo: '2026-10-01',
          hi: '2026-10-31',
        ),
        ['2026-10-02', '2026-10-03', '2026-10-04'],
      );
    });

    test('count stops the series', () {
      final r = rule(Freq.weekly, count: 3);
      expect(dates(r, from: '2026-10-02', lo: '2026-10-01', hi: '2026-12-31'), [
        '2026-10-02',
        '2026-10-09',
        '2026-10-16',
      ]);
      // A range after the last one is empty. A range in the middle counts from the start.
      expect(
        dates(r, from: '2026-10-02', lo: '2026-10-17', hi: '2026-12-31'),
        isEmpty,
      );
      expect(dates(r, from: '2026-10-02', lo: '2026-10-09', hi: '2026-12-31'), [
        '2026-10-09',
        '2026-10-16',
      ]);
    });

    test('count with chosen weekdays', () {
      expect(
        dates(
          rule(Freq.weekly, weekdays: [1, 3], count: 3),
          from: '2026-10-05',
          lo: '2026-10-01',
          hi: '2026-12-31',
        ),
        ['2026-10-05', '2026-10-07', '2026-10-12'],
      );
    });

    test('counted dates that are removed still count', () {
      expect(
        dates(
          rule(Freq.daily, count: 3),
          from: '2026-10-02',
          lo: '2026-10-01',
          hi: '2026-10-31',
          except: ['2026-10-03'],
        ),
        ['2026-10-02', '2026-10-04'],
      );
    });

    test('removed dates are left out', () {
      expect(
        dates(
          rule(Freq.weekly),
          from: '2026-10-02',
          lo: '2026-10-01',
          hi: '2026-10-31',
          except: ['2026-10-09', '2026-10-23'],
        ),
        ['2026-10-02', '2026-10-16', '2026-10-30'],
      );
    });

    test('a range far from the start is fast', () {
      // Ten years of a daily series. Must not walk every day.
      final watch = Stopwatch()..start();
      expect(
        dates(
          rule(Freq.daily),
          from: '2016-01-01',
          lo: '2026-10-02',
          hi: '2026-10-02',
        ),
        ['2026-10-02'],
      );
      expect(watch.elapsedMilliseconds, lessThan(500));
    });

    test('a range that ends before the start is empty', () {
      expect(
        dates(
          rule(Freq.daily),
          from: '2026-10-02',
          lo: '2026-09-01',
          hi: '2026-09-05',
        ),
        isEmpty,
      );
    });
  });

  group('occurrence ids and events', () {
    EventItem series(RecurrenceRule r, {int from = 540, int to = 600}) =>
        EventItem(
          id: 'S1',
          title: 'Standup',
          start: WallTime(day: const DayKey('2026-10-05'), minute: from),
          end: WallTime(day: const DayKey('2026-10-05'), minute: to),
          color: 'accent3',
          location: 'Room 4',
          recurrence: r,
        );

    test('id round trips', () {
      final id = OccurrenceId.make(
        series: 'S1',
        day: const DayKey('2026-10-12'),
      );
      expect(id, 'S1@2026-10-12');
      final parsed = OccurrenceId.parse(id);
      expect(parsed?.series, 'S1');
      expect(parsed?.day, const DayKey('2026-10-12'));
    });

    test('plain ids are not occurrences', () {
      expect(
        OccurrenceId.parse('2D6F1B1C-0000-4000-8000-000000000000'),
        isNull,
      );
      expect(OccurrenceId.parse('S1@not-a-date'), isNull);
    });

    test('expand copies the series onto each day', () {
      final items = RecurrenceEngine.expand(
        series(rule(Freq.weekly)),
        exdates: const {},
        from: const DayKey('2026-10-01'),
        to: const DayKey('2026-10-31'),
      );
      expect(items.map((e) => e.start.day.string).toList(), [
        '2026-10-05',
        '2026-10-12',
        '2026-10-19',
        '2026-10-26',
      ]);
      expect(items.map((e) => e.id).toList(), [
        'S1@2026-10-05',
        'S1@2026-10-12',
        'S1@2026-10-19',
        'S1@2026-10-26',
      ]);
      final second = items[1];
      expect(second.title, 'Standup');
      expect(second.start.minute, 540);
      expect(second.end.minute, 600);
      expect(second.end.day, second.start.day);
      expect(second.seriesId, 'S1');
      expect(second.originalDate, const DayKey('2026-10-12'));
      expect(second.recurrence, isNull);
      expect(second.color, 'accent3');
      expect(second.location, 'Room 4');
    });

    test('expand skips removed days', () {
      final items = RecurrenceEngine.expand(
        series(rule(Freq.daily)),
        exdates: {const DayKey('2026-10-06')},
        from: const DayKey('2026-10-05'),
        to: const DayKey('2026-10-07'),
      );
      expect(items.map((e) => e.start.day.string).toList(), [
        '2026-10-05',
        '2026-10-07',
      ]);
    });

    EventItem monToWed() => series(rule(Freq.weekly), from: 0, to: 0).copyWith(
      allDay: true,
      end: const WallTime(day: DayKey('2026-10-07'), minute: 0),
    );

    test('a multi-day event keeps its length', () {
      final items = RecurrenceEngine.expand(
        monToWed(),
        exdates: const {},
        from: const DayKey('2026-10-12'),
        to: const DayKey('2026-10-12'),
      );
      expect(items.length, 1);
      expect(items[0].end.day, const DayKey('2026-10-14'));
    });

    test('an event that started before the range still shows', () {
      // Range is Tue–Wed. The occurrence that began Monday the 12th covers it.
      final items = RecurrenceEngine.expand(
        monToWed(),
        exdates: const {},
        from: const DayKey('2026-10-13'),
        to: const DayKey('2026-10-14'),
      );
      expect(items.map((e) => e.start.day.string).toList(), ['2026-10-12']);
    });

    test('one occurrence on a day', () {
      final o = RecurrenceEngine.occurrence(
        of: series(rule(Freq.weekly)),
        on: const DayKey('2026-10-19'),
      );
      expect(o.id, 'S1@2026-10-19');
      expect(o.start, const WallTime(day: DayKey('2026-10-19'), minute: 540));
      expect(o.end, const WallTime(day: DayKey('2026-10-19'), minute: 600));
    });
  });

  group('next', () {
    test('daily', () {
      expect(next('2026-10-02', rule(Freq.daily)), '2026-10-03');
      expect(next('2026-10-02', rule(Freq.daily, interval: 3)), '2026-10-05');
      expect(next('2026-12-31', rule(Freq.daily)), '2027-01-01');
    });

    test('weekly without weekdays keeps the same weekday', () {
      expect(next('2026-10-02', rule(Freq.weekly)), '2026-10-09');
      expect(next('2026-10-02', rule(Freq.weekly, interval: 2)), '2026-10-16');
    });

    test('weekly on one weekday', () {
      final monday = rule(Freq.weekly, weekdays: [1]);
      expect(next('2026-10-02', monday), '2026-10-05'); // from a Friday
      expect(next('2026-10-05', monday), '2026-10-12'); // from a Monday
    });

    test('every weekday', () {
      final weekdays = rule(Freq.weekly, weekdays: [1, 2, 3, 4, 5]);
      expect(next('2026-10-02', weekdays), '2026-10-05'); // Friday → Monday
      expect(next('2026-10-05', weekdays), '2026-10-06'); // Monday → Tuesday
      expect(next('2026-10-03', weekdays), '2026-10-05'); // Saturday → Monday
    });

    test('several weekdays', () {
      final mwf = rule(
        Freq.weekly,
        weekdays: [5, 1, 3],
      ); // order does not matter
      expect(next('2026-10-05', mwf), '2026-10-07');
      expect(next('2026-10-07', mwf), '2026-10-09');
      expect(next('2026-10-09', mwf), '2026-10-12');
    });

    test('every other week on Monday', () {
      final r = rule(Freq.weekly, interval: 2, weekdays: [1]);
      expect(next('2026-10-05', r), '2026-10-19');
      expect(next('2026-10-02', r), '2026-10-12');
    });

    test('monthly keeps the day and clamps short months', () {
      expect(next('2026-10-02', rule(Freq.monthly)), '2026-11-02');
      expect(next('2026-10-02', rule(Freq.monthly, interval: 2)), '2026-12-02');
      expect(next('2026-12-15', rule(Freq.monthly)), '2027-01-15');
      expect(next('2026-01-31', rule(Freq.monthly)), '2026-02-28');
    });

    test('yearly', () {
      expect(next('2026-10-02', rule(Freq.yearly)), '2027-10-02');
      expect(next('2028-02-29', rule(Freq.yearly)), '2029-02-28');
    });

    test('until stops the series', () {
      final r = rule(Freq.daily, until: '2026-10-03');
      expect(next('2026-10-02', r), '2026-10-03');
      expect(next('2026-10-03', r), isNull);
    });
  });
}
