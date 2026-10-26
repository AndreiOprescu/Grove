import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/services/bedtime_planner.dart';
import 'package:grove/core/sleep/sleep_night.dart';

const today = DayKey('2026-10-05');

WallTime w(String day, int hour, [int minute = 0]) =>
    WallTime(day: DayKey(day), minute: hour * 60 + minute);

List<BedtimeReminder> plan({
  WallTime? now,
  int lead = 90,
  bool enabled = true,
  Map<DayKey, SleepNight> nights = const {},
  int? Function(DayKey)? sleepLine,
  int? Function(DayKey)? wakeLine,
  int Function(DayKey)? plannedCount,
  DateTime? nextAlarm,
}) => BedtimePlanner.plan(
  now: now ?? w('2026-10-05', 20),
  lead: lead,
  enabled: enabled,
  nights: nights,
  sleepLine: sleepLine ?? (_) => null,
  wakeLine: wakeLine ?? (_) => null,
  plannedCount: plannedCount ?? (_) => 0,
  nextAlarm: nextAlarm,
);

void main() {
  test('lead choices', () {
    expect(BedtimePlanner.leadChoices, [60, 90, 120]);
    expect(BedtimePlanner.defaultLead, 90);
  });

  test('one reminder per night from yesterday to 6 days ahead, past left '
      'out', () {
    final list = plan();
    expect(list.map((r) => r.id), [
      'bed-2026-10-05',
      'bed-2026-10-06',
      'bed-2026-10-07',
      'bed-2026-10-08',
      'bed-2026-10-09',
      'bed-2026-10-10',
      'bed-2026-10-11',
    ]);
    expect(list.first.fireAt, w('2026-10-05', 21, 30));
    expect(list.first.day, const DayKey('2026-10-06'));
    expect(list.last.fireAt, w('2026-10-11', 21, 30));
  });

  test('a reminder at now is left out', () {
    final list = plan(now: w('2026-10-05', 21, 30));
    expect(list.first.id, 'bed-2026-10-06');
  });

  test('last night still reminds after midnight, and says today', () {
    final list = plan(
      now: w('2026-10-06', 0, 10),
      lead: 60,
      sleepLine: (d) => d == today ? 90 : null,
    );
    final first = list.first;
    expect(first.id, 'bed-2026-10-05');
    expect(first.fireAt, w('2026-10-06', 0, 30));
    expect(first.day, const DayKey('2026-10-06'));
    expect('${first.title} ${first.body}', contains('oday'));
    expect('${first.title} ${first.body}', isNot(contains('omorrow')));
    expect('${list[1].title} ${list[1].body}', contains('omorrow'));
  });

  test('bedtime comes from the nights before', () {
    final nights = <DayKey, SleepNight>{};
    for (final back in [7, 14]) {
      final d = today.adding(days: -back);
      final asleep = WallTime(day: d, minute: 22 * 60);
      final woke = WallTime(day: d.adding(days: 1), minute: 6 * 60);
      nights[d] = SleepNight(
        night: d,
        asleep: asleep,
        woke: woke,
        sources: const ['android'],
        parts: {'android': NightPart(asleep: asleep, woke: woke)},
      );
    }
    final list = plan(nights: nights, now: w('2026-10-05', 12));
    expect(list.first.id, 'bed-2026-10-05');
    expect(list.first.fireAt, w('2026-10-05', 20, 30));
    expect(list[1].fireAt, w('2026-10-06', 21, 30));
  });

  test('an early alarm moves that night earlier', () {
    final list = plan(
      sleepLine: (_) => 22 * 60,
      wakeLine: (d) => d == const DayKey('2026-10-07') ? 5 * 60 : null,
      nextAlarm: DateTime(2026, 10, 7, 4),
    );
    final byId = {for (final r in list) r.id: r};
    // Usual length 22:00 → 05:00 = 7 h; alarm 04:00 → bed 21:00.
    expect(byId['bed-2026-10-06']!.fireAt, w('2026-10-06', 19, 30));
    expect(byId['bed-2026-10-05']!.fireAt, w('2026-10-05', 20, 30));
    expect(byId['bed-2026-10-07']!.fireAt, w('2026-10-07', 20, 30));
    expect(
      list.map((r) => r.fireAt).toList(),
      [for (final r in list) r.fireAt]..sort(),
    );
  });

  test('an empty tomorrow asks to plan it', () {
    for (final r in plan()) {
      expect(r.body, contains('about 1½ hours'));
      expect('${r.title} ${r.body}', isNot(contains('thing')));
      expect('${r.title} ${r.body}', contains('omorrow'));
    }
  });

  test('a planned tomorrow says how many things', () {
    final list = plan(
      plannedCount: (d) => switch (d.string) {
        '2026-10-06' => 3,
        '2026-10-07' => 1,
        _ => 0,
      },
    );
    expect(list[0].body, contains('3 things'));
    expect(list[1].body, contains('1 thing'));
    expect(list[1].body, isNot(contains('1 things')));
    expect(list[2].body, isNot(contains('thing')));
  });

  test('the lead shows as words', () {
    expect(plan(lead: 60).first.body, contains('about an hour'));
    expect(plan(lead: 120).first.body, contains('about 2 hours'));
  });

  test('off or a lead not in the choices gives nothing', () {
    expect(plan(enabled: false), isEmpty);
    expect(plan(lead: 45), isEmpty);
  });

  test('the words of a night never change on a refresh, and vary by night', () {
    final a = plan();
    final b = plan(now: w('2026-10-05', 20, 5));
    expect(a, b);
    expect(a.map((r) => r.title).toSet().length, greaterThan(1));

    final planned = plan(plannedCount: (_) => 2);
    expect(planned.map((r) => r.title).toSet().length, greaterThan(1));
  });

  test('the first variant reads as asked', () {
    final all = <String>{
      for (var i = 0; i < 40; i++)
        ...plan(
          now: WallTime(day: today.adding(days: i), minute: 0),
        ).map((r) => '${r.title}|${r.body}'),
    };
    expect(
      all,
      contains(
        'Plan tomorrow 🌙|Bedtime is in about 1½ hours. '
        'A few minutes now make the morning easier.',
      ),
    );
  });

  test('a bedtime reminder is a reminder that opens the planner', () {
    final b = plan().first;
    final r = b.reminder;
    expect(r.id, b.id);
    expect(r.title, b.title);
    expect(r.body, b.body);
    expect(r.fireAt, b.fireAt);
    expect(r.day, const DayKey('2026-10-06'));
    expect(r.ref, isNull);
  });

  test('the bedtime of a night: the usual one, made earlier by an alarm', () {
    const night = DayKey('2026-10-05');
    expect(
      BedtimePlanner.bedtime(
        night: night,
        nights: const {},
        sleepLine: null,
        wakeLine: null,
      ),
      w('2026-10-05', 23),
    );
    expect(
      BedtimePlanner.bedtime(
        night: night,
        nights: const {},
        sleepLine: null,
        wakeLine: null,
        nextAlarm: DateTime(2026, 10, 6, 6),
      ),
      w('2026-10-05', 22),
    );
  });
}
