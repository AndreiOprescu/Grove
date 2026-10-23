import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/sleep/activity.dart';
import 'package:grove/core/sleep/sleep_night.dart';

const night = DayKey('2026-10-05');
const next = DayKey('2026-10-06');

/// A local time on the evening day (offset 0) or the morning after (1).
DateTime t(int dayOffset, int hour, [int minute = 0, int second = 0]) =>
    DateTime(2026, 10, 5 + dayOffset, hour, minute, second);

List<ActivityEvent> use(DateTime from, DateTime to) => [
  ActivityEvent(from, ActivitySignal.useStart),
  ActivityEvent(to, ActivitySignal.useEnd),
];

ActivityEvent recordStart(DateTime at) =>
    ActivityEvent(at, ActivitySignal.recordStart);

ActivityEvent recordStop(DateTime at) =>
    ActivityEvent(at, ActivitySignal.recordStop);

WallTime w(DayKey day, int hour, [int minute = 0]) =>
    WallTime(day: day, minute: hour * 60 + minute);

NightPart part(WallTime asleep, WallTime woke) =>
    NightPart(asleep: asleep, woke: woke);

NightPart? derive(List<ActivityEvent> events, {DateTime? now}) =>
    SleepNightRules.derivePart(events, night, now ?? t(1, 9));

