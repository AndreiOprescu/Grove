import Testing
import Foundation
import GroveCore
@testable import Grove

/// Subtasks of one goal block on the planner. They stay on that block only.
/// The block shows them like a task block does: rows, then "+N more" or a done/total badge.
@MainActor
struct GoalBlockSubtaskTests {
    func makeStore() throws -> AppStore { AppStore(repos: Repos(db: try Database.inMemory())) }

    let monday = DayKey("2026-10-05")

    /// A goal with two blocks on Monday: 10:00 and 14:00. Returns their event ids.
    private func twoBlocks(_ s: AppStore) throws -> (String, String) {
        let g = try #require(s.addGoal(title: "Read", target: 300))
        s.scheduleGoal(goalId: g.id, day: monday, start: 600)
        s.scheduleGoal(goalId: g.id, day: monday, start: 840)
        let ids = s.blocks(for: monday...monday).filter { $0.goalId == g.id }.sorted { $0.startMinute < $1.startMinute }.map(\.id)
        try #require(ids.count == 2)
        return (ids[0], ids[1])
    }

    private func block(_ s: AppStore, _ id: String) throws -> PlannerBlock {
        try #require(s.blocks(for: monday...monday).first { $0.id == id })
    }

    // MARK: One instance only

    @Test func aSubtaskShowsOnlyInItsOwnBlock() throws {
        let s = try makeStore()
        let (a, b) = try twoBlocks(s)
        try #require(s.addBlockSubtask(to: a, title: "Chapter 3") != nil)
        try #require(s.addBlockSubtask(to: a, title: "Chapter 4") != nil)
        #expect(try block(s, a).subtasks.map(\.title) == ["Chapter 3", "Chapter 4"])
        #expect(try block(s, a).subtasks.map(\.isDone) == [false, false])
        #expect(try block(s, b).subtasks.isEmpty)
        #expect(s.undoName == "New Subtask")
    }

    @Test func aNewBlockOfTheSameGoalStartsEmpty() throws {
        let s = try makeStore()
        let (a, _) = try twoBlocks(s)
        try #require(s.addBlockSubtask(to: a, title: "Chapter 3") != nil)
        let g = try #require(s.goals().first)
        s.scheduleGoal(goalId: g.id, day: monday.adding(days: 1), start: 600)
        let next = try #require(s.blocks(for: monday.adding(days: 1)...monday.adding(days: 1)).first { $0.goalId == g.id })
        #expect(next.subtasks.isEmpty)
    }

    @Test func onlyAGoalBlockTakesANewSubtask() throws {
        let s = try makeStore()
        let (a, _) = try twoBlocks(s)
        #expect(s.addBlockSubtask(to: a, title: "   ") == nil)
        #expect(s.addBlockSubtask(to: "missing", title: "x") == nil)
        let task = try #require(s.quickAdd("Write today 10am for 1h"))
        let taskBlock = try #require(s.blocks(for: DayKey.today()...DayKey.today()).first { $0.taskId == task.id })
        #expect(s.addBlockSubtask(to: taskBlock.id, title: "x") == nil)
        #expect(s.blockSubtasks(of: a).isEmpty)
    }

    @Test func duplicatingABlockDoesNotCopyItsSubtasks() throws {
        let s = try makeStore()
        let (a, _) = try twoBlocks(s)
        try #require(s.addBlockSubtask(to: a, title: "Chapter 3") != nil)
        s.duplicate(blockIds: [a])
        let copy = try #require(s.selection.first)
        #expect(copy != a)
        #expect(s.blockSubtasks(of: copy).isEmpty)
        #expect(s.blockSubtasks(of: a).count == 1)
    }

