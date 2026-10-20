// Port of Tests/GroveTests/MeetingNoteTests.swift.
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const friday = DayKey('2026-10-02');
const seriesId = 'AAAAAAAA-1111-2222-3333-444444444444';
const fixedId = '11111111-2222-3333-4444-555555555555';

EventItem makeEvent(AppStore s, String title, {String notes = ''}) {
  final e = EventItem(
    title: title,
    start: const WallTime(day: friday, minute: 540),
    end: const WallTime(day: friday, minute: 600),
    notes: notes,
  );
  s.saveEvent(e, from: null);
  return s.event(e.id)!;
}

EventItem plain(String title, {String? id}) => EventItem(
  id: id,
  title: title,
  start: const WallTime(day: friday, minute: 540),
  end: const WallTime(day: friday, minute: 600),
);

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

List<ItemRef> refs(AppStore s, ItemRef to) => [
  for (final l in s.linkedItems(to)) l.ref,
];

void main() {
  group('event notes make links', () {
    test('a mention in event notes becomes a link', () {
      final s = makeStore();
      final n = s.newNote(title: 'Plan');
      final e = makeEvent(s, 'Dentist', notes: 'See [[Plan|${n.id}]]');
      expect(refs(s, noteRef(n.id)), [eventRef(e.id)]);
    });

    test('a mention without an id is written with the current title', () {
      final s = makeStore();
      final n = s.newNote(title: 'Plan');
      final e = makeEvent(s, 'Dentist', notes: 'See [[plan]]');
      expect(s.event(e.id)?.notes, 'See [[Plan|${n.id}]]');
      expect(s.linkedItems(noteRef(n.id)).length, 1);
    });

    test('changing the notes changes the links', () {
      final s = makeStore();
      final a = s.newNote(title: 'Alpha'), b = s.newNote(title: 'Beta');
      final e = makeEvent(s, 'Dentist', notes: '[[Alpha|${a.id}]]');
      s.saveEvent(e.copyWith(notes: '[[Beta|${b.id}]]'), from: e);
      expect(s.linkedItems(noteRef(a.id)), isEmpty);
      expect(s.linkedItems(noteRef(b.id)).length, 1);
      s.undo();
      expect(s.linkedItems(noteRef(a.id)).length, 1);
      expect(s.linkedItems(noteRef(b.id)), isEmpty);
    });

    test('renaming a note rewrites the event notes', () {
      final s = makeStore();
      final n = s.newNote(title: 'Plan');
      final e = makeEvent(s, 'Dentist', notes: 'See [[Plan|${n.id}]]');
      s.renameNote(n.id, to: 'Big plan');
      expect(s.event(e.id)?.notes, 'See [[Big plan|${n.id}]]');
    });

    test('renaming an event rewrites the notes that mention it', () {
      final s = makeStore();
      final e = makeEvent(s, 'Dentist');
      final n = s.newNote(title: 'Plan', body: 'Go to [[Dentist|${e.id}]]');
      expect(refs(s, eventRef(e.id)), [noteRef(n.id)]);
      s.saveEvent(e.copyWith(title: 'Orthodontist'), from: e);
      expect(s.note(n.id)?.body, 'Go to [[Orthodontist|${e.id}]]');
    });

    test('deleting an event and undo brings the links back', () {
      final s = makeStore();
      final n = s.newNote(title: 'Plan');
      final e = makeEvent(s, 'Dentist', notes: 'See [[Plan|${n.id}]]');
      s.setNoteBody(n.id, 'Go to [[Dentist|${e.id}]]');
      expect(s.linkedItems(eventRef(e.id)).length, 1);
      s.deleteEvent(e);
      expect(s.linkedItems(noteRef(n.id)), isEmpty);
      expect(s.linkedItems(eventRef(e.id)), isEmpty);
      s.undo();
      // The event's own link is back, and the note's link to it.
      expect(refs(s, noteRef(n.id)), [eventRef(e.id)]);
      expect(refs(s, eventRef(e.id)), [noteRef(n.id)]);
    });

    test('a task block is not a link source', () {
      final s = makeStore();
      s.createFromDraft(
        title: 'Write',
        day: friday,
        start: 600,
        end: 660,
        asEvent: false,
      );
      final block = s.eventItems(const DayRange.single(friday)).first;
      expect(block.kind, EventKind.block);
      expect(s.repos.links.outgoing(eventRef(block.id)), isEmpty);
    });

    test('a day of a repeating event links to the series', () {
      final s = makeStore();
      saveSeries(s);
      final n = s.newNote(
        title: 'Retro',
        body: 'Talk at [[Standup|$seriesId]]',
      );
      expect(refs(s, eventRef(seriesId)), [noteRef(n.id)]);
      final day = s.event('$seriesId@2026-10-09')!;
      expect(MeetingNote.linkId(day), seriesId);
      expect(MeetingNote.linkId(s.event(seriesId)!), seriesId);
    });
  });

  group('the note text', () {
    test('the title has the event name and the short date', () {
      expect(MeetingNote.title(plain('Team sync')), 'Team sync — 2 Oct');
      final blank = EventItem(
        title: '  ',
        start: const WallTime(day: DayKey('2026-03-15'), minute: 0),
        end: const WallTime(day: DayKey('2026-03-15'), minute: 30),
      );
      expect(MeetingNote.title(blank), 'Meeting — 15 Mar');
    });

    test('the body starts with the link and has the three sections', () {
      final e = plain('Team sync', id: fixedId);
      final body = MeetingNote.body(e);
      expect(
        body,
        'Meeting: [[Team sync|$fixedId]]\n\n'
        '## Agenda\n\n## Notes\n\n## Action items\n- [ ] ',
      );
      expect([for (final m in ReferenceParser.mentions(body)) m.id], [e.id]);
    });

    test('a title with brackets stays one mention', () {
      final e = plain('Fix [[odd]] | talk', id: fixedId);
      expect(
        [for (final m in ReferenceParser.mentions(MeetingNote.body(e))) m.id],
        [e.id],
      );
    });
  });

  group('making the note', () {
    test('createMeetingNote makes a linked note and opens it', () {
      final s = makeStore();
      final e = makeEvent(s, 'Team sync');
      final n = s.createMeetingNote(e)!;
      expect(n.title, 'Team sync — 2 Oct');
      expect(n.kind, NoteKind.note);
      expect(
        s.note(n.id)?.body,
        startsWith('Meeting: [[Team sync|${e.id}]]\n\n## Agenda'),
      );
      expect(refs(s, eventRef(e.id)), [noteRef(n.id)]);
      expect(s.screen, Screen.notes);
      expect(s.selectedNoteId, n.id);
      expect(s.undoName, 'New Meeting Note');
    });

    test('one undo removes the note and redo brings it back', () {
      final s = makeStore();
      final e = makeEvent(s, 'Team sync');
      final n = s.createMeetingNote(e)!;
      s.undo();
      expect(s.note(n.id), isNull);
      expect(s.linkedItems(eventRef(e.id)), isEmpty);
      s.redo();
      expect(s.note(n.id), isNotNull);
      expect(s.linkedItems(eventRef(e.id)).length, 1);
    });

    test('asking again opens the same note', () {
      final s = makeStore();
      final e = makeEvent(s, 'Team sync');
      final first = s.createMeetingNote(e)!;
      expect(s.meetingNote(e)?.id, first.id);
      s.screen = Screen.planner;
      final second = s.createMeetingNote(e)!;
      expect(second.id, first.id);
      expect(s.screen, Screen.notes);
      expect(s.selectedNoteId, first.id);
      expect(s.repos.notes.all().length, 1);
    });

    test('a note that only mentions the event is not its meeting note', () {
      final s = makeStore();
      final e = makeEvent(s, 'Team sync');
      s.newNote(title: 'Ideas', body: 'Bring up [[Team sync|${e.id}]]');
      expect(s.meetingNote(e), isNull);
    });

    test('each day of a repeating event gets its own note', () {
      final s = makeStore();
      saveSeries(s);
      final nine = s.event('$seriesId@2026-10-09')!;
      final sixteen = s.event('$seriesId@2026-10-16')!;
      final a = s.createMeetingNote(nine)!;
      final b = s.createMeetingNote(sixteen)!;
      expect(a.id, isNot(b.id));
      expect(a.title, 'Standup — 9 Oct');
      expect(b.title, 'Standup — 16 Oct');
      expect(s.note(a.id)?.body, startsWith('Meeting: [[Standup|$seriesId]]'));
      expect(
        {for (final l in s.linkedItems(eventRef(seriesId))) l.id},
        {a.id, b.id},
      );
      expect(s.meetingNote(nine)?.id, a.id);
    });

    test('renaming the event renames the link line in the note', () {
      final s = makeStore();
      final e = makeEvent(s, 'Team sync');
      final n = s.createMeetingNote(e)!;
      s.saveEvent(e.copyWith(title: 'Weekly sync'), from: e);
      expect(
        s.note(n.id)?.body,
        startsWith('Meeting: [[Weekly sync|${e.id}]]'),
      );
    });

    test('an action item becomes a task linked to the note', () {
      final s = makeStore();
      final e = makeEvent(s, 'Team sync');
      final n = s.createMeetingNote(e)!;
      s.setNoteBody(
        n.id,
        (s.note(n.id)?.body ?? '').replaceAll(
          '- [ ] ',
          '- [ ] Send the notes to Sam',
        ),
      );
      expect(s.syncNoteTasks(n.id), 1);
      final t = s.repos.tasks.inbox().first;
      expect(t.title, 'Send the notes to Sam');
      expect(t.notes, 'From [[Team sync — 2 Oct|${n.id}]]');
    });

    test('a missing event makes no note', () {
      final s = makeStore();
      expect(s.createMeetingNote(plain('Ghost')), isNull);
      expect(s.repos.notes.all(), isEmpty);
    });
  });
}
