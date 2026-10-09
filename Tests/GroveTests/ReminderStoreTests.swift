import Testing
import Foundation
import GroveCore
@testable import Grove

/// A stand-in for the system notification centre. It remembers what Grove asked for.
@MainActor
final class FakeNotifier: Notifier {
    var status: NotifyAuthorization
    var answer: NotifyAuthorization
    private(set) var sent: [[Reminder]] = []
    private(set) var asked = 0
    private(set) var focusEnds: [FocusEnd] = []
    private(set) var focusCancels = 0
    var onOpen: ((DayKey, ItemRef) -> Void)?
    var onFocusDone: ((String) -> Void)?

    init(status: NotifyAuthorization = .allowed, answer: NotifyAuthorization = .allowed) {
        self.status = status
        self.answer = answer
    }

    func authorization() async -> NotifyAuthorization { status }
    func requestAuthorization() async -> NotifyAuthorization { asked += 1; status = answer; return answer }
    func replaceAll(_ reminders: [Reminder]) async { sent.append(reminders) }
    func scheduleFocusEnd(_ end: FocusEnd) async { focusEnds.append(end) }
    func cancelFocusEnd() async { focusCancels += 1 }
}

/// What the store sends to the notification centre, and when (PLAN §5.6).
@MainActor
@Suite(.serialized)
struct ReminderStoreTests {
    private let defaults = UserDefaults.standard
    private let keys = ["notifications.enabled", "notifications.lead"]
    private func clean() { keys.forEach(defaults.removeObject(forKey:)) }

    // 2026-10-05 is a Monday. "Now" is Sunday evening before it.
    private let sunday = DayKey("2026-10-04")
    private let monday = DayKey("2026-10-05")

    private func makeStore(notifier: FakeNotifier? = nil) throws -> AppStore {
        let s = AppStore(repos: Repos(db: try Database.inMemory()), notifier: notifier ?? FakeNotifier())
        s.clockOverride = WallTime(day: sunday, minute: 20 * 60)
        return s
    }

    @discardableResult
    private func addEvent(_ s: AppStore, id: String = "E1", title: String = "Standup", day: DayKey? = nil, start: Int = 540,
                          end: Int = 600, taskId: String? = nil, rule: RecurrenceRule? = nil, allDay: Bool = false) throws -> EventItem {
        let d = day ?? monday
        var e = EventItem(id: id, title: title, start: WallTime(day: d, minute: start), end: WallTime(day: d, minute: end),
                          color: "accent3", recurrence: rule)
        e.allDay = allDay
        e.taskId = taskId
        e.kind = taskId == nil ? .event : .block
        try s.repos.events.save(e)
        return e
    }

    // MARK: Building the list

    @Test func aComingEventRemindsFiveMinutesEarly() throws {
        clean(); defer { clean() }
        let s = try makeStore()
        try addEvent(s)
        let list = s.buildReminders()
        #expect(list.count == 1)
        #expect(list[0].id == "ev-E1-2026-10-05T09:00")
        #expect(list[0].title == "Standup")
        #expect(list[0].body == "09:00 – 10:00")
        #expect(list[0].fireAt == WallTime(day: monday, minute: 535))
    }

    @Test func theLeadTimeComesFromTheSetting() throws {
        clean(); defer { clean() }
        let s = try makeStore()
        try addEvent(s)
        s.setNotifyLead(15)
        #expect(s.buildReminders()[0].fireAt == WallTime(day: monday, minute: 525))
        s.setNotifyLead(0)
        #expect(s.buildReminders()[0].fireAt == WallTime(day: monday, minute: 540))
    }

    @Test func aLeadThatIsNotOnTheListIsIgnored() throws {
        clean(); defer { clean() }
        let s = try makeStore()
        s.setNotifyLead(7)
        #expect(s.notifyLead == 5)
        s.setNotifyLead(10)
        #expect(s.notifyLead == 10)
        s.setNotifyLead(99)
        #expect(s.notifyLead == 10)
    }