    @Test func splittingABlockKeepsTheSubtasksOnTheFirstHalf() throws {
        let s = try makeStore()
        let (a, _) = try twoBlocks(s)
        try #require(s.addBlockSubtask(to: a, title: "Chapter 3") != nil)
        s.scheduleGoal(goalId: try #require(s.goals().first).id, day: monday, start: 300, length: 120)
        let long = try #require(s.blocks(for: monday...monday).first { $0.startMinute == 300 }).id
        try #require(s.addBlockSubtask(to: long, title: "Part") != nil)
        s.split(blockId: long)
        let halves = s.blocks(for: monday...monday).filter { $0.startMinute >= 300 && $0.startMinute < 420 }
        #expect(halves.count == 2)
        #expect(halves.first { $0.id == long }?.subtasks.map(\.title) == ["Part"])
        #expect(halves.first { $0.id != long }?.subtasks.isEmpty == true)
    }

    // MARK: Tick, rename, delete, with undo

    @Test func tickingASubtaskStrikesItAndUndoBringsItBack() throws {
        let s = try makeStore()
        let (a, _) = try twoBlocks(s)
        let id = try #require(s.addBlockSubtask(to: a, title: "Chapter 3"))
        s.toggleBlockSubtask(id)
        #expect(try block(s, a).subtasks.first?.isDone == true)
        #expect(s.undoName == "Complete Subtask")
        s.undo()
        #expect(try block(s, a).subtasks.first?.isDone == false)
        s.redo()
        #expect(try block(s, a).subtasks.first?.isDone == true)
        s.toggleBlockSubtask(id)
        #expect(s.undoName == "Reopen Subtask")
        #expect(try block(s, a).subtasks.first?.isDone == false)
    }

    @Test func tickingASubtaskDoesNotTickTheBlock() throws {
        let s = try makeStore()
        let (a, _) = try twoBlocks(s)
        let id = try #require(s.addBlockSubtask(to: a, title: "Chapter 3"))
        s.toggleBlockSubtask(id)
        #expect(try block(s, a).isDone == false)
    }

    @Test func renamingASubtaskIsOneUndoStep() throws {
        let s = try makeStore()
        let (a, _) = try twoBlocks(s)
        let id = try #require(s.addBlockSubtask(to: a, title: "Chapter 3"))
        s.renameBlockSubtask(id, to: "  Chapter 3 and 4 ")
        #expect(s.blockSubtasks(of: a).first?.title == "Chapter 3 and 4")
        #expect(s.undoName == "Rename Subtask")
        s.undo()
        #expect(s.blockSubtasks(of: a).first?.title == "Chapter 3")
    }

    @Test func anEmptyOrSameNameChangesNothing() throws {
        let s = try makeStore()
        let (a, _) = try twoBlocks(s)
        let id = try #require(s.addBlockSubtask(to: a, title: "Chapter 3"))
        s.renameBlockSubtask(id, to: "   ")
        s.renameBlockSubtask(id, to: "Chapter 3")
        #expect(s.blockSubtasks(of: a).first?.title == "Chapter 3")
        #expect(s.undoName == "New Subtask")
    }

    @Test func deletingASubtaskAndUndoingPutsItBackInItsPlace() throws {
        let s = try makeStore()
        let (a, _) = try twoBlocks(s)
        _ = try #require(s.addBlockSubtask(to: a, title: "One"))
        let two = try #require(s.addBlockSubtask(to: a, title: "Two"))
        _ = try #require(s.addBlockSubtask(to: a, title: "Three"))
        s.deleteBlockSubtask(two)
        #expect(s.blockSubtasks(of: a).map(\.title) == ["One", "Three"])
        #expect(s.undoName == "Delete Subtask")
        s.undo()
        #expect(s.blockSubtasks(of: a).map(\.title) == ["One", "Two", "Three"])
    }

    @Test func undoingTheAddRemovesTheSubtask() throws {
        let s = try makeStore()
        let (a, _) = try twoBlocks(s)
        _ = try #require(s.addBlockSubtask(to: a, title: "One"))
        s.undo()
        #expect(s.blockSubtasks(of: a).isEmpty)
    }

    @Test func deletingTheBlockAndUndoingBringsTheSubtasksBack() throws {
        let s = try makeStore()
        let (a, b) = try twoBlocks(s)
        let one = try #require(s.addBlockSubtask(to: a, title: "One"))
        _ = try #require(s.addBlockSubtask(to: a, title: "Two"))
        s.toggleBlockSubtask(one)
        s.deleteBlocks([a], name: "Delete Goal Block")
        #expect(s.blockSubtasks(of: a).isEmpty)
        s.undo()
        #expect(try block(s, a).subtasks.map(\.title) == ["One", "Two"])
        #expect(try block(s, a).subtasks.map(\.isDone) == [true, false])
        #expect(try block(s, b).subtasks.isEmpty)
        s.redo()
        #expect(s.blockSubtasks(of: a).isEmpty)
    }

    @Test func deletingTheGoalKeepsTheSubtasksOnThePlainBlock() throws {
        let s = try makeStore()
        let (a, _) = try twoBlocks(s)
        _ = try #require(s.addBlockSubtask(to: a, title: "One"))
        s.deleteGoal(try #require(s.goals().first).id)
        let plain = try block(s, a)
        #expect(plain.goalId == nil)
        #expect(plain.subtasks.map(\.title) == ["One"])
        s.undo()
        #expect(try block(s, a).goalId != nil && block(s, a).subtasks.count == 1)
    }

    // MARK: The editor popover

    @Test func theSubtaskEditorOpensOnlyForAGoalBlock() throws {
        let s = try makeStore()
        let (a, _) = try twoBlocks(s)
        s.openBlockSubtasks(a)
        #expect(s.editingBlockSubtasks == a)
        s.closeBlockSubtasks()
        #expect(s.editingBlockSubtasks == nil)
        s.openBlockSubtasks("missing")
        #expect(s.editingBlockSubtasks == nil)
    }

    // MARK: The block layout

    @Test func aTallGoalBlockShowsEveryRow() throws {
        let s = try makeStore()
        let (a, _) = try twoBlocks(s)
        for t in ["One", "Two", "Three"] { _ = try #require(s.addBlockSubtask(to: a, title: t)) }
        let b = try block(s, a)
        let rows = PlannerLayoutRules.blockRows(height: 320, hasSummary: !b.summary.isEmpty, subtaskCount: b.subtasks.count)
        #expect(rows.subtasks == 3 && !rows.moreRow && !rows.badge)
    }

    @Test func aShortGoalBlockShowsSomeRowsAndPlusNMore() throws {
        let s = try makeStore()
        let (a, _) = try twoBlocks(s)
        for t in ["One", "Two", "Three", "Four", "Five"] { _ = try #require(s.addBlockSubtask(to: a, title: t)) }
        s.toggleBlockSubtask(try #require(s.blockSubtasks(of: a).first).id)
        let b = try block(s, a)
        #expect(b.summary.isEmpty)
        // 64 pt: 3 lines. Title, one subtask, one "+N more" row.
        let rows = PlannerLayoutRules.blockRows(height: 64, hasSummary: false, subtaskCount: b.subtasks.count)
        #expect(rows == BlockRows(title: 1, summary: 0, subtasks: 1, moreRow: true, badge: false))
        let done = b.subtasks.filter(\.isDone).count
        #expect(SubtaskRules.moreLabel(hidden: rows.hidden(of: 5), shown: rows.subtasks, done: done, total: 5) == "+4 more")
        // 36 pt: no spare line. The title row shows "1/5".
        let tiny = PlannerLayoutRules.blockRows(height: 36, hasSummary: false, subtaskCount: 5)
        #expect(tiny.badge && SubtaskRules.badge(done: done, total: 5) == "1/5")
    }
}
