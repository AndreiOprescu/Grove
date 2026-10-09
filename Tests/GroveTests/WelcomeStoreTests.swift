import Testing
import Foundation
import GroveCore
@testable import Grove

/// The welcome card and the sample tasks in the store (PLAN §9, §5.6).
@MainActor
struct WelcomeStoreTests {
    private func seeded(notifier: FakeNotifier? = nil) throws -> AppStore {
        let repos = Repos(db: try Database.inMemory())
        try FirstRun.seedIfNew(repos, today: .today())
        return AppStore(repos: repos, notifier: notifier ?? FakeNotifier(status: .notAsked))
    }

    @Test func aStoreOnAnEmptyDatabaseShowsNoCard() throws {
        let s = AppStore(repos: Repos(db: try Database.inMemory()), notifier: FakeNotifier())
        #expect(!s.welcomeVisible)
    }

    @Test func aStoreOnASeededDatabaseShowsTheCard() throws {
        let s = try seeded()
        #expect(s.welcomeVisible)
        #expect(try s.repos.tasks.all().count == 3)
    }

    @Test func gotItHidesTheCardAndKeepsTheTasks() throws {
        let s = try seeded()
        s.dismissWelcome()
        #expect(!s.welcomeVisible)
        #expect(try s.repos.tasks.all().count == 3)
        #expect(!FirstRun.welcomeVisible(s.repos))
    }

    @Test func gotItAsksForNotificationsOnce() async throws {
        let fake = FakeNotifier(status: .notAsked, answer: .allowed)
        let s = try seeded(notifier: fake)
        s.dismissWelcome()
        await s.welcomeAsk?.value
        #expect(fake.asked == 1)
        #expect(s.notifyStatus == .allowed)
    }

    @Test func itDoesNotAskAgainWhenTheMacAlreadyAnswered() async throws {
        let fake = FakeNotifier(status: .denied)
        let s = try seeded(notifier: fake)
        s.dismissWelcome()
        await s.welcomeAsk?.value
        #expect(fake.asked == 0)
        #expect(s.notifyStatus == .denied)
    }

    @Test func removeSamplesDeletesThemAsOneUndoStep() throws {
        let s = try seeded()
        s.removeSamples()
        #expect(!s.welcomeVisible)
        #expect(try s.repos.tasks.all().isEmpty)
        #expect(s.undoName == "Remove Samples")
        s.undo()
        #expect(try s.repos.tasks.all().count == 3)
    }

    @Test func removeSamplesKeepsTheTasksThePersonAdded() throws {
        let s = try seeded()
        try s.repos.tasks.save(TaskItem(title: "Mine", bucket: .day, planDate: .today()))
        s.removeSamples()
        #expect(try s.repos.tasks.all().map(\.title) == ["Mine"])
    }

    @Test func removeSamplesAlsoAsksForNotifications() async throws {
        let fake = FakeNotifier(status: .notAsked, answer: .allowed)
        let s = try seeded(notifier: fake)
        s.removeSamples()
        await s.welcomeAsk?.value
        #expect(fake.asked == 1)
    }

    @Test func aSampleTheOwnerAlreadyDeletedDoesNotBreakRemove() throws {
        let s = try seeded()
        let first = try #require(FirstRun.sampleTaskIds(s.repos).first)
        s.deleteTask(first)
        s.removeSamples()
        #expect(try s.repos.tasks.all().isEmpty)
    }
}
