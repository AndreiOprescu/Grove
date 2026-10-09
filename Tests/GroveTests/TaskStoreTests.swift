import Testing
import Foundation
import GroveCore
@testable import Grove

@MainActor
struct TaskStoreTests {
    func makeStore() throws -> AppStore { AppStore(repos: Repos(db: try Database.inMemory())) }
    let today = DayKey.today()
    var monday: DayKey { today.weekStart().adding(days: 14) }   // a Monday two weeks ahead, never today

    private func order(_ s: AppStore, _ placement: TaskPlacement) -> [String] {
        s.openTasks(in: placement).map(\.title)
    }

    // MARK: quick add

    @Test func quickAddMakesTaskAndBlockAndUndoRemovesAll() throws {
        let s = try makeStore()
        try s.repos.lists.save(ListItem(name: "Home"))
        let t = try #require(s.quickAdd("Call mum tomorrow 6pm for 20m #home /home !2"))
        let tomorrow = today.adding(days: 1)
        let task = try #require(s.task(t.id))
        #expect(task.title == "Call mum" && task.bucket == .day && task.planDate == tomorrow)
        #expect(task.priority == 2 && task.estimateMin == 20)
        #expect(task.listId == (try s.repos.lists.all().first { $0.name == "Home" })?.id)
        #expect(try s.repos.tags.tags(forTask: t.id) == ["home"])
        let block = try #require(s.blocks(for: tomorrow...tomorrow).first)
        #expect(block.taskId == t.id && block.startMinute == 18 * 60 && block.endMinute == 18 * 60 + 20)

        s.undo()
        #expect(try s.repos.tasks.all().isEmpty)
        #expect(s.blocks(for: tomorrow...tomorrow).isEmpty)
        #expect(try s.repos.tags.tags(forTask: t.id).isEmpty)
        s.redo()
        #expect(try s.repos.tags.tags(forTask: t.id) == ["home"])
        #expect(s.blocks(for: tomorrow...tomorrow).count == 1)
    }

    @Test func quickAddWithoutADateUsesTheDefaultPlacement() throws {
        let s = try makeStore()
        let a = try #require(s.quickAdd("Buy milk", default: .day(monday)))
        #expect(s.task(a.id)?.bucket == .day && s.task(a.id)?.planDate == monday)
        let b = try #require(s.quickAdd("Learn piano", default: .someday))
        #expect(s.task(b.id)?.bucket == .someday)
        let c = try #require(s.quickAdd("Plan trip", default: .week(monday)))
        #expect(s.task(c.id)?.bucket == .week && s.task(c.id)?.planWeek == monday)
        let d = try #require(s.quickAdd("Sort mail"))
        #expect(s.task(d.id)?.bucket == .inbox)
    }

    @Test func aDateInTheTextBeatsTheDefaultPlacement() throws {
        let s = try makeStore()
        let t = try #require(s.quickAdd("Read ch 5 next week", default: .someday))
        #expect(s.task(t.id)?.bucket == .week)
        #expect(s.task(t.id)?.planWeek == today.weekStart().adding(days: 7))
    }

    @Test func emptyTextMakesNothing() throws {
        let s = try makeStore()
        #expect(s.quickAdd("   ") == nil)
        #expect(try s.repos.tasks.all().isEmpty)
        #expect(s.undoName == nil)
    }

    @Test func newTasksGoToTheEndOfTheList() throws {
        let s = try makeStore()
        _ = s.quickAdd("One"); _ = s.quickAdd("Two"); _ = s.quickAdd("Three")
        #expect(order(s, .inbox) == ["One", "Two", "Three"])
    }

    // MARK: completing and repeating

    private func repeatingTask(_ s: AppStore) throws -> TaskItem {
        var t = TaskItem(title: "Gym", bucket: .day, planDate: monday, estimateMin: 60,
                         recurrence: RecurrenceRule(freq: .weekly, weekdays: [1]))
        t.notes = "bring towel"
        try s.repos.tasks.save(t)
        var done = TaskItem(title: "Pack bag", parentId: t.id); done.status = .done
        try s.repos.tasks.save(done)
        try s.repos.tasks.save(TaskItem(title: "Fill bottle", parentId: t.id))
        try s.repos.events.save(EventItem(title: "Gym", start: WallTime(day: monday, minute: 420), end: WallTime(day: monday, minute: 480),
                                          kind: .block, taskId: t.id))
        return t
    }

