import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/event.dart';
import 'package:grove/state/rules/deadline_rules.dart';

EventItem deadline(
  String title, {
  required String day,
  int start = 9 * 60,
  int end = 10 * 60,
  bool allDay = false,
  String? doneAt,
}) => EventItem(
  id: title,
  title: title,
  start: WallTime(day: DayKey(day), minute: start),
  end: WallTime(day: DayKey(day), minute: end),
  allDay: allDay,
  isDeadline: true,
  doneAt: doneAt,
);

void main() {
  // Saturday 18 October 2026, 12:00.
  final now = DateTime(2026, 10, 18, 12);

  group('DeadlineRules.due', () {
    test('a deadline is due at its end', () {
      final e = deadline('Essay', day: '2026-10-20', end: 17 * 60);
      expect(DeadlineRules.due(e), DateTime(2026, 10, 20, 17));
    });

    test('an all-day deadline is due at the end of its last day', () {
      final e = deadline(
        'Trip form',
        day: '2026-10-20',
        start: 0,
        end: 0,
        allDay: true,
      );
      expect(DeadlineRules.due(e), DateTime(2026, 10, 21));
    });
  });

  group('DeadlineRules.sections', () {
    test('missed, coming and done, each in its order', () {
      final list = [
        deadline('Later', day: '2026-10-25'),
        deadline('Soon', day: '2026-10-19'),
        deadline('Missed long ago', day: '2026-10-10'),
        deadline('Missed today', day: '2026-10-18', end: 11 * 60),
        deadline(
          'Done first',
          day: '2026-10-12',
          doneAt: '2026-10-11T08:00:00',
        ),
        deadline('Done last', day: '2026-10-30', doneAt: '2026-10-17T08:00:00'),
        // Due later today: still coming.
        deadline('Today', day: '2026-10-18', end: 15 * 60),
      ];
      final s = DeadlineRules.sections(list, now: now);
      expect(s.missed.map((e) => e.title), ['Missed long ago', 'Missed today']);
      expect(s.coming.map((e) => e.title), ['Today', 'Soon', 'Later']);
      expect(s.done.map((e) => e.title), ['Done last', 'Done first']);
      expect(s.isEmpty, isFalse);
    });

    test('plain events and repeating events stay out', () {
      final plain = EventItem(
        title: 'Lunch',
        start: const WallTime(day: DayKey('2026-10-19'), minute: 720),
        end: const WallTime(day: DayKey('2026-10-19'), minute: 780),
      );
      final s = DeadlineRules.sections([plain], now: now);
      expect(s.isEmpty, isTrue);
    });
  });

  group('DeadlineRules.span', () {
    test('minutes, hours and days, as on the planner', () {
      expect(DeadlineRules.span(const Duration(minutes: 40)), '40m');
      expect(DeadlineRules.span(const Duration(hours: 3)), '3h');
      expect(DeadlineRules.span(const Duration(hours: 3, minutes: 5)), '3h 5m');
      expect(DeadlineRules.span(const Duration(days: 2)), '2d');
      expect(DeadlineRules.span(const Duration(days: 2, hours: 3)), '2d 3h');
      // Minutes do not count once it is a day or more.
      expect(DeadlineRules.span(const Duration(days: 1, minutes: 50)), '1d');
    });
  });

  group('DeadlineRules.marginText', () {
    test('how early or how late it was ticked', () {
      final e = deadline('Essay', day: '2026-10-20', end: 17 * 60);
      expect(
        DeadlineRules.marginText(e.copyWith(doneAt: '2026-10-18T14:00:00')),
        'Done 2d 3h early',
      );
      expect(
        DeadlineRules.marginText(e.copyWith(doneAt: '2026-10-20T17:40:00')),
        'Done 40m late',
      );
      expect(
        DeadlineRules.marginText(e.copyWith(doneAt: '2026-10-20T17:00:30')),
        'Done just on time',
      );
    });

    test('a deadline not ticked has no margin', () {
      expect(
        DeadlineRules.marginText(deadline('Essay', day: '2026-10-20')),
        isNull,
      );
    });
  });

  group('DeadlineRules.margin', () {
    test('due minus the tick: plus is early, minus is late', () {
      final e = deadline('Essay', day: '2026-10-20', end: 17 * 60);
      expect(
        DeadlineRules.margin(e.copyWith(doneAt: '2026-10-20T16:00:00')),
        const Duration(hours: 1),
      );
      expect(
        DeadlineRules.margin(e.copyWith(doneAt: '2026-10-20T18:00:00')),
        const Duration(hours: -1),
      );
    });
  });

  group('DeadlineRules.dueText', () {
    test('the day and time, with how long is left', () {
      expect(
        DeadlineRules.dueText(
          deadline('A', day: '2026-10-18', end: 17 * 60),
          now: now,
        ),
        'Today 17:00 · in 5h',
      );
      expect(
        DeadlineRules.dueText(
          deadline('B', day: '2026-10-19', end: 9 * 60),
          now: now,
        ),
        'Tomorrow 09:00 · in 21h',
      );
      expect(
        DeadlineRules.dueText(
          deadline('C', day: '2026-10-22', end: 15 * 60),
          now: now,
        ),
        'Thu 22 Oct, 15:00 · in 4d 3h',
      );
    });

    test('an all-day deadline shows no time', () {
      expect(
        DeadlineRules.dueText(
          deadline('D', day: '2026-10-22', start: 0, end: 0, allDay: true),
          now: now,
        ),
        'Thu 22 Oct · in 4d 12h',
      );
    });

    test('a missed deadline says by how much', () {
      expect(
        DeadlineRules.dueText(
          deadline('E', day: '2026-10-18', end: 9 * 60),
          now: now,
        ),
        'Today 09:00 · missed by 3h',
      );
    });

    test('a done deadline shows the day only', () {
      expect(
        DeadlineRules.dueText(
          deadline(
            'F',
            day: '2026-10-16',
            end: 9 * 60,
            doneAt: '2026-10-15T09:00:00',
          ),
          now: now,
        ),
        'Fri 16 Oct, 09:00',
      );
    });
  });
}
