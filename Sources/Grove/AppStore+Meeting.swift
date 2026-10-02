import Foundation
import GroveCore

/// Meeting notes: a note that is made from an event and linked to it (PLAN §5.5 item 6).
extension AppStore {
    /// The meeting note of this event (or of this day of a repeating event). It must link to the event and have the meeting title.
    func meetingNote(for event: EventItem) -> Note? {
        let title = MeetingNote.title(for: event)
        let found = linkedItems(to: ItemRef(.event, MeetingNote.linkId(for: event)))
            .first { $0.ref.type == .note && $0.title == title }
        return found.flatMap { note($0.id) }
    }

    /// Makes the meeting note and shows it. When it already exists, it only shows it. Nil when the event is gone.
    @discardableResult
    func createMeetingNote(for event: EventItem) -> Note? {
        guard self.event(event.id) != nil else { return nil }
        if let existing = meetingNote(for: event) {
            openNote(existing.id)
            return existing
        }
        let n = Note(title: MeetingNote.title(for: event), body: MeetingNote.body(for: event))
        var m = Mutation(name: "New Meeting Note")
        m.notes.append((nil, n))
        guard commit(m) else { return nil }
        openNote(n.id)
        return n
    }
}
