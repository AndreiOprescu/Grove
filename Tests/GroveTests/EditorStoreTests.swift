import Testing
import AppKit
import GroveCore
@testable import Grove

/// What the editor asks of the store: the `[[` list, opening a mention, images.
@MainActor
struct EditorStoreTests {
    func makeStore() throws -> AppStore { AppStore(repos: Repos(db: try Database.inMemory())) }

    // MARK: the [[ list

    @Test func anEmptyQueryListsTodayThenTheInbox() throws {
        let s = try makeStore()
        s.selectedDay = DayKey.today()
        let inbox = try #require(s.quickAdd("Inbox thing"))
        let today = try #require(s.quickAdd("Plan the thing today"))
        let titles = s.mentionSuggestions(for: "", excluding: nil).map(\.title)
        #expect(titles.first == "Plan the thing")
        #expect(titles.contains("Inbox thing"))
        #expect(s.mentionSuggestions(for: "", excluding: ItemRef(.task, today.id)).map(\.title) == ["Inbox thing"])
        _ = inbox
    }

    @Test func theListHoldsAtMostEightRows() throws {
        let s = try makeStore()
        for i in 1...12 { _ = try #require(s.quickAdd("Thing \(i)")) }
        #expect(s.mentionSuggestions(for: "", excluding: nil).count == 8)
        #expect(s.mentionSuggestions(for: "thing", excluding: nil).count == 8)
    }

    @Test func typingNarrowsTheListByAPrefixOfAnyWord() throws {
        let s = try makeStore()
        _ = try #require(s.quickAdd("Buy oat milk"))
        _ = try #require(s.quickAdd("Call mum"))
        #expect(s.mentionSuggestions(for: "mil", excluding: nil).map(\.title) == ["Buy oat milk"])
        #expect(s.mentionSuggestions(for: "zzz", excluding: nil).isEmpty)
    }

    @Test func notesAndEventsAreListedWithTheirKind() throws {
        let s = try makeStore()
        try s.repos.notes.save(Note(title: "Garden plan", body: "roses"))
        let hit = try #require(s.mentionSuggestions(for: "garden", excluding: nil).first)
        #expect(hit.kind == "Note" && hit.ref.type == .note)
    }

    @Test func theItemBeingEditedIsLeftOutOfTheSearchList() throws {
        let s = try makeStore()
        let t = try #require(s.quickAdd("Buy milk"))
        #expect(s.mentionSuggestions(for: "buy", excluding: ItemRef(.task, t.id)).isEmpty)
    }

    // MARK: opening a mention

    @Test func openingATaskMentionSelectsTheTaskAndItsDay() throws {
        let s = try makeStore()
        let tomorrow = DayKey.today().adding(days: 1)
        let t = try #require(s.quickAdd("Call mum tomorrow"))
        s.selectedDay = DayKey.today()
        s.openMention(id: t.id, title: "Call mum")
        #expect(s.selectedTaskId == t.id)
        #expect(s.selectedDay == tomorrow)
    }

    @Test func openingAGoneMentionShowsAToast() throws {
        let s = try makeStore()
        s.openMention(id: "11111111-2222-3333-4444-555555555555", title: "Old thing")
        #expect(s.toast == "That item is gone.")
        #expect(s.selectedTaskId == nil)
    }

    @Test func aMentionWithoutAnIdIsFoundByItsTitle() throws {
        let s = try makeStore()
        let t = try #require(s.quickAdd("Buy milk"))
        s.openMention(id: nil, title: "Buy milk")
        #expect(s.selectedTaskId == t.id)
    }

    // MARK: services and images

    @Test func servicesSayWhichItemsAreLiveAndFindTheirTitles() throws {
        let s = try makeStore()
        let t = try #require(s.quickAdd("Buy milk"))
        let svc = s.editorServices()
        #expect(svc.isLive(t.id))
        #expect(svc.title(t.id) == "Buy milk")
        #expect(!svc.isLive("11111111-2222-3333-4444-555555555555"))
        #expect(svc.title("11111111-2222-3333-4444-555555555555") == nil)
    }

    @Test func aStoredImageComesBackAndIsCached() throws {
        let s = try makeStore()
        _ = NSApplication.shared
        let img = NSImage(size: NSSize(width: 40, height: 30), flipped: false) { r in NSColor.red.setFill(); r.fill(); return true }
        let tiff = try #require(img.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        let svc = s.editorServices()
        let id = try #require(svc.storeImage(png))
        let first = try #require(svc.loadImage(id))
        #expect(first.size.width > 0)
        // gone from the database, still served from the cache
        try s.repos.attachments.delete(id)
        #expect(svc.loadImage(id) === first)
    }

    @Test func dataThatIsNotAnImageIsRefused() throws {
        let s = try makeStore()
        #expect(s.editorServices().storeImage(Data([1, 2, 3])) == nil)
        #expect(s.editorServices().loadImage("nope") == nil)
    }
}
