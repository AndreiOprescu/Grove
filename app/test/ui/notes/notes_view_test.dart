// The notes screen (milestone F9): the list, the search, the filters, the
// note itself with its side card, and the notes in the left panel.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/editor/markdown_controller.dart';
import 'package:grove/ui/notes/day_panel.dart';
import 'package:grove/ui/notes/note_editor_pane.dart';
import 'package:grove/ui/notes/notes_pane.dart';
import 'package:grove/ui/notes/notes_view.dart';
import 'package:grove/ui/settings/settings_tabs.dart' show saveSetting;

import '../planner/planner_support.dart';
import '../tasks/tasks_support.dart' show addTask;

AppStore notesStore() => plannerStore()..screen = Screen.notes;

Finder key(String name) => find.byKey(ValueKey(name));

Finder fieldOf(String name) =>
    find.descendant(of: key(name), matching: find.byType(EditableText));

String shown(WidgetTester tester, String name) =>
    tester.widget<EditableText>(fieldOf(name)).controller.text;

Future<void> tapKey(WidgetTester tester, String name) async {
  await tester.ensureVisible(key(name));
  await tester.pump();
  await tester.tap(key(name));
  await tester.pumpAndSettle();
}

List<TaskItem> openTasks(AppStore store) {
  final all = store.allOpenTasks();
  return [...all.noDay, ...all.byDay];
}

/// Takes the keyboard away from the field that has it.
Future<void> leaveField(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

/// The time the pane waits before it saves the text.
Future<void> waitForSave(WidgetTester tester) async {
  await tester.pump(NoteEditorPane.saveDelay);
  await tester.pump();
}

/// A click of a mouse, with a frame between the press and the release.
Future<void> mouseClick(WidgetTester tester, Finder target) async {
  final gesture = await tester.startGesture(
    tester.getCenter(target),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 80));
  await gesture.up();
  await tester.pump();
}

