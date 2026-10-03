import Testing
import Foundation
@testable import GroveCore

/// The text rules of the ⌘K palette (PLAN §5.5 item 11).
struct PaletteRulesTests {
    let friday = DayKey("2026-10-02")

    // MARK: Reading the box

    @Test func aLeadingArrowMeansCommandsOnly() {
        #expect(PaletteRules.parse(">new") == .init(commandsOnly: true, text: "new"))
        #expect(PaletteRules.parse("  > plan ") == .init(commandsOnly: true, text: "plan"))
        #expect(PaletteRules.parse(">") == .init(commandsOnly: true, text: ""))
    }

    @Test func otherTextSearchesEverything() {
        #expect(PaletteRules.parse("  report ") == .init(commandsOnly: false, text: "report"))
        #expect(PaletteRules.parse("") == .init(commandsOnly: false, text: ""))
        #expect(PaletteRules.parse("a > b") == .init(commandsOnly: false, text: "a > b"))
    }

    // MARK: Commands

    @Test func anEmptySearchListsEveryCommandInOrder() {
        #expect(PaletteRules.commands(matching: "").map(\.id) == PaletteCommandId.allCases)
        #expect(PaletteRules.commands(matching: "   ").count == PaletteCommandId.allCases.count)
    }

    @Test func everyWordMustStartAWordOfTheCommand() {
        #expect(PaletteRules.commands(matching: "new").map(\.id) == [.newTask, .newNote])
        #expect(PaletteRules.commands(matching: "new t").map(\.id) == [.newTask])
        #expect(PaletteRules.commands(matching: "PLAN").map(\.id) == [.planMyDay, .showPlanner])   // "planner" starts with "plan" too
        #expect(PaletteRules.commands(matching: "ask").isEmpty)   // inside a word is not a start
    }

    @Test func keywordsFindACommandToo() {
        #expect(PaletteRules.commands(matching: "calendar").map(\.id).contains(.showPlanner))
        #expect(PaletteRules.commands(matching: "journal").map(\.id) == [.todayNote])
    }

    @Test func theCommandsHaveTitlesAndTheNewTaskShortcut() {
        let task = PaletteRules.commands(matching: "new task").first
        #expect(task?.title == "New task")
        #expect(task?.shortcut == "⌘N")
        #expect(PaletteRules.commands(matching: "plan my").first?.title == "Plan my day")
        #expect(PaletteRules.commands(matching: "go to date").first?.title == "Go to date…")
    }

    @Test func theScreenCommandsCarryTheMenuShortcuts() {
        let shortcuts = Dictionary(uniqueKeysWithValues: PaletteRules.commands.compactMap { c in c.shortcut.map { (c.id, $0) } })
        #expect(shortcuts[.goToday] == "⌘T")
        #expect(shortcuts[.showPlanner] == "⌘1")
        #expect(shortcuts[.showCalendar] == "⌘3")
        #expect(shortcuts[.showNotes] == "⌘4")
    }

    @Test func theCalendarCommandIsFoundByMonth() {
        #expect(PaletteRules.commands(matching: "month").map(\.id) == [.showCalendar])
        #expect(PaletteRules.commands(matching: "open cal").map(\.id).contains(.showCalendar))
    }

    @Test func theThemeAndMotionCommandsAreFound() {
        #expect(PaletteRules.commands(matching: "toggle theme").map(\.id) == [.toggleTheme])
        #expect(PaletteRules.commands(matching: "dark").map(\.id) == [.toggleTheme])
        #expect(PaletteRules.commands(matching: "toggle").map(\.id) == [.toggleTheme, .toggleMotion])
        #expect(PaletteRules.commands(matching: "animation").map(\.id) == [.toggleMotion])
        #expect(PaletteRules.commands(matching: "toggle theme").first?.title == "Toggle theme")
    }

    // MARK: Dates

    @Test func aDayWordIsADate() {
        #expect(PaletteRules.date(in: "sat", today: friday) == DayKey("2026-10-03"))
        #expect(PaletteRules.date(in: "mon", today: friday) == DayKey("2026-10-05"))
        #expect(PaletteRules.date(in: "tomorrow", today: friday) == DayKey("2026-10-03"))
        #expect(PaletteRules.date(in: "today", today: friday) == friday)
    }

    @Test func goToInFrontIsAllowed() {
        #expect(PaletteRules.date(in: "go to mon", today: friday) == DayKey("2026-10-05"))
        #expect(PaletteRules.date(in: "Go To Sat", today: friday) == DayKey("2026-10-03"))
        #expect(PaletteRules.date(in: "goto sat", today: friday) == DayKey("2026-10-03"))
    }

    @Test func aTimeAfterTheDayDoesNotMatter() {
        #expect(PaletteRules.date(in: "sat 3pm", today: friday) == DayKey("2026-10-03"))
    }

    @Test func wordsAroundTheDateMeanItIsASearch() {
        #expect(PaletteRules.date(in: "meeting sat", today: friday) == nil)
        #expect(PaletteRules.date(in: "sat report", today: friday) == nil)
        #expect(PaletteRules.date(in: "hello", today: friday) == nil)
        #expect(PaletteRules.date(in: "", today: friday) == nil)
    }

    @Test func aTimeAloneIsNotADate() {
        #expect(PaletteRules.date(in: "3pm", today: friday) == nil)
    }

    @Test func goToWithNothingAfterAsksForADay() {
        #expect(PaletteRules.asksForDay("go to"))
        #expect(PaletteRules.asksForDay("Go to "))
        #expect(PaletteRules.asksForDay("goto"))
        #expect(!PaletteRules.asksForDay("go to sat"))
        #expect(!PaletteRules.asksForDay("go"))
        #expect(!PaletteRules.asksForDay("good"))
    }

    @Test func theDateRowReadsLikeAPerson() {
        #expect(PaletteRules.dayTitle(friday, today: friday) == "Go to today")
        #expect(PaletteRules.dayTitle(DayKey("2026-10-03"), today: friday) == "Go to tomorrow")
        #expect(PaletteRules.dayTitle(DayKey("2026-10-09"), today: friday) == "Go to Friday")
        #expect(PaletteRules.dayTitle(DayKey("2026-10-01"), today: friday) == "Go to Thursday")
        #expect(PaletteRules.dayDetail(DayKey("2026-10-09")) == "Fri 9 Oct")
    }
}
