// The linked note of a block, through the screen (PLAN §5.1.2: "a small ✎
// icon if linked notes exist"; §5.1.4: "Open / create linked note" in the
// menu of a block). Card Q-35, answer A: the linked note is the meeting note
// of the block.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'planner_support.dart';

/// A line of the open menu.
Finder menuLine(String label) =>
    find.widgetWithText(PopupMenuItem<VoidCallback>, label);

/// Clicks a line of the open menu.
Future<void> pick(WidgetTester tester, String label) async {
  await tester.tap(menuLine(label));
  await tester.pumpAndSettle();
}

const create = 'Create Linked Note';
const open = 'Open Linked Note';

Finder pencil(String blockId) => find.byKey(ValueKey('block-note-$blockId'));

/// A block from `start` on Wednesday, one hour long. Gives its id.
String addBlock(
  AppStore store,
  String title, {
  bool asEvent = false,
  int start = 11 * 60,
}) {
  store.createFromDraft(
    title: title,
    day: wednesday,
    start: start,
    end: start + 60,
    asEvent: asEvent,
  );
  return blockNamed(store, title).id;
}

/// The middle of the block on the screen.
Offset middle(WidgetTester tester, String blockId) =>
    tester.getCenter(blockFinder(blockId));

/// The notes of the store that are not the note of a day or a week.
List<Note> plainNotes(AppStore store) => [
  for (final n in store.repos.notes.all())
    if (n.kind == NoteKind.note) n,
];

void main() {
  /// The three kinds of block. Each gives the id of its block.
  final kinds = <String, String Function(AppStore store)>{
    'an event': (store) => addBlock(store, 'Design review', asEvent: true),
    'a task block': (store) => addBlock(store, 'Design review'),
    'a goal block': goalBlock,
  };

  group('the menu line of the linked note', () {
    for (final MapEntry(key: kind, value: make) in kinds.entries) {
      testWidgets('$kind: the line makes the note and shows it', (
        tester,
      ) async {
        final store = plannerStore();
        final id = make(store);
        final title = store.event(id)!.title;
        await pumpPlanner(tester, store);
        expect(pencil(id), findsNothing);

        await rightClick(tester, middle(tester, id));
        expect(menuLine(create), findsOneWidget);
        expect(menuLine(open), findsNothing);
        await pick(tester, create);

        // The note is made, it is the meeting note of the block, and the
        // Notes screen shows it.
        final note = plainNotes(store).single;
        expect(note.title, '$title — 7 Oct');
        expect(note.body, startsWith('Meeting: [[$title|$id]]'));
        expect(store.meetingNote(store.event(id)!)?.id, note.id);
        expect(store.screen, Screen.notes);
        expect(store.selectedNoteId, note.id);
        expect(store.undoName, 'New Meeting Note');
        expect(find.text('$title — 7 Oct'), findsWidgets);
      });

      testWidgets('$kind: with a note, the block has the pencil and the line '
          'opens the same note', (tester) async {
        final store = plannerStore();
        final id = make(store);
        final note = store.createMeetingNote(store.event(id)!)!;
        store.screen = Screen.planner;
        await pumpPlanner(tester, store);

        expect(pencil(id), findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp('Has a linked note')),
          findsOneWidget,
        );

        await rightClick(tester, middle(tester, id));
        expect(menuLine(open), findsOneWidget);
        expect(menuLine(create), findsNothing);
        await pick(tester, open);

        expect(plainNotes(store).single.id, note.id);
        expect(store.screen, Screen.notes);
        expect(store.selectedNoteId, note.id);
      });
    }

    testWidgets('the line is after "Split in Two", as in the plan', (
      tester,
    ) async {
      final store = plannerStore();
      final id = addBlock(store, 'Lunch');
      await pumpPlanner(tester, store);
      await rightClick(tester, middle(tester, id));

      final split = tester.getRect(menuLine('Split in Two'));
      final note = tester.getRect(menuLine(create));
      final done = tester.getRect(menuLine('Mark Done'));
      expect(note.top, split.bottom);
      expect(done.top, note.bottom);
    });

    testWidgets('with two blocks selected, the line is for the block under '
        'the pointer', (tester) async {
      final store = plannerStore();
      final a = addBlock(store, 'Lunch');
      final b = addBlock(store, 'Walk', start: 13 * 60);
      store.selection = {a, b};
      await pumpPlanner(tester, store);

      await rightClick(tester, middle(tester, b));
      await pick(tester, create);

      expect(plainNotes(store).single.title, 'Walk — 7 Oct');
      expect(store.meetingNote(store.event(a)!), isNull);
    });

    testWidgets('a day of a repeating event gets its own note', (tester) async {
      final store = plannerStore();
      store.saveEvent(
        EventItem(
          id: 'SERIES',
          title: 'Standup',
          start: WallTime(day: wednesday.adding(days: -7), minute: 11 * 60),
          end: WallTime(day: wednesday.adding(days: -7), minute: 12 * 60),
          recurrence: RecurrenceRule(freq: Freq.weekly),
        ),
        from: null,
      );
      store.createMeetingNote(store.event('SERIES@2026-09-30')!);
      store
        ..selectedDay = wednesday
        ..screen = Screen.planner;
      await pumpPlanner(tester, store);

      // The note of last week is not the note of this day.
      expect(pencil('SERIES@2026-10-07'), findsNothing);
      await rightClick(tester, middle(tester, 'SERIES@2026-10-07'));
      await pick(tester, create);

      expect(
        {for (final n in plainNotes(store)) n.title},
        {'Standup — 30 Sep', 'Standup — 7 Oct'},
      );
      expect(store.selectedNoteId, isNot(plainNotes(store).first.id));
    });
  });

  group('the pencil follows the store', () {
    testWidgets('the pencil comes with the note and goes with it', (
      tester,
    ) async {
      final store = plannerStore();
      final id = addBlock(store, 'Design review');
      final other = addBlock(store, 'Lunch', start: 13 * 60);
      await pumpPlanner(tester, store);
      expect(pencil(id), findsNothing);

      final note = store.createMeetingNote(store.event(id)!)!;
      store.screen = Screen.planner;
      await tester.pumpAndSettle();
      expect(pencil(id), findsOneWidget);
      expect(pencil(other), findsNothing);

      store.deleteNote(note.id);
      await tester.pumpAndSettle();
      expect(pencil(id), findsNothing);

      store.undo();
      await tester.pumpAndSettle();
      expect(pencil(id), findsOneWidget);
      await endToast(tester);
    });

    testWidgets('"Unschedule" and then Undo: the block has its pencil again', (
      tester,
    ) async {
      final store = plannerStore();
      final id = addBlock(store, 'Design review');
      store.createMeetingNote(store.event(id)!);
      store.screen = Screen.planner;
      await pumpPlanner(tester, store);

      await rightClick(tester, middle(tester, id));
      await pick(tester, 'Unschedule');
      expect(blockFinder(id), findsNothing);

      store.undo();
      await tester.pumpAndSettle();
      expect(pencil(id), findsOneWidget);
      await endToast(tester);
    });
  });
}
