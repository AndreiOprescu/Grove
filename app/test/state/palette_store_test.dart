// Port of Tests/GroveTests/PaletteStoreTests.swift.
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// The command palette on a real store (PLAN §5.5 item 11).

final friday = d('2026-10-02');
final saturday = d('2026-10-03');

List<PaletteCommandId> commandIds(List<PaletteItem> items) => [
  for (final i in items)
    if (i.action case PaletteRun(:final command)) command,
];

PaletteItem? rowFor(List<PaletteItem> items, ItemRef ref) =>
    items.where((i) => i.action == PaletteOpen(ref)).firstOrNull;

void main() {
  group('PaletteStore', () {
    // What the box lists

    test('an empty box lists the commands', () {
      final s = makeStore();
      s.quickAdd('Report taxes');
      final items = s.paletteItems('', today: friday);
      expect(commandIds(items), PaletteCommandId.values);
      expect(items.length, PaletteCommandId.values.length);
    });

    test('an arrow keeps only commands', () {
      final s = makeStore();
      s.quickAdd('New shoes');
      final items = s.paletteItems('>new', today: friday);
      expect(commandIds(items), [
        PaletteCommandId.newTask,
        PaletteCommandId.newNote,
      ]);
      expect(items.length, 2); // the task "New shoes" is not listed
      expect(
        s.paletteItems('>', today: friday).length,
        PaletteCommandId.values.length,
      );
    });

    test('a search finds tasks, events and notes', () {
      final s = makeStore();
      final t = s.quickAdd(
        'Report taxes',
        placement: TaskPlacement.day(saturday),
      )!;
      s.saveEvent(
        EventItem(
          title: 'Report review',
          start: WallTime(day: friday, minute: 540),
          end: WallTime(day: friday, minute: 600),
        ),
        from: null,
      );
      final e = s.eventItems(DayRange.single(friday)).first;
      final n = s.newNote(title: 'Report ideas');
      final items = s.paletteItems('report', today: friday);
      final refs = {
        for (final i in items)
          if (i.action case PaletteOpen(:final ref)) ref,
      };
      final task = ItemRef(ItemType.task, t.id);
      final event = ItemRef(ItemType.event, e.id);
      final note = ItemRef(ItemType.note, n.id);
      expect(refs, {task, event, note});
      expect(rowFor(items, task)?.detail, 'Task · Sat 3 Oct');
      expect(rowFor(items, event)?.detail, 'Event · Fri 2 Oct, 09:00–10:00');
      expect(rowFor(items, note)?.detail, 'Note');
    });

    test('a task block is not listed beside its task', () {
      final s = makeStore();
      s.createFromDraft(
        title: 'Write report',
        day: friday,
        start: 600,
        end: 660,
        asEvent: false,
      );
      final items = s.paletteItems('report', today: friday);
      expect(items.length, 1);
      final action = items.first.action;
      expect(action, isA<PaletteOpen>());
      expect((action as PaletteOpen).ref.type, ItemType.task);
    });

    test('a finished task is marked done', () {
      final s = makeStore();
      final t = s.quickAdd('Report taxes')!;
      s.toggleDone(taskId: t.id);
      final item = s.paletteItems('report', today: friday).first;
      expect(item.done, isTrue);
      expect(item.detail, 'Task · done');
    });

    test('daily and weekly notes say what they are', () {
      final s = makeStore();
      final daily = s.dailyNote(friday);
      s.setNoteBody(daily.id, 'zebra thoughts');
      final weekly = s.weeklyNote(friday);
      s.setNoteBody(weekly.id, 'zebra goals');
      final items = s.paletteItems('zebra', today: friday);
      expect(
        rowFor(items, ItemRef(ItemType.note, daily.id))?.detail,
        'Daily note',
      );
      expect(
        rowFor(items, ItemRef(ItemType.note, weekly.id))?.detail,
        'Weekly note',
      );
    });

    test('a note with no title is called Untitled', () {
      final s = makeStore();
      final n = s.newNote(title: '', body: 'zebra thoughts');
      final item = s.paletteItems('zebra', today: friday).first;
      expect(item.action, PaletteOpen(ItemRef(ItemType.note, n.id)));
      expect(item.title, 'Untitled');
    });

    test('matching commands come before items', () {
      final s = makeStore();
      s.quickAdd('New shoes');
      final items = s.paletteItems('new', today: friday);
      expect(commandIds(items), [
        PaletteCommandId.newTask,
        PaletteCommandId.newNote,
      ]);
      expect(items[0].action, isA<PaletteRun>());
      expect(items[1].action, isA<PaletteRun>());
      expect(items[2].action, isA<PaletteOpen>());
    });

    test('nothing found means no rows', () {
      final s = makeStore();
      expect(s.paletteItems('qqqq', today: friday), isEmpty);
    });

    // Dates

    test('a day word offers "go to that day" first', () {
      final s = makeStore();
      s.newNote(title: 'Saturday plans');
      final items = s.paletteItems('sat', today: friday);
      expect(items.first.action, PaletteGoTo(saturday));
      expect(items.first.title, 'Go to tomorrow');
      expect(items.first.detail, 'Sat 3 Oct');
      // The search still runs.
      expect(items.any((i) => i.action is PaletteOpen), isTrue);
    });

    test('a far day reads as its weekday', () {
      final s = makeStore();
      final item = s.paletteItems('go to mon', today: friday).first;
      expect(item.action, PaletteGoTo(d('2026-10-05')));
      expect(item.title, 'Go to Monday');
    });

    test('today is offered once', () {
      final s = makeStore();
      final items = s.paletteItems('today', today: friday);
      expect(items.first.action, PaletteGoTo(friday));
      expect(commandIds(items), isNot(contains(PaletteCommandId.goToday)));
    });

    test('an arrow turns the date row off', () {
      final s = makeStore();
      final items = s.paletteItems('>sat', today: friday);
      expect(items.any((i) => i.action is PaletteGoTo), isFalse);
    });

    // Running a row

    test('going to another day shows it on the planner', () {
      final s = makeStore();
      s.screen = Screen.notes;
      s.paletteOpen = true;
      s.runPalette(s.paletteItems('sat', today: friday).first);
      expect(s.selectedDay, saturday);
      expect(s.screen, Screen.planner);
      expect(s.paletteOpen, isFalse);
    });

    test('opening an item closes the palette and opens it', () {
      final s = makeStore();
      final t = s.quickAdd(
        'Report taxes',
        placement: TaskPlacement.day(saturday),
      )!;
      s.paletteOpen = true;
      s.screen = Screen.notes;
      s.runPalette(s.paletteItems('report', today: friday).first);
      expect(s.paletteOpen, isFalse);
      expect(s.screen, Screen.planner);
      expect(s.selectedTaskId, t.id);
      expect(s.selectedDay, saturday);
    });

    test('New Task focuses the quick-add field', () {
      final s = makeStore();
      s.screen = Screen.notes;
      s.paletteOpen = true;
      final before = s.quickAddRequest;
      s.run(PaletteCommandId.newTask);
      expect(s.screen, Screen.today);
      expect(s.quickAddRequest, before + 1);
      expect(s.paletteOpen, isFalse);
    });

    test('New Task stays on the planner screen', () {
      final s = makeStore();
      s.screen = Screen.planner;
      s.run(PaletteCommandId.newTask);
      expect(s.screen, Screen.planner);
    });

    test('New Note makes one and shows it', () {
      final s = makeStore();
      s.paletteOpen = true;
      s.run(PaletteCommandId.newNote);
      expect(s.screen, Screen.notes);
      expect(s.paletteOpen, isFalse);
      expect(s.repos.notes.all().length, 1);
      expect(s.selectedNoteId, isNotNull);
    });

    test("Today's Note opens the daily note", () {
      final s = makeStore();
      s.run(PaletteCommandId.todayNote);
      final note = s.note(s.selectedNoteId!)!;
      expect(note.kind, NoteKind.daily);
      expect(note.date, DayKey.today());
      expect(s.screen, Screen.notes);
    });

    test('Go to Today moves the planner', () {
      final s = makeStore();
      s.selectedDay = DayKey.today().adding(days: 9);
      s.screen = Screen.notes;
      s.run(PaletteCommandId.goToday);
      expect(s.selectedDay, DayKey.today());
      expect(s.screen, Screen.today);
    });

    test('Plan My Day asks the today planner to open its plan', () {
      final s = makeStore();
      s.selectedDay = DayKey.today().adding(days: 3);
      s.screen = Screen.notes;
      final before = s.planMyDayRequest;
      s.run(PaletteCommandId.planMyDay);
      expect(s.screen, Screen.today);
      expect(s.selectedDay, DayKey.today());
      expect(s.planMyDayRequest, before + 1);
      expect(s.paletteOpen, isFalse);
    });

    test('the screen commands switch screens', () {
      final s = makeStore();
      s.run(PaletteCommandId.showNotes);
      expect(s.screen, Screen.notes);
      s.run(PaletteCommandId.showPlanner);
      expect(s.screen, Screen.planner);
      s.run(PaletteCommandId.showCalendar);
      expect(s.screen, Screen.calendar);
    });

    test('Go to Date keeps the palette open and asks for a day', () {
      final s = makeStore();
      s.paletteOpen = true;
      s.run(PaletteCommandId.goToDate);
      expect(s.paletteOpen, isTrue);
      expect(s.paletteText, 'go to ');
      expect(PaletteRules.asksForDay(s.paletteText), isTrue);
    });

    // Opening and closing

    test('toggling opens it empty and closes it', () {
      final s = makeStore();
      s.paletteText = 'old words';
      s.togglePalette();
      expect(s.paletteOpen, isTrue);
      expect(s.paletteText, '');
      s.togglePalette();
      expect(s.paletteOpen, isFalse);
    });
  });
}
