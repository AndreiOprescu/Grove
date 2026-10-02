import Foundation
import GroveCore

/// The text of a meeting note (PLAN §5.5 item 6). No database and no views here.
enum MeetingNote {
    /// What a link to this event points at. A day of a repeating event points at the series.
    static func linkId(for event: EventItem) -> String {
        OccurrenceID.parse(event.id)?.series ?? event.id
    }

    /// "Team sync — 2 Oct". The day is the day of this event, so each day of a series gets its own note.
    static func title(for event: EventItem) -> String {
        let name = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(name.isEmpty ? "Meeting" : name) — \(NotesRules.shortDate(event.start.day))"
    }

    /// The first line links to the event. The last line is an empty action item, which makes no task until it has words.
    static func body(for event: EventItem) -> String {
        "Meeting: \(ReferenceParser.mention(title: event.title, id: linkId(for: event)))\n\n## Agenda\n\n## Notes\n\n## Action items\n- [ ] "
    }
}
