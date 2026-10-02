import Testing
import Foundation
import GroveCore
@testable import Grove

/// Title, short description and long description of a task, and opening the panel from the planner.
@MainActor
struct TaskDescriptionTests {
    func makeStore() throws -> AppStore { AppStore(repos: Repos(db: try Database.inMemory())) }

    @Test func summaryTextIsOneShortLine() {
        #expect(SummaryText.clean("  hello  ") == "hello")
        #expect(SummaryText.clean("one\ntwo\r\nthree") == "one two three")
        #expect(SummaryText.clean(String(repeating: "a", count: 500)).count == SummaryText.maxLength)
        #expect(SummaryText.clean("   ") == "")
    }

    @Test func savingASummaryStoresItAndTypingIsOneUndoStep() throws {
        let s = try makeStore()
        let a = try #require(s.quickAdd("A"))
        s.setSummary(a.id, "f")
        s.setSummary(a.id, "fl")
        s.setSummary(a.id, "flights")
        #expect(s.task(a.id)?.summary == "flights")
        s.undo()
        #expect(s.task(a.id)?.summary == "")
        s.redo()
        #expect(s.task(a.id)?.summary == "flights")
    }

    @Test func savingTheSameSummaryChangesNothing() throws {
        let s = try makeStore()
        let a = try #require(s.quickAdd("A"))
        s.setSummary(a.id, "x")
        let before = s.undoName
        s.setSummary(a.id, " x ")
        #expect(s.undoName == before)
        s.setSummary(a.id, "")
        #expect(s.task(a.id)?.summary == "")
    }

    @Test func aBlockCarriesTheSummaryOfItsTask() throws {
        let s = try makeStore()
        let day = DayKey.today()
        let a = try #require(s.quickAdd("Plan trip today 10am for 1h"))
        s.setSummary(a.id, "Flights and hotel")
        let block = try #require(s.blocks(for: day...day).first { $0.taskId == a.id })
        #expect(block.summary == "Flights and hotel")
        #expect(block.title == "Plan trip")
    }

    @Test func clickingATaskBlockOpensItsPanel() throws {
        let s = try makeStore()
        let day = DayKey.today()
        let a = try #require(s.quickAdd("Plan trip today 10am for 1h"))
        let block = try #require(s.blocks(for: day...day).first { $0.taskId == a.id })
        #expect(s.selectedTaskId == nil)
        s.selectBlock(block, extend: false)
        #expect(s.selection == [block.id])
        #expect(s.selectedTaskId == a.id)
    }

    @Test func commandClickingBlocksBuildsASelectionAndLeavesThePanelAlone() throws {
        let s = try makeStore()
        let day = DayKey.today()
        let a = try #require(s.quickAdd("A today 10am for 1h"))
        let b = try #require(s.quickAdd("B today 12pm for 1h"))
        let blocks = s.blocks(for: day...day)
        let ba = try #require(blocks.first { $0.taskId == a.id })
        let bb = try #require(blocks.first { $0.taskId == b.id })
        s.selectBlock(ba, extend: false)
        s.selectBlock(bb, extend: true)
        #expect(s.selection == [ba.id, bb.id])
        #expect(s.selectedTaskId == a.id)
        s.selectBlock(bb, extend: true)
        #expect(s.selection == [ba.id])
    }

    @Test func aBlockShowsTheSummaryOnlyWhenThereIsRoomForIt() {
        // Height 64 (a 1 h block at the default zoom): three text lines in all.
        let tall = PlannerLayoutRules.blockTextLines(height: 64, hasSummary: true)
        #expect(tall.title == 2 && tall.summary == 1)
        // No summary: the title may use all lines, as before.
        #expect(PlannerLayoutRules.blockTextLines(height: 64, hasSummary: false) == (title: 3, summary: 0))
        // One line only: the title wins.
        #expect(PlannerLayoutRules.blockTextLines(height: 36, hasSummary: true) == (title: 1, summary: 0))
        // A long block gives the summary many lines.
        let long = PlannerLayoutRules.blockTextLines(height: 320, hasSummary: true)
        #expect(long.title == 2 && long.summary > 5)
    }
}

struct SummaryClearanceTests {
    @Test func aBlockWithASummaryStaysTightForOneMoreRow() {
        // 110 pt per hour: a 32 pt title row is 18 minutes, a 46 pt title + summary block is 26 minutes.
        #expect(PlannerLayoutRules.tightMinutes(hourHeight: 110, blockHeight: 220, hasSummary: false) == 18)
        #expect(PlannerLayoutRules.tightMinutes(hourHeight: 110, blockHeight: 220, hasSummary: true) == 26)
        // A block too short to show its summary does not get the extra.
        #expect(PlannerLayoutRules.tightMinutes(hourHeight: 110, blockHeight: 40, hasSummary: true) == 18)
    }

    @Test func clearanceLeavesTheWholeSummaryReadableWhenThereIsRoom() {
        let wide = PlannerLayoutRules.textClearance(title: "Plan", summary: String(repeating: "a", count: 32), columnWidth: 540)
        #expect(wide > 150 && wide <= 270)
        // In a narrow column the clearance stops at half the column.
        let narrow = PlannerLayoutRules.textClearance(title: "Plan", summary: String(repeating: "a", count: 32), columnWidth: 100)
        #expect(narrow == 50)
        // A short summary needs little.
        #expect(PlannerLayoutRules.textClearance(title: "Plan", summary: "Hi", columnWidth: 540) < 80)
    }
}
