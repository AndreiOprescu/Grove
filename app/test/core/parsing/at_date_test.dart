import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/parsing/at_date.dart';
import 'package:grove/core/parsing/note_parser.dart';

// Port of Tests/GroveCoreTests/AtDateParserTests.swift and AtDatePlanTests.swift.
void main() {
  const friday = DayKey('2026-10-02');
  const saturday = DayKey('2026-10-03');

  AtDate? find(String line) => AtDateParser.find(line, today: friday);
  String? text(String line, AtDate? hit) =>
      hit == null ? null : line.substring(hit.range.location, hit.range.end);

  group('AtDateParser', () {
    test('a weekday and a time', () {
      const line = 'Lunch with Sam @mon 12:30 at the cafe';
      final hit = find(line);
      expect(text(line, hit), '@mon 12:30');
      expect(hit?.day, const DayKey('2026-10-05'));
      expect(hit?.startMinute, 750);
      expect(hit?.durationMin, isNull);
    });

    test('a word and an am/pm time', () {
      const line = 'Call Sam @tomorrow 3pm';
      final hit = find(line);
      expect(text(line, hit), '@tomorrow 3pm');
      expect(hit?.day, saturday);
      expect(hit?.startMinute, 900);
    });

    test('a length is part of the token', () {
      const line = 'Review @today 9:30 for 1h30 and send it';
      final hit = find(line);
      expect(text(line, hit), '@today 9:30 for 1h30');
      expect(hit?.startMinute, 570);
      expect(hit?.durationMin, 90);
    });

    test('a day with no time has no start minute', () {
      final hit = find('Dentist @tomorrow');
      expect(hit?.day, saturday);
      expect(hit?.startMinute, isNull);
    });

    test('a time with no day leaves the day to the caller', () {
      final hit = find('Stand up @9am');
      expect(hit, isNotNull);
      expect(hit?.day, isNull);
      expect(hit?.startMinute, 540);
    });

    test('a month and a day', () {
      final hit = find('Flight @oct 20 6am');
      expect(hit?.day, const DayKey('2026-10-20'));
      expect(hit?.startMinute, 360);
    });

    test('a name is not a token', () {
      expect(find('Ask @sam about it'), isNull);
      expect(find('Ask @ about it'), isNull);
      expect(find('No at sign here, fri 3pm'), isNull);
    });

    test('an email address is not a token', () {
      expect(find('Write to sam@tomorrow.com'), isNull);
    });

    test('words after the date stay outside the token', () {
      const line = '@fri call Sam';
      expect(text(line, find(line)), '@fri');
    });

    test('tags and other quick-add words are not part of the token', () {
      const line = 'Pay rent @fri #home';
      expect(text(line, find(line)), '@fri');
      expect(find('Pay @every day'), isNull);
      expect(find('Pay @due fri'), isNull);
      expect(find('Plan @next week'), isNull); // a week is not a day
    });

    test('the first good token wins', () {
      const line = '@sam says @fri 10am';
      expect(text(line, find(line)), '@fri 10am');
    });

    test('offsets are UTF-16', () {
      const line = 'Café ☕ 🌳 @fri 3pm';
      expect(text(line, find(line)), '@fri 3pm');
    });
  });

  group('AtDatePlanner', () {
    AtDatePlan? plan(String line, {DayKey? noteDay}) =>
        AtDatePlanner.plan(line, noteDay: noteDay, today: friday);

    test('a plain line is an event', () {
      final p = plan('Call Sam @tomorrow 3pm')!;
      expect(p.title, 'Call Sam');
      expect(p.isTask, isFalse);
      expect(p.taskId, isNull);
      expect(p.day, saturday);
      expect(p.startMinute, 900);
      expect(p.durationMin, isNull);
      expect(p.head, '');
    });

    test('an open box is a task', () {
      final p = plan('- [ ] Write report @tomorrow 9am for 2h')!;
      expect(p.title, 'Write report');
      expect(p.isTask, isTrue);
      expect(p.taskId, isNull);
      expect(p.startMinute, 540);
      expect(p.durationMin, 120);
      expect(p.head, '- [ ] ');
    });

    test('a box that has a task keeps its id', () {
      final p = plan('- [ ] Write report @tomorrow 9am ⟦t:ABC⟧')!;
      expect(p.taskId, 'ABC');
      expect(p.title, 'Write report');
    });

    test('a ticked box is refused', () {
      expect(plan('- [x] Write report @tomorrow 9am'), isNull);
    });

    test('a line without a token is refused', () {
      expect(plan('Call Sam tomorrow'), isNull);
      expect(plan('mail me@home.com'), isNull);
    });

    test('a token with no words around it is refused', () {
      expect(plan('@tomorrow 3pm'), isNull);
      expect(plan('- [ ] @tomorrow'), isNull);
    });

    test('the token can sit in the middle of the words', () {
      expect(plan('Call @tomorrow 3pm Sam')?.title, 'Call Sam');
    });

    test('a time alone takes the note day, then today', () {
      const other = DayKey('2026-10-20');
      final a = plan('Standup @14:00', noteDay: other)!;
      expect(a.day, other);
      expect(a.startMinute, 840);
      expect(plan('Standup @14:00')?.day, friday);
    });

    test('a day word beats the note day', () {
      final p = plan(
        'Standup @tomorrow 14:00',
        noteDay: const DayKey('2026-10-20'),
      )!;
      expect(p.day, saturday);
    });

    test('a day alone has no time', () {
      final p = plan('## Plan @tomorrow')!;
      expect(p.day, saturday);
      expect(p.startMinute, isNull);
      expect(p.head, '## ');
      expect(p.title, 'Plan');
    });

    test('a list marker and indent stay', () {
      expect(plan('  - Lunch @tomorrow 12pm')?.head, '  - ');
      expect(plan('2. Lunch @tomorrow 12pm')?.head, '2. ');
    });

    test('a token inside the prefix is not read', () {
      expect(plan('@tomorrow'), isNull);
    });

    test('the line may end with a line break', () {
      expect(plan('Call Sam @tomorrow 3pm\n')?.title, 'Call Sam');
    });

    group('length', () {
      test('the span uses the length the user typed', () {
        final p = plan('Workshop @tomorrow 9am for 2h')!;
        final s = AtDatePlanner.span(p, defaultMinutes: 60)!;
        expect(s, (start: 540, end: 660));
      });

      test('the span uses the default when no length was typed', () {
        final p = plan('Workshop @tomorrow 9am')!;
        final s = AtDatePlanner.span(
          p,
          defaultMinutes: AtDatePlan.blockMinutes,
        )!;
        expect(s, (start: 540, end: 570));
      });

      test('the span stops at midnight', () {
        final p = plan('Late @tomorrow 23:30 for 2h')!;
        expect(AtDatePlanner.span(p, defaultMinutes: 60), (
          start: 1410,
          end: 1440,
        ));
      });

      test('no time means no span', () {
        final p = plan('Holiday @tomorrow')!;
        expect(AtDatePlanner.span(p, defaultMinutes: 60), isNull);
      });
    });

    group('writing the line back', () {
      test('the when label', () {
        String label(int? start, int? end) =>
            AtDatePlanner.whenLabel(saturday, start: start, end: end);
        expect(label(null, null), 'Sat 3 Oct');
        expect(label(900, null), 'Sat 3 Oct, 15:00');
        expect(label(900, 960), 'Sat 3 Oct, 15:00–16:00');
        expect(label(1410, 1440), 'Sat 3 Oct, 23:30–23:59');
      });

      test('a task line keeps its box and ends with the mark', () {
        final p = plan('- [ ] Write report @tomorrow 9am')!;
        expect(
          AtDatePlanner.taskLine(
            p,
            taskId: 'ABC',
            when: 'Sat 3 Oct, 09:00–09:30',
          ),
          '- [ ] Write report · Sat 3 Oct, 09:00–09:30 ⟦t:ABC⟧',
        );
      });

      test('an event line is a link, then when', () {
        final p = plan('- Dentist @tomorrow 9am')!;
        expect(
          AtDatePlanner.eventLine(
            p,
            mention: '[[Dentist|E1]]',
            when: 'Sat 3 Oct, 09:00–10:00',
          ),
          '- [[Dentist|E1]] · Sat 3 Oct, 09:00–10:00',
        );
      });

      test('the new task line is still one box with that task', () {
        final p = plan('- [ ] Write report @tomorrow 9am')!;
        final line = AtDatePlanner.taskLine(
          p,
          taskId: 'ABC',
          when: 'Sat 3 Oct',
        );
        final box = NoteParser.checkboxes(line).first;
        expect(box.taskId, 'ABC');
        expect(box.checked, isFalse);
        expect(box.text, 'Write report · Sat 3 Oct');
        // Nothing left to add twice.
        expect(AtDateParser.find(line, today: friday), isNull);
      });
    });
  });
}
