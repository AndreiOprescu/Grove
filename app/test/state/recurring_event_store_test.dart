// Port of Tests/GroveTests/RecurringEventStoreTests.swift.
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// 2026-10-05 is a Monday.
const monday = DayKey('2026-10-05');
const nextMonday = DayKey('2026-10-12');
const month = DayRange(DayKey('2026-10-01'), DayKey('2026-10-31'));
const onNextMonday = DayRange.single(nextMonday);

/// A weekly "Standup" on Mondays, 09:00–10:00.
EventItem addStandup(AppStore s, {RecurrenceRule? rule}) {
  final e = EventItem(
    id: 'S1',
    title: 'Standup',
    start: const WallTime(day: monday, minute: 540),
    end: const WallTime(day: monday, minute: 600),
    color: 'accent3',
    recurrence: rule ?? RecurrenceRule(freq: Freq.weekly),
  );
  s.repos.events.save(e);
  return e;
}

List<String> blockIds(AppStore s) => [for (final b in s.blocks(month)) b.id];

List<String> days(Iterable<PlannerBlock> blocks) => [
  for (final b in blocks) b.day.string,
];

DayRange range(String a, String b) => DayRange(DayKey(a), DayKey(b));

void move(AppStore s, String id, DayKey day, int start, int end) =>
    s.applyEdits(
      [BlockEdit(id: id, day: day, start: start, end: end)],
      ripple: false,
      name: 'Move Block',
    );

