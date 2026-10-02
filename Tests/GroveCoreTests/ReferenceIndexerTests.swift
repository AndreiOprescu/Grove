import Testing
import Foundation
@testable import GroveCore

struct ReferenceIndexerTests {
    func makeRepos() throws -> Repos { Repos(db: try Database.inMemory()) }

    // MARK: resolving and canonical text

    @Test func titleMentionBecomesIdMention() throws {
        let r = try makeRepos()
        let milk = TaskItem(title: "Buy milk")
        try r.tasks.save(milk)
        let out = try r.refs.canonicalize("see [[buy MILK]]")
        #expect(out.text == "see [[Buy milk|\(milk.id)]]")
        #expect(out.targets == [ItemRef(.task, milk.id)])
    }

    @Test func idWinsOverTitle() throws {
        let r = try makeRepos()
        let a = TaskItem(title: "Same"), b = TaskItem(title: "Same")
        try r.tasks.save(a); try r.tasks.save(b)
        let out = try r.refs.canonicalize("[[Same|\(b.id)]]")
        #expect(out.targets == [ItemRef(.task, b.id)])
        #expect(out.text == "[[Same|\(b.id)]]")
    }

    @Test func openTaskBeatsDoneTaskWithTheSameTitle() throws {
        let r = try makeRepos()
        var done = TaskItem(title: "Same"); done.status = .done
        let open = TaskItem(title: "Same")
        try r.tasks.save(open); try r.tasks.save(done)
        #expect(try r.refs.canonicalize("[[Same]]").targets == [ItemRef(.task, open.id)])
    }

    @Test func noteBeatsTaskOnATitleTie() throws {
        let r = try makeRepos()
        let task = TaskItem(title: "Plan"), note = Note(title: "Plan")
        try r.tasks.save(task); try r.notes.save(note)
        #expect(try r.refs.canonicalize("[[Plan]]").targets == [ItemRef(.note, note.id)])
    }

    @Test func eventsCanBeMentioned() throws {
        let r = try makeRepos()
        let e = EventItem(title: "Dentist", start: WallTime("2026-10-05T09:00")!, end: WallTime("2026-10-05T10:00")!)
        try r.events.save(e)
        #expect(try r.refs.canonicalize("[[Dentist]]").targets == [ItemRef(.event, e.id)])
    }

    @Test func unknownMentionStaysAsTyped() throws {
        let r = try makeRepos()
        let out = try r.refs.canonicalize("[[Nope]] and text")
        #expect(out.text == "[[Nope]] and text")
        #expect(out.targets.isEmpty)
    }

    @Test func deletedTargetStaysDanglingAndDoesNotRebind() throws {
        let r = try makeRepos()
        let gone = TaskItem(title: "Old"), other = TaskItem(title: "Old")
        try r.tasks.save(gone); try r.tasks.save(other)
        try r.tasks.delete(gone.id)
        let text = "[[Old|\(gone.id)]]"
        let out = try r.refs.canonicalize(text)
        #expect(out.text == text)
        #expect(out.targets.isEmpty)
    }

    @Test func staleTitleIsHealed() throws {
        let r = try makeRepos()
        let t = TaskItem(title: "New name")
        try r.tasks.save(t)
        #expect(try r.refs.canonicalize("[[Old name|\(t.id)]]").text == "[[New name|\(t.id)]]")
    }

    @Test func subtasksCanBeMentioned() throws {
        let r = try makeRepos()
        let parent = TaskItem(title: "Trip")
        var child = TaskItem(title: "Book hotel"); child.parentId = parent.id
        try r.tasks.save(parent); try r.tasks.save(child)
        #expect(try r.refs.canonicalize("[[Book hotel]]").targets == [ItemRef(.task, child.id)])
    }

    // MARK: links table

    @Test func reindexWritesAndClearsBacklinks() throws {
        let r = try makeRepos()
        let a = TaskItem(title: "A"), b = TaskItem(title: "B")
        try r.tasks.save(a); try r.tasks.save(b)
        let canon = try r.refs.reindex(ItemRef(.task, a.id), text: "needs [[B]]")
        #expect(canon == "needs [[B|\(b.id)]]")
        #expect(try r.links.backlinks(to: ItemRef(.task, b.id)) == [ItemRef(.task, a.id)])
        _ = try r.refs.reindex(ItemRef(.task, a.id), text: "no mention now")
        #expect(try r.links.backlinks(to: ItemRef(.task, b.id)).isEmpty)
    }

    @Test func reindexKeepsManualLinks() throws {
        let r = try makeRepos()
        let a = TaskItem(title: "A"), c = TaskItem(title: "C")
        try r.tasks.save(a); try r.tasks.save(c)
        try r.links.addManual(src: ItemRef(.task, a.id), dst: ItemRef(.task, c.id))
        _ = try r.refs.reindex(ItemRef(.task, a.id), text: "")
        #expect(try r.links.outgoing(from: ItemRef(.task, a.id)) == [ItemRef(.task, c.id)])
    }

    @Test func mentioningYourselfMakesNoLink() throws {
        let r = try makeRepos()
        let a = TaskItem(title: "A")
        try r.tasks.save(a)
        _ = try r.refs.reindex(ItemRef(.task, a.id), text: "[[A]]")
        #expect(try r.links.outgoing(from: ItemRef(.task, a.id)).isEmpty)
    }

    @Test func notesAndEventsLinkToTasksToo() throws {
        let r = try makeRepos()
        let t = TaskItem(title: "Report")
        let n = Note(title: "Journal")
        try r.tasks.save(t); try r.notes.save(n)
        _ = try r.refs.reindex(ItemRef(.note, n.id), text: "finish [[Report]]")
        #expect(try r.links.backlinks(to: ItemRef(.task, t.id)) == [ItemRef(.note, n.id)])
    }