    @Test func completingARepeatingTaskMakesTheNextOne() throws {
        let s = try makeStore()
        let t = try repeatingTask(s)
        s.toggleDone(taskId: t.id)
        #expect(s.task(t.id)?.isDone == true)

        let nextDay = monday.adding(days: 7)
        let nexts = try s.repos.tasks.forDay(nextDay)
        let next = try #require(nexts.first)
        #expect(nexts.count == 1 && next.id != t.id)
        #expect(next.title == "Gym" && next.status == .open && next.notes == "bring towel" && next.recurrence == t.recurrence)
        let subs = try s.repos.tasks.subtasks(of: next.id)
        #expect(subs.map(\.title).sorted() == ["Fill bottle", "Pack bag"])
        #expect(subs.allSatisfy { $0.status == .open })
        let block = try #require(s.blocks(for: nextDay...nextDay).first)
        #expect(block.taskId == next.id && block.startMinute == 420 && block.endMinute == 480)
        // the finished one keeps its own block
        #expect(s.blocks(for: monday...monday).count == 1)

        s.undo()
        #expect(s.task(t.id)?.isDone == false)
        #expect(try s.repos.tasks.forDay(nextDay).isEmpty)
        #expect(s.blocks(for: nextDay...nextDay).isEmpty)
    }

    @Test func aLateRepeatingTaskNeverGetsADateInThePast() throws {
        let s = try makeStore()
        let past = today.adding(days: -10)
        let t = TaskItem(title: "Water plants", bucket: .day, planDate: past, recurrence: RecurrenceRule(freq: .daily))
        try s.repos.tasks.save(t)
        s.toggleDone(taskId: t.id)
        let next = try #require(try s.repos.tasks.all().first { $0.id != t.id })
        #expect(next.planDate == today.adding(days: 1))
    }

    @Test func aPlainTaskMakesNoCopy() throws {
        let s = try makeStore()
        let t = try #require(s.quickAdd("One-off"))
        s.toggleDone(taskId: t.id)
        #expect(try s.repos.tasks.all().count == 1)
        s.toggleDone(taskId: t.id)
        #expect(s.task(t.id)?.isDone == false && s.task(t.id)?.completedAt == nil)
    }

    @Test func reopeningARepeatingTaskDoesNotMakeAnotherCopy() throws {
        let s = try makeStore()
        let t = try repeatingTask(s)
        s.toggleDone(taskId: t.id)
        let after = try s.repos.tasks.all().count
        s.toggleDone(taskId: t.id)   // reopen
        #expect(try s.repos.tasks.all().count == after)
    }

    // MARK: subtasks, edit, tags

    @Test func addSubtask() throws {
        let s = try makeStore()
        let t = try #require(s.quickAdd("Trip"))
        s.addSubtask(to: t.id, title: "  Book hotel ")
        s.addSubtask(to: t.id, title: "   ")
        let subs = try s.repos.tasks.subtasks(of: t.id)
        #expect(subs.map(\.title) == ["Book hotel"])
        s.undo()
        #expect(try s.repos.tasks.subtasks(of: t.id).isEmpty)
    }

    @Test func editTaskIsUndoable() throws {
        let s = try makeStore()
        let t = try #require(s.quickAdd("Draft"))
        s.editTask(t.id, name: "Edit Task") { $0.title = "Final"; $0.priority = 3 }
        #expect(s.task(t.id)?.title == "Final" && s.task(t.id)?.priority == 3)
        #expect(s.undoName == "Edit Task")
        s.undo()
        #expect(s.task(t.id)?.title == "Draft" && s.task(t.id)?.priority == 0)
    }

