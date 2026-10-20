// Port of Tests/GroveTests/CalendarRulesTests.swift.
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

EventItem event(WallTime start, WallTime end, {bool allDay = false}) =>
    EventItem(title: 'E', start: start, end: end, allDay: allDay);

WallTime at(String day, int minute) =>
    WallTime(day: DayKey(day), minute: minute);

void main() {
  group('month grid', () {
    test('starts on the Monday of the first week', () {
      final grid = CalendarRules.monthGrid(d('2026-10-15'));
      expect(grid.length, 42);
      expect(grid.first, d('2026-09-28')); // 1 Oct 2026 is a Thursday
      expect(grid.last, d('2026-11-08'));
    });

    test('when the first is a Monday', () {
      final grid = CalendarRules.monthGrid(d('2027-02-10'));
      expect(grid.first, d('2027-02-01'));
      expect(grid.last, d('2027-03-14'));
    });

    test('when the first is a Sunday', () {
      // 1 Feb 2026 is a Sunday.
      final grid = CalendarRules.monthGrid(d('2026-02-20'));
      expect(grid.first, d('2026-01-26'));
    });

    test('moving by months keeps the day when it can', () {
      expect(CalendarRules.addMonths(d('2026-10-15'), 1), d('2026-11-15'));
      expect(CalendarRules.addMonths(d('2026-10-15'), -10), d('2025-12-15'));
      expect(CalendarRules.addMonths(d('2026-01-31'), 1), d('2026-02-28'));
      expect(CalendarRules.addMonths(d('2026-03-31'), -1), d('2026-02-28'));
    });
  });

  group('pills', () {
    test('pill slots grow with the cell', () {
      expect(CalendarRules.pillSlots(cellHeight: 130), 3);
      expect(CalendarRules.pillSlots(cellHeight: 97), 3);
      expect(CalendarRules.pillSlots(cellHeight: 82), 2);
      expect(CalendarRules.pillSlots(cellHeight: 20), 1);
    });

    test('extra events become +N', () {
      final list = [
        for (var i = 1; i <= 5; i++)
          EventItem(
            title: 'E$i',
            start: at('2026-10-05', 600),
            end: at('2026-10-05', 660),
          ),
      ];
      final r = CalendarRules.pills(list, slots: 3);
      expect(eventTitles(r.shown), ['E1', 'E2', 'E3']);
      expect(r.hidden, 2);
      final few = CalendarRules.pills(list.sublist(0, 2), slots: 3);
      expect(few.shown.length, 2);
      expect(few.hidden, 0);
    });

    test('all-day events come first, then by start', () {
      final late = event(at('2026-10-05', 900), at('2026-10-05', 960));
      final early = event(at('2026-10-05', 540), at('2026-10-05', 600));
      final allDay = event(
        at('2026-10-05', 0),
        at('2026-10-05', 0),
        allDay: true,
      );
      expect(
        [
          for (final e in CalendarRules.sorted([late, allDay, early]))
            e.start.minute,
        ],
        [0, 540, 900],
      );
    });

    test('strip dots stop at three', () {
      expect(
        [
          for (final n in [0, 1, 2, 3, 4, 9]) CalendarRules.dots(n),
        ],
        [0, 1, 2, 3, 3, 3],
      );
    });
  });

  group('which days an event covers', () {
    test('an all-day event covers every day it names', () {
      final e = event(at('2026-10-05', 0), at('2026-10-07', 0), allDay: true);
      expect(
        [
          for (final day in [
            '2026-10-04',
            '2026-10-05',
            '2026-10-06',
            '2026-10-07',
            '2026-10-08',
          ])
            CalendarRules.covers(e, d(day)),
        ],
        [false, true, true, true, false],
      );
    });

    test('a timed event that ends at midnight stays on its day', () {
      final e = event(at('2026-10-05', 22 * 60), at('2026-10-06', 0));
      expect(CalendarRules.covers(e, d('2026-10-05')), isTrue);
      expect(CalendarRules.covers(e, d('2026-10-06')), isFalse);
    });

    test('a timed event that runs past midnight covers both days', () {
      final e = event(at('2026-10-05', 22 * 60), at('2026-10-06', 120));
      expect(CalendarRules.covers(e, d('2026-10-05')), isTrue);
      expect(CalendarRules.covers(e, d('2026-10-06')), isTrue);
    });
  });

  group("the editor's draft", () {
    test('turning all-day on drops the clock times', () {
      final e = EventDraft.setAllDay(
        event(at('2026-10-05', 540), at('2026-10-05', 630)),
        true,
      );
      expect(e.allDay, isTrue);
      expect(e.start, at('2026-10-05', 0));
      expect(e.end, at('2026-10-05', 0));
    });

    test('turning all-day off gives an hour from nine on the first day', () {
      final e = EventDraft.setAllDay(
        event(at('2026-10-05', 0), at('2026-10-07', 0), allDay: true),
        false,
      );
      expect(e.allDay, isFalse);
      expect(e.start, at('2026-10-05', 540));
      expect(e.end, at('2026-10-05', 600));
    });

    test('moving the start keeps the length', () {
      var e = event(at('2026-10-05', 540), at('2026-10-05', 630));
      e = EventDraft.setStart(e, at('2026-10-05', 14 * 60));
      expect(e.start, at('2026-10-05', 840));
      expect(e.end, at('2026-10-05', 930));
      e = EventDraft.setStart(e, at('2026-10-06', 480));
      expect(e.start, at('2026-10-06', 480));
      expect(e.end, at('2026-10-06', 570));
    });

    test('moving the start can push the end past midnight', () {
      final e = EventDraft.setStart(
        event(at('2026-10-05', 23 * 60), at('2026-10-05', 23 * 60 + 30)),
        at('2026-10-05', 23 * 60 + 45),
      );
      expect(e.end, at('2026-10-06', 15));
    });

    test('moving the start of an all-day event keeps its days', () {
      final e = EventDraft.setStart(
        event(at('2026-10-05', 0), at('2026-10-07', 0), allDay: true),
        at('2026-10-08', 0),
      );
      expect(e.start, at('2026-10-08', 0));
      expect(e.end, at('2026-10-10', 0));
    });

    test('an end before the start is fixed', () {
      final e = EventDraft.normalize(
        event(at('2026-10-05', 600), at('2026-10-05', 540)),
      );
      expect(e.end, at('2026-10-05', 630)); // 30 minutes after the start
      final late = EventDraft.normalize(
        event(at('2026-10-05', 1430), at('2026-10-05', 1400)),
      );
      expect(late.end, at('2026-10-05', 1440));
      final allDay = EventDraft.normalize(
        event(at('2026-10-07', 0), at('2026-10-05', 0), allDay: true),
      );
      expect(allDay.end, at('2026-10-07', 0));
    });

    test('a good event is left alone', () {
      final before = event(at('2026-10-05', 540), at('2026-10-05', 600));
      expect(EventDraft.normalize(before), before);
    });

    test('wall time and date round trip', () {
      for (final w in [
        at('2026-10-05', 0),
        at('2026-10-05', 541),
        at('2026-12-31', 1439),
        at('2026-07-15', 150),
      ]) {
        expect(EventDraft.wallTime(EventDraft.date(w)), w);
      }
    });

    test('ends choices', () {
      expect(
        EventDraft.ends(RecurrenceRule(freq: Freq.daily)),
        RepeatEnds.never,
      );
      expect(
        EventDraft.ends(
          RecurrenceRule(freq: Freq.daily, until: d('2026-12-01')),
        ),
        RepeatEnds.on,
      );
      expect(
        EventDraft.ends(RecurrenceRule(freq: Freq.daily, count: 5)),
        RepeatEnds.after,
      );
    });
  });

  group('the repeat rule in words', () {
    test('repeat labels', () {
      String label(Freq freq, {int interval = 1, List<int>? weekdays}) =>
          EventDraft.repeatLabel(
            RecurrenceRule(freq: freq, interval: interval, weekdays: weekdays),
          );
      expect(label(Freq.daily), 'Every day');
      expect(label(Freq.daily, interval: 3), 'Every 3 days');
      expect(label(Freq.weekly), 'Every week');
      expect(label(Freq.weekly, interval: 2), 'Every 2 weeks');
      expect(
        label(Freq.weekly, weekdays: [5, 1, 3]),
        'Every week on Mon, Wed, Fri',
      );
      expect(label(Freq.weekly, weekdays: [1, 2, 3, 4, 5]), 'Every weekday');
      expect(label(Freq.monthly), 'Every month');
      expect(label(Freq.yearly, interval: 2), 'Every 2 years');
    });

    test('toggling weekdays', () {
      final weekly = RecurrenceRule(freq: Freq.weekly);
      // The start day is Friday (5). Add Monday.
      final withMonday = EventDraft.toggleWeekday(weekly, 1, start: 5);
      expect(withMonday.weekdays, [1, 5]);
      // Take Friday off again: only Monday is left.
      expect(EventDraft.toggleWeekday(withMonday, 5, start: 5).weekdays, [1]);
      // The last chosen day cannot be turned off.
      expect(
        EventDraft.toggleWeekday(
          RecurrenceRule(freq: Freq.weekly, weekdays: [1]),
          1,
          start: 5,
        ).weekdays,
        [1],
      );
      // Back to only the start day means "no list".
      expect(
        EventDraft.toggleWeekday(withMonday, 1, start: 5).weekdays,
        isNull,
      );
      // Turning on the only start day of a plain weekly rule changes nothing.
      expect(EventDraft.toggleWeekday(weekly, 5, start: 5).weekdays, isNull);
    });
  });
}