    // MARK: rename

    @Test func renameRewritesEveryBodyThatLinks() throws {
        let r = try makeRepos()
        var target = TaskItem(title: "Old title")
        let other = TaskItem(title: "Other")
        try r.tasks.save(target); try r.tasks.save(other)

        var host = TaskItem(title: "Host")
        host.notes = try r.refs.canonicalize("depends on [[Old title]]").text
        try r.tasks.save(host)
        var note = Note(title: "Journal")
        note.body = try r.refs.canonicalize("x [[Old title]] y [[Other]] z").text
        try r.notes.save(note)
        var event = EventItem(title: "Sync", start: WallTime("2026-10-05T09:00")!, end: WallTime("2026-10-05T10:00")!)
        event.notes = try r.refs.canonicalize("talk about [[Old title]]").text
        try r.events.save(event)
        _ = try r.refs.reindex(ItemRef(.task, host.id), text: host.notes)
        _ = try r.refs.reindex(ItemRef(.note, note.id), text: note.body)
        _ = try r.refs.reindex(ItemRef(.event, event.id), text: event.notes)
        let noteStamp = try #require(try r.notes.get(note.id)).updatedAt

        target.title = "Fresh title"
        try r.tasks.save(target)
        try r.refs.renamed(ItemRef(.task, target.id), to: "Fresh title")

        #expect(try r.tasks.get(host.id)?.notes == "depends on [[Fresh title|\(target.id)]]")
        #expect(try r.notes.get(note.id)?.body == "x [[Fresh title|\(target.id)]] y [[Other|\(other.id)]] z")
        #expect(try r.events.get(event.id)?.notes == "talk about [[Fresh title|\(target.id)]]")
        // a rename must not make every linking note look freshly edited
        #expect(try r.notes.get(note.id)?.updatedAt == noteStamp)
        // search sees the new title text
        #expect(try r.search.search("Fresh").map(\.ref).contains(ItemRef(.task, host.id)))
        // links are still in place
        #expect(try r.links.backlinks(to: ItemRef(.task, target.id)).count == 3)
    }

    // MARK: deleting

    @Test func deletingAnItemRemovesItsLinksBothWays() throws {
        let r = try makeRepos()
        let a = TaskItem(title: "A"), b = TaskItem(title: "B")
        let n = Note(title: "N")
        let e = EventItem(title: "E", start: WallTime("2026-10-05T09:00")!, end: WallTime("2026-10-05T10:00")!)
        try r.tasks.save(a); try r.tasks.save(b); try r.notes.save(n); try r.events.save(e)
        let ta = ItemRef(.task, a.id), tb = ItemRef(.task, b.id), rn = ItemRef(.note, n.id), re = ItemRef(.event, e.id)
        try r.links.addManual(src: ta, dst: tb)
        try r.links.addManual(src: rn, dst: ta)
        try r.links.addManual(src: re, dst: ta)

        try r.notes.delete(n.id)
        #expect(try r.links.backlinks(to: ta) == [re])
        try r.events.delete(e.id)
        #expect(try r.links.backlinks(to: ta).isEmpty)
        try r.tasks.delete(b.id)
        #expect(try r.links.outgoing(from: ta).isEmpty)
    }

    @Test func deletingAParentTaskAlsoClearsTheLinksOfItsSubtasks() throws {
        let r = try makeRepos()
        let parent = TaskItem(title: "Parent")
        var child = TaskItem(title: "Child"); child.parentId = parent.id
        let n = Note(title: "N")
        try r.tasks.save(parent); try r.tasks.save(child); try r.notes.save(n)
        try r.links.addManual(src: ItemRef(.task, child.id), dst: ItemRef(.note, n.id))
        try r.tasks.delete(parent.id)
        #expect(try r.links.backlinks(to: ItemRef(.note, n.id)).isEmpty)
    }

    @Test func rebuildIncomingRestoresLinksToABroughtBackTarget() throws {
        let r = try makeRepos()
        let target = TaskItem(title: "Target")
        try r.tasks.save(target)
        var host = TaskItem(title: "Host")
        host.notes = try r.refs.canonicalize("see [[Target]]").text
        try r.tasks.save(host)
        _ = try r.refs.reindex(ItemRef(.task, host.id), text: host.notes)
        try r.tasks.delete(target.id)
        #expect(try r.links.backlinks(to: ItemRef(.task, target.id)).isEmpty)
        try r.tasks.save(target)   // same id, as undo does
        try r.refs.rebuildIncoming(to: ItemRef(.task, target.id))
        #expect(try r.links.backlinks(to: ItemRef(.task, target.id)) == [ItemRef(.task, host.id)])
    }

    // MARK: search

    @Test func searchSeesWordsNotIdsOrMarkup() throws {
        let r = try makeRepos()
        let dentist = TaskItem(title: "Dentist")
        try r.tasks.save(dentist)
        var host = TaskItem(title: "Errands")
        let imageId = UUID().uuidString
        host.notes = "call [[Dentist|\(dentist.id)]] ![front door](grove-image:\(imageId))"
        try r.tasks.save(host)

        #expect(try r.search.search("front").map(\.ref).contains(ItemRef(.task, host.id)))
        let idPrefix = String(imageId.prefix(8))
        #expect(try r.search.search(idPrefix).isEmpty)
        #expect(try r.search.search("grove").isEmpty)
    }
}
