import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/recurrence.dart';
import 'package:grove/core/model/task.dart';
import 'package:grove/core/parsing/quick_add_parser.dart';

// Port of Tests/GroveCoreTests/QuickAddParserTests.swift.
// "Today" is Friday 2026-10-02 in every test.
void main() {
  const parser = QuickAddParser(
    today: DayKey('2026-10-02'),
    lists: ['Home', 'Work', 'Personal'],
  );
  QuickAddResult p(String s) => parser.parse(s);
  DayKey d(String s) => DayKey(s);

  group('plan examples', () {
    test('call mum', () {
      final r = p('Call mum tomorrow 6pm for 20m #home !2');
      expect(r.title, 'Call mum');
      expect(r.bucket, TaskBucket.day);
      expect(r.planDate, d('2026-10-03'));
      expect(r.startMinute, 18 * 60);
      expect(r.durationMin, 20);
      expect(r.blockEnd, 18 * 60 + 20);
      expect(r.tags, ['home']);
      expect(r.priority, 2);
    });

    test('read next week', () {
      final r = p('Read ch 5 next week');
      expect(r.title, 'Read ch 5');
      expect(r.bucket, TaskBucket.week);
      expect(r.planWeek, d('2026-10-05'));
      expect(r.planDate, isNull);
    });

    test('gym every monday', () {
      final r = p('Gym every mon 7am');
      expect(r.title, 'Gym');
      expect(r.recurrence, RecurrenceRule(freq: Freq.weekly, weekdays: [1]));
      expect(r.planDate, d('2026-10-05'));
      expect(r.startMinute, 7 * 60);
      expect(r.blockEnd, 7 * 60 + 30);
    });

    test('pay rent due', () {
      final r = p('Pay rent due 5 oct');
      expect(r.title, 'Pay rent');
      expect(r.due, '2026-10-05');
      expect(r.bucket, TaskBucket.inbox);
      expect(r.planDate, isNull);
    });
  });

  group('plain text', () {
    test('plain title', () {
      final r = p('Buy milk');
      expect(r.title, 'Buy milk');
      expect(r.bucket, TaskBucket.inbox);
      expect(r.chips, isEmpty);
    });

    test('spaces are tidied', () {
      expect(p('  Buy   milk  tomorrow ').title, 'Buy milk');
    });

    test('words that only look like tokens stay', () {
      expect(p('Sundae party').title, 'Sundae party');
      expect(p('Monitor setup').title, 'Monitor setup');
      expect(p('Learn C# basics').tags, isEmpty);
      expect(p('Wow!').title, 'Wow!');
      expect(p('Fix bug !9').priority, 0);
    });

    test('nothing left keeps what you typed', () {
      final r = p('tomorrow');
      expect(r.title, 'tomorrow');
      expect(r.planDate, isNull);
      expect(r.bucket, TaskBucket.inbox);
    });

    test('case does not matter', () {
      expect(p('Call Sam TOMORROW').planDate, d('2026-10-03'));
    });

    test('hex-looking numbers are not numbers', () {
      expect(p('Call in 0x3 days').planDate, isNull);
    });
  });

  group('dates', () {
    test('today words', () {
      expect(p('Email Sam today').planDate, d('2026-10-02'));
      expect(p('Email Sam tod').planDate, d('2026-10-02'));
      expect(p('Email Sam tmr').planDate, d('2026-10-03'));
    });

    test('weekday is next occurrence or today if same', () {
      expect(p('Gym fri').planDate, d('2026-10-02'));
      expect(p('Gym sat').planDate, d('2026-10-03'));
      expect(p('Gym mon').planDate, d('2026-10-05'));
      expect(p('Gym wednesday').planDate, d('2026-10-07'));
      expect(p('Gym thurs').planDate, d('2026-10-08'));
    });

    test('week buckets', () {
      final next = p('Plan next week');
      expect(next.bucket, TaskBucket.week);
      expect(next.planWeek, d('2026-10-05'));
      expect(next.title, 'Plan');
      final thisWeek = p('Review this week');
      expect(thisWeek.bucket, TaskBucket.week);
      expect(thisWeek.planWeek, d('2026-09-28'));
    });

    test('someday', () {
      final r = p('Learn piano someday');
      expect(r.bucket, TaskBucket.someday);
      expect(r.title, 'Learn piano');
    });

    test('calendar dates', () {
      expect(p('Dentist 3 oct').planDate, d('2026-10-03'));
      expect(p('Dentist oct 3').planDate, d('2026-10-03'));
      expect(p('Dentist 3/10').planDate, d('2026-10-03'));
      expect(p('Dentist 3 October').planDate, d('2026-10-03'));
      expect(p('Dentist 3 oct').title, 'Dentist');
    });

    test('past date rolls to next year', () {
      expect(p('Renew 1 oct').planDate, d('2027-10-01'));
    });

    test('impossible date stays in title', () {
      final r = p('Party 31 feb');
      expect(r.planDate, isNull);
      expect(r.title, 'Party 31 feb');
    });

    test('in some days', () {
      expect(p('Call in 3 days').planDate, d('2026-10-05'));
      expect(p('Call in 2 weeks').planDate, d('2026-10-16'));
      expect(p('Call in 3 days').title, 'Call');
    });
  });

  group('times and lengths', () {
    test('clock times', () {
      expect(p('Standup 9:30am').startMinute, 570);
      expect(p('Lunch at 12').startMinute, 720);
      expect(p('Call 18:00').startMinute, 1080);
      expect(p('Call 6:30pm').startMinute, 1110);
      expect(p('Wake 12am').startMinute, 0);
      expect(p('Eat 12pm').startMinute, 720);
    });

    test('time alone means today', () {
      final r = p('Standup 9am');
      expect(r.planDate, d('2026-10-02'));
      expect(r.bucket, TaskBucket.day);
      expect(r.title, 'Standup');
    });

    test('lengths', () {
      expect(p('Write for 45m').durationMin, 45);
      expect(p('Write for 1h').durationMin, 60);
      expect(p('Write for 1h30').durationMin, 90);
      expect(p('Write 90m').durationMin, 90);
      expect(p('Write 1h30m').durationMin, 90);
      expect(p('Write for 2 hours').durationMin, 120);
      expect(p('Write for 45m').title, 'Write');
    });

    test('length alone makes no block', () {
      final r = p('Write 45m');
      expect(r.startMinute, isNull);
      expect(r.bucket, TaskBucket.inbox);
    });

    test('block end stops at midnight', () {
      final r = p('Late 11:50pm for 30m');
      expect(r.startMinute, 23 * 60 + 50);
      expect(r.blockEnd, 1440);
    });

    test('time on a week task stays in the title', () {
      final r = p('Read next week 6pm');
      expect(r.startMinute, isNull);
      expect(r.title, 'Read 6pm');
    });
  });

  group('tags, priority, lists', () {
    test('tags and priority', () {
      final r = p('Plan #work #Q4 !3');
      expect(r.tags, ['work', 'q4']);
      expect(r.priority, 3);
      expect(r.title, 'Plan');
    });

    test('list matching', () {
      expect(p('Mow lawn /home').listName, 'Home');
      expect(p('Mow lawn /wo').listName, 'Work');
      expect(p('Mow lawn /home').title, 'Mow lawn');
      final none = p('Pay /xyz');
      expect(none.listName, isNull);
      expect(none.title, 'Pay /xyz');
    });
  });

  group('repeats', () {
    test('every day', () {
      final r = p('Water plants every day');
      expect(r.recurrence, RecurrenceRule(freq: Freq.daily));
      expect(r.planDate, d('2026-10-02'));
      expect(r.title, 'Water plants');
    });

    test('every weekday', () {
      final r = p('Standup every weekday 9am');
      expect(
        r.recurrence,
        RecurrenceRule(freq: Freq.weekly, weekdays: [1, 2, 3, 4, 5]),
      );
      expect(r.planDate, d('2026-10-02'));
      expect(r.startMinute, 540);
      final weekend = const QuickAddParser(today: DayKey('2026-10-03'))
          .parse('Standup every weekday');
      expect(weekend.planDate, d('2026-10-05'));
    });

    test('other repeats', () {
      expect(
        p('Review every week').recurrence,
        RecurrenceRule(freq: Freq.weekly),
      );
      expect(
        p('Pay every 2 weeks').recurrence,
        RecurrenceRule(freq: Freq.weekly, interval: 2),
      );
      expect(
        p('Rent every month').recurrence,
        RecurrenceRule(freq: Freq.monthly),
      );
      expect(
        p('Dust every 3 days').recurrence,
        RecurrenceRule(freq: Freq.daily, interval: 3),
      );
      expect(
        p('Rent every year').recurrence,
        RecurrenceRule(freq: Freq.yearly),
      );
    });
  });

  group('deadlines', () {
    test('due is not the plan date', () {
      final r = p('Report due fri');
      expect(r.due, '2026-10-02');
      expect(r.planDate, isNull);
      expect(r.title, 'Report');
    });

    test('due with a time', () {
      final r = p('Report due tomorrow 5pm');
      expect(r.due, '2026-10-03T17:00');
      expect(r.startMinute, isNull);
    });
  });

  group('everything together', () {
    test('everything', () {
      final r = p('Finish report fri 2pm for 2h #work !1 /Work');
      expect(r.title, 'Finish report');
      expect(r.planDate, d('2026-10-02'));
      expect(r.startMinute, 840);
      expect(r.durationMin, 120);
      expect(r.tags, ['work']);
      expect(r.priority, 1);
      expect(r.listName, 'Work');
    });

    test('chips show what was parsed', () {
      final r = p('Call mum tomorrow 6pm for 20m #home !2 /Home');
      expect(r.chips.map((c) => c.kind).toList(), [
        ChipKind.date,
        ChipKind.time,
        ChipKind.duration,
        ChipKind.list,
        ChipKind.tag,
        ChipKind.priority,
      ]);
      expect(r.chips.first.text, 'Sat 3 Oct');
      expect(r.chips[1].text, '18:00');
      expect(r.chips[2].text, '20m');
    });
  });
}