    @Test func aBlockOfAFinishedTaskDoesNotRemind() throws {
        clean(); defer { clean() }
        let s = try makeStore()
        var t = TaskItem(id: "T1", title: "Write report")
        try s.repos.tasks.save(t)
        try addEvent(s, id: "B1", title: "Write report", taskId: "T1")
        #expect(s.buildReminders().count == 1)
        #expect(s.buildReminders()[0].ref == ItemRef(.task, "T1"))
        t.status = .done
        try s.repos.tasks.save(t)
        #expect(s.buildReminders().isEmpty)
    }

    @Test func aTaskDueAtATimeRemindsAndADueDayAloneDoesNot() throws {
        clean(); defer { clean() }
        let s = try makeStore()
        var timed = TaskItem(id: "T1", title: "Send invoice")
        timed.due = "2026-10-05T17:00"
        var dayOnly = TaskItem(id: "T2", title: "Pay rent")
        dayOnly.due = "2026-10-05"
        try s.repos.tasks.save(timed)
        try s.repos.tasks.save(dayOnly)
        let list = s.buildReminders()
        #expect(list.map(\.id) == ["due-T1-2026-10-05T17:00"])
        #expect(list[0].body == "Due 17:00")
        #expect(list[0].ref == ItemRef(.task, "T1"))
    }

    @Test func aRepeatingEventRemindsOnEachDayOfTheWindow() throws {
        clean(); defer { clean() }
        let s = try makeStore()
        try addEvent(s, rule: RecurrenceRule(freq: .daily))
        let list = s.buildReminders()
        // The window is today and the 14 days after it: 4 Oct to 18 Oct. The series starts on 5 Oct.
        #expect(list.count == 14)
        #expect(list.first?.day == monday)
        #expect(list.last?.day == DayKey("2026-10-18"))
        #expect(Set(list.map(\.id)).count == list.count)
    }

    @Test func anEventPastTheWindowIsLeftOut() throws {
        clean(); defer { clean() }
        let s = try makeStore()
        try addEvent(s, day: DayKey("2026-11-20"))
        #expect(s.buildReminders().isEmpty)
    }

    @Test func anEventThatAlreadyStartedIsLeftOut() throws {
        clean(); defer { clean() }
        let s = try makeStore()
        s.clockOverride = WallTime(day: monday, minute: 9 * 60 + 3)   // 3 minutes into it
        try addEvent(s)
        #expect(s.buildReminders().isEmpty)
    }

    // MARK: Sending the list

    @Test func refreshSendsTheListWhenAllowed() async throws {
        clean(); defer { clean() }
        let fake = FakeNotifier(status: .allowed)
        let s = try makeStore(notifier: fake)
        try addEvent(s)
        await s.refreshReminders()
        #expect(fake.sent.count == 1)
        #expect(fake.sent[0].map(\.id) == ["ev-E1-2026-10-05T09:00"])
        #expect(s.notifyStatus == .allowed)
    }

    @Test func switchedOffSendsAnEmptyListSoOldOnesGoAway() async throws {
        clean(); defer { clean() }
        let fake = FakeNotifier(status: .allowed)
        let s = try makeStore(notifier: fake)
        try addEvent(s)
        s.setNotifyEnabled(false)
        await s.refreshReminders()
        #expect(fake.sent.last == [])
    }

    @Test func nothingIsSentWhenTheUserSaidNoOrWasNeverAsked() async throws {
        clean(); defer { clean() }
        for status in [NotifyAuthorization.denied, .notAsked] {
            let fake = FakeNotifier(status: status)
            let s = try makeStore(notifier: fake)
            try addEvent(s)
            await s.refreshReminders()
            #expect(fake.sent.isEmpty)
            #expect(s.notifyStatus == status)
        }
    }

    @Test func askingForPermissionSchedulesAtOnceWhenGranted() async throws {
        clean(); defer { clean() }
        let fake = FakeNotifier(status: .notAsked, answer: .allowed)
        let s = try makeStore(notifier: fake)
        try addEvent(s)
        await s.askForNotifications()
        #expect(s.notifyStatus == .allowed)
        #expect(fake.sent.count == 1)
    }

