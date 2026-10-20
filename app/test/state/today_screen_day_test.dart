import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The Today screen shows today, or only tomorrow after its switch, so the
/// user can plan the next day. The store keeps the day of the screen.
void main() {
  // A day far from the real one, so the real clock cannot pass by luck.
  final day = d('2031-03-05');
  final tomorrow = d('2031-03-06');
  final clock = WallTime(day: day, minute: 10 * 60 + 20);

  /// A store on the Today screen. A new store has the real day, so the test
  /// comes to the screen from another one: that picks the day of the clock.
  AppStore onToday({Prefs? prefs}) => makeStore(clock: clock, prefs: prefs)
    ..screen = Screen.planner
    ..screen = Screen.today;

  test('the Today screen starts on today', () {
    final s = onToday();
    expect(s.todayScreenDay, day);
    expect(s.showsTomorrow, isFalse);
    expect(s.selectedDay, day);
  });

  test('the switch shows tomorrow, and today again', () {
    final s = onToday();
    var changes = 0;
    s.addListener(() => changes += 1);

    s.showsTomorrow = true;
    expect(s.showsTomorrow, isTrue);
    expect(s.todayScreenDay, tomorrow);
    expect(s.selectedDay, tomorrow);
    expect(s.screen, Screen.today);
    expect(changes, greaterThan(0));

    s.showsTomorrow = false;
    expect(s.showsTomorrow, isFalse);
    expect(s.todayScreenDay, day);
    expect(s.selectedDay, day);
  });

  test('the choice stays when the user goes to another screen and back', () {
    final s = onToday()..showsTomorrow = true;
    s.screen = Screen.planner;
    s.selectedDay = d('2031-01-01');
    expect(s.todayScreenDay, tomorrow);
    s.screen = Screen.today;
    expect(s.selectedDay, tomorrow);
    expect(s.showsTomorrow, isTrue);
  });

  test('the switch on another screen leaves the day of that screen', () {
    final s = onToday()..screen = Screen.planner;
    s.selectedDay = d('2031-01-01');
    s.showsTomorrow = true;
    expect(s.selectedDay, d('2031-01-01'));
    expect(s.todayScreenDay, tomorrow);
  });

  test('the choice is not saved: a new start opens on today', () {
    final prefs = MemoryPrefs();
    onToday(prefs: prefs).showsTomorrow = true;
    final again = onToday(prefs: prefs);
    expect(again.showsTomorrow, isFalse);
    expect(again.selectedDay, day);
  });

  group('View ▸ Today', () {
    test('brings the Today screen back to today', () {
      final s = onToday()..showsTomorrow = true;
      s.showToday();
      expect(s.screen, Screen.today);
      expect(s.showsTomorrow, isFalse);
      expect(s.selectedDay, day);
    });

    test('from the Notes screen opens the Today screen on today', () {
      final s = onToday()..showsTomorrow = true;
      s.screen = Screen.notes;
      s.showToday();
      expect(s.screen, Screen.today);
      expect(s.showsTomorrow, isFalse);
      expect(s.selectedDay, day);
    });

    test('on the Planner moves the week only', () {
      final s = onToday()..showsTomorrow = true;
      s.screen = Screen.planner;
      s.selectedDay = d('2031-01-01');
      s.showToday();
      expect(s.screen, Screen.planner);
      expect(s.selectedDay, day);
      expect(s.showsTomorrow, isTrue);
    });
  });

  group('showDay', () {
    test('today opens the Today screen on today', () {
      final s = onToday()..showsTomorrow = true;
      s.screen = Screen.notes;
      s.showDay(day);
      expect(s.screen, Screen.today);
      expect(s.showsTomorrow, isFalse);
      expect(s.selectedDay, day);
    });

    test('tomorrow stays on the Today screen that shows tomorrow', () {
      final s = onToday()..showsTomorrow = true;
      s.showDay(tomorrow);
      expect(s.screen, Screen.today);
      expect(s.selectedDay, tomorrow);
    });

    test('tomorrow opens the Planner from every other place', () {
      final s = onToday();
      s.showDay(tomorrow);
      expect(s.screen, Screen.planner);
      expect(s.selectedDay, tomorrow);
      expect(s.showsTomorrow, isFalse);

      final other = onToday()..showsTomorrow = true;
      other.screen = Screen.notes;
      other.showDay(tomorrow);
      expect(other.screen, Screen.planner);
    });
  });

  test('File ▸ New Event on the tomorrow view makes the event there', () {
    final s = onToday()..showsTomorrow = true;
    s.newEventNow();
    expect(s.screen, Screen.today);
    final event = s.repos.events.all().single;
    expect(event.start.day, tomorrow);
    // Tomorrow has no "now": the event starts with the working hours.
    expect(event.start.minute, 9 * 60);
  });

  test('"New task" of the palette opens the screen on the day it shows', () {
    final s = onToday()..showsTomorrow = true;
    s.screen = Screen.notes;
    s.run(PaletteCommandId.newTask);
    expect(s.screen, Screen.today);
    expect(s.selectedDay, tomorrow);
  });

  group('midnight', () {
    test('the day the user looked at stays, and is today now', () {
      final s = onToday()..showsTomorrow = true;
      s.clockOverride = WallTime(day: tomorrow, minute: 1);
      expect(s.todayScreenDay, tomorrow);
      expect(s.showsTomorrow, isFalse);
    });

    test('an old choice is forgotten', () {
      final s = onToday()..showsTomorrow = true;
      final later = day.adding(days: 3);
      s.clockOverride = WallTime(day: later, minute: 1);
      expect(s.todayScreenDay, later);
      expect(s.showsTomorrow, isFalse);
    });

    test('the switch after midnight shows the new tomorrow', () {
      final s = onToday()..showsTomorrow = true;
      s.clockOverride = WallTime(day: tomorrow, minute: 1);
      s.showsTomorrow = true;
      expect(s.todayScreenDay, tomorrow.adding(days: 1));
    });
  });

  group('quick add in the list of a day', () {
    List<PlannerBlock> blocksOn(AppStore s, DayKey on) =>
        s.blocks(DayRange.single(on));

    test('a time with no day makes the block on the day of the list', () {
      final s = onToday();
      final t = s.quickAdd(
        'Standup 9am',
        placement: TaskPlacement.day(tomorrow),
      )!;
      expect(s.task(t.id)!.planDate, tomorrow);
      expect(blocksOn(s, tomorrow).single.startMinute, 9 * 60);
      expect(blocksOn(s, day), isEmpty);
    });

    test('a repeating task with no day starts on the day of the list', () {
      final s = onToday();
      final t = s.quickAdd(
        'Water plants every day',
        placement: TaskPlacement.day(tomorrow),
      )!;
      expect(s.task(t.id)!.planDate, tomorrow);
    });

    test('a day in the text beats the day of the list', () {
      final s = onToday();
      final t = s.quickAdd(
        'Standup today 9am',
        placement: TaskPlacement.day(tomorrow),
      )!;
      expect(s.task(t.id)!.planDate, day);
      expect(blocksOn(s, day).single.startMinute, 9 * 60);
    });

    test('a time with no day is today in every other list', () {
      final s = onToday();
      final inbox = s.quickAdd('Standup 9am')!;
      expect(s.task(inbox.id)!.planDate, day);
      final someday = s.quickAdd('Call 4pm', placement: TaskPlacement.someday)!;
      expect(s.task(someday.id)!.planDate, day);
    });
  });
}