    @Test func setTagsIsUndoable() throws {
        let s = try makeStore()
        let t = try #require(s.quickAdd("Tagged #a"))
        s.setTags(taskId: t.id, to: ["b", "c"])
        #expect(try s.repos.tags.tags(forTask: t.id) == ["b", "c"])
        s.undo()
        #expect(try s.repos.tags.tags(forTask: t.id) == ["a"])
    }

    // MARK: moving and reordering

    @Test func movingToAnotherDayShiftsItsBlocksAndUndoPutsThemBack() throws {
        let s = try makeStore()
        let t = try #require(s.quickAdd("Write", default: .day(monday)))
        s.schedule(taskId: t.id, day: monday, start: 600, length: 60)
        let other = monday.adding(days: 1)
        s.moveTask(t.id, to: .day(other))
        #expect(s.task(t.id)?.planDate == other)
        let b = try #require(s.blocks(for: other...other).first)
        #expect(b.startMinute == 600 && b.endMinute == 660)
        #expect(s.blocks(for: monday...monday).isEmpty)
        s.undo()
        #expect(s.task(t.id)?.planDate == monday)
        #expect(s.blocks(for: monday...monday).count == 1)
        #expect(s.blocks(for: other...other).isEmpty)
    }

    @Test func movingOffTheCalendarRemovesBlocks() throws {
        let s = try makeStore()
        let t = try #require(s.quickAdd("Write", default: .day(monday)))
        s.schedule(taskId: t.id, day: monday, start: 600, length: 60)
        s.moveTask(t.id, to: .someday)
        #expect(s.task(t.id)?.bucket == .someday && s.task(t.id)?.planDate == nil)
        #expect(s.blocks(for: monday...monday).isEmpty)
        s.undo()
        #expect(s.blocks(for: monday...monday).count == 1)
        #expect(s.task(t.id)?.bucket == .day)
    }

    @Test func movingToAWeekSetsTheMonday() throws {
        let s = try makeStore()
        let t = try #require(s.quickAdd("Plan"))
        s.moveTask(t.id, to: .week(monday.adding(days: 3)))
        #expect(s.task(t.id)?.bucket == .week && s.task(t.id)?.planWeek == monday && s.task(t.id)?.planDate == nil)
    }

    @Test func reorderPutsATaskBeforeAnother() throws {
        let s = try makeStore()
        _ = s.quickAdd("A"); _ = s.quickAdd("B"); let c = try #require(s.quickAdd("C"))
        let a = try #require(s.openTasks(in: .inbox).first)
        s.moveTask(c.id, to: .inbox, before: a.id)
        #expect(order(s, .inbox) == ["C", "A", "B"])
        s.moveTask(c.id, to: .inbox, before: nil)   // to the end
        #expect(order(s, .inbox) == ["A", "B", "C"])
        s.undo()
        #expect(order(s, .inbox) == ["C", "A", "B"])
    }

    @Test func reorderWorksWhenAllSortValuesAreEqual() throws {
        let s = try makeStore()
        for name in ["A", "B", "C"] { try s.repos.tasks.save(TaskItem(title: name, sort: 0)) }
        let first = try #require(s.openTasks(in: .inbox).first)
        let last = try #require(s.openTasks(in: .inbox).last)
        s.moveTask(last.id, to: .inbox, before: first.id)
        #expect(order(s, .inbox) == ["C", "A", "B"])
    }

