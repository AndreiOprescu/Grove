import Testing
import Foundation
@testable import GroveCore

/// Which reminders to ask the system for (PLAN §5.6). Plain data in, plain list out.
struct ReminderPlannerTests {
    private let day = DayKey("2026-10-05")
    private func at(_ minute: Int, _ d: DayKey? = nil) -> WallTime { WallTime(day: d ?? day, minute: minute) }

    private func event(_ id: String, _ title: String, from: Int, to: Int, day d: DayKey? = nil,
                       allDay: Bool = false, kind: EventKind = .event, taskId: String? = nil) -> EventItem {
        EventItem(id: id, title: title, start: at(from, d), end: at(to, d), allDay: allDay, kind: kind, taskId: taskId)
    }

    private func plan(_ events: [EventItem] = [], due: [TaskItem] = [], finished: Set<String> = [],
                      now: Int = 8 * 60, lead: Int = 5, limit: Int = ReminderPlanner.limit) -> [Reminder] {
        ReminderPlanner.plan(events: events, dueTasks: due, finishedTaskIds: finished, now: at(now), lead: lead, limit: limit)
    }

    // MARK: One event

    @Test func anEventRemindsOnTheLeadTimeBeforeItStarts() {
        let r = plan([event("E1", "Stand-up", from: 9 * 60 + 30, to: 10 * 60)])
        #expect(r.count == 1)
        #expect(r[0].fireAt == at(9 * 60 + 25))
        #expect(r[0].title == "Stand-up")
        #expect(r[0].body == "09:30 – 10:00")
        #expect(r[0].day == day && r[0].ref == ItemRef(.event, "E1"))
    }

    @Test func theIdHasTheEventAndItsStart() {
        let r = plan([event("E1", "Stand-up", from: 570, to: 600)])
        #expect(r[0].id == "ev-E1-2026-10-05T09:30")
    }

    @Test func leadTimeZeroRemindsAtTheStart() {
        #expect(plan([event("E1", "x", from: 600, to: 660)], lead: 0)[0].fireAt == at(600))
        #expect(plan([event("E1", "x", from: 600, to: 660)], lead: 15)[0].fireAt == at(585))
    }

    @Test func aReminderCanFallOnTheDayBefore() throws {
        let early = event("E1", "Flight", from: 3, to: 120)
        let r = ReminderPlanner.plan(events: [early], dueTasks: [], finishedTaskIds: [], now: at(20 * 60, DayKey("2026-10-04")), lead: 10)
        try #require(r.isEmpty == false)
        #expect(r[0].fireAt == WallTime(day: DayKey("2026-10-04"), minute: 24 * 60 - 7))
        #expect(r[0].day == day)   // clicking it still opens the day of the event
    }

    // MARK: What is left out

    @Test func allDayEventsAreLeftOut() {
        #expect(plan([event("E1", "Holiday", from: 0, to: 1440, allDay: true)]).isEmpty)
    }

    @Test func aReminderThatIsAlreadyPastIsLeftOut() {
        // 08:00 now, event at 08:03, lead 5: the reminder time (07:58) has passed.
        #expect(plan([event("E1", "x", from: 8 * 60 + 3, to: 9 * 60)], now: 8 * 60).isEmpty)
        // Exactly now is past too. The system can only fire in the future.
        #expect(plan([event("E1", "x", from: 8 * 60 + 5, to: 9 * 60)], now: 8 * 60).isEmpty)
        #expect(plan([event("E1", "x", from: 8 * 60 + 6, to: 9 * 60)], now: 8 * 60).count == 1)
    }

    @Test func aBlockOfAFinishedTaskIsLeftOut() {
        let block = event("B1", "Write report", from: 600, to: 660, kind: .block, taskId: "T1")
        #expect(plan([block], finished: ["T1"]).isEmpty)
        #expect(plan([block], finished: ["T2"]).count == 1)
    }

    @Test func aBlockOpensItsTask() {
        let r = plan([event("B1", "Write report", from: 600, to: 660, kind: .block, taskId: "T1")])
        #expect(r[0].ref == ItemRef(.task, "T1"))
        #expect(r[0].id == "ev-B1-2026-10-05T10:00")
    }

    // MARK: Due times

    @Test func aTaskDueAtATimeReminds() {
        let t = TaskItem(id: "T1", title: "Send invoice", due: "2026-10-05T17:00")
        let r = plan(due: [t], lead: 10)
        #expect(r.count == 1)
        #expect(r[0].fireAt == at(16 * 60 + 50))
        #expect(r[0].body == "Due 17:00")
        #expect(r[0].ref == ItemRef(.task, "T1") && r[0].day == day)
        #expect(r[0].id == "due-T1-2026-10-05T17:00")
    }

    @Test func aDueDateWithNoTimeIsLeftOut() {
        #expect(plan(due: [TaskItem(id: "T1", title: "x", due: "2026-10-05")]).isEmpty)
    }

    @Test func aDoneOrCancelledTaskDoesNotRemind() {
        var done = TaskItem(id: "T1", title: "x", due: "2026-10-05T17:00"); done.status = .done
        var gone = TaskItem(id: "T2", title: "y", due: "2026-10-05T18:00"); gone.status = .cancelled
        #expect(plan(due: [done, gone]).isEmpty)
    }

    // MARK: The list

    @Test func theListIsInTimeOrderAndTheEarliestWinTheLimit() {
        let events = (0..<5).map { event("E\($0)", "e\($0)", from: 600 + (4 - $0) * 60, to: 700 + (4 - $0) * 60) }
        let r = plan(events, limit: 3)
        #expect(r.map(\.title) == ["e4", "e3", "e2"])
        #expect(r.map(\.fireAt) == r.map(\.fireAt).sorted())
    }

    @Test func theDefaultLimitIsSixtyBecauseTheSystemKeepsSixtyFour() {
        #expect(ReminderPlanner.limit == 60)
        let many = (0..<100).map { event("E\($0)", "e", from: 600, to: 660, day: day.adding(days: $0 + 1)) }
        #expect(plan(many).count == 60)
    }

    @Test func twoThingsAtTheSameTimeBothRemind() {
        let r = plan([event("E1", "a", from: 600, to: 660), event("E2", "b", from: 600, to: 660)])
        #expect(r.count == 2 && Set(r.map(\.id)).count == 2)
    }

    @Test func aRepeatingEventKeepsOneIdPerDay() {
        let a = event("S@2026-10-05", "Daily", from: 600, to: 630)
        let b = event("S@2026-10-06", "Daily", from: 600, to: 630, day: day.adding(days: 1))
        #expect(Set(plan([a, b]).map(\.id)).count == 2)
    }

    @Test func theLeadChoicesAreTheFourInThePlan() {
        #expect(ReminderPlanner.leadChoices == [0, 5, 10, 15])
        #expect(ReminderPlanner.defaultLead == 5)
    }
}
