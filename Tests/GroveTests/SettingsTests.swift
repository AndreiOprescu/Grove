import Testing
import Foundation
import GroveCore
@testable import Grove

/// The small rules behind the Settings window (PLAN §5.8).
struct SettingsRulesTests {
    @Test func theChoicesAreSmallAndSorted() {
        #expect(SettingsRules.eventLengths == [15, 30, 45, 60, 90, 120])
        #expect(SettingsRules.eventLengths.contains(SettingsRules.defaultEventLength))
    }

    @Test func theBusyDayLimitIsWholeHoursFromSixToTwelve() {
        #expect(SettingsRules.dailyLimits == [360, 420, 480, 540, 600, 660, 720])
        #expect(SettingsRules.dailyLimits.contains(SettingsRules.defaultDailyLimit))
        #expect(SettingsRules.defaultDailyLimit == 540)
    }

    @Test func workHoursStayAtLeastOneHourLong() {
        // The start moves past the end: the end follows.
        #expect(SettingsRules.workHours(start: 19 * 60, end: 18 * 60, startChanged: true) == (19 * 60, 20 * 60))
        // The end moves before the start: the start follows.
        #expect(SettingsRules.workHours(start: 9 * 60, end: 8 * 60, startChanged: false) == (7 * 60, 8 * 60))
        // Good values stay as they are.
        #expect(SettingsRules.workHours(start: 9 * 60, end: 18 * 60, startChanged: true) == (9 * 60, 18 * 60))
    }

    @Test func workHoursStayInsideTheDay() {
        #expect(SettingsRules.workHours(start: 24 * 60, end: 24 * 60, startChanged: true) == (23 * 60, 24 * 60))
        #expect(SettingsRules.workHours(start: 0, end: 0, startChanged: false) == (0, 60))
    }

    @Test func anHourReadsAsClockTime() {
        #expect(SettingsRules.hourText(9 * 60) == "09:00")
        #expect(SettingsRules.hourText(24 * 60) == "24:00")
    }

    @Test func accentIntensityScalesTheCirclesButNeverPastFull() {
        #expect(AmbientMath.strength(base: 0.55, intensity: 1) == 0.55)
        #expect(abs(AmbientMath.strength(base: 0.55, intensity: 0.5) - 0.275) < 0.0001)
        #expect(AmbientMath.strength(base: 0.55, intensity: 0) == 0)
        #expect(AmbientMath.strength(base: 0.55, intensity: 5) == 1)
        #expect(AmbientMath.strength(base: 0.55, intensity: -1) == 0)
    }

    @Test func aBackupNameBecomesADay() {
        #expect(SettingsRules.backupDay(fileName: "grove-2026-10-04.sqlite") == DayKey("2026-10-04"))
        #expect(SettingsRules.backupDay(fileName: "grove-nope.sqlite") == nil)
        #expect(SettingsRules.backupDay(fileName: "other.sqlite") == nil)
    }

    @Test func weekStartsOnMondayOrSunday() {
        let wed = DayKey("2026-10-07")
        #expect(CalendarRules.weekStart(of: wed, sundayFirst: false) == DayKey("2026-10-05"))
        #expect(CalendarRules.weekStart(of: wed, sundayFirst: true) == DayKey("2026-10-04"))
        // A Sunday starts its own week when Sunday is first, and ends the old one when Monday is first.
        #expect(CalendarRules.weekStart(of: "2026-10-04", sundayFirst: true) == DayKey("2026-10-04"))
        #expect(CalendarRules.weekStart(of: "2026-10-04", sundayFirst: false) == DayKey("2026-09-28"))
    }

    @Test func theMonthGridCanStartOnSunday() {
        // 1 October 2026 is a Thursday.
        let monday = CalendarRules.monthGrid(containing: "2026-10-15")
        let sunday = CalendarRules.monthGrid(containing: "2026-10-15", sundayFirst: true)
        #expect(monday.first == DayKey("2026-09-28") && monday.count == 42)
        #expect(sunday.first == DayKey("2026-09-27") && sunday.count == 42)
        #expect(sunday.contains("2026-10-31"))
    }
}

/// Export, import and the note templates on a real store.
@MainActor
struct DataStoreTests {
    private func makeStore() throws -> AppStore { AppStore(repos: Repos(db: try Database.inMemory())) }

    @Test func aStoreExportsAndAnotherOneImports() throws {
        let a = try makeStore()
        _ = a.quickAdd("Water the plants today")
        let b = try makeStore()
        _ = b.quickAdd("Something old")
        try b.importData(try a.exportData())
        let titles = try b.repos.tasks.all().map(\.title)
        #expect(titles == ["Water the plants"])
    }

    @Test func importStartsFresh() throws {
        let a = try makeStore()
        _ = a.quickAdd("Keep")
        let data = try a.exportData()
        let b = try makeStore()
        let task = try #require(b.quickAdd("Old one"))
        b.selectedTaskId = task.id
        b.selection = [task.id]
        b.selectedNoteId = "gone"
        let before = b.revision
        try b.importData(data)
        #expect(b.selectedTaskId == nil && b.selection.isEmpty && b.selectedNoteId == nil)
        #expect(b.undoName == nil && b.redoName == nil)
        #expect(b.revision > before)
    }

    @Test func aBadFileLeavesTheStoreAsItWas() throws {
        let b = try makeStore()
        let task = try #require(b.quickAdd("Stay"))
        b.selectedTaskId = task.id
        #expect(throws: (any Error).self) { try b.importData(Data("nope".utf8)) }
        #expect(b.selectedTaskId == task.id)
        #expect(b.undoName != nil)
        #expect(try b.repos.tasks.all().count == 1)
    }

    @Test func aNoteTemplateIsKeptInTheSettingsTable() throws {
        let s = try makeStore()
        #expect(s.template(.daily) == NotesRules.template(.daily))
        s.setTemplate(.daily, "## Mood\n")
        #expect(s.template(.daily) == "## Mood\n")
        #expect(try s.repos.settings.get("notes.dailyTemplate") == "## Mood\n")
        let note = s.dailyNote(for: "2026-10-05")
        #expect(note.body == "## Mood\n")
        #expect(s.weeklyNote(for: "2026-10-05").body == NotesRules.template(.weekly))
    }

    @Test func anEmptyTemplateIsAllowedAndResetBringsBackTheDefault() throws {
        let s = try makeStore()
        s.setTemplate(.weekly, "")
        #expect(s.weeklyNote(for: "2026-10-05").body == "")
        s.resetTemplate(.weekly)
        #expect(s.template(.weekly) == NotesRules.template(.weekly))
        #expect(try s.repos.settings.get("notes.weeklyTemplate") == nil)
    }

    @Test func templatesTravelInTheExportFile() throws {
        let a = try makeStore()
        a.setTemplate(.daily, "## Mine\n")
        let b = try makeStore()
        try b.importData(try a.exportData())
        #expect(b.template(.daily) == "## Mine\n")
    }
}
