import Testing
import Foundation
import GroveCore
@testable import Grove

@MainActor
struct PlannerStoreTests {
    func makeStore() throws -> AppStore { AppStore(repos: Repos(db: try Database.inMemory())) }
    let day = DayKey.today().adding(days: 3) // never "today", so "now" does not change slot maths

    @Test func draftCreatesTaskAndBlockAndUndoRemovesBoth() throws {
        let s = try makeStore()
        s.createFromDraft(title: "Write report", day: day, start: 600, end: 660, asEvent: false)
        let blocks = s.blocks(for: day...day)
        #expect(blocks.count == 1)
        #expect(blocks[0].isTaskBlock && blocks[0].title == "Write report")
        #expect(blocks[0].startMinute == 600 && blocks[0].endMinute == 660)
        let taskId = try #require(blocks[0].taskId)
        let task = try #require(s.task(taskId))
        #expect(task.bucket == .day && task.planDate == day && task.estimateMin == 60)
        s.undo()
        #expect(s.blocks(for: day...day).isEmpty)
        #expect(try s.repos.tasks.all().isEmpty)
        s.redo()
        #expect(s.blocks(for: day...day).count == 1)
        #expect(try s.repos.tasks.all().count == 1)
    }

    @Test func commandDraftMakesPlainEvent() throws {
        let s = try makeStore()
        s.createFromDraft(title: "Dentist", day: day, start: 840, end: 900, asEvent: true)
        let b = try #require(s.blocks(for: day...day).first)
        #expect(!b.isTaskBlock && b.kind == .event)
        #expect(try s.repos.tasks.all().isEmpty)
    }

    @Test func moveAndResizeAreUndoable() throws {
        let s = try makeStore()
        s.createFromDraft(title: "A", day: day, start: 600, end: 660, asEvent: true)
        let id = try #require(s.blocks(for: day...day).first).id
        s.applyEdits([BlockEdit(id: id, day: day, start: 615, end: 735)], ripple: false, name: "Move Block")
        #expect(s.blocks(for: day...day).first?.startMinute == 615)
        #expect(s.blocks(for: day...day).first?.endMinute == 735)
        s.undo()
        #expect(s.blocks(for: day...day).first?.startMinute == 600)
        #expect(s.undoName == "New Block")
    }

    @Test func movingTaskBlockToAnotherDayUpdatesTaskPlanDate() throws {
        let s = try makeStore()
        s.createFromDraft(title: "T", day: day, start: 600, end: 630, asEvent: false)
        let b = try #require(s.blocks(for: day...day).first)
        let next = day.adding(days: 1)
        s.applyEdits([BlockEdit(id: b.id, day: next, start: 600, end: 630)], ripple: false, name: "Move Block")
        #expect(s.blocks(for: day...day).isEmpty)
        #expect(s.blocks(for: next...next).count == 1)
        let tid = try #require(b.taskId)
        #expect(s.task(tid)?.planDate == next)
        s.undo()
        #expect(s.task(tid)?.planDate == day)
    }

    @Test func overlapIsAllowed() throws {
        let s = try makeStore()
        s.createFromDraft(title: "A", day: day, start: 600, end: 660, asEvent: true)
        s.createFromDraft(title: "B", day: day, start: 630, end: 690, asEvent: true)
        #expect(s.blocks(for: day...day).count == 2)
    }

    @Test func rippleWithShiftPushesLaterBlocks() throws {
        let s = try makeStore()
        s.createFromDraft(title: "A", day: day, start: 600, end: 660, asEvent: true)
        s.createFromDraft(title: "B", day: day, start: 660, end: 720, asEvent: true)
        s.createFromDraft(title: "C", day: day, start: 720, end: 780, asEvent: true)
        let a = try #require(s.blocks(for: day...day).first { $0.title == "A" })
        let pushed = s.applyEdits([BlockEdit(id: a.id, day: day, start: 600, end: 690)], ripple: true, name: "Resize Block")
        #expect(pushed == 2)
        let byTitle = Dictionary(uniqueKeysWithValues: s.blocks(for: day...day).map { ($0.title, $0) })
        #expect(byTitle["B"]?.startMinute == 690 && byTitle["B"]?.endMinute == 750)
        #expect(byTitle["C"]?.startMinute == 750 && byTitle["C"]?.endMinute == 810)
        s.undo() // one undo step reverts the resize and the push together
        let after = Dictionary(uniqueKeysWithValues: s.blocks(for: day...day).map { ($0.title, $0) })
        #expect(after["A"]?.endMinute == 660 && after["B"]?.startMinute == 660 && after["C"]?.startMinute == 720)
    }

