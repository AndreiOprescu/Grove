// The linked note of a planner block (PLAN §5.1.2 and §5.1.4, card Q-35,
// answer A): it is the meeting note of the block. `PlannerBlock.hasNote` says
// that the block has one.
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const friday = DayKey('2026-10-02');
const saturday = DayKey('2026-10-03');
const seriesId = 'AAAAAAAA-1111-2222-3333-444444444444';

const days = DayRange(DayKey('2026-09-28'), DayKey('2026-10-18'));

PlannerBlock block(AppStore s, String id) =>
    s.blocks(days).firstWhere((b) => b.id == id);

bool flag(AppStore s, String id) => block(s, id).hasNote;

/// A plain event from 9:00 to 10:00 on Friday. Gives its id.
String eventBlock(AppStore s, String title, {int start = 540}) {
  final before = {for (final b in s.blocks(days)) b.id};
  s.createFromDraft(
    title: title,
    day: friday,
    start: start,
    end: start + 60,
    asEvent: true,
  );
  return s.blocks(days).firstWhere((b) => !before.contains(b.id)).id;
}

/// A task with a block from 10:00 to 11:00 on Friday. Gives the id of the block.
String taskBlock(AppStore s, String title, {int start = 600}) {
  final before = {for (final b in s.blocks(days)) b.id};
  s.createFromDraft(
    title: title,
    day: friday,
    start: start,
    end: start + 60,
    asEvent: false,
  );
  return s.blocks(days).firstWhere((b) => !before.contains(b.id)).id;
}

/// A block of the goal "Read" from 11:00 to 12:30 on Friday. Gives its id.
String goalBlock(AppStore s) {
  final goal = s.addGoal(title: 'Read', target: 300)!;
  final before = {for (final b in s.blocks(days)) b.id};
  s.scheduleGoal(goalId: goal.id, day: friday, start: 660, length: 90);
  return s.blocks(days).firstWhere((b) => !before.contains(b.id)).id;
}

void saveSeries(AppStore s) => s.saveEvent(
  EventItem(
    id: seriesId,
    title: 'Standup',
    start: const WallTime(day: friday, minute: 540),
    end: const WallTime(day: friday, minute: 570),
    recurrence: RecurrenceRule(freq: Freq.weekly),
  ),
  from: null,
);

ItemRef noteRef(String id) => ItemRef(ItemType.note, id);
ItemRef eventRef(String id) => ItemRef(ItemType.event, id);

