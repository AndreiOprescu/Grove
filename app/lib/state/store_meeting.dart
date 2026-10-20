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

  /// The ids of the events in [events] that have a meeting note, by the rule
  /// of [meetingNote]. One query for all of them: the planner asks for every
  /// block of its days.
  Set<String> withMeetingNote(Iterable<EventItem> events) {
    final byLink = <String, List<EventItem>>{};
    for (final e in events) {
      (byLink[MeetingNote.linkId(e)] ??= []).add(e);
    }
    if (byLink.isEmpty) return const {};
    final notes =
        _try(
          () => repos.db.query(
            'SELECT l.dst_id, n.title FROM links l '
            'JOIN notes n ON n.id = l.src_id '
            "WHERE l.src_type = 'note' AND l.dst_type = 'event' "
            'AND l.dst_id IN (SELECT value FROM json_each(?))',
            [jsonEncode(byLink.keys.toList())],
            (r) => (link: r.text(0), title: r.text(1)),
          ),
        ) ??
        const <({String link, String title})>[];
    final out = <String>{};
    for (final n in notes) {
      for (final e in byLink[n.link] ?? const <EventItem>[]) {
        if (MeetingNote.title(e) == n.title) out.add(e.id);
      }
    }
    return out;
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
      createdAt: clockStamp(),
    );
    final m = Mutation('New Meeting Note')..notes.add((before: null, after: n));
    if (!commit(m)) return null;
    openNote(n.id);
    return n;
  }
}