    @Test func askingForPermissionAndGettingNoSendsNothing() async throws {
        clean(); defer { clean() }
        let fake = FakeNotifier(status: .notAsked, answer: .denied)
        let s = try makeStore(notifier: fake)
        try addEvent(s)
        await s.askForNotifications()
        #expect(s.notifyStatus == .denied)
        #expect(fake.sent.isEmpty)
    }

    @Test func manyChangesInARowMakeOneRefresh() async throws {
        clean(); defer { clean() }
        let fake = FakeNotifier(status: .allowed)
        let s = try makeStore(notifier: fake)
        s.reminderDelay = .milliseconds(40)
        try addEvent(s)
        for _ in 0..<5 { s.scheduleReminderRefresh() }
        #expect(fake.sent.isEmpty)   // not yet: it waits
        try await Task.sleep(for: .milliseconds(400))
        #expect(fake.sent.count == 1)
    }

    @Test func aSavedChangeMakesTheRemindersAgain() async throws {
        clean(); defer { clean() }
        let fake = FakeNotifier(status: .allowed)
        let s = try makeStore(notifier: fake)
        s.reminderDelay = .milliseconds(20)
        var t = TaskItem(id: "T1", title: "Send invoice")
        t.due = "2026-10-05T17:00"
        #expect(s.commit(Mutation(name: "Add task", tasks: [(before: nil, after: t)])))
        try await Task.sleep(for: .milliseconds(400))
        #expect(fake.sent.count == 1)
        #expect(fake.sent[0].map(\.id) == ["due-T1-2026-10-05T17:00"])
    }

    // MARK: Settings

    @Test func theSwitchAndTheLeadAreSaved() throws {
        clean(); defer { clean() }
        let a = try makeStore()
        #expect(a.notifyEnabled)
        #expect(a.notifyLead == 5)
        a.setNotifyEnabled(false)
        a.setNotifyLead(15)
        let b = try makeStore()
        #expect(!b.notifyEnabled)
        #expect(b.notifyLead == 15)
    }

    // MARK: A click on a notification

    @Test func aClickOnABlockReminderOpensItsTaskOnItsDay() throws {
        clean(); defer { clean() }
        let fake = FakeNotifier()
        let s = try makeStore(notifier: fake)
        var t = TaskItem(id: "T1", title: "Write report")
        t.planDate = monday
        try s.repos.tasks.save(t)
        s.screen = .notes
        #expect(fake.onOpen != nil)
        fake.onOpen?(monday, ItemRef(.task, "T1"))
        #expect(s.screen == .planner)   // that Monday is not today
        #expect(s.selectedDay == monday)
        #expect(s.selectedTaskId == "T1")
    }

    @Test func aClickOnAnEventReminderOpensItsDayEvenWhenTheEventIsGone() throws {
        clean(); defer { clean() }
        let fake = FakeNotifier()
        let s = try makeStore(notifier: fake)
        s.screen = .notes
        fake.onOpen?(monday, ItemRef(.event, "gone"))
        #expect(s.screen == .planner)   // that Monday is not today
        #expect(s.selectedDay == monday)
    }
}

/// The words in the Notifications tab of Settings.
struct NotificationSettingsRulesTests {
    @Test func leadChoicesReadInPlainWords() {
        #expect(ReminderPlanner.leadChoices.map(SettingsRules.leadText) ==
                ["When it starts", "5 minutes before", "10 minutes before", "15 minutes before"])
        #expect(SettingsRules.leadText(1) == "1 minute before")
    }

    @Test func eachStatusHasAQuietNote() {
        #expect(SettingsRules.notifyStatusText(.allowed) == "Notifications are allowed for Grove.")
        #expect(SettingsRules.notifyStatusText(.notAsked) == "Grove has not asked for permission yet.")
        #expect(SettingsRules.notifyStatusText(.denied).contains("System Settings"))
    }
}
