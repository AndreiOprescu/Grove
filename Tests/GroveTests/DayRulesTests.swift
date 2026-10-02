import Testing
import Foundation
import GroveCore
@testable import Grove

/// The rules behind the day panel, the done log and the weekly review (PLAN §5.5 items 4, 5 and 10).
struct DayRulesTests {
    let monday = DayKey("2026-09-28")
    let tuesday = DayKey("2026-09-29")

    private func at(_ day: DayKey, _ minute: Int) -> WallTime { WallTime(day: day, minute: minute) }
    private func task(_ title: String, id: String? = nil, done: Bool = false, plan: DayKey? = nil) -> TaskItem {
        var t = TaskItem(id: id ?? title, title: title, bucket: plan == nil ? .week : .day, planDate: plan)
        if done { t.status = .done }
        return t
    }
    private func event(_ title: String, _ start: WallTime, _ end: WallTime, allDay: Bool = false) -> EventItem {
        EventItem(id: title, title: title, start: start, end: end, allDay: allDay)
    }
    private func block(of t: TaskItem, _ start: WallTime, _ end: WallTime) -> EventItem {
        EventItem(id: "block-\(t.id)", title: t.title, start: start, end: end, kind: .block, taskId: t.id)
    }
    private func lookup(_ tasks: [TaskItem]) -> (String) -> TaskItem? { { id in tasks.first { $0.id == id } } }

    // MARK: The day panel

    @Test func aDayShowsAllDayFirstThenTimedThenLooseTasks() {
        let loneOpen = task("Open one", plan: tuesday), loneDone = task("Done one", done: true, plan: tuesday)
        let events = [
            event("Lunch", at(tuesday, 720), at(tuesday, 780)),
            event("Holiday", at(tuesday, 0), at(tuesday.adding(days: 1), 0), allDay: true),
            event("Standup", at(tuesday, 540), at(tuesday, 555)),
        ]
        let rows = DayRules.agenda(day: tuesday, events: events, dayTasks: [loneDone, loneOpen], taskFor: lookup([loneOpen, loneDone]))
        #expect(rows.map(\.title) == ["Holiday", "Standup", "Lunch", "Open one", "Done one"])
        #expect(rows.map(\.kind) == [.event, .event, .event, .task, .task])
    }

    @Test func aTaskWithABlockShowsOnceAsItsBlock() {
        let t = task("Write report", done: true, plan: tuesday)
        let rows = DayRules.agenda(day: tuesday, events: [block(of: t, at(tuesday, 600), at(tuesday, 660))], dayTasks: [t], taskFor: lookup([t]))
        #expect(rows.count == 1)
        #expect(rows[0].kind == .block && rows[0].done && rows[0].title == "Write report")
        #expect(rows[0].ref == ItemRef(.task, t.id))
    }

    @Test func aBlockWhoseTaskIsGoneShowsAsAnEvent() {
        let ghost = task("Gone")
        let rows = DayRules.agenda(day: tuesday, events: [block(of: ghost, at(tuesday, 600), at(tuesday, 660))], dayTasks: [], taskFor: { _ in nil })
        #expect(rows.map(\.kind) == [.event])
        #expect(rows[0].ref.type == .event)
    }

    @Test func eventsThatCrossMidnightAreClippedToTheDay() {
        let late = event("Party", at(monday, 1380), at(tuesday, 90))
        let first = DayRules.agenda(day: monday, events: [late], dayTasks: [], taskFor: { _ in nil })
        let second = DayRules.agenda(day: tuesday, events: [late], dayTasks: [], taskFor: { _ in nil })
        #expect(first[0].start == 1380 && first[0].end == 1440)
        #expect(second[0].start == 0 && second[0].end == 90)
        #expect(DayRules.timeLabel(first[0]) == "23:00–23:59")
        #expect(DayRules.timeLabel(second[0]) == "00:00–01:30")
    }

    @Test func eventsOfOtherDaysAreLeftOut() {
        let other = event("Other", at(monday, 600), at(monday, 660))
        #expect(DayRules.agenda(day: tuesday, events: [other], dayTasks: [], taskFor: { _ in nil }).isEmpty)
    }