    @Test func dropBetweenTwoTasksKeepsTheOthersUntouched() throws {
        let s = try makeStore()
        _ = s.quickAdd("A"); _ = s.quickAdd("B"); _ = s.quickAdd("C"); let d = try #require(s.quickAdd("D"))
        let b = try #require(s.openTasks(in: .inbox).first { $0.title == "B" })
        let before = Dictionary(uniqueKeysWithValues: s.openTasks(in: .inbox).map { ($0.id, $0.sort) })
        s.moveTask(d.id, to: .inbox, before: b.id)
        #expect(order(s, .inbox) == ["A", "D", "B", "C"])
        for t in s.openTasks(in: .inbox) where t.id != d.id { #expect(before[t.id] == t.sort) }
    }

    @Test func movingFromAnotherListLandsAtTheDropPosition() throws {
        let s = try makeStore()
        let x = try #require(s.quickAdd("X", default: .someday))
        _ = s.quickAdd("A"); _ = s.quickAdd("B")
        let b = try #require(s.openTasks(in: .inbox).first { $0.title == "B" })
        s.moveTask(x.id, to: .inbox, before: b.id)
        #expect(order(s, .inbox) == ["A", "X", "B"])
        #expect(order(s, .someday).isEmpty)
    }

    // MARK: deleting

    @Test func deletingATaskTakesItsSubtasksAndBlocksAndUndoBringsThemAllBack() throws {
        let s = try makeStore()
        let t = try #require(s.quickAdd("Trip #travel", default: .day(monday)))
        s.addSubtask(to: t.id, title: "Book hotel")
        s.schedule(taskId: t.id, day: monday, start: 540, length: 30)
        s.deleteTask(t.id)
        #expect(try s.repos.tasks.all().isEmpty)
        #expect(s.blocks(for: monday...monday).isEmpty)
        s.undo()
        #expect(try s.repos.tasks.all().count == 2)
        #expect(try s.repos.tasks.subtasks(of: t.id).map(\.title) == ["Book hotel"])
        #expect(s.blocks(for: monday...monday).count == 1)
        #expect(try s.repos.tags.tags(forTask: t.id) == ["travel"])
        s.redo()
        #expect(try s.repos.tasks.all().isEmpty)
    }

    @Test func deletingTheOpenTaskClosesItsPanel() throws {
        let s = try makeStore()
        let t = try #require(s.quickAdd("Trip", default: .day(monday)))
        let other = try #require(s.quickAdd("Other", default: .day(monday)))
        s.selectedTaskId = t.id
        s.deleteTask(other.id)
        #expect(s.selectedTaskId == t.id)
        s.deleteTask(t.id)
        #expect(s.selectedTaskId == nil)
    }

    @Test func deletingAParentClosesTheOpenSubtaskAndDropsItsSelectedBlocks() throws {
        let s = try makeStore()
        let t = try #require(s.quickAdd("Trip", default: .day(monday)))
        s.addSubtask(to: t.id, title: "Book hotel")
        let sub = try #require(try s.repos.tasks.subtasks(of: t.id).first)
        s.schedule(taskId: t.id, day: monday, start: 540, length: 30)
        let block = try #require(s.blocks(for: monday...monday).first)
        s.selectedTaskId = sub.id
        s.selection = [block.id]
        s.deleteTask(t.id)
        #expect(s.selectedTaskId == nil)
        #expect(s.selection.isEmpty)
    }

    // MARK: mentions

    @Test func bodyMentionsBecomeLinksAndRenamesFollow() throws {
        let s = try makeStore()
        let target = try #require(s.quickAdd("Old title"))
        let host = try #require(s.quickAdd("Host"))
        s.editTask(host.id, name: "Edit Notes") { $0.notes = "needs [[old TITLE]]" }
        #expect(s.task(host.id)?.notes == "needs [[Old title|\(target.id)]]")
        #expect(try s.repos.links.backlinks(to: ItemRef(.task, target.id)) == [ItemRef(.task, host.id)])

        s.editTask(target.id, name: "Rename Task") { $0.title = "Fresh title" }
        #expect(s.task(host.id)?.notes == "needs [[Fresh title|\(target.id)]]")
        s.undo()
        #expect(s.task(host.id)?.notes == "needs [[Old title|\(target.id)]]")
        s.redo()
        #expect(s.task(host.id)?.notes == "needs [[Fresh title|\(target.id)]]")
    }

    @Test func undoingADeleteBringsIncomingLinksBack() throws {
        let s = try makeStore()
        let target = try #require(s.quickAdd("Target"))
        let host = try #require(s.quickAdd("Host"))
        s.editTask(host.id, name: "Edit Notes") { $0.notes = "see [[Target]]" }
        s.deleteTask(target.id)
        #expect(try s.repos.links.backlinks(to: ItemRef(.task, target.id)).isEmpty)
        s.undo()
        #expect(try s.repos.links.backlinks(to: ItemRef(.task, target.id)) == [ItemRef(.task, host.id)])
    }
}