void main() {
  group('derivePart', () {
    test('the gap between evening use and morning use is the night', () {
      final p = derive([
        ...use(t(0, 20), t(0, 23, 30)),
        ...use(t(1, 7), t(1, 7, 30)),
      ]);
      expect(p, part(w(night, 23, 30), w(next, 7)));
    });

    test('times are cut to the minute', () {
      final p = derive([
        ...use(t(0, 20), t(0, 23, 30, 45)),
        ...use(t(1, 7, 0, 59), t(1, 7, 30)),
      ]);
      expect(p, part(w(night, 23, 30), w(next, 7)));
    });

    test('a use shorter than 3 minutes does not split the night', () {
      final p = derive([
        ...use(t(0, 20), t(0, 23, 30)),
        ...use(t(1, 2), t(1, 2, 2, 59)),
        ...use(t(1, 7), t(1, 7, 30)),
      ]);
      expect(p, part(w(night, 23, 30), w(next, 7)));
    });

    test('a use of 3 minutes or more splits it, and the longest gap wins', () {
      final p = derive([
        ...use(t(0, 20), t(0, 23, 30)),
        ...use(t(1, 2), t(1, 2, 5)),
        ...use(t(1, 7), t(1, 7, 30)),
      ]);
      expect(p, part(w(next, 2, 5), w(next, 7)));
    });

    test('the longest of two long gaps wins', () {
      final p = derive([
        ...use(t(0, 20), t(0, 22)),
        ...use(t(1, 1, 30), t(1, 1, 40)),
        ...use(t(1, 7), t(1, 7, 30)),
      ]);
      expect(p, part(w(next, 1, 40), w(next, 7)));
    });

    test('a gap under 3 hours is not a night', () {
      final p = derive([
        ...use(t(0, 20), t(1, 2)),
        ...use(t(1, 4, 59), t(1, 5, 30)),
      ]);
      expect(p, isNull);
    });

    test('a gap of exactly 3 hours is a night', () {
      final p = derive([
        ...use(t(0, 20), t(1, 2)),
        ...use(t(1, 5), t(1, 5, 30)),
      ]);
      expect(p, part(w(next, 2), w(next, 5)));
    });

    test('a gap outside 18:00 to 06:00 is not a night', () {
      expect(
        derive([...use(t(0, 12, 30), t(0, 13)), ...use(t(0, 17), t(0, 20))]),
        isNull,
      );
      expect(
        derive([...use(t(1, 6, 30), t(1, 6, 40)), ...use(t(1, 11), t(1, 12))]),
        isNull,
      );
    });

    test('a gap that overlaps the window edge counts', () {
      final p = derive([
        ...use(t(0, 14), t(0, 15)),
        ...use(t(0, 18, 30), t(0, 19)),
      ], now: t(0, 20));
      expect(p, part(w(night, 15), w(night, 18, 30)));
    });

    test('no night until the device is used again', () {
      final events = [...use(t(0, 20), t(0, 23, 30))];
      expect(derive(events, now: t(1, 3)), isNull);
    });

    test('a use still going on counts up to now', () {
      final events = [
        ...use(t(0, 20), t(0, 23, 30)),
        ActivityEvent(t(1, 7), ActivitySignal.useStart),
      ];
      expect(
        derive(events, now: t(1, 7, 10)),
        part(w(night, 23, 30), w(next, 7)),
      );
      expect(derive(events, now: t(1, 7, 1)), isNull);
    });

    test('no use before 14:00 the next day gives no night', () {
      final events = [
        ...use(t(0, 20), t(0, 23, 30)),
        ...use(t(1, 15), t(1, 16)),
      ];
      expect(derive(events, now: t(1, 17)), isNull);
    });

    test('a first event that ends a use means in use from 12:00', () {
      final p = derive([
        ActivityEvent(t(0, 23, 30), ActivitySignal.useEnd),
        ...use(t(1, 7), t(1, 7, 30)),
      ]);
      expect(p, part(w(night, 23, 30), w(next, 7)));
    });

    test('events outside the range are left out', () {
      final p = derive([
        ...use(t(-1, 20), t(-1, 23)),
        ...use(t(0, 20), t(0, 23, 30)),
        ...use(t(1, 7), t(1, 7, 30)),
        ...use(t(1, 20), t(1, 21)),
      ], now: t(1, 22));
      expect(p, part(w(night, 23, 30), w(next, 7)));
    });

    test('events in any order are sorted first', () {
      final events = [
        ...use(t(1, 7), t(1, 7, 30)),
        ...use(t(0, 20), t(0, 23, 30)),
      ];
      expect(derive(events), part(w(night, 23, 30), w(next, 7)));
    });

    group('Mac log', () {
      test('Grove listening all night gives a night', () {
        final p = derive([
          recordStart(t(0, 9)),
          ...use(t(0, 20), t(0, 23, 30)),
          ...use(t(1, 7), t(1, 7, 30)),
        ]);
        expect(p, part(w(night, 23, 30), w(next, 7)));
      });

      test('Grove starting inside the gap gives no night', () {
        final p = derive([
          recordStart(t(0, 9)),
          ...use(t(0, 20), t(0, 23, 30)),
          recordStart(t(1, 3)),
          ...use(t(1, 7), t(1, 7, 30)),
        ]);
        expect(p, isNull);
      });

      test('Grove stopping ends the use, so the gap is unknown', () {
        final p = derive([
          recordStart(t(0, 9)),
          ActivityEvent(t(0, 20), ActivitySignal.useStart),
          recordStop(t(0, 23, 30)),
          recordStart(t(1, 7)),
          ...use(t(1, 7), t(1, 7, 30)),
        ]);
        expect(p, isNull);
      });

      test('Grove starting at the end of the gap gives no night', () {
        final p = derive([
          recordStart(t(0, 9)),
          ...use(t(0, 20), t(0, 23, 30)),
          recordStart(t(1, 7)),
          ...use(t(1, 7), t(1, 7, 30)),
        ]);
        expect(p, isNull);
      });

      test('no start before the gap gives no night', () {
        final p = derive([
          ...use(t(0, 20), t(0, 23, 30)),
          ...use(t(1, 7), t(1, 7, 30)),
          recordStop(t(1, 8)),
        ]);
        expect(p, isNull);
      });

      test('a covered shorter gap wins over an uncovered longer one', () {
        final p = derive([
          recordStart(t(0, 9)),
          ...use(t(0, 20), t(0, 21)),
          recordStop(t(0, 21)),
          recordStart(t(1, 1)),
          ...use(t(1, 1), t(1, 1, 10)),
          ...use(t(1, 4, 10), t(1, 4, 30)),
        ]);
        expect(p, part(w(next, 1, 10), w(next, 4, 10)));
      });
    });
  });

  group('combine', () {
    test('two devices give the time both were unused', () {
      final n = SleepNightRules.combine(night, {
        'mac': part(w(night, 23, 45), w(next, 6, 50)),
        'android': part(w(night, 23, 30), w(next, 7)),
      });
      expect(n!.asleep, w(night, 23, 45));
      expect(n.woke, w(next, 6, 50));
      expect(n.sources, ['android', 'mac']);
      expect(n.parts.keys.toSet(), {'android', 'mac'});
      expect(n.night, night);
    });

    test('a too short overlap falls back to the longest part', () {
      final n = SleepNightRules.combine(night, {
        'android': part(w(night, 22), w(next, 1)),
        'mac': part(w(next, 0, 30), w(next, 7)),
      });
      expect(n!.asleep, w(next, 0, 30));
      expect(n.woke, w(next, 7));
      expect(n.sources, ['mac']);
      expect(n.parts.length, 2);
    });

    test('parts that do not meet fall back too', () {
      final n = SleepNightRules.combine(night, {
        'android': part(w(night, 22), w(next, 1, 30)),
        'mac': part(w(next, 2), w(next, 7)),
      });
      expect(n!.sources, ['mac']);
    });

    test('a start outside 18:00 to 06:00 is not a night', () {
      expect(
        SleepNightRules.combine(night, {
          'android': part(w(night, 17), w(next, 7)),
        }),
        isNull,
      );
      expect(
        SleepNightRules.combine(night, {
          'android': part(w(next, 6, 30), w(next, 11)),
        }),
        isNull,
      );
      expect(
        SleepNightRules.combine(night, {
          'android': part(w(night, 18), w(night, 23)),
        }),
        isNotNull,
      );
    });

    test('no parts give nothing', () {
      expect(SleepNightRules.combine(night, {}), isNull);
    });
  });

  group('codec', () {
    test('key, prefix and day', () {
      expect(SleepNightRules.key(night), 'sleep.night.2026-10-05');
      expect(SleepNightRules.prefix, 'sleep.night.');
      expect(SleepNightRules.prefixEnd, 'sleep.night/');
      expect(SleepNightRules.dayOf('sleep.night.2026-10-05'), night);
      expect(SleepNightRules.dayOf('sleep.night.2026-02-30'), isNull);
      expect(SleepNightRules.dayOf('planner.wake.2026-10-05'), isNull);
    });

    test('encode is fixed and decode reads it back', () {
      final n = SleepNightRules.combine(night, {
        'mac': part(w(night, 23, 45), w(next, 6, 50)),
        'android': part(w(night, 23, 30), w(next, 7)),
      })!;
      final json = SleepNightRules.encode(n);
      expect(
        json,
        '{"v":1,"asleep":"2026-10-05T23:45","woke":"2026-10-06T06:50",'
        '"source":"android+mac","parts":{'
        '"android":{"a":"2026-10-05T23:30","w":"2026-10-06T07:00"},'
        '"mac":{"a":"2026-10-05T23:45","w":"2026-10-06T06:50"}}}',
      );
      final back = SleepNightRules.decode(night, json)!;
      expect(back, n);
      expect(SleepNightRules.encode(back), json);
    });

    test('bad text decodes to null', () {
      expect(SleepNightRules.decode(night, 'not json'), isNull);
      expect(SleepNightRules.decode(night, '[1,2]'), isNull);
      expect(SleepNightRules.decode(night, '{"v":1,"asleep":"x"}'), isNull);
      expect(
        SleepNightRules.decode(
          night,
          '{"v":2,"asleep":"2026-10-05T23:45","woke":"2026-10-06T06:50",'
          '"source":"mac","parts":{}}',
        ),
        isNull,
      );
    });

    test('parse reads a settings row', () {
      final n = SleepNightRules.combine(night, {
        'android': part(w(night, 23, 30), w(next, 7)),
      })!;
      final row = SleepNightRules.encode(n);
      expect(SleepNightRules.parse(SleepNightRules.key(night), row), n);
      expect(SleepNightRules.parse('planner.wake.2026-10-05', row), isNull);
    });
  });

  group('merge', () {
    final android = part(w(night, 23, 30), w(next, 7));
    final mac = part(w(night, 23, 45), w(next, 6, 50));

    test('a first part makes a row', () {
      final json = SleepNightRules.merge(null, night, 'android', android)!;
      final n = SleepNightRules.decode(night, json)!;
      expect(n.sources, ['android']);
      expect(n.asleep, w(night, 23, 30));
    });

    test('a part replaces only its own part', () {
      final first = SleepNightRules.merge(null, night, 'android', android)!;
      final second = SleepNightRules.merge(first, night, 'mac', mac)!;
      final n = SleepNightRules.decode(night, second)!;
      expect(n.parts['android'], android);
      expect(n.parts['mac'], mac);
      expect(n.sources, ['android', 'mac']);

      final newer = part(w(night, 23, 50), w(next, 6, 40));
      final third = SleepNightRules.merge(second, night, 'mac', newer)!;
      final m = SleepNightRules.decode(night, third)!;
      expect(m.parts['android'], android);
      expect(m.parts['mac'], newer);
    });

    test('the same input again changes nothing', () {
      final first = SleepNightRules.merge(null, night, 'android', android)!;
      expect(SleepNightRules.merge(first, night, 'android', android), isNull);
    });

    test('a null part keeps the old one', () {
      final first = SleepNightRules.merge(null, night, 'android', android)!;
      expect(SleepNightRules.merge(first, night, 'mac', null), isNull);
    });

    test('bad stored text is replaced', () {
      final json = SleepNightRules.merge('{oops', night, 'android', android)!;
      expect(SleepNightRules.decode(night, json)!.sources, ['android']);
    });

    test('an unknown part name is kept', () {
      const stored =
          '{"v":1,"asleep":"2026-10-05T23:40","woke":"2026-10-06T06:55",'
          '"source":"watch","parts":{'
          '"watch":{"a":"2026-10-05T23:40","w":"2026-10-06T06:55"}}}';
      final json = SleepNightRules.merge(stored, night, 'android', android)!;
      final n = SleepNightRules.decode(night, json)!;
      expect(n.parts.keys.toSet(), {'android', 'watch'});
      expect(n.sources, ['android', 'watch']);
      expect(n.asleep, w(night, 23, 40));
      expect(n.woke, w(next, 6, 55));
    });

    test('nothing to store gives null', () {
      expect(SleepNightRules.merge(null, night, 'android', null), isNull);
      final early = part(w(night, 15), w(night, 19));
      expect(SleepNightRules.merge(null, night, 'android', early), isNull);
    });
  });
}
