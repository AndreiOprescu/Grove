// Port of Tests/GroveTests/CalendarStoreTests.swift.
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const monday = DayKey('2026-10-05');
const october = DayRange(DayKey('2026-10-01'), DayKey('2026-10-31'));
const week = DayRange(DayKey('2026-10-04'), DayKey('2026-10-10'));

EventItem timed(String title, int start, int end, {String? id}) => EventItem(
  id: id,
  title: title,
  start: WallTime(day: monday, minute: start),
  end: WallTime(day: monday, minute: end),
);

EventItem dentist() => timed('Dentist', 840, 900);

void addStandup(AppStore s) => s.repos.events.save(
  EventItem(
    id: 'S1',
    title: 'Standup',
    start: const WallTime(day: monday, minute: 540),
    end: const WallTime(day: monday, minute: 600),
    recurrence: RecurrenceRule(freq: Freq.weekly),
  ),
);

void main() {
  group('reading a range of days', () {
    test('day info counts events, tasks and notes', () {
      final s = makeStore();
      s.repos.events.save(dentist());
      s.repos.events.save(
        EventItem(
          title: 'Birthday',
          start: const WallTime(day: monday, minute: 0),
          end: const WallTime(day: monday, minute: 0),
          allDay: true,
        ),
      );
      final t = TaskItem(
        title: 'Write',
        bucket: TaskBucket.day,
        planDate: monday,
      );
      s.repos.tasks.save(t);
      // A block is the task, not an event.
      s.repos.events.save(s.blockEvent(t, day: monday, start: 600, end: 660));
      s.repos.notes.save(
        Note(
          title: 'Mon',
          kind: NoteKind.daily,
          date: monday,
          body: 'Went well.',
        ),
      );

      final info = s.dayInfo(week);
      final day = info[monday]!;
      expect(eventTitles(day.events), ['Birthday', 'Dentist']); // all-day first
      expect(day.openTasks, 1);
      expect(day.hasNote, isTrue);
      expect(day.itemCount, 3);
      expect(info[const DayKey('2026-10-06')]?.itemCount ?? 0, 0);
    });

    test('day info shows a multi-day event on every day', () {
      final s = makeStore();
      s.repos.events.save(
        EventItem(
          title: 'Trip',
          start: const WallTime(day: monday, minute: 0),
          end: const WallTime(day: DayKey('2026-10-07'), minute: 0),
          allDay: true,
        ),
      );
      final info = s.dayInfo(week);
      expect(
        [
          for (final x in [
            '2026-10-04',
            '2026-10-05',
            '2026-10-06',
            '2026-10-07',
            '2026-10-08',
          ])
            info[DayKey(x)]?.events.length ?? 0,
        ],
        [0, 1, 1, 1, 0],
      );
    });

    test('day info includes the days of a repeating event', () {
      final s = makeStore();
      addStandup(s);
      final info = s.dayInfo(october);
      final days = [
        for (final e in info.entries)
          if (e.value.events.isNotEmpty) e.key.string,
      ]..sort();
      expect(days, ['2026-10-05', '2026-10-12', '2026-10-19', '2026-10-26']);
      expect(
        info[const DayKey('2026-10-12')]?.events.first.id,
        'S1@2026-10-12',
      );
    });

    test('a task that is done is not a dot', () {
      final s = makeStore();
      s.repos.tasks.save(
        TaskItem(
          title: 'Done',
          bucket: TaskBucket.day,
          planDate: monday,
          status: TaskStatus.done,
        ),
      );
      expect(
        s.dayInfo(const DayRange.single(monday))[monday]?.openTasks ?? 0,
        0,
      );
    });
  });

  group('opening the editor', () {
    test('a new event starts as an all-day draft on that day', () {
      final s = makeStore();
      s.newEvent(on: monday);
      final e = s.editingEvent!;
      expect(e.isNew, isTrue);
      expect(e.anchor, 'new:2026-10-05');
      expect(e.item.allDay, isTrue);
      expect(e.item.start.day, monday);
      expect(e.item.end.day, monday);
      // Nothing is saved until the user saves.
      expect(s.repos.events.all(), isEmpty);
      s.closeEditor();
      expect(s.editingEvent, isNull);
    });

    test('editing an existing event uses its id', () {
      final s = makeStore();
      final e = dentist();
      s.repos.events.save(e);
      s.editEvent(e);
      expect(s.editingEvent?.anchor, e.id);
      expect(s.editingEvent?.isNew, isFalse);
    });
  });

  group('saving', () {
    test('saving a new event creates it and undo removes it', () {
      final s = makeStore();
      s.newEvent(on: monday);
      final e = s.editingEvent!.item.copyWith(title: 'Conference');
      s.saveEvent(e, from: null);
      expect(eventTitles(s.repos.events.all()), ['Conference']);
      expect(s.editingEvent, isNull);
      s.undo();
      expect(s.repos.events.all(), isEmpty);
    });

    test('saving a stored event changes it in place', () {
      final s = makeStore();
      final e = dentist();
      s.repos.events.save(e);
      final edited = e.copyWith(title: 'Dentist (new)', location: 'Main St');
      s.saveEvent(edited, from: e);
      expect(s.recurringPrompt, isNull);
      expect(s.repos.events.get(e.id)?.title, 'Dentist (new)');
      expect(s.repos.events.get(e.id)?.location, 'Main St');
      s.undo();
      expect(s.repos.events.get(e.id)?.title, 'Dentist');
    });

    test('saving without changes does nothing', () {
      final s = makeStore();
      final e = dentist();
      s.repos.events.save(e);
      s.saveEvent(e, from: e);
      expect(s.undoName, isNull);
    });

    test('making a stored event repeat makes a series', () {
      final s = makeStore();
      final e = timed('Gym', 420, 480);
      s.repos.events.save(e);
      final edited = e.copyWith(recurrence: RecurrenceRule(freq: Freq.weekly));
      s.saveEvent(edited, from: e);
      expect(s.blocks(october).length, 4);
    });

    test('saving a day of a series asks which ones', () {
      final s = makeStore();
      addStandup(s);
      final day = s.event('S1@2026-10-12')!;
      final edited = s.draft(day).copyWith(title: 'Sync', location: 'Room 4');
      s.saveEvent(edited, from: day);
      expect(s.recurringPrompt?.verb, 'Change');
      s.answerRecurring(RecurringScope.only);
      expect(
        [for (final b in s.blocks(october)) b.title],
        ['Standup', 'Sync', 'Standup', 'Standup'],
      );
      expect(s.repos.events.get('S1')?.location, '');
    });

    test('saving a day of a series for all changes the series', () {
      final s = makeStore();
      addStandup(s);
      final day = s.event('S1@2026-10-12')!;
      final edited = s
          .draft(day)
          .copyWith(
            title: 'Sync',
            recurrence: RecurrenceRule(freq: Freq.weekly, interval: 2),
          );
      s.saveEvent(edited, from: day);
      s.answerRecurring(RecurringScope.all);
      expect(
        [for (final b in s.blocks(october)) b.day.string],
        ['2026-10-05', '2026-10-19'],
      );
      expect(s.repos.events.get('S1')?.title, 'Sync');
    });

    test('turning repeat off for all events leaves the first event', () {
      final s = makeStore();
      addStandup(s);
      final day = s.event('S1@2026-10-12')!;
      final edited = s.draft(day).copyWith(recurrence: null);
      s.saveEvent(edited, from: day);
      s.answerRecurring(RecurringScope.all);
      // The series keeps its first day. The other days go away.
      expect([for (final b in s.blocks(october)) b.day.string], ['2026-10-05']);
    });

    test('deleting an event from the editor', () {
      final s = makeStore();
      final e = dentist();
      s.repos.events.save(e);
      s.editEvent(e);
      s.deleteEvent(e);
      expect(s.repos.events.all(), isEmpty);
      expect(s.editingEvent, isNull);
      s.undo();
      expect(s.repos.events.all().length, 1);
    });

    test('deleting a day of a series asks', () {
      final s = makeStore();
      addStandup(s);
      final day = s.event('S1@2026-10-12')!;
      s.deleteEvent(day);
      expect(s.recurringPrompt?.verb, 'Delete');
      expect(s.editingEvent, isNull);
    });
  });

  test('dropping a task on a day plans it', () {
    final s = makeStore();
    final t = TaskItem(title: 'Call');
    s.repos.tasks.save(t);
    s.dropTask(t.id, on: monday);
    final moved = s.task(t.id)!;
    expect(moved.bucket, TaskBucket.day);
    expect(moved.planDate, monday);
  });
}
