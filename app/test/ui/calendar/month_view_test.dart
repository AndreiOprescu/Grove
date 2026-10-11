// The Calendar screen (milestone F9): the grid of the month and its header.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter/widgets.dart' as w show Row;
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/calendar/month_view.dart';
import 'package:grove/ui/planner/payload_drag.dart';
import 'package:grove/ui/planner/planner_view.dart';
import 'package:grove/ui/theme/grove_theme.dart';

import '../planner/planner_support.dart';
import '../tasks/tasks_support.dart' show addTask, dragOnto, pumpPane;

AppStore calendarStore() => plannerStore()..screen = Screen.calendar;

Finder dayFinder(DayKey day) => find.byKey(ValueKey('month-day-${day.string}'));

void event(
  AppStore store,
  String title,
  DayKey day, {
  int start = 9 * 60,
  int end = 10 * 60,
}) => store.createFromDraft(
  title: title,
  day: day,
  start: start,
  end: end,
  asEvent: true,
);

EventItem eventNamed(AppStore store, String title) => store
    .eventItems(DayRange(d('2026-09-01'), d('2026-11-30')))
    .firstWhere((e) => e.title == title);

void main() {
  testWidgets('the month shows six weeks from Monday', (tester) async {
    final store = calendarStore();
    await pumpPlanner(tester, store);
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.byType(MonthView), findsOneWidget);
    for (final name in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) {
      expect(find.text(name), findsOneWidget);
    }
    // 28 September to 8 November
    expect(dayFinder(d('2026-09-28')), findsOneWidget);
    expect(dayFinder(d('2026-11-08')), findsOneWidget);
    expect(dayFinder(d('2026-09-27')), findsNothing);
    expect(dayFinder(d('2026-11-09')), findsNothing);
    final first = tester.getRect(dayFinder(d('2026-09-28')));
    final next = tester.getRect(dayFinder(d('2026-09-29')));
    final below = tester.getRect(dayFinder(d('2026-10-05')));
    expect(next.left, first.right);
    expect(below.top, first.bottom);
    expect(first.left, tester.getRect(find.byType(MonthView)).left);
    // no zoom and no plan in a month
    expect(find.bySemanticsLabel('Zoom in'), findsNothing);
    expect(find.byKey(const ValueKey('plan-my-day')), findsNothing);
  });

  testWidgets('the week starts on Sunday when the setting says so', (
    tester,
  ) async {
    final store = calendarStore();
    store.prefs.set('calendar.weekStartsSunday', true);
    await pumpPlanner(tester, store);
    expect(dayFinder(d('2026-09-27')), findsOneWidget);
    expect(dayFinder(d('2026-11-07')), findsOneWidget);
    expect(dayFinder(d('2026-11-08')), findsNothing);
    expect(
      tester.getRect(find.text('Sun')).left,
      lessThan(tester.getRect(find.text('Mon')).left),
    );
  });

  testWidgets('a day shows its events, with the time of a timed event', (
    tester,
  ) async {
    final store = calendarStore();
    event(store, 'Stand-up', wednesday);
    store.saveEvent(
      EventItem(
        title: 'Trip',
        start: WallTime(day: d('2026-10-12'), minute: 0),
        end: WallTime(day: d('2026-10-13'), minute: 0),
        allDay: true,
      ),
      from: null,
    );
    await pumpPlanner(tester, store);
    expect(find.text('09:00 Stand-up', findRichText: true), findsOneWidget);
    // an event of two days is on both days, with no time
    expect(find.text('Trip', findRichText: true), findsNWidgets(2));
    expect(find.text('2 events · 0 open tasks'), findsOneWidget);
  });

  testWidgets('events that do not fit are counted', (tester) async {
    final store = calendarStore();
    for (final (i, name) in ['One', 'Two', 'Three', 'Four', 'Five'].indexed) {
      event(store, name, wednesday, start: (9 + i) * 60, end: (10 + i) * 60);
    }
    await pumpPlanner(tester, store);
    final cell = tester.getRect(dayFinder(wednesday));
    final slots = CalendarRules.pillSlots(cellHeight: cell.height);
    expect(
      find.descendant(
        of: dayFinder(wednesday),
        matching: find.textContaining('more'),
      ),
      findsOneWidget,
    );
    expect(find.text('+${5 - slots} more'), findsOneWidget);
    expect(find.text('5 events · 0 open tasks'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a day shows a dot for each open task, up to three, and a leaf '
      'for a note', (tester) async {
    final store = calendarStore();
    for (final name in ['A', 'B', 'C', 'D']) {
      addTask(store, 'Task $name', day: d('2026-10-08'));
    }
    addTask(store, 'Alone', day: d('2026-10-09'));
    // a daily note counts when it has words of its own
    store.setNoteBody(
      store.dailyNote(d('2026-10-09')).id,
      '## Plan\n\nBuy bread\n',
    );
    store.dailyNote(d('2026-10-10'));
    await pumpPlanner(tester, store);
    Finder dots(String day) => find.descendant(
      of: find.byKey(ValueKey('month-dots-$day')),
      matching: find.byType(DecoratedBox),
    );
    expect(dots('2026-10-08'), findsNWidgets(3));
    expect(dots('2026-10-09'), findsOneWidget);
    expect(find.byKey(const ValueKey('month-dots-2026-10-10')), findsNothing);
    expect(find.byKey(const ValueKey('month-leaf-2026-10-09')), findsOneWidget);
    expect(find.byKey(const ValueKey('month-leaf-2026-10-10')), findsNothing);
    expect(find.text('0 events · 5 open tasks'), findsOneWidget);
  });

  testWidgets('a click on a day opens the Planner on that week', (
    tester,
  ) async {
    final store = calendarStore();
    await pumpPlanner(tester, store);
    await mouseTap(tester, tester.getCenter(dayFinder(d('2026-10-20'))));
    await endTapWindow(tester);
    await tester.pumpAndSettle();
    expect(store.selectedDay, d('2026-10-20'));
    expect(store.screen, Screen.planner);
    expect(store.editingEvent, isNull);
  });

  testWidgets('a double click on a day starts an all-day event', (
    tester,
  ) async {
    final store = calendarStore();
    await pumpPlanner(tester, store);
    final at = tester.getCenter(dayFinder(d('2026-10-20')));
    await mouseTap(tester, at);
    await tester.pump(const Duration(milliseconds: 80));
    await mouseTap(tester, at);
    await endTapWindow(tester);
    await tester.pumpAndSettle();
    final editing = store.editingEvent!;
    expect(editing.isNew, isTrue);
    expect(editing.anchor, 'new:2026-10-20');
    expect(editing.item.allDay, isTrue);
    expect(editing.item.start.day, d('2026-10-20'));
    expect(store.screen, Screen.calendar);
  });

  testWidgets('a click on an event opens it', (tester) async {
    final store = calendarStore();
    event(store, 'Stand-up', wednesday);
    await pumpPlanner(tester, store);
    await mouseTap(
      tester,
      tester.getCenter(find.text('09:00 Stand-up', findRichText: true)),
    );
    await endTapWindow(tester);
    await tester.pumpAndSettle();
    final editing = store.editingEvent!;
    expect(editing.isNew, isFalse);
    expect(editing.item.title, 'Stand-up');
    expect(editing.anchor, '${eventNamed(store, 'Stand-up').id}#2026-10-07');
    expect(store.screen, Screen.calendar);
  });

  testWidgets('Previous, Next and Today move by a month', (tester) async {
    final store = calendarStore();
    await pumpPlanner(tester, store);
    await tester.tap(find.bySemanticsLabel('Next'));
    await tester.pumpAndSettle();
    expect(find.text('November 2026'), findsOneWidget);
    expect(store.selectedDay, d('2026-11-07'));
    await tester.tap(find.bySemanticsLabel('Previous'));
    await tester.tap(find.bySemanticsLabel('Previous'));
    await tester.pumpAndSettle();
    expect(find.text('September 2026'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('planner-today')));
    await tester.pumpAndSettle();
    expect(find.text('October 2026'), findsOneWidget);
    expect(store.selectedDay, wednesday);
  });

  testWidgets('the mood switch tints the days by the mood of their note', (
    tester,
  ) async {
    final store = calendarStore();
    store.setMood(store.dailyNote(d('2026-10-06')).id, Mood.sun);
    store.dailyNote(d('2026-10-08'));
    await pumpPlanner(tester, store);
    const tint = ValueKey('month-mood-2026-10-06');
    expect(find.byKey(tint), findsNothing);
    await tester.tap(find.byKey(const ValueKey('mood-tint')));
    await tester.pumpAndSettle();
    expect(store.prefs.getBool(PlannerView.moodTintKey), isTrue);
    final box = tester.widget<DecoratedBox>(find.byKey(tint));
    expect(
      (box.decoration as BoxDecoration).color,
      moodTint(Mood.sun).withValues(alpha: 0.2),
    );
    // a note with no mood has no colour
    expect(find.byKey(const ValueKey('month-mood-2026-10-08')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('mood-tint')));
    await tester.pumpAndSettle();
    expect(find.byKey(tint), findsNothing);
    expect(store.prefs.getBool(PlannerView.moodTintKey), isFalse);
  });

  testWidgets('a task can be dropped on a day', (tester) async {
    final store = calendarStore();
    final task = addTask(store, 'Buy bread');
    await pumpPane(
      tester,
      w.Row(
        children: [
          PayloadDrag(
            payload: DragPayload.task(task.id),
            label: 'Buy bread',
            child: const ColoredBox(
              key: ValueKey('source'),
              color: Color(0xFF808080),
              child: SizedBox(width: 80, height: 40),
            ),
          ),
          Expanded(
            child: MonthView(store: store, openDay: (_) {}),
          ),
        ],
      ),
      size: const Size(900, 600),
    );
    await dragOnto(
      tester,
      find.byKey(const ValueKey('source')),
      dayFinder(d('2026-10-22')),
    );
    expect(store.task(task.id)!.planDate, d('2026-10-22'));
    expect(store.toast, 'Planned for Thu 22 Oct');
    await endToast(tester);
    // a note is not a task: the day does not take it
    final note = store.newNote(title: 'Ideas');
    await pumpPane(
      tester,
      w.Row(
        children: [
          PayloadDrag(
            payload: DragPayload.note(note.id),
            label: 'Ideas',
            child: const ColoredBox(
              key: ValueKey('source'),
              color: Color(0xFF808080),
              child: SizedBox(width: 80, height: 40),
            ),
          ),
          Expanded(
            child: MonthView(store: store, openDay: (_) {}),
          ),
        ],
      ),
      size: const Size(900, 600),
    );
    await dragOnto(
      tester,
      find.byKey(const ValueKey('source')),
      dayFinder(d('2026-10-23')),
    );
    expect(store.task(task.id)!.planDate, d('2026-10-22'));
  });

  testWidgets('the month fits a phone', (tester) async {
    final store = calendarStore();
    event(store, 'A long name of an event', wednesday);
    await pumpPlanner(tester, store, size: phoneSize);
    expect(find.text('October 2026'), findsOneWidget);
    expect(dayFinder(d('2026-11-08')), findsOneWidget);
    expect(tester.takeException(), isNull);
    final grid = tester.getRect(find.byType(MonthView));
    for (final day in [d('2026-09-28'), d('2026-11-08')]) {
      final cell = tester.getRect(dayFinder(day));
      expect(cell.left, greaterThanOrEqualTo(grid.left));
      expect(cell.right, lessThanOrEqualTo(grid.right));
      expect(cell.left, cell.left.roundToDouble());
    }
  });

  testWidgets('a narrow day keeps its leaf and its dots inside', (
    tester,
  ) async {
    final store = calendarStore();
    addTask(store, 'One');
    addTask(store, 'Two');
    addTask(store, 'Three');
    store.setNoteBody(store.dailyNote(wednesday).id, 'some words');
    Future<void> check(Size size) async {
      await pumpPlanner(tester, store, size: size);
      expect(tester.takeException(), isNull, reason: '$size');
      final cell = tester.getRect(dayFinder(wednesday));
      for (final part in ['leaf', 'dots']) {
        final found = find.byKey(ValueKey('month-$part-${wednesday.string}'));
        if (found.evaluate().isEmpty) continue;
        final box = tester.getRect(found);
        expect(box.left, greaterThanOrEqualTo(cell.left), reason: '$size');
        expect(box.right, lessThanOrEqualTo(cell.right), reason: '$size');
      }
    }

    // a phone: the cell is 52 points wide
    await check(phoneSize);
    expect(find.byKey(ValueKey('month-leaf-${wednesday.string}')), findsOne);
    // the narrowest window with the left panel and the panel of a task
    store.selectedTaskId = 'one';
    await check(const Size(700, 620));
    // a wide window has room for all of it
    store.selectedTaskId = null;
    await check(desktopSize);
    expect(find.byKey(ValueKey('month-leaf-${wednesday.string}')), findsOne);
    expect(
      tester.getSize(find.byKey(ValueKey('month-dots-${wednesday.string}'))),
      const Size(16, 4),
    );
  });

  testWidgets('today has its number on the accent colour', (tester) async {
    final store = calendarStore();
    await pumpPlanner(tester, store);
    Text number(DayKey day) => tester.widget<Text>(
      find.descendant(of: dayFinder(day), matching: find.text('${day.day}')),
    );
    expect(number(wednesday).style!.fontWeight, FontWeight.w700);
    expect(number(d('2026-10-08')).style!.fontWeight, FontWeight.w600);
    // the round mark under the number
    final theme = GroveTheme.of(tester.element(find.byType(MonthView)));
    BoxDecoration mark(DayKey day) =>
        tester
                .widget<DecoratedBox>(
                  find
                      .ancestor(
                        of: find.descendant(
                          of: dayFinder(day),
                          matching: find.text('${day.day}'),
                        ),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(mark(wednesday).color, theme.accent);
    expect(mark(wednesday).shape, BoxShape.circle);
    expect(mark(d('2026-10-08')).color, isNull);
    // a touch works like a mouse
    await tester.tapAt(
      tester.getCenter(dayFinder(d('2026-10-08'))),
      kind: PointerDeviceKind.touch,
    );
    await endTapWindow(tester);
    await tester.pumpAndSettle();
    expect(store.screen, Screen.planner);
    expect(store.selectedDay, d('2026-10-08'));
  });
}
