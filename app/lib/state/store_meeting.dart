part of 'app_store.dart';

/// Meeting notes: a note that is made from an event and linked to it (PLAN
/// §5.5 item 6).
extension AppStoreMeeting on AppStore {
  /// The meeting note of this event (or of this day of a repeating event). It
  /// must link to the event and have the meeting title.
  Note? meetingNote(EventItem event) {
    final title = MeetingNote.title(event);
    final linked = linkedItems(
      ItemRef(ItemType.event, MeetingNote.linkId(event)),
    );
    for (final item in linked) {
      if (item.ref.type == ItemType.note && item.title == title) {
        return note(item.id);
      }
    }
    return null;
  }

  /// Makes the meeting note and shows it. When it already exists, it only
  /// shows it. Null when the event is gone.
  Note? createMeetingNote(EventItem event) {
    if (this.event(event.id) == null) return null;
    final existing = meetingNote(event);
    if (existing != null) {
      openNote(existing.id);
      return existing;
    }
    final n = Note(
      title: MeetingNote.title(event),
      body: MeetingNote.body(event),
    );
    final m = Mutation('New Meeting Note')..notes.add((before: null, after: n));
    if (!commit(m)) return null;
    openNote(n.id);
    return n;
  }
}
