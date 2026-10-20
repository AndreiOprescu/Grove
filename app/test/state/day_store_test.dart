// Port of Tests/GroveTests/DayStoreTests.swift.
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final today = DayKey.today();
final monday = today.weekStart();

void draft(
  AppStore s,
  String title,
  DayKey day,
  int start,
  int end, {
  required bool asEvent,
}) => s.createFromDraft(
  title: title,
  day: day,
  start: start,
  end: end,
  asEvent: asEvent,
);

void main() {
  group('the day panel', () {
    test('the agenda holds events, blocks and loose tasks', () {
      final s = makeStore();
      final day = today.adding(days: 3);
      draft(s, 'Write report', day, 600, 660, asEvent: false);
      draft(s, 'Dentist', day, 540, 600, asEvent: true);
      s.quickAdd('Buy stamps', placement: TaskPlacement.day(day));
      final rows = s.agenda(day);
      expect(
        [for (final r in rows) r.title],
        ['Dentist', 'Write report', 'Buy stamps'],
      );
      expect(
        [for (final r in rows) r.kind],
        [AgendaKind.event, AgendaKind.block, AgendaKind.task],
      );
    });

    test('the agenda follows changes', () {
      final s = makeStore();
      final day = today.adding(days: 3);
      final t = s.quickAdd('Buy stamps', placement: TaskPlacement.day(day))!;
      expect(s.agenda(day).first.done, isFalse);
      s.toggleDone(taskId: t.id);
      expect(s.agenda(day).first.done, isTrue);
    });
  });

  test('completed tasks lists what was finished on the day', () {
    final s = makeStore();
    final a = s.quickAdd('First')!;
    final b = s.quickAdd('Second')!;
    expect(s.quickAdd('Not done'), isNotNull);
    s.toggleDone(taskId: a.id);
    s.toggleDone(taskId: b.id);
    expect(titles(s.completedTasks(today)).toSet(), {'First', 'Second'});
    expect(s.completedTasks(today.adding(days: -1)), isEmpty);
    s.toggleDone(taskId: a.id); // reopened
    expect(titles(s.completedTasks(today)), ['Second']);
  });

  group('the weekly review', () {
    test('the review shows done, open, hours and the busiest day', () {
      final s = makeStore();
      final tue = monday.adding(days: 1);
      draft(s, 'Write report', monday, 600, 720, asEvent: false); // 2h
      draft(s, 'Call Sam', tue, 540, 600, asEvent: false); // 1h
      draft(s, 'Workshop', tue, 780, 900, asEvent: true); // 2h, not a task
      s.quickAdd('Plan the trip', placement: TaskPlacement.week(monday));
      final report = s.repos.tasks.all().firstWhere(
        (t) => t.title == 'Write report',
      );
      s.toggleDone(taskId: report.id);

      final r = s.weekReview(monday);
      expect(titles(r.done), ['Write report']);
      expect(titles(r.open).toSet(), {'Call Sam', 'Plan the trip'});
      // The task with a day comes first.
      expect(r.open.first.title, 'Call Sam');
      expect(r.plannedMinutes, 180);
      expect(r.doneMinutes, 120);
      expect(r.busiest, BusyDay(day: tue, minutes: 180));
    });

    test('the review ignores other weeks', () {
      final s = makeStore();
      draft(s, 'Next week', monday.adding(days: 8), 600, 660, asEvent: false);
      final r = s.weekReview(monday);
      expect(r.open, isEmpty);
      expect(r.plannedMinutes, 0);
      expect(r.busiest, isNull);
    });

    test('inserting the summary writes it under Review and undo takes it '
        'back', () {
      final s = makeStore();
      final w = s.weeklyNote(today);
      s.setNoteBody(w.id, '## Goals\n- Ship it\n');
      s.insertWeekSummary(w.id);
      final body = s.note(w.id)!.body;
      expect(body, contains('## Review\n**Week summary**\n- Done: 0 tasks'));
      expect(body, startsWith('## Goals\n- Ship it\n'));
      expect(DayRules.hasSummary(body), isTrue);
      s.undo();
      expect(s.note(w.id)?.body, '## Goals\n- Ship it\n');
    });

    test('the summary is its own undo step even right after typing', () {
      final s = makeStore();
      final w = s.weeklyNote(today);
      s.setNoteBody(w.id, '## Goals\n');
      s.insertWeekSummary(w.id);
      expect(s.undoName, 'Insert Week Summary');
      s.undo();
      // The typing before it stays.
      expect(s.note(w.id)?.body, '## Goals\n');
      s.setNoteBody(w.id, '## Goals\nMore');
      s.insertWeekSummary(w.id);
      s.setNoteBody(w.id, '${s.note(w.id)?.body ?? ''}\nAfter');
      s.undo();
      // Typing after it is its own step too.
      expect(DayRules.hasSummary(s.note(w.id)?.body ?? ''), isTrue);
    });

    test('a second insert updates the summary in place', () {
      final s = makeStore();
      final w = s.weeklyNote(today);
      s.insertWeekSummary(w.id);
      s.quickAdd('New thing', placement: TaskPlacement.day(monday));
      s.insertWeekSummary(w.id);
      final body = s.note(w.id)!.body;
      expect(body.split('**Week summary**').length, 2); // one summary
      expect(body, contains('- Still open: 1 task'));
    });

    test('the summary only goes in a weekly note', () {
      final s = makeStore();
      final n = s.newNote(title: 'Plain', body: 'text');
      s.insertWeekSummary(n.id);
      expect(s.note(n.id)?.body, 'text');
      final d = s.dailyNote(today);
      s.insertWeekSummary(d.id);
      expect(DayRules.hasSummary(s.note(d.id)?.body ?? ''), isFalse);
    });
  });

  group('mood', () {
    test('a mood is set, changed and cleared by the same click', () {
      final s = makeStore();
      final d = s.dailyNote(today);
      expect(s.note(d.id)?.mood, isNull);
      s.setMood(d.id, Mood.sun);
      expect(s.note(d.id)?.mood, 3);
      s.setMood(d.id, Mood.rain);
      expect(s.note(d.id)?.mood, 1);
      s.setMood(d.id, Mood.rain);
      expect(s.note(d.id)?.mood, isNull);
    });

    test('a mood change is one undo step and keeps the text', () {
      final s = makeStore();
      final d = s.dailyNote(today);
      s.setNoteBody(d.id, 'A good day');
      s.setMood(d.id, Mood.cloud);
      expect(s.undoName, 'Set Mood');
      s.undo();
      expect(s.note(d.id)?.mood, isNull);
      expect(s.note(d.id)?.body, 'A good day');
      s.redo();
      expect(s.note(d.id)?.mood, 2);
    });

    test('only a daily note takes a mood', () {
      final s = makeStore();
      final n = s.newNote(title: 'Plain');
      s.setMood(n.id, Mood.sun);
      expect(s.note(n.id)?.mood, isNull);
      final w = s.weeklyNote(today);
      s.setMood(w.id, Mood.sun);
      expect(s.note(w.id)?.mood, isNull);
    });

    test('the calendar knows the mood of each day', () {
      final s = makeStore();
      final d = s.dailyNote(today);
      final other = s.dailyNote(today.adding(days: 1));
      s.setNoteBody(other.id, 'A note with no mood');
      s.setMood(d.id, Mood.sun);
      final info = s.dayInfo(DayRange(today, today.adding(days: 2)));
      expect(info[today]?.mood, 3);
      // A note with no mood.
      expect(info[today.adding(days: 1)]?.mood, isNull);
      expect(info[today.adding(days: 1)]?.hasNote, isTrue);
      expect(info[today.adding(days: 2)]?.mood, isNull);
    });

    test('the mood query returns only days in range with a mood', () {
      final s = makeStore();
      s.setMood(s.dailyNote(today).id, Mood.cloud);
      s.setMood(s.dailyNote(today.adding(days: 5)).id, Mood.rain);
      s.setMood(s.dailyNote(today.adding(days: 40)).id, Mood.sun);
      final moods = s.repos.notes.moods(
        from: today,
        to: today.adding(days: 10),
      );
      expect(moods, {today: 2, today.adding(days: 5): 1});
    });
  });

  group('opening things from a note', () {
    test('opening a task on another day shows that day on the planner', () {
      final s = makeStore();
      final day = today.adding(days: 2);
      final t = s.quickAdd('Buy stamps', placement: TaskPlacement.day(day))!;
      s.screen = Screen.notes;
      s.open(ItemRef(ItemType.task, t.id));
      expect(s.screen, Screen.planner);
      expect(s.selectedTaskId, t.id);
      expect(s.selectedDay, day);
    });

    test('opening a task of today shows the today screen', () {
      final s = makeStore();
      final t = s.quickAdd('Buy stamps', placement: TaskPlacement.day(today))!;
      s.screen = Screen.notes;
      s.open(ItemRef(ItemType.task, t.id));
      expect(s.screen, Screen.today);
      expect(s.selectedTaskId, t.id);
      expect(s.selectedDay, today);
    });

    test('opening an event on another day shows that day on the planner', () {
      final s = makeStore();
      final day = today.adding(days: 2);
      draft(s, 'Dentist', day, 540, 600, asEvent: true);
      final e = s.eventItems(DayRange.single(day)).first;
      s.screen = Screen.notes;
      s.open(ItemRef(ItemType.event, e.id));
      expect(s.screen, Screen.planner);
      expect(s.selection, {e.id});
      expect(s.selectedDay, day);
    });
  });
}