    @Test func unscheduleKeepsTaskAndReturnsItToTray() throws {
        let s = try makeStore()
        s.createFromDraft(title: "Read", day: day, start: 600, end: 630, asEvent: false)
        #expect(s.unscheduled(for: day).isEmpty)
        let b = try #require(s.blocks(for: day...day).first)
        s.deleteBlocks([b.id], name: "Unschedule")
        #expect(s.blocks(for: day...day).isEmpty)
        #expect(s.unscheduled(for: day).map(\.title) == ["Read"])
    }

    @Test func dropTaskFromTrayUsesEstimate() throws {
        let s = try makeStore()
        let t = TaskItem(title: "Email", estimateMin: 45)
        try s.repos.tasks.save(t)
        s.schedule(taskId: t.id, day: day, start: 540)
        let b = try #require(s.blocks(for: day...day).first)
        #expect(b.startMinute == 540 && b.length == 45)
        let saved = try #require(s.task(t.id))
        #expect(saved.bucket == .day && saved.planDate == day)
    }

    @Test func aShortEstimateMakesABlockOfAtLeastFifteenMinutes() throws {
        let s = try makeStore()
        let short = TaskItem(title: "Call", estimateMin: 10)
        let odd = TaskItem(title: "Tidy", estimateMin: 20)
        try s.repos.tasks.save(short)
        try s.repos.tasks.save(odd)
        s.schedule(taskId: short.id, day: day, start: 540)
        s.schedule(taskId: odd.id, day: day, start: 600)
        let byTitle = Dictionary(uniqueKeysWithValues: s.blocks(for: day...day).map { ($0.title, $0) })
        #expect(byTitle["Call"]?.length == 15)
        #expect(byTitle["Tidy"]?.length == 30)
    }

    @Test func timelessTasksAreTheDayTasksWithNoBlock() throws {
        let s = try makeStore()
        let next = day.adding(days: 1)
        let free = TaskItem(title: "Free", bucket: .day, planDate: day)
        let urgent = TaskItem(title: "Urgent", priority: 3, bucket: .day, planDate: day)
        let blocked = TaskItem(title: "Blocked", bucket: .day, planDate: day)
        let done = TaskItem(title: "Done", status: .done, bucket: .day, planDate: day)
        let sub = TaskItem(title: "Sub", parentId: free.id, bucket: .day, planDate: day)
        let tomorrow = TaskItem(title: "Tomorrow", bucket: .day, planDate: next)
        let week = TaskItem(title: "Week", bucket: .week, planWeek: day.weekStart())
        let inbox = TaskItem(title: "Inbox")
        for t in [free, urgent, blocked, done, sub, tomorrow, week, inbox] { try s.repos.tasks.save(t) }
        s.schedule(taskId: blocked.id, day: day, start: 600)

        let map = s.timeless(for: [day, next])
        #expect(map[day]?.map(\.title) == ["Urgent", "Free"])
        #expect(map[next]?.map(\.title) == ["Tomorrow"])

        // A block on another day does not give the task a time today.
        s.schedule(taskId: free.id, day: next, start: 600)
        #expect(s.timeless(for: [day])[day]?.map(\.title) == ["Urgent"])
    }

    @Test func aBlockShorterThanHalfAnHourCannotSplit() throws {
        let s = try makeStore()
        s.createFromDraft(title: "Short", day: day, start: 600, end: 615, asEvent: true)
        let b = try #require(s.blocks(for: day...day).first)
        s.split(blockId: b.id)
        #expect(s.blocks(for: day...day).count == 1)
        s.createFromDraft(title: "Half", day: day, start: 700, end: 730, asEvent: true)
        let half = try #require(s.blocks(for: day...day).first { $0.title == "Half" })
        s.split(blockId: half.id)
        let parts = s.blocks(for: day...day).filter { $0.title == "Half" }.map { [$0.startMinute, $0.endMinute] }.sorted { $0[0] < $1[0] }
        #expect(parts == [[700, 715], [715, 730]])
    }

    @Test func fitUsesFirstFreeGap() throws {
        let s = try makeStore()
        s.createFromDraft(title: "Busy", day: day, start: 540, end: 600, asEvent: true)
        let t = TaskItem(title: "Fit me", estimateMin: 30)
        try s.repos.tasks.save(t)
        s.fit(taskId: t.id, day: day, workStart: 540, workEnd: 1080, step: 5)
        let placed = try #require(s.blocks(for: day...day).first { $0.taskId == t.id })
        #expect(placed.startMinute == 600)
    }

