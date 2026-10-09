import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/parsing/palette_rules.dart';

// Port of Tests/GroveCoreTests/PaletteRulesTests.swift: the text rules of the
// command palette (PLAN §5.5 item 11).
void main() {
  const friday = DayKey('2026-10-02');

  List<PaletteCommandId> ids(String text) =>
      PaletteRules.commandsMatching(text).map((c) => c.id).toList();

  group('reading the box', () {
    test('a leading arrow means commands only', () {
      expect(
        PaletteRules.parse('>new'),
        const PaletteParsed(commandsOnly: true, text: 'new'),
      );
      expect(
        PaletteRules.parse('  > plan '),
        const PaletteParsed(commandsOnly: true, text: 'plan'),
      );
      expect(
        PaletteRules.parse('>'),
        const PaletteParsed(commandsOnly: true, text: ''),
      );
    });

    test('other text searches everything', () {
      expect(
        PaletteRules.parse('  report '),
        const PaletteParsed(commandsOnly: false, text: 'report'),
      );
      expect(
        PaletteRules.parse(''),
        const PaletteParsed(commandsOnly: false, text: ''),
      );
      expect(
        PaletteRules.parse('a > b'),
        const PaletteParsed(commandsOnly: false, text: 'a > b'),
      );
    });
  });

  group('commands', () {
    test('an empty search lists every command in order', () {
      expect(ids(''), PaletteCommandId.values);
      expect(ids('   ').length, PaletteCommandId.values.length);
    });

    test('every word must start a word of the command', () {
      expect(ids('new'), [PaletteCommandId.newTask, PaletteCommandId.newNote]);
      expect(ids('new t'), [PaletteCommandId.newTask]);
      // "planner" starts with "plan" too.
      expect(ids('PLAN'), [
        PaletteCommandId.planMyDay,
        PaletteCommandId.showPlanner,
      ]);
      // Inside a word is not a start.
      expect(ids('ask'), isEmpty);
    });

    test('keywords find a command too', () {
      expect(ids('calendar'), contains(PaletteCommandId.showPlanner));
      expect(ids('journal'), [PaletteCommandId.todayNote]);
    });

    test('the commands have titles and the new task shortcut', () {
      final task = PaletteRules.commandsMatching('new task').first;
      expect(task.title, 'New task');
      expect(task.shortcut, '⌘N');
      expect(
        PaletteRules.commandsMatching('plan my').first.title,
        'Plan my day',
      );
      expect(
        PaletteRules.commandsMatching('go to date').first.title,
        'Go to date…',
      );
    });

    test('the screen commands carry the menu shortcuts', () {
      final shortcuts = {
        for (final c in PaletteRules.commands)
          if (c.shortcut != null) c.id: c.shortcut,
      };
      expect(shortcuts[PaletteCommandId.goToday], '⌘T');
      expect(shortcuts[PaletteCommandId.showPlanner], '⌘1');
      expect(shortcuts[PaletteCommandId.showCalendar], '⌘3');
      expect(shortcuts[PaletteCommandId.showNotes], '⌘4');
      expect(shortcuts[PaletteCommandId.showGarden], '⌘5');
    });

    test('the calendar command is found by month', () {
      expect(ids('month'), [PaletteCommandId.showCalendar]);
      expect(ids('open cal'), contains(PaletteCommandId.showCalendar));
    });

    test('the theme and motion commands are found', () {
      expect(ids('toggle theme'), [PaletteCommandId.toggleTheme]);
      expect(ids('dark'), [PaletteCommandId.toggleTheme]);
      expect(ids('toggle'), [
        PaletteCommandId.toggleTheme,
        PaletteCommandId.toggleMotion,
      ]);
      expect(ids('animation'), [PaletteCommandId.toggleMotion]);
      expect(
        PaletteRules.commandsMatching('toggle theme').first.title,
        'Toggle theme',
      );
    });
  });

  group('dates', () {
    DayKey? date(String text) => PaletteRules.date(text, today: friday);

    test('a day word is a date', () {
      expect(date('sat'), const DayKey('2026-10-03'));
      expect(date('mon'), const DayKey('2026-10-05'));
      expect(date('tomorrow'), const DayKey('2026-10-03'));
      expect(date('today'), friday);
    });

    test('go to in front is allowed', () {
      expect(date('go to mon'), const DayKey('2026-10-05'));
      expect(date('Go To Sat'), const DayKey('2026-10-03'));
      expect(date('goto sat'), const DayKey('2026-10-03'));
    });

    test('a time after the day does not matter', () {
      expect(date('sat 3pm'), const DayKey('2026-10-03'));
    });

    test('words around the date mean it is a search', () {
      expect(date('meeting sat'), isNull);
      expect(date('sat report'), isNull);
      expect(date('hello'), isNull);
      expect(date(''), isNull);
    });

    test('a time alone is not a date', () {
      expect(date('3pm'), isNull);
    });

    test('go to with nothing after asks for a day', () {
      expect(PaletteRules.asksForDay('go to'), isTrue);
      expect(PaletteRules.asksForDay('Go to '), isTrue);
      expect(PaletteRules.asksForDay('goto'), isTrue);
      expect(PaletteRules.asksForDay('go to sat'), isFalse);
      expect(PaletteRules.asksForDay('go'), isFalse);
      expect(PaletteRules.asksForDay('good'), isFalse);
    });

    test('the date row reads like a person', () {
      expect(PaletteRules.dayTitle(friday, today: friday), 'Go to today');
      expect(
        PaletteRules.dayTitle(const DayKey('2026-10-03'), today: friday),
        'Go to tomorrow',
      );
      expect(
        PaletteRules.dayTitle(const DayKey('2026-10-09'), today: friday),
        'Go to Friday',
      );
      expect(
        PaletteRules.dayTitle(const DayKey('2026-10-01'), today: friday),
        'Go to Thursday',
      );
      expect(PaletteRules.dayDetail(const DayKey('2026-10-09')), 'Fri 9 Oct');
    });
  });
}
