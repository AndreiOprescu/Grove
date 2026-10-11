import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// "Now" for the whole store. A test fixes it with `clockOverride`, so a
/// picture of a screen does not change with the real day.
void main() {
  // A day far from the real one, so the real clock cannot pass by luck.
  final day = d('2031-03-05');
  final clock = WallTime(day: day, minute: 10 * 60 + 20);

  test('the real clock gives the real day and minute', () {
    final s = makeStore();
    expect(s.clockToday, DayKey.today());
    expect(s.nowMinute(), inInclusiveRange(0, 1439));
  });

  test('a fixed clock gives its day and minute', () {
    final s = makeStore(clock: clock);
    expect(s.clockToday, day);
    expect(s.nowMinute(), 620);
    expect(s.reminderNow(), clock);
  });

  test('View ▸ Today goes to the day of the clock', () {
    final s = makeStore(clock: clock);
    s.selectedDay = d('2031-01-01');
    s.showToday();
    expect(s.selectedDay, day);
  });

  test('coming to the Today screen picks the day of the clock', () {
    final s = makeStore(clock: clock);
    s.screen = Screen.planner;
    s.selectedDay = d('2031-01-01');
    s.screen = Screen.today;
    expect(s.selectedDay, day);
  });

  test('showDay opens the Today screen for the day of the clock only', () {
    final s = makeStore(clock: clock);
    s.screen = Screen.notes;
    s.showDay(day);
    expect(s.screen, Screen.today);
    s.showDay(day.adding(days: 1));
    expect(s.screen, Screen.planner);
  });

  test('quick add reads "tomorrow" from the day of the clock', () {
    final s = makeStore(clock: clock);
    final task = s.quickAdd('Call mum tomorrow');
    expect(task?.planDate, day.adding(days: 1));
  });

  test('a task is late when its day is before the day of the clock', () {
    final s = makeStore(clock: clock);
    s.quickAdd('Old', placement: TaskPlacement.day(day.adding(days: -1)));
    s.quickAdd('Now', placement: TaskPlacement.day(day));
    final waiting = s.unscheduledTasks();
    expect(waiting.overdue.map((t) => t.title), ['Old']);
    expect(waiting.unscheduled, isEmpty);
  });

  test('the menu bar adds a task to the day of the clock', () {
    final s = makeStore(clock: clock);
    expect(s.menuBarAdd('Buy milk')?.planDate, day);
  });

  test('the palette goes to the day of the clock', () {
    final s = makeStore(clock: clock);
    s.screen = Screen.notes;
    s.run(PaletteCommandId.goToday);
    expect(s.selectedDay, day);
    expect(s.screen, Screen.today);
  });

  test('the next gap starts at the minute of the clock on its day', () {
    final s = makeStore(clock: clock);
    expect(
      s.nextFreeSlot(day: day, length: 30, workStart: 9 * 60, step: 15),
      10 * 60 + 30,
    );
    expect(
      s.nextFreeSlot(
        day: day.adding(days: 1),
        length: 30,
        workStart: 9 * 60,
        step: 15,
      ),
      9 * 60,
    );
  });

  test('a task checked off gets the time of the clock', () {
    final s = makeStore(clock: clock);
    final task = s.quickAdd('Buy milk', placement: TaskPlacement.inbox)!;
    s.toggleDone(taskId: task.id);
    expect(s.task(task.id)!.completedAt, '2031-03-05T10:20:00');
    expect(s.repos.tasks.completedOn(day).map((t) => t.id), [task.id]);
  });

  test('a goal block ticked done gets the time of the clock', () {
    final s = makeStore(clock: clock);
    final goal = s.addGoal(title: 'Read')!;
    s.scheduleGoal(goalId: goal.id, day: day, start: 600);
    final block = s.repos.events.all().single;
    s.toggleGoalBlockDone(eventId: block.id);
    expect(s.repos.events.get(block.id)!.doneAt, '2031-03-05T10:20:00');
  });

  group('the stamps of a note', () {
    const stamp = '2031-03-05T10:20:00';
    const laterStamp = '2031-03-07T08:05:00';
    final later = WallTime(day: day.adding(days: 2), minute: 8 * 60 + 5);

    void expectStamps(
      Note? note, {
      String made = stamp,
      String edited = stamp,
    }) {
      expect(note, isNotNull);
      expect(note!.createdAt, made, reason: 'made');
      expect(note.updatedAt, edited, reason: 'edited');
    }

    test('a new note gets the time of the clock', () {
      final s = makeStore(clock: clock);
      final n = s.newNote(title: 'Ideas');
      expectStamps(n);
      expectStamps(s.note(n.id));
    });

    test('the note of a day gets the time of the clock', () {
      final s = makeStore(clock: clock);
      final n = s.dailyNote(day.adding(days: -3));
      expectStamps(n);
      expectStamps(s.note(n.id));
    });

    test('the note of a week gets the time of the clock', () {
      final s = makeStore(clock: clock);
      final n = s.weeklyNote(day);
      expectStamps(n);
      expectStamps(s.note(n.id));
    });

    test('the copy of a note gets the time of the clock', () {
      final s = makeStore(clock: clock);
      final n = s.newNote(title: 'Ideas');
      s.clockOverride = later;
      s.duplicateNote(n.id);
      final copy = s.note(s.selectedNoteId!);
      expect(copy!.id, isNot(n.id));
      expectStamps(copy, made: laterStamp, edited: laterStamp);
      expectStamps(s.note(n.id));
    });

    test('the note of a meeting gets the time of the clock', () {
      final s = makeStore(clock: clock);
      final event = EventItem(
        title: 'Team sync',
        start: WallTime(day: day, minute: 600),
        end: WallTime(day: day, minute: 660),
      );
      s.repos.events.save(event);
      // The text of this note has a link, so the store saves it two times.
      final n = s.createMeetingNote(event)!;
      expectStamps(n);
      expectStamps(s.note(n.id));
    });

    test('a change gets the time of the clock at that moment', () {
      final s = makeStore(clock: clock);
      final n = s.newNote(title: 'Ideas');

      s.clockOverride = later;
      s.setNoteBody(n.id, 'More words');
      expectStamps(s.note(n.id), edited: laterStamp);

      s.clockOverride = clock;
      s.renameNote(n.id, to: 'Plans');
      expectStamps(s.note(n.id));

      s.clockOverride = later;
      s.togglePin(n.id);
      expectStamps(s.note(n.id), edited: laterStamp);
    });

    test('a text with a link is saved with the time of the clock', () {
      final s = makeStore(clock: clock);
      final other = s.newNote(title: 'Trip plan');
      final n = s.newNote(title: 'Ideas');
      s.clockOverride = later;
      s.setNoteBody(n.id, 'See [[Trip plan]]');
      // The store wrote the id of the note into the link: a second save.
      expect(s.note(n.id)!.body, 'See [[Trip plan|${other.id}]]');
      expectStamps(s.note(n.id), edited: laterStamp);
    });

    test('undo and redo get the time of the clock too', () {
      final s = makeStore(clock: clock);
      final n = s.newNote(title: 'Ideas');
      s.setNoteBody(n.id, 'More words');
      s.clockOverride = later;
      s.undo();
      expect(s.note(n.id)!.body, '');
      expectStamps(s.note(n.id), edited: laterStamp);
      s.clockOverride = clock;
      s.redo();
      expect(s.note(n.id)!.body, 'More words');
      expectStamps(s.note(n.id));
    });

    test('the list of notes has the last edited note first, by the clock', () {
      final s = makeStore(clock: clock);
      final a = s.newNote(title: 'First');
      s.clockOverride = WallTime(day: day, minute: 10 * 60 + 21);
      final b = s.newNote(title: 'Second');
      expect([for (final n in s.notes()) n.id], [b.id, a.id]);
      s.clockOverride = WallTime(day: day, minute: 10 * 60 + 22);
      s.setNoteBody(a.id, 'New words');
      expect([for (final n in s.notes()) n.id], [a.id, b.id]);
    });

    test('with the real clock a note gets the real time', () {
      final s = makeStore();
      final before = Stamp.now();
      final n = s.newNote(title: 'Ideas');
      final saved = s.note(n.id)!;
      final after = Stamp.now();
      for (final at in [saved.createdAt, saved.updatedAt]) {
        expect(at.compareTo(before), greaterThanOrEqualTo(0));
        expect(at.compareTo(after), lessThanOrEqualTo(0));
      }
    });
  });
}