void main() {
  testWidgets('no notes: the screen says so, and "New note" makes one', (
    tester,
  ) async {
    final store = notesStore();
    await pumpPlanner(tester, store);
    expect(find.text('No notes here yet.'), findsOneWidget);
    expect(find.text('Your thoughts grow here.'), findsOneWidget);
    expect(find.byType(NoteEditorPane), findsNothing);

    await tapKey(tester, 'notes-empty-new');
    final note = store.notes().single;
    expect(store.selectedNoteId, note.id);
    expect(find.byType(NoteEditorPane), findsOneWidget);
    expect(shown(tester, 'note-title'), note.title);
    expect(key('note-row-${note.id}'), findsOneWidget);
    // the header button makes a second one
    await tapKey(tester, 'notes-new');
    expect(store.notes(), hasLength(2));
  });

  testWidgets('a click on a row opens that note', (tester) async {
    final store = notesStore();
    final a = store.newNote(title: 'Alpha', body: 'First line of alpha');
    final b = store.newNote(title: 'Beta', body: 'Beta text');
    store.selectedNoteId = null;
    await pumpPlanner(tester, store);
    expect(find.text('Pick a note, or start a new one.'), findsOneWidget);
    expect(find.text('First line of alpha'), findsOneWidget);

    await tapKey(tester, 'note-row-${a.id}');
    expect(store.selectedNoteId, a.id);
    expect(shown(tester, 'note-title'), 'Alpha');
    expect(shown(tester, 'note-text'), 'First line of alpha');

    await tapKey(tester, 'note-row-${b.id}');
    expect(shown(tester, 'note-title'), 'Beta');
    expect(shown(tester, 'note-text'), 'Beta text');
  });

  testWidgets('the search shows the notes that match, and can be cleared', (
    tester,
  ) async {
    final store = notesStore();
    final a = store.newNote(title: 'Alpha', body: 'apples');
    final b = store.newNote(title: 'Beta', body: 'pears');
    await pumpPlanner(tester, store);
    expect(key('notes-search-clear'), findsNothing);

    await tester.enterText(fieldOf('notes-search'), 'pear');
    await tester.pumpAndSettle();
    expect(store.noteQuery, 'pear');
    expect(key('note-row-${a.id}'), findsNothing);
    expect(key('note-row-${b.id}'), findsOneWidget);

    await tester.enterText(fieldOf('notes-search'), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Nothing matches.'), findsOneWidget);

    await tapKey(tester, 'notes-search-clear');
    expect(store.noteQuery, '');
    expect(shown(tester, 'notes-search'), '');
    expect(key('note-row-${a.id}'), findsOneWidget);
    expect(key('note-row-${b.id}'), findsOneWidget);
  });

  testWidgets('the filters: daily, weekly, pinned and a tag', (tester) async {
    final store = notesStore();
    final plain = store.newNote(title: 'Plain', body: 'about #garden');
    final other = store.newNote(title: 'Other', body: 'nothing');
    store.togglePin(other.id);
    final daily = store.dailyNote(wednesday);
    final weekly = store.weeklyNote(wednesday);
    await pumpPlanner(tester, store);
    Set<String> rows() => {
      for (final n in [plain, other, daily, weekly])
        if (key('note-row-${n.id}').evaluate().isNotEmpty) n.title,
    };

    expect(rows(), {'Plain', 'Other', daily.title, weekly.title});
    await tapKey(tester, 'notes-filter-daily');
    expect(rows(), {daily.title});
    await tapKey(tester, 'notes-filter-weekly');
    expect(rows(), {weekly.title});
    await tapKey(tester, 'notes-filter-pinned');
    expect(rows(), {'Other'});
    await tapKey(tester, 'notes-filter-tag-garden');
    expect(rows(), {'Plain'});
    expect(store.noteFilter, const NoteFilter.tag('garden'));
    await tapKey(tester, 'notes-filter-all');
    expect(rows(), hasLength(4));

    // the tag under the title of a note sets the same filter
    await tapKey(tester, 'note-row-${plain.id}');
    await tapKey(tester, 'note-tag-garden');
    expect(store.noteFilter, const NoteFilter.tag('garden'));
    expect(rows(), {'Plain'});
  });

  testWidgets('"Today" opens the note of today with the card of the day', (
    tester,
  ) async {
    final store = notesStore();
    store.createFromDraft(
      title: 'Standup',
      day: wednesday,
      start: 9 * 60,
      end: 10 * 60,
      asEvent: true,
    );
    await pumpPlanner(tester, store);
    await tapKey(tester, 'notes-today');
    final note = store.existingDailyNote(wednesday)!;
    expect(store.selectedNoteId, note.id);
    // the title of a daily note is not a field
    expect(key('note-title'), findsNothing);
    expect(find.text(note.title), findsWidgets);
    expect(find.textContaining('Daily note · Edited'), findsOneWidget);
    // the card of the day is beside the text
    expect(find.byType(DayPanel), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(DayPanel)).dx,
      greaterThan(tester.getTopRight(key('note-text')).dx),
    );
    expect(
      find.descendant(
        of: find.byType(DayPanel),
        matching: find.text('Standup'),
      ),
      findsOneWidget,
    );
    expect(find.text('Nothing finished yet.'), findsOneWidget);

    // the mood
    expect(store.note(note.id)!.mood, isNull);
    await tapKey(tester, 'mood-sun');
    expect(store.note(note.id)!.mood, Mood.sun.value);

    // "Open in planner" shows that day
    store.selectedDay = d('2026-10-20');
    await tapKey(tester, 'day-open-planner');
    expect(store.screen, Screen.planner);
    expect(store.selectedDay, wednesday);
  });

  testWidgets('the mood: each of the three, and a second click clears it', (
    tester,
  ) async {
    final store = notesStore();
    await pumpPlanner(tester, store);
    await tapKey(tester, 'notes-today');
    final id = store.existingDailyNote(wednesday)!.id;
    for (final m in Mood.values) {
      await tapKey(tester, 'mood-${m.name}');
      expect(store.note(id)!.mood, m.value, reason: m.name);
    }
    // the last one was the sun; a click on it again takes the mood away
    await tapKey(tester, 'mood-sun');
    expect(store.note(id)!.mood, isNull);
    await tapKey(tester, 'mood-rain');
    expect(store.note(id)!.mood, Mood.rain.value);
    await tapKey(tester, 'mood-cloud');
    expect(store.note(id)!.mood, Mood.cloud.value);
  });

  testWidgets('a finished task shows under "Done today" with its time', (
    tester,
  ) async {
    final store = notesStore();
    final task = addTask(store, 'Water the plants');
    addTask(store, 'Write the report');
    await pumpPlanner(tester, store);
    await tapKey(tester, 'notes-today');
    expect(find.text('Done today'), findsOneWidget);
    expect(find.text('Nothing finished yet.'), findsOneWidget);
    expect(key('done-${task.id}'), findsNothing);

    store.toggleDone(taskId: task.id);
    await tester.pumpAndSettle();
    expect(find.text('Nothing finished yet.'), findsNothing);
    expect(
      find.descendant(
        of: key('done-${task.id}'),
        matching: find.text('Water the plants'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: key('done-${task.id}'),
        matching: find.text(DayRules.finishedClock(store.task(task.id)!)),
      ),
      findsOneWidget,
    );
    // the open task is not in the list
    expect(key('done-write-the-report'), findsNothing);
    // the list is not written in the note
    expect(
      store.existingDailyNote(wednesday)!.body,
      isNot(contains('Water the plants')),
    );
  });

  testWidgets('the card of the week counts what is done and what is open', (
    tester,
  ) async {
    final store = notesStore();
    final done = addTask(store, 'Water the plants');
    final open = addTask(store, 'Write the report', day: d('2026-10-08'));
    store.toggleDone(taskId: done.id);
    await pumpPlanner(tester, store);
    await tapKey(tester, 'notes-week');
    final panel = find.byType(WeekReviewPanel);
    Finder inPanel(Finder f) => find.descendant(of: panel, matching: f);
    final review = store.weekReview(wednesday.weekStart());
    expect(titles(review.done), ['Water the plants']);
    expect(titles(review.open), ['Write the report']);
    // the two numbers, each over its word
    expect(inPanel(find.text('done')), findsOneWidget);
    expect(inPanel(find.text('still open')), findsOneWidget);
    expect(inPanel(find.text('1')), findsNWidgets(2));
    expect(inPanel(find.text('Finished')), findsOneWidget);
    expect(inPanel(find.text('Left open')), findsOneWidget);
    expect(
      find.descendant(
        of: key('week-task-${done.id}'),
        matching: find.text('Water the plants'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: key('week-task-${open.id}'),
        matching: find.text('Write the report'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('"This week" opens the note of the week; the summary goes in', (
    tester,
  ) async {
    final store = notesStore();
    await pumpPlanner(tester, store);
    await tapKey(tester, 'notes-week');
    final note = store.weeklyNote(wednesday);
    expect(store.selectedNoteId, note.id);
    expect(find.byType(WeekReviewPanel), findsOneWidget);
    expect(find.textContaining('Weekly note · Edited'), findsOneWidget);
    expect(find.text('Insert summary'), findsOneWidget);
    expect(DayRules.hasSummary(store.note(note.id)!.body), isFalse);

    await tapKey(tester, 'week-summary');
    final body = store.note(note.id)!.body;
    expect(DayRules.hasSummary(body), isTrue);
    expect(shown(tester, 'note-text'), body);
    expect(find.text('Update summary'), findsOneWidget);
    expect(find.text('Summary added to the note.'), findsOneWidget);
    await endToast(tester);
  });

  testWidgets('typed text is saved after a short wait', (tester) async {
    final store = notesStore();
    final note = store.newNote(title: 'Draft');
    await pumpPlanner(tester, store);
    await tester.enterText(fieldOf('note-text'), 'Hello there');
    await tester.pump();
    expect(store.note(note.id)!.body, '');
    await waitForSave(tester);
    expect(store.note(note.id)!.body, 'Hello there');
    // the row of the list follows
    expect(
      find.descendant(
        of: key('note-row-${note.id}'),
        matching: find.text('Hello there'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a box in the text makes a task when the typing ends', (
    tester,
  ) async {
    final store = notesStore();
    final note = store.newNote(title: 'Plan');
    await pumpPlanner(tester, store);
    await tester.enterText(fieldOf('note-text'), '- [ ] Water the plants');
    await waitForSave(tester);
    expect(store.note(note.id)!.body, '- [ ] Water the plants');
    expect(openTasks(store), isEmpty);

    await leaveField(tester);
    expect(titles(openTasks(store)), ['Water the plants']);
    // the saved text has the id of the task, and the field shows it
    final body = store.note(note.id)!.body;
    expect(body, isNot('- [ ] Water the plants'));
    expect(shown(tester, 'note-text'), body);
  });

  testWidgets('text that was not saved yet is saved when the note closes', (
    tester,
  ) async {
    final store = notesStore();
    final a = store.newNote(title: 'Alpha');
    final b = store.newNote(title: 'Beta');
    store.openNote(a.id);
    await pumpPlanner(tester, store);
    await tester.enterText(fieldOf('note-text'), 'Quick thought');
    await tester.pump();
    // before the wait is over, the user opens the other note
    await tapKey(tester, 'note-row-${b.id}');
    expect(store.note(a.id)!.body, 'Quick thought');
    expect(shown(tester, 'note-text'), '');
  });

  testWidgets('text that was not saved yet is saved when the app goes to the '
      'back', (tester) async {
    final store = notesStore();
    final note = store.newNote(title: 'Draft');
    await pumpPlanner(tester, store);
    await tester.enterText(fieldOf('note-text'), 'Half a thought');
    await tester.pump();
    expect(store.note(note.id)!.body, '');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(store.note(note.id)!.body, 'Half a thought');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    // the note is still open with the same text
    expect(shown(tester, 'note-text'), 'Half a thought');
  });

  testWidgets('text that was not saved yet is saved when the text loses the '
      'keyboard', (tester) async {
    final store = notesStore();
    final note = store.newNote(title: 'Draft');
    await pumpPlanner(tester, store);
    await tester.tap(fieldOf('note-text'));
    await tester.pump();
    await tester.enterText(fieldOf('note-text'), 'Half a thought');
    await tester.pump();
    expect(store.note(note.id)!.body, '');
    await leaveField(tester);
    expect(store.note(note.id)!.body, 'Half a thought');
  });

  testWidgets('a plain note says when it was edited; the rows keep the order '
      'of the store', (tester) async {
    final store = notesStore();
    final a = store.newNote(title: 'Alpha');
    final b = store.newNote(title: 'Beta');
    final c = store.newNote(title: 'Gamma');
    store.togglePin(b.id);
    store.openNote(a.id);
    await pumpPlanner(tester, store);
    // under the title: "Edited", the day and the time; no kind in front
    final line = tester.widget<Text>(find.textContaining('Edited')).data!;
    expect(line, startsWith('Edited '));
    expect(line, matches(RegExp(r', \d\d:\d\d$')));
    expect(find.textContaining('Daily note'), findsNothing);
    expect(find.textContaining('Weekly note'), findsNothing);

    // the store gives the pinned notes first, then the newest; the rows
    // follow that list from top to bottom
    final order = [for (final n in store.notes()) n.id];
    expect(order.first, b.id);
    expect(order.toSet(), {a.id, b.id, c.id});
    final tops = [
      for (final id in order) tester.getTopLeft(key('note-row-$id')).dy,
    ];
    expect(tops[0], lessThan(tops[1]));
    expect(tops[1], lessThan(tops[2]));
  });

  testWidgets('a change from outside shows in the open note', (tester) async {
    final store = notesStore();
    final note = store.newNote(title: 'Alpha', body: 'one');
    await pumpPlanner(tester, store);
    store.setNoteBody(note.id, 'two');
    await tester.pumpAndSettle();
    expect(shown(tester, 'note-text'), 'two');
    store.undo();
    await tester.pumpAndSettle();
    expect(shown(tester, 'note-text'), 'one');
    await endToast(tester);
    store.renameNote(note.id, to: 'Gamma');
    await tester.pumpAndSettle();
    expect(shown(tester, 'note-title'), 'Gamma');
  });

  testWidgets('the marks are hidden at first, and show as soon as the '
      'switch in Settings is on', (tester) async {
    final store = notesStore();
    store.newNote(title: 'Alpha', body: 'a **b**');
    await pumpPlanner(tester, store);
    MarkdownController text() =>
        tester.widget<EditableText>(fieldOf('note-text')).controller
            as MarkdownController;
    expect(text().showMarks, isFalse);
    saveSetting(store, EditorServices.showMarksKey, true);
    await tester.pumpAndSettle();
    expect(text().showMarks, isTrue);
    saveSetting(store, EditorServices.showMarksKey, false);
    await tester.pumpAndSettle();
    expect(text().showMarks, isFalse);
  });

  testWidgets('a task ticked somewhere else while the caret is in the note '
      'stays ticked when the note closes', (tester) async {
    final store = notesStore();
    final task = addTask(store, 'Water', id: 'T1');
    final a = store.newNote(title: 'Alpha', body: '- [ ] Water ⟦t:T1⟧\nx');
    final b = store.newNote(title: 'Beta');
    store.openNote(a.id);
    await pumpPlanner(tester, store);
    await tester.tap(fieldOf('note-text'));
    await tester.pump();
    await tester.enterText(fieldOf('note-text'), '- [ ] Water ⟦t:T1⟧\nxy');
    await waitForSave(tester);
    expect(store.note(a.id)!.body, '- [ ] Water ⟦t:T1⟧\nxy');

    // the caret is still in the text. The task is ticked in another place
    store.toggleDone(taskId: task.id);
    await tester.pumpAndSettle();
    expect(store.task('T1')!.isDone, isTrue);
    expect(store.note(a.id)!.body, '- [x] Water ⟦t:T1⟧\nxy');
    expect(shown(tester, 'note-text'), '- [x] Water ⟦t:T1⟧\nxy');

    await tapKey(tester, 'note-row-${b.id}');
    expect(store.note(a.id)!.body, '- [x] Water ⟦t:T1⟧\nxy');
    expect(store.task('T1')!.isDone, isTrue);
    await endToast(tester);
  });

  testWidgets('text that came from outside is not lost when the app goes to '
      'the back', (tester) async {
    final store = notesStore();
    final note = store.newNote(title: 'Alpha', body: 'one');
    await pumpPlanner(tester, store);
    await tester.tap(fieldOf('note-text'));
    await tester.pump();
    await tester.enterText(fieldOf('note-text'), 'one two');
    await waitForSave(tester);
    store.setNoteBody(note.id, 'from the other device');
    await tester.pumpAndSettle();
    expect(shown(tester, 'note-text'), 'from the other device');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(store.note(note.id)!.body, 'from the other device');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });

  testWidgets('text that is not saved yet stays when a change comes from '
      'outside', (tester) async {
    final store = notesStore();
    final note = store.newNote(title: 'Alpha', body: 'one');
    await pumpPlanner(tester, store);
    await tester.enterText(fieldOf('note-text'), 'one two');
    await tester.pump();
    // before the save, another change of the store comes
    store.togglePin(note.id);
    await tester.pumpAndSettle();
    expect(shown(tester, 'note-text'), 'one two');
    await waitForSave(tester);
    expect(store.note(note.id)!.body, 'one two');
  });

  testWidgets('a change of the text from outside while the caret is in the '
      'title is kept', (tester) async {
    final store = notesStore();
    final a = store.newNote(title: 'Alpha', body: 'old text');
    final b = store.newNote(title: 'Beta');
    store.openNote(a.id);
    await pumpPlanner(tester, store);
    await tester.tap(fieldOf('note-title'));
    await tester.pump();
    store.setNoteBody(a.id, 'new text from the other device');
    await tester.pumpAndSettle();
    expect(shown(tester, 'note-text'), 'new text from the other device');
    // a new name from outside shows too: the user typed no name
    store.renameNote(a.id, to: 'Gamma');
    await tester.pumpAndSettle();
    expect(shown(tester, 'note-title'), 'Gamma');

    await tapKey(tester, 'note-row-${b.id}');
    expect(store.note(a.id)!.body, 'new text from the other device');
    expect(store.note(a.id)!.title, 'Gamma');
  });

  testWidgets('a name the user is typing stays when a change comes from '
      'outside', (tester) async {
    final store = notesStore();
    final note = store.newNote(title: 'Alpha');
    await pumpPlanner(tester, store);
    await tester.tap(fieldOf('note-title'));
    await tester.pump();
    await tester.enterText(fieldOf('note-title'), 'Trav');
    store.renameNote(note.id, to: 'Gamma');
    await tester.pumpAndSettle();
    expect(shown(tester, 'note-title'), 'Trav');
    await leaveField(tester);
    expect(store.note(note.id)!.title, 'Trav');
  });

  testWidgets('"Delete note" right after a key: undo brings back the note '
      'with that key', (tester) async {
    final store = notesStore();
    final note = store.newNote(title: 'Alpha', body: 'old');
    await pumpPlanner(tester, store);
    await tester.tap(fieldOf('note-text'));
    await tester.pump();
    await tester.enterText(fieldOf('note-text'), 'old and much new text');
    await tester.pump();
    await tester.tap(key('note-menu'));
    await tester.pump();
    // the menu opens in 300 ms, the save waits 500 ms. The menu takes the
    // keyboard, so the text is saved before the wait is over
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.tap(find.text('Delete note'));
    await tester.pumpAndSettle();
    expect(store.note(note.id), isNull);
    store.undo();
    await tester.pumpAndSettle();
    expect(store.note(note.id)!.body, 'old and much new text');
    await endToast(tester);
  });

  testWidgets('"Duplicate" right after a key: the copy has that key', (
    tester,
  ) async {
    final store = notesStore();
    final note = store.newNote(title: 'Alpha', body: 'old');
    await pumpPlanner(tester, store);
    await tester.tap(fieldOf('note-text'));
    await tester.pump();
    await tester.enterText(fieldOf('note-text'), 'old and new');
    await tester.pump();
    await tester.tap(key('note-menu'));
    await tester.pump();
    // the menu opens in 300 ms, the save waits 500 ms. The menu takes the
    // keyboard, so the text is saved before the wait is over
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();
    final copy = store.notes().firstWhere((n) => n.id != note.id);
    expect(copy.body, 'old and new');
    await endToast(tester);
  });

  testWidgets(
    'a click of a mouse on "Bold" does not end the typing: the open box '
    'keeps its line and the word is bold',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      final store = notesStore();
      final note = store.newNote(title: 'Plan');
      await pumpPlanner(tester, store);
      await tester.tap(fieldOf('note-text'), kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.enterText(
        fieldOf('note-text'),
        '- [ ] Water the plants\nmake this loud',
      );
      await tester.pump();
      final field = tester.widget<EditableText>(fieldOf('note-text'));
      final at = field.controller.text.indexOf('this');
      field.controller.selection = TextSelection(
        baseOffset: at,
        extentOffset: at + 4,
      );
      await tester.pump();
      await mouseClick(tester, find.bySemanticsLabel('Bold'));
      expect(
        shown(tester, 'note-text'),
        '- [ ] Water the plants\nmake **this** loud',
      );
      expect(field.focusNode.hasFocus, isTrue);
      expect(openTasks(store), isEmpty);
      await waitForSave(tester);
      expect(
        store.note(note.id)!.body,
        '- [ ] Water the plants\nmake **this** loud',
      );

      // the typing ends: the box makes its task, and the mark is whole
      await leaveField(tester);
      expect(titles(openTasks(store)), ['Water the plants']);
      final id = openTasks(store).single.id;
      expect(
        store.note(note.id)!.body,
        '- [ ] Water the plants ⟦t:$id⟧\nmake **this** loud',
      );
    },
  );

  testWidgets(
    'a click of a mouse on "Add to planner" adds the line with the caret',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      final store = notesStore();
      store.newNote(title: 'Plan');
      await pumpPlanner(tester, store);
      await tester.tap(fieldOf('note-text'), kind: PointerDeviceKind.mouse);
      await tester.pump();
      const text = '- [ ] Water the plants\n- [ ] Feed the cat\nlunch @fri 1pm';
      await tester.enterText(fieldOf('note-text'), text);
      await tester.pump();
      final field = tester.widget<EditableText>(fieldOf('note-text'));
      field.controller.selection = const TextSelection.collapsed(
        offset: text.length,
      );
      await tester.pump();
      await mouseClick(tester, find.text('Add to planner'));
      await tester.pump();
      expect(find.textContaining('Added to the planner'), findsOneWidget);
      expect(
        shown(tester, 'note-text'),
        startsWith('- [ ] Water the plants\n- [ ] Feed the cat\n[[lunch|'),
      );
      expect(field.focusNode.hasFocus, isTrue);
      await endToast(tester);
    },
  );

  testWidgets('the title: Return renames, an empty title goes back', (
    tester,
  ) async {
    final store = notesStore();
    final note = store.newNote(title: 'Alpha');
    await pumpPlanner(tester, store);
    await tester.enterText(fieldOf('note-title'), 'Travel plans');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(store.note(note.id)!.title, 'Travel plans');

    await tester.enterText(fieldOf('note-title'), '  ');
    await leaveField(tester);
    expect(store.note(note.id)!.title, 'Travel plans');
    expect(shown(tester, 'note-title'), 'Travel plans');

    // a new title is also kept when the field loses the keyboard
    await tester.enterText(fieldOf('note-title'), 'Trips');
    await leaveField(tester);
    expect(store.note(note.id)!.title, 'Trips');
  });

  testWidgets('pin, duplicate and delete from the header of the note', (
    tester,
  ) async {
    final store = notesStore();
    final note = store.newNote(title: 'Alpha', body: 'text');
    await pumpPlanner(tester, store);
    await tapKey(tester, 'note-pin');
    expect(store.note(note.id)!.pinned, isTrue);
    await tapKey(tester, 'note-pin');
    expect(store.note(note.id)!.pinned, isFalse);

    await tapKey(tester, 'note-menu');
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();
    expect(store.notes(), hasLength(2));

    store.openNote(note.id);
    await tester.pumpAndSettle();
    await tapKey(tester, 'note-menu');
    await tester.tap(find.text('Delete note'));
    await tester.pumpAndSettle();
    expect(store.note(note.id), isNull);
    expect(store.notes(), hasLength(1));
    expect(find.textContaining('Note deleted.'), findsOneWidget);
    await endToast(tester);
    // undo brings it back
    store.undo();
    await tester.pumpAndSettle();
    expect(store.note(note.id), isNotNull);
    await endToast(tester);
  });

  testWidgets('a right click on a row: pin and delete', (tester) async {
    final store = notesStore();
    final a = store.newNote(title: 'Alpha');
    final b = store.newNote(title: 'Beta');
    await pumpPlanner(tester, store);
    Future<void> menu(String id, String line) async {
      await tester.tapAt(
        tester.getCenter(key('note-row-$id')),
        buttons: kSecondaryButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(line));
      await tester.pumpAndSettle();
    }

    await menu(a.id, 'Pin');
    expect(store.note(a.id)!.pinned, isTrue);
    // a pinned note is first
    expect(store.notes().first.id, a.id);
    expect(
      tester.getTopLeft(key('note-row-${a.id}')).dy,
      lessThan(tester.getTopLeft(key('note-row-${b.id}')).dy),
    );
    await menu(a.id, 'Unpin');
    expect(store.note(a.id)!.pinned, isFalse);
    await menu(b.id, 'Delete');
    expect(store.note(b.id), isNull);
  });

  testWidgets('"Linked here" lists what mentions the note', (tester) async {
    final store = notesStore();
    final target = store.newNote(title: 'Target');
    final from = store.newNote(
      title: 'Source',
      body: 'See [[Target|${target.id}]]',
    );
    store.openNote(target.id);
    await pumpPlanner(tester, store);
    expect(find.text('Linked here'), findsOneWidget);
    await tapKey(tester, 'note-linked-${from.id}');
    expect(store.selectedNoteId, from.id);
  });

  testWidgets('a note that is deleted under the screen', (tester) async {
    final store = notesStore();
    final a = store.newNote(title: 'Alpha');
    await pumpPlanner(tester, store);
    expect(find.byType(NoteEditorPane), findsOneWidget);
    store.deleteNote(a.id);
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorPane), findsNothing);
    expect(find.text('Your thoughts grow here.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a narrow window puts the card of the day under the text', (
    tester,
  ) async {
    final store = notesStore();
    store.openDailyNote(wednesday);
    await pumpPlanner(tester, store, size: const Size(840, 620));
    expect(tester.takeException(), isNull);
    final card = tester.getRect(find.byType(DayPanel));
    final text = tester.getRect(key('note-text'));
    expect(card.top, greaterThan(text.bottom));
  });

  testWidgets('a phone shows the list, then the note with a way back', (
    tester,
  ) async {
    final store = notesStore();
    final a = store.newNote(title: 'Alpha', body: 'text of alpha');
    store.selectedNoteId = null;
    await pumpPlanner(tester, store, size: phoneSize);
    expect(tester.takeException(), isNull);
    expect(find.byType(NotesList), findsOneWidget);
    expect(find.byType(NoteEditorPane), findsNothing);

    await tapKey(tester, 'note-row-${a.id}');
    expect(find.byType(NotesList), findsNothing);
    expect(find.byType(NoteEditorPane), findsOneWidget);
    expect(shown(tester, 'note-text'), 'text of alpha');
    expect(tester.takeException(), isNull);

    await tapKey(tester, 'note-back');
    expect(store.selectedNoteId, isNull);
    expect(find.byType(NotesList), findsOneWidget);

    // a daily note fits too: the card of the day is under the text
    await tapKey(tester, 'notes-today');
    expect(tester.takeException(), isNull);
    expect(find.byType(DayPanel), findsOneWidget);
  });

  testWidgets('the notes in the left panel: a click opens a note', (
    tester,
  ) async {
    final store = plannerStore();
    final a = store.newNote(title: 'Alpha');
    store.newNote(title: 'Beta');
    store
      ..screen = Screen.planner
      ..leftPane = LeftPane.notes;
    await pumpPlanner(tester, store);
    expect(find.byType(NotesPane), findsOneWidget);
    expect(find.text('2 notes'), findsOneWidget);
    expect(NotesPane.count(0), 'No notes');
    expect(NotesPane.count(1), '1 note');

    await tester.tap(key('pane-note-${a.id}'));
    await tester.pumpAndSettle();
    expect(store.screen, Screen.notes);
    expect(store.selectedNoteId, a.id);
  });

  testWidgets('a note dragged from the left panel onto the planner gets a '
      'time', (tester) async {
    final store = plannerStore();
    final a = store.newNote(title: 'Alpha');
    store
      ..screen = Screen.planner
      ..leftPane = LeftPane.notes;
    await pumpPlanner(tester, store);
    final from = tester.getCenter(key('pane-note-${a.id}'));
    final to = pointAt(tester, wednesday, 9 * 60);
    final gesture = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    for (var i = 1; i <= 8; i++) {
      await gesture.moveTo(Offset.lerp(from, to, i / 8)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    final block = blockNamed(store, '📝 Alpha');
    expect(block.day, wednesday);
    expect(block.startMinute, 9 * 60);
    // the drag did not open the note
    expect(store.screen, Screen.planner);
  });
}
