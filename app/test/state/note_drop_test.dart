// Port of Tests/GroveTests/NoteDropTests.swift.
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const day = DayKey('2026-10-06');
const today = DayRange.single(day);

void main() {
  test('a note makes a half-hour event linked to it', () {
    final s = makeStore();
    final n = s.newNote(title: 'Trip plan');
    final e = s.addNoteToPlanner(n.id, on: day, at: 600)!;
    final saved = s.event(e.id)!;
    expect(saved.title, '📝 Trip plan');
    expect(saved.kind, EventKind.event);
    expect(saved.allDay, isFalse);
    expect(saved.start, const WallTime(day: day, minute: 600));
    expect(saved.end, const WallTime(day: day, minute: 630));
    expect(saved.notes, '[[Trip plan|${n.id}]]');
    expect(
      [for (final l in s.linkedItems(ItemRef(ItemType.note, n.id))) l.ref],
      [ItemRef(ItemType.event, e.id)],
    );
    expect(s.selection, {e.id});
    expect(s.undoName, 'Add Note to Planner');
  });

  test('a drop near midnight stays inside the day', () {
    final s = makeStore();
    final n = s.newNote(title: 'Late');
    final e = s.addNoteToPlanner(n.id, on: day, at: 1435)!;
    expect(e.end.minute, lessThanOrEqualTo(1440));
    expect(e.end.minute - e.start.minute, 30);
    expect(e.start.day, day);
    expect(e.end.day, day);
  });

  test('a note with no title gets a name', () {
    final s = makeStore();
    final n = s.newNote(title: '  ');
    final e = s.addNoteToPlanner(n.id, on: day, at: 600)!;
    expect(e.title, '📝 Untitled');
  });

  test('a missing note makes nothing', () {
    final s = makeStore();
    expect(s.addNoteToPlanner('missing', on: day, at: 600), isNull);
    expect(s.repos.events.all(), isEmpty);
  });

  test('one undo removes the event and the link', () {
    final s = makeStore();
    final n = s.newNote(title: 'Trip plan');
    s.addNoteToPlanner(n.id, on: day, at: 600);
    s.undo();
    expect(s.eventItems(today), isEmpty);
    expect(s.linkedItems(ItemRef(ItemType.note, n.id)), isEmpty);
    s.redo();
    expect(s.eventItems(today).length, 1);
    expect(s.linkedItems(ItemRef(ItemType.note, n.id)).length, 1);
  });

  test('the same note can go on twice', () {
    final s = makeStore();
    final n = s.newNote(title: 'Trip plan');
    s.addNoteToPlanner(n.id, on: day, at: 600);
    s.addNoteToPlanner(n.id, on: day, at: 900);
    expect(s.eventItems(today).length, 2);
  });

  test('the drag text holds the note id and not a task id', () {
    expect(DragPayload.noteId(DragPayload.note('ABC')), 'ABC');
    expect(DragPayload.noteId(DragPayload.task('ABC')), isNull);
    expect(DragPayload.noteId('plain text'), isNull);
    expect(DragPayload.note('ABC'), isNot(DragPayload.task('ABC')));
  });
}
