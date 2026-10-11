// The card of an event (milestone F9): make, change and delete an event.
import 'package:flutter/material.dart' hide Row;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/calendar/event_editor.dart';
import 'package:grove/ui/editor/rich_text_field.dart';

import '../planner/planner_support.dart';

AppStore calendarStore() => plannerStore()..screen = Screen.calendar;

Finder key(String name) => find.byKey(ValueKey(name));

Finder fieldOf(String name) =>
    find.descendant(of: key(name), matching: find.byType(EditableText));

List<EventItem> eventsOf(AppStore store) =>
    store.eventItems(DayRange(d('2026-09-01'), d('2026-12-31')));

EventItem eventNamed(AppStore store, String title) =>
    eventsOf(store).firstWhere((e) => e.title == title);

/// Makes an event from 09:00 to 10:00 and gives it back.
EventItem makeEvent(AppStore store, String title, {DayKey? day}) {
  store.createFromDraft(
    title: title,
    day: day ?? wednesday,
    start: 9 * 60,
    end: 10 * 60,
    asEvent: true,
  );
  return eventNamed(store, title);
}

Future<void> tapKey(WidgetTester tester, String name) async {
  await tester.ensureVisible(key(name));
  await tester.pump();
  await tester.tap(key(name));
  await tester.pumpAndSettle();
}