    @Test func planMyDayOrdersByPriority() throws {
        let s = try makeStore()
        try s.repos.tasks.save(TaskItem(title: "low", priority: 1, bucket: .day, planDate: day, estimateMin: 60))
        try s.repos.tasks.save(TaskItem(title: "high", priority: 3, bucket: .day, planDate: day, estimateMin: 30))
        let plan = s.planMyDayPreview(day: day, workStart: 540, workEnd: 1080, step: 5)
        #expect(plan.map(\.task.title) == ["high", "low"])
        #expect(plan.map(\.start) == [540, 570])
        s.applyPlan(plan, day: day)
        #expect(s.blocks(for: day...day).count == 2)
        s.undo()
        #expect(s.blocks(for: day...day).isEmpty)
    }

    @Test func duplicateSplitAndDuration() throws {
        let s = try makeStore()
        s.createFromDraft(title: "A", day: day, start: 600, end: 660, asEvent: true)
        let a = try #require(s.blocks(for: day...day).first)
        s.duplicate(blockIds: [a.id])
        #expect(s.blocks(for: day...day).map(\.startMinute).sorted() == [600, 660])
        s.split(blockId: a.id)
        #expect(s.blocks(for: day...day).count == 3)
        s.setDuration(blockIds: [a.id], minutes: 15)
        #expect(s.blocks(for: day...day).first { $0.id == a.id }?.length == 15)
    }

    @Test func completingTaskMarksBlockDone() throws {
        let s = try makeStore()
        s.createFromDraft(title: "Do it", day: day, start: 600, end: 630, asEvent: false)
        let b = try #require(s.blocks(for: day...day).first)
        let tid = try #require(b.taskId)
        s.toggleDone(taskId: tid)
        #expect(s.blocks(for: day...day).first?.isDone == true)
        s.undo()
        #expect(s.blocks(for: day...day).first?.isDone == false)
    }

    @Test func blockEndingAtMidnightRoundTrips() throws {
        let s = try makeStore()
        s.createFromDraft(title: "Late", day: day, start: 1380, end: 1440, asEvent: true)
        #expect(s.blocks(for: day...day).first?.endMinute == 1440)
    }

    // MARK: Busy-day alert

    private func addEvent(_ s: AppStore, _ start: Int, _ end: Int, day: DayKey? = nil) {
        s.createFromDraft(title: "E\(start)", day: day ?? self.day, start: start, end: end, asEvent: true)
    }

    @Test func plannedMinutesCountOverlapsOnce() throws {
        let s = try makeStore()
        addEvent(s, 600, 720)
        addEvent(s, 660, 780)   // overlaps 60 min
        #expect(s.plannedMinutes(on: day) == 180)
    }

    @Test func noAlertAtExactlyNineHours() throws {
        let s = try makeStore()
        for h in 0..<9 { addEvent(s, 480 + h * 60, 540 + h * 60) }
        #expect(s.plannedMinutes(on: day) == 540)
        #expect(s.overloadWarning == nil)
    }

    @Test func alertWhenDayPassesNineHours() throws {
        let s = try makeStore()
        for h in 0..<9 { addEvent(s, 480 + h * 60, 540 + h * 60) }
        addEvent(s, 1020, 1050)  // 9h30m
        let warning = try #require(s.overloadWarning)
        #expect(warning.contains("9h 30m"))
    }

    @Test func alertOnlyWhenCrossingNotWhileAlreadyOver() throws {
        let s = try makeStore()
        for h in 0..<9 { addEvent(s, 480 + h * 60, 540 + h * 60) }
        addEvent(s, 1020, 1050)
        s.overloadWarning = nil          // user dismissed it
        addEvent(s, 1100, 1130)          // still over: no new alert
        #expect(s.overloadWarning == nil)
    }

    @Test func movingBlockToAnotherDayCanTriggerAlert() throws {
        let s = try makeStore()
        let next = day.adding(days: 1)
        for h in 0..<9 { addEvent(s, 480 + h * 60, 540 + h * 60, day: next) }
        addEvent(s, 1200, 1230)
        let b = try #require(s.blocks(for: day...day).first)
        s.applyEdits([BlockEdit(id: b.id, day: next, start: 1200, end: 1230)], ripple: false, name: "Move Block")
        #expect(s.overloadWarning != nil)
    }

    @Test func undoDoesNotAlert() throws {
        let s = try makeStore()
        for h in 0..<9 { addEvent(s, 480 + h * 60, 540 + h * 60) }
        addEvent(s, 1020, 1050)
        s.overloadWarning = nil
        s.undo()
        s.redo()
        #expect(s.overloadWarning == nil)
    }
}
