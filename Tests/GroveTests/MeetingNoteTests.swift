import Testing
import Foundation
import GroveCore
@testable import Grove

/// Events as link sources, and meeting notes (PLAN §5.5 items 3, 6 and 9).
@MainActor
struct MeetingNoteTests {
    func makeStore() throws -> AppStore { AppStore(repos: Repos(db: try Database.inMemory())) }
    let friday = DayKey("2026-10-02")
    let seriesId = "AAAAAAAA-1111-2222-3333-444444444444"

    private func event(_ s: AppStore, _ title: String, notes: String = "", day: DayKey? = nil) throws -> EventItem {
        let d = day ?? friday
        let e = EventItem(title: title, start: WallTime(day: d, minute: 540), end: WallTime(day: d, minute: 600), notes: notes)
        s.saveEvent(e, from: nil)
        return try #require(s.event(e.id))
    }

    // MARK: Event notes make links

    @Test func aMentionInEventNotesBecomesALink() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Plan")
        let e = try event(s, "Dentist", notes: "See [[Plan|\(n.id)]]")
        #expect(s.linkedItems(to: ItemRef(.note, n.id)).map(\.ref) == [ItemRef(.event, e.id)])
    }

    @Test func aMentionWithoutAnIdIsWrittenWithTheCurrentTitle() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Plan")
        let e = try event(s, "Dentist", notes: "See [[plan]]")
        #expect(s.event(e.id)?.notes == "See [[Plan|\(n.id)]]")
        #expect(s.linkedItems(to: ItemRef(.note, n.id)).count == 1)
    }

    @Test func changingTheNotesChangesTheLinks() throws {
        let s = try makeStore()
        let a = s.newNote(title: "Alpha"), b = s.newNote(title: "Beta")
        let e = try event(s, "Dentist", notes: "[[Alpha|\(a.id)]]")
        var edited = e
        edited.notes = "[[Beta|\(b.id)]]"
        s.saveEvent(edited, from: e)
        #expect(s.linkedItems(to: ItemRef(.note, a.id)).isEmpty)
        #expect(s.linkedItems(to: ItemRef(.note, b.id)).count == 1)
        s.undo()
        #expect(s.linkedItems(to: ItemRef(.note, a.id)).count == 1)
        #expect(s.linkedItems(to: ItemRef(.note, b.id)).isEmpty)
    }

    @Test func renamingANoteRewritesTheEventNotes() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Plan")
        let e = try event(s, "Dentist", notes: "See [[Plan|\(n.id)]]")
        s.renameNote(n.id, to: "Big plan")
        #expect(s.event(e.id)?.notes == "See [[Big plan|\(n.id)]]")
    }

    @Test func renamingAnEventRewritesTheNotesThatMentionIt() throws {
        let s = try makeStore()
        let e = try event(s, "Dentist")
        let n = s.newNote(title: "Plan", body: "Go to [[Dentist|\(e.id)]]")
        #expect(s.linkedItems(to: ItemRef(.event, e.id)).map(\.ref) == [ItemRef(.note, n.id)])
        var edited = e
        edited.title = "Orthodontist"
        s.saveEvent(edited, from: e)
        #expect(s.note(n.id)?.body == "Go to [[Orthodontist|\(e.id)]]")
    }

    @Test func deletingAnEventAndUndoBringsTheLinksBack() throws {
        let s = try makeStore()
        let n = s.newNote(title: "Plan")
        let e = try event(s, "Dentist", notes: "See [[Plan|\(n.id)]]")
        s.setNoteBody(n.id, "Go to [[Dentist|\(e.id)]]")
        #expect(s.linkedItems(to: ItemRef(.event, e.id)).count == 1)
        s.deleteEvent(e)
        #expect(s.linkedItems(to: ItemRef(.note, n.id)).isEmpty)
        #expect(s.linkedItems(to: ItemRef(.event, e.id)).isEmpty)
        s.undo()
        #expect(s.linkedItems(to: ItemRef(.note, n.id)).map(\.ref) == [ItemRef(.event, e.id)])   // the event's own link is back
        #expect(s.linkedItems(to: ItemRef(.event, e.id)).map(\.ref) == [ItemRef(.note, n.id)])   // and the note's link to it
    }

    @Test func aTaskBlockIsNotALinkSource() throws {
        let s = try makeStore()
        s.createFromDraft(title: "Write", day: friday, start: 600, end: 660, asEvent: false)
        let block = try #require(s.eventItems(in: friday...friday).first)
        #expect(block.kind == .block)
        #expect(try s.repos.links.outgoing(from: ItemRef(.event, block.id)).isEmpty)
    }

    @Test func aDayOfARepeatingEventLinksToTheSeries() throws {
        let s = try makeStore()
        let series = EventItem(id: seriesId, title: "Standup", start: WallTime(day: friday, minute: 540), end: WallTime(day: friday, minute: 570),
                               recurrence: .init(freq: .weekly))
        s.saveEvent(series, from: nil)
        let n = s.newNote(title: "Retro", body: "Talk at [[Standup|\(seriesId)]]")
        #expect(s.linkedItems(to: ItemRef(.event, seriesId)).map(\.ref) == [ItemRef(.note, n.id)])
        let day = try #require(s.event("\(seriesId)@2026-10-09"))
        #expect(MeetingNote.linkId(for: day) == seriesId)
        #expect(MeetingNote.linkId(for: series) == seriesId)
    }

    // MARK: The note text

    @Test func theTitleHasTheEventNameAndTheShortDate() {
        let e = EventItem(title: "Team sync", start: WallTime(day: friday, minute: 540), end: WallTime(day: friday, minute: 600))
        #expect(MeetingNote.title(for: e) == "Team sync — 2 Oct")
        let blank = EventItem(title: "  ", start: WallTime(day: DayKey("2026-03-15"), minute: 0), end: WallTime(day: DayKey("2026-03-15"), minute: 30))
        #expect(MeetingNote.title(for: blank) == "Meeting — 15 Mar")
    }

    @Test func theBodyStartsWithTheLinkAndHasTheThreeSections() {
        let e = EventItem(id: "11111111-2222-3333-4444-555555555555", title: "Team sync",
                          start: WallTime(day: friday, minute: 540), end: WallTime(day: friday, minute: 600))
        let body = MeetingNote.body(for: e)
        #expect(body == "Meeting: [[Team sync|11111111-2222-3333-4444-555555555555]]\n\n## Agenda\n\n## Notes\n\n## Action items\n- [ ] ")
        #expect(ReferenceParser.mentions(in: body).map(\.id) == [e.id])
    }

    @Test func aTitleWithBracketsStaysOneMention() {
        let e = EventItem(id: "11111111-2222-3333-4444-555555555555", title: "Fix [[odd]] | talk",
                          start: WallTime(day: friday, minute: 540), end: WallTime(day: friday, minute: 600))
        #expect(ReferenceParser.mentions(in: MeetingNote.body(for: e)).map(\.id) == [e.id])
    }

    // MARK: Making the note

    @Test func createMeetingNoteMakesALinkedNoteAndOpensIt() throws {
        let s = try makeStore()
        let e = try event(s, "Team sync")
        let n = try #require(s.createMeetingNote(for: e))
        #expect(n.title == "Team sync — 2 Oct" && n.kind == .note)
        #expect(s.note(n.id)?.body.hasPrefix("Meeting: [[Team sync|\(e.id)]]\n\n## Agenda") == true)
        #expect(s.linkedItems(to: ItemRef(.event, e.id)).map(\.ref) == [ItemRef(.note, n.id)])
        #expect(s.screen == .notes && s.selectedNoteId == n.id)
        #expect(s.undoName == "New Meeting Note")
    }

    @Test func oneUndoRemovesTheNoteAndRedoBringsItBack() throws {
        let s = try makeStore()
        let e = try event(s, "Team sync")
        let n = try #require(s.createMeetingNote(for: e))
        s.undo()
        #expect(s.note(n.id) == nil)
        #expect(s.linkedItems(to: ItemRef(.event, e.id)).isEmpty)
        s.redo()
        #expect(s.note(n.id) != nil)
        #expect(s.linkedItems(to: ItemRef(.event, e.id)).count == 1)
    }

    @Test func askingAgainOpensTheSameNote() throws {
        let s = try makeStore()
        let e = try event(s, "Team sync")
        let first = try #require(s.createMeetingNote(for: e))
        #expect(s.meetingNote(for: e)?.id == first.id)
        s.screen = .planner
        let second = try #require(s.createMeetingNote(for: e))
        #expect(second.id == first.id)
        #expect(s.screen == .notes && s.selectedNoteId == first.id)
        #expect(try s.repos.notes.all().count == 1)
    }

    @Test func aNoteThatOnlyMentionsTheEventIsNotItsMeetingNote() throws {
        let s = try makeStore()
        let e = try event(s, "Team sync")
        s.newNote(title: "Ideas", body: "Bring up [[Team sync|\(e.id)]]")
        #expect(s.meetingNote(for: e) == nil)
    }

    @Test func eachDayOfARepeatingEventGetsItsOwnNote() throws {
        let s = try makeStore()
        s.saveEvent(EventItem(id: seriesId, title: "Standup", start: WallTime(day: friday, minute: 540), end: WallTime(day: friday, minute: 570),
                              recurrence: .init(freq: .weekly)), from: nil)
        let nine = try #require(s.event("\(seriesId)@2026-10-09"))
        let sixteen = try #require(s.event("\(seriesId)@2026-10-16"))
        let a = try #require(s.createMeetingNote(for: nine))
        let b = try #require(s.createMeetingNote(for: sixteen))
        #expect(a.id != b.id)
        #expect(a.title == "Standup — 9 Oct" && b.title == "Standup — 16 Oct")
        #expect(s.note(a.id)?.body.hasPrefix("Meeting: [[Standup|\(seriesId)]]") == true)
        #expect(Set(s.linkedItems(to: ItemRef(.event, seriesId)).map(\.id)) == [a.id, b.id])
        #expect(s.meetingNote(for: nine)?.id == a.id)
    }

    @Test func renamingTheEventRenamesTheLinkLineInTheNote() throws {
        let s = try makeStore()
        let e = try event(s, "Team sync")
        let n = try #require(s.createMeetingNote(for: e))
        var edited = e
        edited.title = "Weekly sync"
        s.saveEvent(edited, from: e)
        #expect(s.note(n.id)?.body.hasPrefix("Meeting: [[Weekly sync|\(e.id)]]") == true)
    }

    @Test func anActionItemBecomesATaskLinkedToTheNote() throws {
        let s = try makeStore()
        let e = try event(s, "Team sync")
        let n = try #require(s.createMeetingNote(for: e))
        s.setNoteBody(n.id, (s.note(n.id)?.body ?? "").replacingOccurrences(of: "- [ ] ", with: "- [ ] Send the notes to Sam"))
        #expect(s.syncNoteTasks(n.id) == 1)
        let t = try #require(try s.repos.tasks.inbox().first)
        #expect(t.title == "Send the notes to Sam")
        #expect(t.notes == "From [[Team sync — 2 Oct|\(n.id)]]")
    }

    @Test func aMissingEventMakesNoNote() throws {
        let s = try makeStore()
        let ghost = EventItem(title: "Ghost", start: WallTime(day: friday, minute: 540), end: WallTime(day: friday, minute: 600))
        #expect(s.createMeetingNote(for: ghost) == nil)
        #expect(try s.repos.notes.all().isEmpty)
    }
}
