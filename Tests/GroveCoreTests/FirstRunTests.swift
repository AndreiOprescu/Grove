import Testing
import Foundation
@testable import GroveCore

/// What a brand new Grove holds on first launch (PLAN §9).
struct FirstRunTests {
    let today = DayKey("2026-10-05")

    func makeRepos() throws -> Repos { Repos(db: try Database.inMemory()) }

    @Test func aNewDatabaseGetsThreeListsAndThreeSampleTasks() throws {
        let r = try makeRepos()
        #expect(try FirstRun.seedIfNew(r, today: today))
        let lists = try r.lists.all()
        #expect(lists.map(\.name) == ["Home", "Work", "Personal"])
        #expect(lists.map(\.emoji) == ["🌿", "💼", "✨"])
        let tasks = try r.tasks.forDay(today)
        #expect(tasks.count == 3)
        #expect(tasks.allSatisfy { $0.status == .open && $0.bucket == .day })
        #expect(FirstRun.welcomeVisible(r))
    }

    @Test func theSampleTasksExplainDragToPlanLinksAndTheCommandPalette() throws {
        let r = try makeRepos()
        _ = try FirstRun.seedIfNew(r, today: today)
        let titles = try r.tasks.forDay(today).map(\.title)
        #expect(titles.contains { $0.localizedCaseInsensitiveContains("drag") && $0.localizedCaseInsensitiveContains("planner") })
        #expect(titles.contains { $0.contains("[[") })
        #expect(titles.contains { $0.contains("⌘K") })
    }

    @Test func theSampleTaskIdsAreKeptSoTheyCanBeRemoved() throws {
        let r = try makeRepos()
        _ = try FirstRun.seedIfNew(r, today: today)
        let ids = FirstRun.sampleTaskIds(r)
        #expect(Set(ids) == Set(try r.tasks.all().map(\.id)))
        #expect(ids.count == 3)
    }

    @Test func seedingTwiceDoesNothingTheSecondTime() throws {
        let r = try makeRepos()
        #expect(try FirstRun.seedIfNew(r, today: today))
        #expect(try !FirstRun.seedIfNew(r, today: today))
        #expect(try r.lists.all().count == 3)
        #expect(try r.tasks.all().count == 3)
    }

    @Test func aDatabaseWithDataIsLeftAlone() throws {
        let r = try makeRepos()
        try r.tasks.save(TaskItem(title: "My own task"))
        #expect(try !FirstRun.seedIfNew(r, today: today))
        #expect(try r.lists.all().isEmpty)
        #expect(try r.tasks.all().map(\.title) == ["My own task"])
        #expect(!FirstRun.welcomeVisible(r))
    }

    @Test func aNoteOrAnEventOrAListAloneCountsAsData() throws {
        for fill in [
            { (r: Repos) in try r.notes.save(Note(title: "A note", body: "", kind: .note)) },
            { (r: Repos) in try r.events.save(EventItem(title: "Dentist", start: WallTime(day: DayKey("2026-10-05"), minute: 540),
                                                        end: WallTime(day: DayKey("2026-10-05"), minute: 600))) },
            { (r: Repos) in try r.lists.save(ListItem(name: "Mine")) },
        ] {
            let r = try makeRepos()
            try fill(r)
            #expect(try !FirstRun.seedIfNew(r, today: today))
        }
    }

    @Test func aSeededDatabaseThatWasEmptiedIsNotSeededAgain() throws {
        let r = try makeRepos()
        _ = try FirstRun.seedIfNew(r, today: today)
        for t in try r.tasks.all() { try r.tasks.delete(t.id) }
        for l in try r.lists.all(includeArchived: true) { try r.lists.delete(l.id) }
        #expect(try !FirstRun.seedIfNew(r, today: today))
        #expect(try r.lists.all().isEmpty)
    }

    @Test func dismissingTheCardKeepsTheTasks() throws {
        let r = try makeRepos()
        _ = try FirstRun.seedIfNew(r, today: today)
        FirstRun.dismissWelcome(r)
        #expect(!FirstRun.welcomeVisible(r))
        #expect(try r.tasks.all().count == 3)
        #expect(FirstRun.sampleTaskIds(r).count == 3)   // "Remove samples" still knows them
    }

    @Test func forgettingTheSamplesClearsTheList() throws {
        let r = try makeRepos()
        _ = try FirstRun.seedIfNew(r, today: today)
        FirstRun.forgetSamples(r)
        #expect(FirstRun.sampleTaskIds(r).isEmpty)
        #expect(!FirstRun.welcomeVisible(r))
    }
}