    @Test func timeLabels() {
        let allDay = AgendaRow(id: "a", kind: .event, title: "A", allDay: true, ref: ItemRef(.event, "a"))
        let range = AgendaRow(id: "b", kind: .event, title: "B", start: 540, end: 630, ref: ItemRef(.event, "b"))
        let point = AgendaRow(id: "c", kind: .event, title: "C", start: 540, end: 540, ref: ItemRef(.event, "c"))
        let loose = AgendaRow(id: "d", kind: .task, title: "D", ref: ItemRef(.task, "d"))
        #expect(DayRules.timeLabel(allDay) == "All day")
        #expect(DayRules.timeLabel(range) == "09:00–10:30")
        #expect(DayRules.timeLabel(point) == "09:00")
        #expect(DayRules.timeLabel(loose) == "")
    }

    // MARK: The done log

    @Test func finishedClockReadsTheTimeOfDay() {
        var t = task("A", done: true)
        t.completedAt = "2026-10-02T14:35:10"
        #expect(DayRules.finishedClock(t) == "14:35")
        t.completedAt = nil
        #expect(DayRules.finishedClock(t) == "")
        t.completedAt = "2026-10-02"
        #expect(DayRules.finishedClock(t) == "")
    }

    // MARK: The weekly review

    @Test func reviewCountsOpenTasksOnceAndPutsTasksWithADayFirst() {
        let weekTask = task("Week goal")
        let dayTask = task("Day job", plan: tuesday)
        let finished = task("Finished", done: true, plan: monday)
        var cancelled = task("Dropped", plan: monday)
        cancelled.status = .cancelled
        let r = DayRules.review(monday: monday, done: [finished], openCandidates: [weekTask, dayTask, dayTask, finished, cancelled],
                                events: [], taskFor: lookup([]))
        #expect(r.open.map(\.title) == ["Day job", "Week goal"])
        #expect(r.done.map(\.title) == ["Finished"])
    }

    @Test func reviewAddsUpTaskBlockHoursAndTheDoneShare() {
        let a = task("A", done: true, plan: monday), b = task("B", plan: tuesday)
        let events = [
            block(of: a, at(monday, 600), at(monday, 720)),      // 2h, done
            block(of: b, at(tuesday, 540), at(tuesday, 600)),    // 1h, open
            event("Standup", at(tuesday, 480), at(tuesday, 495)),   // not a task block
        ]
        let r = DayRules.review(monday: monday, done: [a], openCandidates: [b], events: events, taskFor: lookup([a, b]))
        #expect(r.plannedMinutes == 180)
        #expect(r.doneMinutes == 120)
    }

    @Test func theBusiestDayCountsTimedEventsToo() {
        let a = task("A", plan: monday)
        let events = [
            block(of: a, at(monday, 600), at(monday, 720)),              // monday: 120
            event("Workshop", at(tuesday, 540), at(tuesday, 780)),       // tuesday: 240
            event("Holiday", at(monday, 0), at(monday.adding(days: 1), 0), allDay: true),   // all day counts for nothing
        ]
        let r = DayRules.review(monday: monday, done: [], openCandidates: [a], events: events, taskFor: lookup([a]))
        #expect(r.busiest == BusyDay(day: tuesday, minutes: 240))
    }

    @Test func aTieGoesToTheEarlierDay() {
        let events = [event("One", at(tuesday, 540), at(tuesday, 600)), event("Two", at(monday, 540), at(monday, 600))]
        let r = DayRules.review(monday: monday, done: [], openCandidates: [], events: events, taskFor: lookup([]))
        #expect(r.busiest == BusyDay(day: monday, minutes: 60))
    }

    @Test func anEventThatCrossesMidnightCountsOnBothDays() {
        let events = [event("Night", at(monday, 1320), at(tuesday, 120))]   // 2h before midnight, 2h after
        let r = DayRules.review(monday: monday, done: [], openCandidates: [], events: events, taskFor: lookup([]))
        #expect(r.busiest == BusyDay(day: monday, minutes: 120))
    }

