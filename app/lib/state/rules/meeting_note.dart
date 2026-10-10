import '../../core/model/event.dart';
import '../../core/parsing/reference_parser.dart';
import '../../core/recurrence/recurrence_engine.dart';
import 'notes_rules.dart';

/// The text of a meeting note (PLAN §5.5 item 6). No database and no views here.
abstract final class MeetingNote {
  /// What a link to this event points at. A day of a repeating event points at the series.
  static String linkId(EventItem event) =>
      OccurrenceId.parse(event.id)?.series ?? event.id;

  /// "Team sync — 2 Oct". The day is the day of this event, so each day of a
  /// series gets its own note.
  static String title(EventItem event) {
    final name = event.title.trim();
    return '${name.isEmpty ? 'Meeting' : name} — ${NotesRules.shortDate(event.start.day)}';
  }

  /// The first line links to the event. The last line is an empty action item,
  /// which makes no task until it has words.
  static String body(EventItem event) =>
      'Meeting: ${ReferenceParser.mention(title: event.title, id: linkId(event))}'
      '\n\n## Agenda\n\n## Notes\n\n## Action items\n- [ ] ';
}
