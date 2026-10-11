import Testing
import Foundation
import GroveCore
@testable import Grove

/// Subtasks inside a task's block on the planner, with a "+N more" row when they do not all fit.
@MainActor
struct PlannerSubtaskTests {
    func makeStore() throws -> AppStore { AppStore(repos: Repos(db: try Database.inMemory())) }

    // MARK: rows

    @Test func noSubtasksKeepsTheOldLines() {
        for h: CGFloat in [22, 36, 64, 320] {
            for summary in [false, true] {
                let old = PlannerLayoutRules.blockTextLines(height: h, hasSummary: summary)
                let rows = PlannerLayoutRules.blockRows(height: h, hasSummary: summary, subtaskCount: 0)
                #expect(rows == BlockRows(title: old.title, summary: old.summary, subtasks: 0, moreRow: false, badge: false))
            }
        }
    }

    @Test func allSubtasksShowWhenThereIsRoom() {
        // 320 pt: 20 lines. Title, then 3 subtasks; the rest goes back to the title.
        let r = PlannerLayoutRules.blockRows(height: 320, hasSummary: false, subtaskCount: 3)
        #expect(r.subtasks == 3 && !r.moreRow && !r.badge)
        #expect(r.hidden(of: 3) == 0)
        #expect(r.title >= 1)
    }

    @Test func aFullBlockShowsSomeSubtasksAndAMoreRow() {
        // 64 pt: 3 lines. Title, one subtask, one "+N more" row.
        let r = PlannerLayoutRules.blockRows(height: 64, hasSummary: false, subtaskCount: 5)
        #expect(r == BlockRows(title: 1, summary: 0, subtasks: 1, moreRow: true, badge: false))
        #expect(r.hidden(of: 5) == 4)
    }

    @Test func theSummaryComesBeforeTheSubtasks() {
        // 79 pt: 4 lines. Title, summary, one subtask, more row.
        let r = PlannerLayoutRules.blockRows(height: 79, hasSummary: true, subtaskCount: 3)
        #expect(r == BlockRows(title: 1, summary: 1, subtasks: 1, moreRow: true, badge: false))
    }

    @Test func exactlyEnoughRoomShowsEverySubtaskAndNoMoreRow() {
        // 64 pt: 3 lines = title + 2 subtasks.
        let r = PlannerLayoutRules.blockRows(height: 64, hasSummary: false, subtaskCount: 2)
        #expect(r == BlockRows(title: 1, summary: 0, subtasks: 2, moreRow: false, badge: false))
    }

    @Test func oneSpareLineShowsOnlyTheCountRow() {
        // 43 pt: 2 lines = title + one row. Three subtasks do not fit, so the row is the count.
        let r = PlannerLayoutRules.blockRows(height: 43, hasSummary: false, subtaskCount: 3)
        #expect(r == BlockRows(title: 1, summary: 0, subtasks: 0, moreRow: true, badge: false))
        // One subtask fits on that line itself.
        #expect(PlannerLayoutRules.blockRows(height: 43, hasSummary: false, subtaskCount: 1).subtasks == 1)
    }

    @Test func noSpareLineShowsABadgeInTheTitleRow() {
        let r = PlannerLayoutRules.blockRows(height: 36, hasSummary: false, subtaskCount: 2)
        #expect(r == BlockRows(title: 1, summary: 0, subtasks: 0, moreRow: false, badge: true))
        // A summary that takes the last line also leaves only the badge.
        let s = PlannerLayoutRules.blockRows(height: 43, hasSummary: true, subtaskCount: 2)
        #expect(s.summary == 1 && s.subtasks == 0 && s.badge)
    }

    @Test func leftoverLinesGoBackToTitleAndSummary() {
        let r = PlannerLayoutRules.blockRows(height: 320, hasSummary: true, subtaskCount: 2)
        #expect(r.title == 2 && r.subtasks == 2 && r.summary > 1 && !r.moreRow)
    }

    // MARK: labels

    @Test func labelsForTheMoreRowAndTheBadge() {
        #expect(SubtaskRules.moreLabel(hidden: 3, shown: 2, done: 1, total: 5) == "+3 more")
        #expect(SubtaskRules.moreLabel(hidden: 4, shown: 0, done: 1, total: 4) == "1/4 subtasks")
        #expect(SubtaskRules.badge(done: 1, total: 4) == "1/4")
    }

    // MARK: store

    @Test func aBlockCarriesItsSubtasksInPanelOrderWithoutCancelledOnes() throws {
        let s = try makeStore()
        let day = DayKey.today()
        let a = try #require(s.quickAdd("Plan trip today 10am for 1h"))
        let one = try #require(s.addSubtask(to: a.id, title: "Flights"))
        _ = try #require(s.addSubtask(to: a.id, title: "Hotel"))
        let gone = try #require(s.addSubtask(to: a.id, title: "Old idea"))
        s.toggleDone(taskId: one)
        var cancelled = try #require(s.task(gone))
        cancelled.status = .cancelled
        try s.repos.tasks.save(cancelled)
        let block = try #require(s.blocks(for: day...day).first { $0.taskId == a.id })
        #expect(block.subtasks.map(\.title) == ["Flights", "Hotel"])
        #expect(block.subtasks.map(\.isDone) == [true, false])
    }

    @Test func aBlockWithoutATaskHasNoSubtasks() throws {
        let s = try makeStore()
        let day = DayKey.today()
        let a = try #require(s.quickAdd("Plan trip today 10am for 1h"))
        let block = try #require(s.blocks(for: day...day).first { $0.taskId == a.id })
        #expect(block.subtasks.isEmpty)
    }
}