    @Test func aWeekWithNoTimeHasNoBusiestDay() {
        let r = DayRules.review(monday: monday, done: [], openCandidates: [], events: [], taskFor: lookup([]))
        #expect(r.busiest == nil && r.plannedMinutes == 0 && r.doneMinutes == 0)
    }

    // MARK: The summary text

    private func sample() -> WeekReview {
        WeekReview(monday: monday, done: [task("Write report", id: "T1", done: true)], open: [task("Call Sam", id: "T2")],
                   plannedMinutes: 150, doneMinutes: 60, busiest: BusyDay(day: tuesday, minutes: 180))
    }

    @Test func theSummaryIsPlainLinesWithMentions() {
        #expect(DayRules.summary(sample()) == """
        **Week summary**
        - Done: 1 task
        - Still open: 1 task
        - Time: 1h finished of 2h 30m planned
        - Busiest day: Tuesday, 3h
        - Finished: [[Write report|T1]]
        - Left open: [[Call Sam|T2]]
        """)
    }

    @Test func anEmptyWeekGetsASmallSummary() {
        let r = WeekReview(monday: monday, done: [], open: [], plannedMinutes: 0, doneMinutes: 0, busiest: nil)
        #expect(DayRules.summary(r) == """
        **Week summary**
        - Done: 0 tasks
        - Still open: 0 tasks
        - Time: no task blocks planned
        """)
    }

    @Test func aLongListEndsWithAndNMore() {
        let many = (1...10).map { task("Task \($0)", id: "T\($0)", done: true) }
        let r = WeekReview(monday: monday, done: many, open: [], plannedMinutes: 0, doneMinutes: 0, busiest: nil)
        let line = DayRules.summary(r).components(separatedBy: "\n").first { $0.hasPrefix("- Finished:") } ?? ""
        #expect(line.hasSuffix("[[Task 8|T8]] and 2 more"))
        #expect(!line.contains("Task 9"))
    }

    @Test func aTitleWithBracketsStaysOneMention() {
        let id = "11111111-2222-3333-4444-555555555555"
        let r = WeekReview(monday: monday, done: [task("Fix [[odd]] | title", id: id, done: true)], open: [],
                           plannedMinutes: 0, doneMinutes: 0, busiest: nil)
        let line = DayRules.summary(r).components(separatedBy: "\n").first { $0.hasPrefix("- Finished:") } ?? ""
        #expect(line == "- Finished: " + ReferenceParser.mention(title: "Fix [[odd]] | title", id: id))
        #expect(ReferenceParser.mentions(in: line).map(\.id) == [id])
    }

    // MARK: Putting the summary in the note

    private let block = "**Week summary**\n- Done: 1 task"

    @Test func theSummaryGoesUnderTheReviewHeading() {
        #expect(DayRules.insert(block, into: "## Goals\n- x\n\n## Review\n") == "## Goals\n- x\n\n## Review\n\(block)\n")
    }

    @Test func textUnderTheHeadingStaysBelowTheSummary() {
        #expect(DayRules.insert(block, into: "## Review\nGood week.") == "## Review\n\(block)\n\nGood week.")
    }

    @Test func aSecondInsertReplacesTheFirstAndKeepsTheRest() {
        let first = DayRules.insert("**Week summary**\n- Done: 1 task\n- Still open: 3 tasks", into: "## Review\nGood week.")
        let second = DayRules.insert(block, into: first)
        #expect(second == "## Review\n\(block)\n\nGood week.")
        #expect(DayRules.insert(block, into: second) == second)
    }

    @Test func aNoteWithoutTheHeadingGetsOneAtTheEnd() {
        #expect(DayRules.insert(block, into: "Some text\n") == "Some text\n\n## Review\n\(block)\n")
        #expect(DayRules.insert(block, into: "") == "## Review\n\(block)\n")
    }

    @Test func hasSummaryFindsTheHeadingLine() {
        #expect(DayRules.hasSummary("## Review\n\(block)"))
        #expect(!DayRules.hasSummary("## Review\nNothing yet"))
        #expect(!DayRules.hasSummary("text **Week summary** inside a line"))
    }
}
