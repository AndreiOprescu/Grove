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
}