void main() {
  test('a weekly event shows on every week', () {
    final s = makeStore();
    addStandup(s);
    final blocks = s.blocks(month);
    expect(days(blocks), [
      '2026-10-05',
      '2026-10-12',
      '2026-10-19',
      '2026-10-26',
    ]);
    expect(
      blocks.every(
        (b) =>
            b.startMinute == 540 &&
            b.endMinute == 600 &&
            b.title == 'Standup' &&
            b.isRecurring,
      ),
      isTrue,
    );
    expect(blocks[1].id, 'S1@2026-10-12');
    expect(s.blocks(range('2026-10-06', '2026-10-11')), isEmpty);
  });

  test('a repeating all-day event shows in the all-day row', () {
    final s = makeStore();
    s.repos.events.save(
      EventItem(
        id: 'B1',
        title: 'Birthday',
        start: const WallTime(day: DayKey('2026-10-20'), minute: 0),
        end: const WallTime(day: DayKey('2026-10-20'), minute: 0),
        allDay: true,
        recurrence: RecurrenceRule(freq: Freq.yearly),
      ),
    );
    expect(eventTitles(s.allDayEvents(range('2026-10-19', '2026-10-21'))), [
      'Birthday',
    ]);
    expect(
      [for (final e in s.allDayEvents(range('2027-10-19', '2027-10-21'))) e.id],
      ['B1@2027-10-20'],
    );
    // All-day is not a grid block.
    expect(s.blocks(range('2026-10-19', '2026-10-21')), isEmpty);
  });

  test('an occurrence can be found by id', () {
    final s = makeStore();
    addStandup(s);
    final o = s.event('S1@2026-10-12')!;
    expect(o.start, const WallTime(day: nextMonday, minute: 540));
    expect(s.event('S1@2026-10-13'), isNull); // not a Monday
    expect(s.event('S1@2026-09-28'), isNull); // before the series began
  });

  group('move and resize', () {
    test('moving an occurrence asks first', () {
      final s = makeStore();
      addStandup(s);
      move(s, 'S1@2026-10-12', nextMonday, 600, 660);
      expect(s.recurringPrompt, isNotNull);
      // Nothing changed yet.
      expect(s.blocks(onNextMonday).first.startMinute, 540);
      expect(s.undoName, isNull);
    });

    test('only this event moves one day', () {
      final s = makeStore();
      final series = addStandup(s);
      move(s, 'S1@2026-10-12', nextMonday, 600, 690);
      s.answerRecurring(RecurringScope.only);

      final blocks = s.blocks(month);
      expect(blocks.length, 4);
      final moved = blocks.firstWhere((b) => b.day == nextMonday);
      expect(moved.startMinute, 600);
      expect(moved.endMinute, 690);
      expect(moved.isRecurring, isTrue);
      expect(moved.id, isNot('S1@2026-10-12'));
      expect(
        blocks
            .where((b) => b.day != nextMonday)
            .every((b) => b.startMinute == 540 && b.endMinute == 600),
        isTrue,
      );

      // The series says: this day is taken out. A one-off copy holds the new
      // time.
      expect(s.repos.events.exdates(series.id), [nextMonday]);
      final copy = s.repos.events.detached(series.id).first;
      expect(copy.seriesId, 'S1');
      expect(copy.originalDate, nextMonday);
      expect(copy.recurrence, isNull);
      expect(copy.id, moved.id);
      // The series itself did not change.
      expect(s.repos.events.get('S1')?.start.minute, 540);
      expect(s.selection, {copy.id});
    });

    test('only this event: undo and redo', () {
      final s = makeStore();
      final series = addStandup(s);
      move(s, 'S1@2026-10-12', nextMonday, 600, 660);
      s.answerRecurring(RecurringScope.only);
      s.undo();
      expect(blockIds(s), [
        'S1@2026-10-05',
        'S1@2026-10-12',
        'S1@2026-10-19',
        'S1@2026-10-26',
      ]);
      expect(s.repos.events.exdates(series.id), isEmpty);
      expect(s.repos.events.detached(series.id), isEmpty);
      s.redo();
      expect(s.blocks(onNextMonday).first.startMinute, 600);
      expect(s.repos.events.exdates(series.id), [nextMonday]);
    });

    test('moving one occurrence to another day', () {
      final s = makeStore();
      addStandup(s);
      const tuesday = DayKey('2026-10-13');
      move(s, 'S1@2026-10-12', tuesday, 540, 600);
      s.answerRecurring(RecurringScope.only);
      expect(s.blocks(onNextMonday), isEmpty);
      expect(s.blocks(const DayRange.single(tuesday)).length, 1);
      expect(s.blocks(month).length, 4);
    });

    test('all events changes the time of the series', () {
      final s = makeStore();
      addStandup(s);
      move(s, 'S1@2026-10-12', nextMonday, 600, 690);
      s.answerRecurring(RecurringScope.all);
      final blocks = s.blocks(month);
      expect(days(blocks), [
        '2026-10-05',
        '2026-10-12',
        '2026-10-19',
        '2026-10-26',
      ]);
      expect(
        blocks.every((b) => b.startMinute == 600 && b.endMinute == 690),
        isTrue,
      );
      expect(blocks[1].id, 'S1@2026-10-12');
      expect(s.repos.events.exdates('S1'), isEmpty);
      s.undo();
      expect(
        s
            .blocks(month)
            .every((b) => b.startMinute == 540 && b.endMinute == 600),
        isTrue,
      );
    });

    test('all events moved to another weekday moves the whole series', () {
      final s = makeStore();
      addStandup(s);
      move(s, 'S1@2026-10-12', const DayKey('2026-10-13'), 540, 600);
      s.answerRecurring(RecurringScope.all);
      expect(days(s.blocks(month)), [
        '2026-10-06',
        '2026-10-13',
        '2026-10-20',
        '2026-10-27',
      ]);
      expect(s.selection, {'S1@2026-10-13'});
    });

    test('all events moved to another weekday turns the chosen weekdays', () {
      final s = makeStore();
      // Mon and Wed.
      addStandup(
        s,
        rule: RecurrenceRule(freq: Freq.weekly, weekdays: [1, 3]),
      );
      // Move Wednesday the 14th to Thursday the 15th: Mon → Tue, Wed → Thu.
      move(s, 'S1@2026-10-14', const DayKey('2026-10-15'), 540, 600);
      s.answerRecurring(RecurringScope.all);
      expect(days(s.blocks(range('2026-10-12', '2026-10-18'))), [
        '2026-10-13',
        '2026-10-15',
      ]);
      expect([...?s.repos.events.get('S1')?.recurrence?.weekdays]..sort(), [
        2,
        4,
      ]);
    });

    test('resizing asks the same question', () {
      final s = makeStore();
      addStandup(s);
      s.applyEdits(
        [
          const BlockEdit(
            id: 'S1@2026-10-19',
            day: DayKey('2026-10-19'),
            start: 540,
            end: 660,
          ),
        ],
        ripple: false,
        name: 'Resize Block',
      );
      expect(s.recurringPrompt?.verb, 'Resize');
      s.answerRecurring(RecurringScope.all);
      expect(s.blocks(month).every((b) => b.endMinute == 660), isTrue);
    });

    test('a detached copy moves without asking', () {
      final s = makeStore();
      addStandup(s);
      move(s, 'S1@2026-10-12', nextMonday, 600, 660);
      s.answerRecurring(RecurringScope.only);
      final copyId = s.blocks(onNextMonday).first.id;
      move(s, copyId, nextMonday, 720, 780);
      expect(s.recurringPrompt, isNull);
      expect(s.blocks(onNextMonday).first.startMinute, 720);
    });
  });

  group('delete, colour, other', () {
    test('delete only this event hides one day', () {
      final s = makeStore();
      addStandup(s);
      s.deleteBlocks(['S1@2026-10-19'], name: 'Delete Event');
      expect(s.recurringPrompt?.verb, 'Delete');
      s.answerRecurring(RecurringScope.only);
      expect(blockIds(s), ['S1@2026-10-05', 'S1@2026-10-12', 'S1@2026-10-26']);
      s.undo();
      expect(blockIds(s).length, 4);
    });

    test('delete all events removes the series and its copies', () {
      final s = makeStore();
      addStandup(s);
      move(s, 'S1@2026-10-12', nextMonday, 600, 660);
      s.answerRecurring(RecurringScope.only);
      s.deleteBlocks(['S1@2026-10-19'], name: 'Delete Event');
      s.answerRecurring(RecurringScope.all);
      expect(s.blocks(month), isEmpty);
      expect(s.repos.events.get('S1'), isNull);
      expect(s.repos.events.all(), isEmpty);
      // Undo brings back the series, the moved copy and the removed day.
      s.undo();
      // Three from the series and the moved copy.
      expect(s.blocks(month).length, 4);
      expect(s.repos.events.detached('S1').length, 1);
      expect(s.repos.events.exdates('S1'), [nextMonday]);
    });

    test('deleting a detached copy does not bring the original back', () {
      final s = makeStore();
      addStandup(s);
      move(s, 'S1@2026-10-12', nextMonday, 600, 660);
      s.answerRecurring(RecurringScope.only);
      final copyId = s.blocks(onNextMonday).first.id;
      s.deleteBlocks([copyId], name: 'Delete Event');
      expect(s.recurringPrompt, isNull);
      expect(s.blocks(onNextMonday), isEmpty);
    });

    test('colour of one occurrence or all', () {
      final s = makeStore();
      addStandup(s);
      s.setColor(blockIds: ['S1@2026-10-19'], name: 'accent');
      expect(s.recurringPrompt?.verb, 'Change');
      s.answerRecurring(RecurringScope.only);
      expect(days(s.blocks(month).where((b) => b.color == 'accent')), [
        '2026-10-19',
      ]);
      s.setColor(blockIds: ['S1@2026-10-05'], name: 'accent2');
      s.answerRecurring(RecurringScope.all);
      expect(s.repos.events.get('S1')?.color, 'accent2');
    });

    test('split and duplicate say no', () {
      final s = makeStore();
      addStandup(s);
      s.duplicate(blockIds: ['S1@2026-10-19']);
      s.split(blockId: 'S1@2026-10-19');
      expect(s.repos.events.all().length, 1);
      expect(s.toast, isNotNull);
    });

    test('repeating events count as planned time', () {
      final s = makeStore();
      addStandup(s);
      expect(s.plannedMinutes(nextMonday), 60);
    });
  });
}