Future<void> pickInMenu(WidgetTester tester, String name, String line) async {
  await tapKey(tester, name);
  await tester.tap(find.text(line).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a new event is saved with its title', (tester) async {
    final store = calendarStore();
    await pumpPlanner(tester, store);
    expect(find.byType(EventEditor), findsNothing);
    store.newEvent(on: d('2026-10-20'));
    await tester.pumpAndSettle();
    expect(find.byType(EventEditor), findsOneWidget);
    expect(find.text('Event title'), findsOneWidget);
    // a new event has no Delete and no meeting note
    expect(key('event-delete'), findsNothing);
    expect(key('event-meeting-note'), findsNothing);
    // all day: a day, no time
    expect(key('event-starts-day'), findsOneWidget);
    expect(key('event-starts-time'), findsNothing);

    await tester.enterText(fieldOf('event-title'), 'Dentist');
    await tapKey(tester, 'event-save');
    expect(find.byType(EventEditor), findsNothing);
    final saved = eventNamed(store, 'Dentist');
    expect(saved.allDay, isTrue);
    expect(saved.start.day, d('2026-10-20'));
  });

  testWidgets('Return in the title saves, and no title gives "New Event"', (
    tester,
  ) async {
    final store = calendarStore();
    await pumpPlanner(tester, store);
    store.newEvent(on: wednesday);
    await tester.pumpAndSettle();
    await tester.showKeyboard(fieldOf('event-title'));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(EventEditor), findsNothing);
    expect(eventsOf(store).single.title, 'New Event');
  });

  testWidgets('Cancel, Escape and a click beside the card save nothing', (
    tester,
  ) async {
    final store = calendarStore();
    await pumpPlanner(tester, store);

    store.newEvent(on: wednesday);
    await tester.pumpAndSettle();
    await tester.enterText(fieldOf('event-title'), 'One');
    await tapKey(tester, 'event-cancel');
    expect(find.byType(EventEditor), findsNothing);

    store.newEvent(on: wednesday);
    await tester.pumpAndSettle();
    await tester.enterText(fieldOf('event-title'), 'Two');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(EventEditor), findsNothing);

    expect(eventsOf(store), isEmpty);
  });

  testWidgets('a click on the screen closes a card with no change only', (
    tester,
  ) async {
    final store = calendarStore();
    await pumpPlanner(tester, store);
    // the card is at the top right, and the screen under it still works
    store.newEvent(on: wednesday);
    await tester.pumpAndSettle();
    final card = tester.getRect(find.byType(EventEditor));
    expect(card.right, desktopSize.width - 12);
    expect(key('event-editor-scrim'), findsNothing);
    await tester.tapAt(const Offset(300, 500));
    await tester.pumpAndSettle();
    await endTapWindow(tester);
    await tester.pumpAndSettle();
    expect(store.editingEvent, isNull);

    store
      ..screen = Screen.calendar
      ..selectedDay = wednesday
      ..newEvent(on: wednesday);
    await tester.pumpAndSettle();
    await tester.enterText(fieldOf('event-title'), 'Three');
    await tester.tapAt(const Offset(300, 500));
    await tester.pumpAndSettle();
    await endTapWindow(tester);
    await tester.pumpAndSettle();
    // the click did its work: the Planner is open, and the card kept its text
    expect(store.screen, Screen.planner);
    expect(find.byType(EventEditor), findsOneWidget);
    expect(find.text('Three'), findsOneWidget);
    await tapKey(tester, 'event-cancel');
    expect(eventsOf(store), isEmpty);
  });

  testWidgets('on a phone a touch beside the card closes it', (tester) async {
    final store = calendarStore();
    await pumpPlanner(tester, store, size: phoneSize);
    store.newEvent(on: wednesday);
    await tester.pumpAndSettle();
    expect(key('event-editor-scrim'), findsOneWidget);
    await tester.enterText(fieldOf('event-title'), 'Four');
    await tester.tapAt(
      tester.getRect(key('event-editor-scrim')).topLeft + const Offset(5, 5),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EventEditor), findsNothing);
    expect(eventsOf(store), isEmpty);
  });

  testWidgets('a click on an event of the planner opens its card, and the '
      'keys stay with the planner', (tester) async {
    final store = plannerStore();
    final e = makeEvent(store, 'Lunch');
    await pumpPlanner(tester, store);
    await mouseTap(tester, pointAt(tester, wednesday, 9 * 60 + 30));
    await endTapWindow(tester);
    expect(find.byType(EventEditor), findsOneWidget);
    expect(
      find.descendant(
        of: key('event-starts-time'),
        matching: find.text('09:00'),
      ),
      findsOneWidget,
    );

    // the card follows the event when the arrows move it
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(store.event(e.id)!.start.minute, 9 * 60 + 15);
    expect(
      find.descendant(
        of: key('event-starts-time'),
        matching: find.text('09:15'),
      ),
      findsOneWidget,
    );
    await tapKey(tester, 'event-save');
    expect(store.event(e.id)!.start.minute, 9 * 60 + 15);

    // Delete in the planner takes the event and its card away
    await mouseTap(tester, pointAt(tester, wednesday, 9 * 60 + 30));
    await endTapWindow(tester);
    expect(find.byType(EventEditor), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(find.byType(EventEditor), findsNothing);
    expect(store.editingEvent, isNull);
    expect(eventsOf(store), isEmpty);
  });

  testWidgets('an event can be changed, and Ctrl+Return saves', (tester) async {
    final store = calendarStore();
    final e = makeEvent(store, 'Stand-up');
    await pumpPlanner(tester, store);
    store.editEvent(e);
    await tester.pumpAndSettle();
    expect(find.text('Stand-up'), findsWidgets);
    expect(key('event-starts-time'), findsOneWidget);
    expect(
      find.descendant(
        of: key('event-starts-time'),
        matching: find.text('09:00'),
      ),
      findsOneWidget,
    );

    await tester.enterText(fieldOf('event-title'), 'Daily sync');
    await tester.enterText(fieldOf('event-location'), 'Room 4');
    await tapKey(tester, 'event-colour-accent3');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.byType(EventEditor), findsNothing);
    final saved = store.event(e.id)!;
    expect(saved.title, 'Daily sync');
    expect(saved.location, 'Room 4');
    expect(saved.color, 'accent3');
    expect(eventsOf(store), hasLength(1));
  });

  testWidgets('the start time moves the end with it', (tester) async {
    final store = calendarStore();
    final e = makeEvent(store, 'Stand-up');
    await pumpPlanner(tester, store);
    store.editEvent(e);
    await tester.pumpAndSettle();

    await tapKey(tester, 'event-starts-time');
    // the time picker, with 24 hours
    final fields = find.descendant(
      of: find.byType(TimePickerDialog),
      matching: find.byType(TextField),
    );
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), '14');
    await tester.enterText(fields.at(1), '30');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: key('event-ends-time'), matching: find.text('15:30')),
      findsOneWidget,
    );

    await tapKey(tester, 'event-save');
    final saved = store.event(e.id)!;
    expect(saved.start.minute, 14 * 60 + 30);
    expect(saved.end.minute, 15 * 60 + 30);
  });

  testWidgets('"All day" hides the times and gives them back', (tester) async {
    final store = calendarStore();
    final e = makeEvent(store, 'Stand-up');
    await pumpPlanner(tester, store);
    store.editEvent(e);
    await tester.pumpAndSettle();

    await tapKey(tester, 'event-all-day');
    expect(key('event-starts-time'), findsNothing);
    expect(key('event-ends-time'), findsNothing);
    await tapKey(tester, 'event-all-day');
    expect(key('event-starts-time'), findsOneWidget);

    await tapKey(tester, 'event-all-day');
    await tapKey(tester, 'event-save');
    expect(store.event(e.id)!.allDay, isTrue);
  });

  testWidgets('an event can repeat on some weekdays, a number of times', (
    tester,
  ) async {
    final store = calendarStore();
    final e = makeEvent(store, 'Gym');
    await pumpPlanner(tester, store);
    store.editEvent(e);
    await tester.pumpAndSettle();
    expect(key('event-ends'), findsNothing);
    expect(key('event-weekday-1'), findsNothing);

    await pickInMenu(tester, 'event-repeat', 'Every week');
    expect(key('event-ends'), findsOneWidget);
    expect(key('event-weekday-1'), findsOneWidget);
    // Wednesday is on from the start; add Friday
    await tapKey(tester, 'event-weekday-5');

    await pickInMenu(tester, 'event-ends', 'After');
    expect(find.text('10 times'), findsOneWidget);
    await tapKey(tester, 'event-count-more');
    await tapKey(tester, 'event-count-more');
    await tapKey(tester, 'event-count-less');
    expect(find.text('11 times'), findsOneWidget);

    await tapKey(tester, 'event-save');
    final rule = store.event(e.id)!.recurrence!;
    expect(rule.freq, Freq.weekly);
    expect(rule.weekdays, [3, 5]);
    expect(rule.count, 11);
    expect(rule.until, isNull);
  });

  testWidgets('a repeat can end on a day, or never', (tester) async {
    final store = calendarStore();
    final e = makeEvent(store, 'Gym');
    await pumpPlanner(tester, store);
    store.editEvent(e);
    await tester.pumpAndSettle();

    await pickInMenu(tester, 'event-repeat', 'Every day');
    expect(key('event-weekday-1'), findsNothing);
    await pickInMenu(tester, 'event-ends', 'On a day');
    expect(key('event-until'), findsOneWidget);
    expect(key('event-count'), findsNothing);
    await tapKey(tester, 'event-save');
    final rule = store.event(e.id)!.recurrence!;
    expect(rule.freq, Freq.daily);
    expect(rule.until, d('2026-11-06'));

    // the first day of the series
    store.editEvent(store.event(e.id)!);
    await tester.pumpAndSettle();
    await pickInMenu(tester, 'event-ends', 'Never');
    expect(key('event-until'), findsNothing);
    await pickInMenu(tester, 'event-repeat', 'Does not repeat');
    expect(key('event-ends'), findsNothing);
  });

  testWidgets('Delete takes the event away', (tester) async {
    final store = calendarStore();
    final e = makeEvent(store, 'Stand-up');
    await pumpPlanner(tester, store);
    store.editEvent(e);
    await tester.pumpAndSettle();
    await tapKey(tester, 'event-delete');
    expect(find.byType(EventEditor), findsNothing);
    expect(eventsOf(store), isEmpty);
  });

  testWidgets('a day of a series asks which events to change', (tester) async {
    final store = calendarStore();
    final e = makeEvent(store, 'Gym');
    store.saveEvent(
      e.copyWith(recurrence: RecurrenceRule(freq: Freq.daily)),
      from: e,
    );
    final second = eventsOf(store)
        .firstWhere((x) => x.start.day == d('2026-10-08'));
    await pumpPlanner(tester, store);
    store.editEvent(second);
    await tester.pumpAndSettle();
    expect(find.textContaining('this event only or all events'), findsOne);

    await tester.enterText(fieldOf('event-title'), 'Swim');
    await tapKey(tester, 'event-save');
    expect(find.byType(EventEditor), findsNothing);
    expect(store.recurringPrompt, isNotNull);
    await tester.tap(find.text('This event only'));
    await tester.pumpAndSettle();
    final titles = [
      for (final x in eventsOf(store))
        if (x.start.day == d('2026-10-08') || x.start.day == d('2026-10-09'))
          x.title,
    ];
    expect(titles, ['Swim', 'Gym']);
  });

  testWidgets('the meeting note is made from a saved event only', (
    tester,
  ) async {
    final store = calendarStore();
    final e = makeEvent(store, 'Review');
    await pumpPlanner(tester, store);
    store.editEvent(e);
    await tester.pumpAndSettle();
    expect(find.text('Create meeting note'), findsOneWidget);

    // with a change that is not saved, the card stays and says why
    await tester.enterText(fieldOf('event-title'), 'Review 2');
    await tapKey(tester, 'event-meeting-note');
    expect(find.byType(EventEditor), findsOneWidget);
    expect(find.text('Save the event first. Then make the note.'), findsOne);
    expect(store.meetingNote(e), isNull);
    await endToast(tester);

    await tester.enterText(fieldOf('event-title'), 'Review');
    await tapKey(tester, 'event-meeting-note');
    expect(find.byType(EventEditor), findsNothing);
    final note = store.meetingNote(e);
    expect(note, isNotNull);
    expect(store.screen, Screen.notes);

    // now the card has the note in "Linked here" and can open it
    store
      ..screen = Screen.calendar
      ..editEvent(e);
    await tester.pumpAndSettle();
    expect(find.text('Open meeting note'), findsOneWidget);
    expect(find.text('Linked here'), findsOneWidget);
    await tapKey(tester, 'event-linked-${note!.id}');
    expect(find.byType(EventEditor), findsNothing);
    expect(store.screen, Screen.notes);
    expect(store.selectedNoteId, note.id);
  });

  testWidgets('the notes of an event are kept', (tester) async {
    final store = calendarStore();
    final e = makeEvent(store, 'Review');
    await pumpPlanner(tester, store);
    store.editEvent(e);
    await tester.pumpAndSettle();
    expect(find.text('Notes. Type [[ to link something.'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(RichTextField),
        matching: find.byType(EditableText),
      ),
      'Bring the numbers',
    );
    await tester.pumpAndSettle();
    await tapKey(tester, 'event-save');
    expect(store.event(e.id)!.notes, 'Bring the numbers');
  });

  testWidgets('the card fits a phone', (tester) async {
    final store = calendarStore();
    final e = makeEvent(store, 'A long name of an event that does not fit');
    store.saveEvent(
      e.copyWith(recurrence: RecurrenceRule(freq: Freq.weekly, count: 10)),
      from: e,
    );
    await pumpPlanner(tester, store, size: phoneSize);
    store.editEvent(store.event(e.id)!);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final card = tester.getRect(find.byType(EventEditor));
    expect(card.left, greaterThanOrEqualTo(12));
    expect(card.right, lessThanOrEqualTo(phoneSize.width - 12));
    expect(card.bottom, lessThanOrEqualTo(phoneSize.height));
    await tapKey(tester, 'event-save');
    expect(find.byType(EventEditor), findsNothing);
  });
}
