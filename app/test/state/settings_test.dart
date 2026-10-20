// Port of Tests/GroveTests/SettingsTests.swift.
// The `AmbientMath` test stays with the theme code (Track B).
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  group('the rules behind the Settings window', () {
    test('the choices are small and sorted', () {
      expect(SettingsRules.eventLengths, [15, 30, 45, 60, 90, 120]);
      expect(
        SettingsRules.eventLengths,
        contains(SettingsRules.defaultEventLength),
      );
    });

    test('the busy day limit is whole hours from six to twelve', () {
      expect(SettingsRules.dailyLimits, [360, 420, 480, 540, 600, 660, 720]);
      expect(
        SettingsRules.dailyLimits,
        contains(SettingsRules.defaultDailyLimit),
      );
      expect(SettingsRules.defaultDailyLimit, 540);
    });

    test('work hours stay at least one hour long', () {
      // The start moves past the end: the end follows.
      expect(
        SettingsRules.workHours(
          start: 19 * 60,
          end: 18 * 60,
          startChanged: true,
        ),
        (start: 19 * 60, end: 20 * 60),
      );
      // The end moves before the start: the start follows.
      expect(
        SettingsRules.workHours(
          start: 9 * 60,
          end: 8 * 60,
          startChanged: false,
        ),
        (start: 7 * 60, end: 8 * 60),
      );
      // Good values stay as they are.
      expect(
        SettingsRules.workHours(
          start: 9 * 60,
          end: 18 * 60,
          startChanged: true,
        ),
        (start: 9 * 60, end: 18 * 60),
      );
    });

    test('work hours stay inside the day', () {
      expect(
        SettingsRules.workHours(
          start: 24 * 60,
          end: 24 * 60,
          startChanged: true,
        ),
        (start: 23 * 60, end: 24 * 60),
      );
      expect(SettingsRules.workHours(start: 0, end: 0, startChanged: false), (
        start: 0,
        end: 60,
      ));
    });

    test('an hour reads as clock time', () {
      expect(SettingsRules.hourText(9 * 60), '09:00');
      expect(SettingsRules.hourText(24 * 60), '24:00');
    });

    test('a backup name becomes a day', () {
      expect(
        SettingsRules.backupDay(fileName: 'grove-2026-10-04.sqlite'),
        d('2026-10-04'),
      );
      expect(SettingsRules.backupDay(fileName: 'grove-nope.sqlite'), isNull);
      expect(SettingsRules.backupDay(fileName: 'other.sqlite'), isNull);
    });

    test('the week starts on Monday or Sunday', () {
      final wed = d('2026-10-07');
      expect(CalendarRules.weekStart(wed, sundayFirst: false), d('2026-10-05'));
      expect(CalendarRules.weekStart(wed, sundayFirst: true), d('2026-10-04'));
      // A Sunday starts its own week when Sunday is first, and ends the old
      // one when Monday is first.
      expect(
        CalendarRules.weekStart(d('2026-10-04'), sundayFirst: true),
        d('2026-10-04'),
      );
      expect(
        CalendarRules.weekStart(d('2026-10-04'), sundayFirst: false),
        d('2026-09-28'),
      );
    });

    test('the month grid can start on Sunday', () {
      // 1 October 2026 is a Thursday.
      final monday = CalendarRules.monthGrid(d('2026-10-15'));
      final sunday = CalendarRules.monthGrid(
        d('2026-10-15'),
        sundayFirst: true,
      );
      expect(monday.first, d('2026-09-28'));
      expect(monday.length, 42);
      expect(sunday.first, d('2026-09-27'));
      expect(sunday.length, 42);
      expect(sunday, contains(d('2026-10-31')));
    });
  });

  group('export, import and the note templates on a real store', () {
    test('a store exports and another one imports', () {
      final a = makeStore();
      a.quickAdd('Water the plants today');
      final b = makeStore();
      b.quickAdd('Something old');
      b.importData(a.exportData());
      expect(titles(b.repos.tasks.all()), ['Water the plants']);
    });

    test('import starts fresh', () {
      final a = makeStore();
      a.quickAdd('Keep');
      final data = a.exportData();
      final b = makeStore();
      final task = b.quickAdd('Old one')!;
      b.selectedTaskId = task.id;
      b.selection = {task.id};
      b.selectedNoteId = 'gone';
      final before = b.revision;
      b.importData(data);
      expect(b.selectedTaskId, isNull);
      expect(b.selection, isEmpty);
      expect(b.selectedNoteId, isNull);
      expect(b.undoName, isNull);
      expect(b.redoName, isNull);
      expect(b.revision, greaterThan(before));
    });

    test('a bad file leaves the store as it was', () {
      final b = makeStore();
      final task = b.quickAdd('Stay')!;
      b.selectedTaskId = task.id;
      expect(() => b.importData('nope'), throwsA(isA<Exception>()));
      expect(b.selectedTaskId, task.id);
      expect(b.undoName, isNotNull);
      expect(b.repos.tasks.all().length, 1);
    });

    test('a note template is kept in the settings table', () {
      final s = makeStore();
      expect(s.template(NoteKind.daily), NotesRules.template(NoteKind.daily));
      s.setTemplate(NoteKind.daily, '## Mood\n');
      expect(s.template(NoteKind.daily), '## Mood\n');
      expect(s.repos.settings.get('notes.dailyTemplate'), '## Mood\n');
      expect(s.dailyNote(d('2026-10-05')).body, '## Mood\n');
      expect(
        s.weeklyNote(d('2026-10-05')).body,
        NotesRules.template(NoteKind.weekly),
      );
    });

    test('an empty template is allowed; reset brings back the default', () {
      final s = makeStore();
      s.setTemplate(NoteKind.weekly, '');
      expect(s.weeklyNote(d('2026-10-05')).body, '');
      s.resetTemplate(NoteKind.weekly);
      expect(s.template(NoteKind.weekly), NotesRules.template(NoteKind.weekly));
      expect(s.repos.settings.get('notes.weeklyTemplate'), isNull);
    });

    test('templates travel in the export file', () {
      final a = makeStore();
      a.setTemplate(NoteKind.daily, '## Mine\n');
      final b = makeStore();
      b.importData(a.exportData());
      expect(b.template(NoteKind.daily), '## Mine\n');
    });
  });
}