void main() {
  group('the note of each kind of block', () {
    test('an event block: the note is made, linked and shown', () {
      final s = makeStore();
      final id = eventBlock(s, 'Team sync');
      expect(block(s, id).kind, EventKind.event);
      expect(flag(s, id), isFalse);

      final n = s.createMeetingNote(s.event(id)!)!;
      expect(n.title, 'Team sync — 2 Oct');
      expect(s.note(n.id)?.body, startsWith('Meeting: [[Team sync|$id]]'));
      expect(s.screen, Screen.notes);
      expect(s.selectedNoteId, n.id);
      expect(flag(s, id), isTrue);
    });

    test('a task block: the note is made, linked to the block and shown', () {
      final s = makeStore();
      final id = taskBlock(s, 'Write report');
      expect(block(s, id).isTaskBlock, isTrue);
      expect(flag(s, id), isFalse);

      final n = s.createMeetingNote(s.event(id)!)!;
      expect(n.title, 'Write report — 2 Oct');
      expect(s.note(n.id)?.body, startsWith('Meeting: [[Write report|$id]]'));
      expect(
        [for (final l in s.linkedItems(eventRef(id))) l.ref],
        [noteRef(n.id)],
      );
      expect(s.screen, Screen.notes);
      expect(s.selectedNoteId, n.id);
      expect(s.meetingNote(s.event(id)!)?.id, n.id);
      expect(flag(s, id), isTrue);
      // The task and the block are as they were.
      expect(block(s, id).title, 'Write report');
      expect(s.task(block(s, id).taskId!)?.status, TaskStatus.open);
    });

    test('a goal block: the note is made, linked to the block and shown', () {
      final s = makeStore();
      final id = goalBlock(s);
      expect(block(s, id).isGoalBlock, isTrue);
      expect(flag(s, id), isFalse);

      final n = s.createMeetingNote(s.event(id)!)!;
      expect(n.title, 'Read — 2 Oct');
      expect(s.note(n.id)?.body, startsWith('Meeting: [[Read|$id]]'));
      expect(
        [for (final l in s.linkedItems(eventRef(id))) l.ref],
        [noteRef(n.id)],
      );
      expect(s.screen, Screen.notes);
      expect(s.selectedNoteId, n.id);
      expect(s.meetingNote(s.event(id)!)?.id, n.id);
      expect(flag(s, id), isTrue);
      expect(block(s, id).goalId, isNotNull);
    });

    test('asking again opens the same note, for each kind of block', () {
      final s = makeStore();
      final ids = [
        eventBlock(s, 'Team sync'),
        taskBlock(s, 'Write report'),
        goalBlock(s),
      ];
      for (final id in ids) {
        final first = s.createMeetingNote(s.event(id)!)!;
        s.screen = Screen.planner;
        final second = s.createMeetingNote(s.event(id)!)!;
        expect(second.id, first.id);
        expect(s.screen, Screen.notes);
        expect(s.selectedNoteId, first.id);
      }
      expect(s.repos.notes.all().length, 3);
    });

    test('one undo takes the note and the flag away, redo gives both back', () {
      final s = makeStore();
      final ids = [
        eventBlock(s, 'Team sync'),
        taskBlock(s, 'Write report'),
        goalBlock(s),
      ];
      for (final id in ids) {
        final n = s.createMeetingNote(s.event(id)!)!;
        expect(s.undoName, 'New Meeting Note');
        s.undo();
        expect(s.note(n.id), isNull);
        expect(flag(s, id), isFalse);
        s.redo();
        expect(s.note(n.id), isNotNull);
        expect(flag(s, id), isTrue);
      }
    });
  });

  group('which block has the flag', () {
    test('only the block with the note, not one with the same name', () {
      final s = makeStore();
      final a = taskBlock(s, 'Write report');
      final b = taskBlock(s, 'Write report', start: 720);
      s.createMeetingNote(s.event(a)!);
      expect(flag(s, a), isTrue);
      expect(flag(s, b), isFalse);
    });

    test('a note that only mentions the block gives no flag', () {
      final s = makeStore();
      final ids = [
        eventBlock(s, 'Team sync'),
        taskBlock(s, 'Write report'),
        goalBlock(s),
      ];
      for (final id in ids) {
        s.newNote(title: 'Ideas $id', body: 'Think of [[x|$id]]');
        expect(s.linkedItems(eventRef(id)), hasLength(1));
        expect(flag(s, id), isFalse);
      }
    });

    test('each day of a repeating event has its own flag', () {
      final s = makeStore();
      saveSeries(s);
      s.createMeetingNote(s.event('$seriesId@2026-10-09')!);
      expect(flag(s, '$seriesId@2026-10-09'), isTrue);
      expect(flag(s, '$seriesId@2026-10-02'), isFalse);
      expect(flag(s, '$seriesId@2026-10-16'), isFalse);
      s.createMeetingNote(s.event('$seriesId@2026-10-02')!);
      expect(flag(s, '$seriesId@2026-10-02'), isTrue);
      expect(flag(s, '$seriesId@2026-10-16'), isFalse);
      expect(s.repos.notes.all().length, 2);
    });

    test('a deleted note takes the flag away, undo gives it back', () {
      final s = makeStore();
      final ids = [
        eventBlock(s, 'Team sync'),
        taskBlock(s, 'Write report'),
        goalBlock(s),
      ];
      for (final id in ids) {
        final n = s.createMeetingNote(s.event(id)!)!;
        s.deleteNote(n.id);
        expect(flag(s, id), isFalse);
        s.undo();
        expect(flag(s, id), isTrue);
      }
    });

    test('a block that is deleted and comes back with undo keeps its note', () {
      final s = makeStore();
      final ids = [
        eventBlock(s, 'Team sync'),
        taskBlock(s, 'Write report'),
        goalBlock(s),
      ];
      for (final id in ids) {
        final n = s.createMeetingNote(s.event(id)!)!;
        s.deleteBlocks([id]);
        expect(s.event(id), isNull);
        // The note stays in Notes.
        expect(s.note(n.id), isNotNull);
        s.undo();
        expect(s.meetingNote(s.event(id)!)?.id, n.id, reason: n.title);
        expect(flag(s, id), isTrue, reason: n.title);
        // The menu line opens the old note and makes no second one.
        expect(s.createMeetingNote(s.event(id)!)?.id, n.id);
      }
      expect(s.repos.notes.all().length, 3);
    });

    test('a block moved in its day keeps its note', () {
      final s = makeStore();
      final ids = [
        eventBlock(s, 'Team sync'),
        taskBlock(s, 'Write report'),
        goalBlock(s),
      ];
      for (final (i, id) in ids.indexed) {
        s.createMeetingNote(s.event(id)!);
        s.applyEdits(
          [
            BlockEdit(
              id: id,
              day: friday,
              start: 900 + i * 60,
              end: 945 + i * 60,
            ),
          ],
          ripple: false,
          name: 'Move Block',
        );
        expect(block(s, id).startMinute, 900 + i * 60);
        expect(flag(s, id), isTrue);
      }
    });

    // The rule of the card of an event: the meeting note is found by its
    // title, "name — day". Card Q-36 asks the owner if it stays.
    test('a new name or a new day: the old note is no longer the note of the '
        'block (Q-36)', () {
      final s = makeStore();
      final renamed = taskBlock(s, 'Write report');
      final moved = goalBlock(s);
      final a = s.createMeetingNote(s.event(renamed)!)!;
      final b = s.createMeetingNote(s.event(moved)!)!;

      s.rename(blockId: renamed, to: 'Write the report');
      expect(flag(s, renamed), isFalse);
      s.undo();
      expect(flag(s, renamed), isTrue);

      s.applyEdits(
        [BlockEdit(id: moved, day: saturday, start: 660, end: 750)],
        ripple: false,
        name: 'Move Block',
      );
      expect(flag(s, moved), isFalse);
      s.undo();
      expect(flag(s, moved), isTrue);
      // The notes are still in Notes.
      expect(s.note(a.id), isNotNull);
      expect(s.note(b.id), isNotNull);
    });

    test('the flag is right for a week of blocks', () {
      final s = makeStore();
      final withNote = <String>{};
      final all = <String>[];
      for (var i = 0; i < 12; i++) {
        final id = i.isEven
            ? taskBlock(s, 'Task $i', start: 480 + i * 60)
            : eventBlock(s, 'Event $i', start: 480 + i * 60);
        all.add(id);
        if (i % 3 == 0) {
          s.createMeetingNote(s.event(id)!);
          withNote.add(id);
        }
      }
      expect({
        for (final b in s.blocks(days))
          if (b.hasNote) b.id,
      }, withNote);
      expect(all.length, 12);
    });
  });
}
