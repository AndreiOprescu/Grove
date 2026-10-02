import Testing
import Foundation
import GroveCore
@testable import Grove

/// The ⌘K palette on a real store (PLAN §5.5 item 11).
@MainActor
struct PaletteStoreTests {
    func makeStore() throws -> AppStore { AppStore(repos: Repos(db: try Database.inMemory())) }
    let friday = DayKey("2026-10-02")
    let saturday = DayKey("2026-10-03")

    private func commandIds(_ items: [PaletteItem]) -> [PaletteCommandId] {
        items.compactMap { if case .command(let id) = $0.action { id } else { nil } }
    }

    // MARK: What the box lists

    @Test func anEmptyBoxListsTheCommands() throws {
        let s = try makeStore()
        _ = s.quickAdd("Report taxes")
        let items = s.paletteItems(for: "", today: friday)
        #expect(commandIds(items) == PaletteCommandId.allCases)
        #expect(items.count == PaletteCommandId.allCases.count)
    }

    @Test func anArrowKeepsOnlyCommands() throws {
        let s = try makeStore()
        _ = s.quickAdd("New shoes")
        let items = s.paletteItems(for: ">new", today: friday)
        #expect(commandIds(items) == [.newTask, .newNote])
        #expect(items.count == 2)   // the task "New shoes" is not listed
        #expect(s.paletteItems(for: ">", today: friday).count == PaletteCommandId.allCases.count)
    }

    @Test func aSearchFindsTasksEventsAndNotes() throws {
        let s = try makeStore()
        let t = try #require(s.quickAdd("Report taxes", default: .day(saturday)))
        s.saveEvent(EventItem(title: "Report review", start: WallTime(day: friday, minute: 540), end: WallTime(day: friday, minute: 600)), from: nil)
        let e = try #require(s.eventItems(in: friday...friday).first)
        let n = s.newNote(title: "Report ideas")
        let items = s.paletteItems(for: "report", today: friday)
        let refs = items.compactMap { if case .open(let r) = $0.action { r } else { nil } }
        #expect(Set(refs) == [ItemRef(.task, t.id), ItemRef(.event, e.id), ItemRef(.note, n.id)])
        #expect(items.first { $0.action == .open(ItemRef(.task, t.id)) }?.detail == "Task · Sat 3 Oct")
        #expect(items.first { $0.action == .open(ItemRef(.event, e.id)) }?.detail == "Event · Fri 2 Oct, 09:00–10:00")
        #expect(items.first { $0.action == .open(ItemRef(.note, n.id)) }?.detail == "Note")
    }

    @Test func aTaskBlockIsNotListedBesideItsTask() throws {
        let s = try makeStore()
        s.createFromDraft(title: "Write report", day: friday, start: 600, end: 660, asEvent: false)
        let items = s.paletteItems(for: "report", today: friday)
        #expect(items.count == 1)
        guard case .open(let ref)? = items.first?.action else { Issue.record("no hit"); return }
        #expect(ref.type == .task)
    }

    @Test func aFinishedTaskIsMarkedDone() throws {
        let s = try makeStore()
        let t = try #require(s.quickAdd("Report taxes"))
        s.toggleDone(taskId: t.id)
        let item = try #require(s.paletteItems(for: "report", today: friday).first)
        #expect(item.done)
        #expect(item.detail == "Task · done")
    }

    @Test func dailyAndWeeklyNotesSayWhatTheyAre() throws {
        let s = try makeStore()
        let d = s.dailyNote(for: friday)
        s.setNoteBody(d.id, "zebra thoughts")
        let w = s.weeklyNote(for: friday)
        s.setNoteBody(w.id, "zebra goals")
        let items = s.paletteItems(for: "zebra", today: friday)
        #expect(items.first { $0.action == .open(ItemRef(.note, d.id)) }?.detail == "Daily note")
        #expect(items.first { $0.action == .open(ItemRef(.note, w.id)) }?.detail == "Weekly note")
    }

    @Test func aNoteWithNoTitleIsCalledUntitled() throws {
        let s = try makeStore()
        let n = s.newNote(title: "", body: "zebra thoughts")
        let item = try #require(s.paletteItems(for: "zebra", today: friday).first)
        #expect(item.action == .open(ItemRef(.note, n.id)))
        #expect(item.title == "Untitled")
    }

    @Test func matchingCommandsComeBeforeItems() throws {
        let s = try makeStore()
        _ = s.quickAdd("New shoes")
        let items = s.paletteItems(for: "new", today: friday)
        #expect(commandIds(items) == [.newTask, .newNote])
        if case .command = items[0].action, case .command = items[1].action, case .open = items[2].action {} else { Issue.record("wrong order") }
    }

    @Test func nothingFoundMeansNoRows() throws {
        let s = try makeStore()
        #expect(s.paletteItems(for: "qqqq", today: friday).isEmpty)
    }

    // MARK: Dates

    @Test func aDayWordOffersGoToThatDayFirst() throws {
        let s = try makeStore()
        s.newNote(title: "Saturday plans")
        let items = s.paletteItems(for: "sat", today: friday)
        #expect(items.first?.action == .goTo(saturday))
        #expect(items.first?.title == "Go to tomorrow")
        #expect(items.first?.detail == "Sat 3 Oct")
        #expect(items.contains { if case .open = $0.action { true } else { false } })   // the search still runs
    }

    @Test func aFarDayReadsAsItsWeekday() throws {
        let s = try makeStore()
        let item = try #require(s.paletteItems(for: "go to mon", today: friday).first)
        #expect(item.action == .goTo(DayKey("2026-10-05")))
        #expect(item.title == "Go to Monday")
    }

    @Test func todayIsOfferedOnce() throws {
        let s = try makeStore()
        let items = s.paletteItems(for: "today", today: friday)
        #expect(items.first?.action == .goTo(friday))
        #expect(!commandIds(items).contains(.goToday))
    }

    @Test func anArrowTurnsTheDateRowOff() throws {
        let s = try makeStore()
        let items = s.paletteItems(for: ">sat", today: friday)
        #expect(!items.contains { if case .goTo = $0.action { true } else { false } })
    }

    // MARK: Running a row

    @Test func goingToADayShowsItInThePlanner() throws {
        let s = try makeStore()
        s.screen = .notes
        s.paletteOpen = true
        s.runPalette(try #require(s.paletteItems(for: "sat", today: friday).first))
        #expect(s.selectedDay == saturday && s.screen == .planner && !s.paletteOpen)
    }

    @Test func goingToADayLeavesTheMonthGridForTheDayView() throws {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: "planner.mode")
        defer { if let saved { defaults.set(saved, forKey: "planner.mode") } else { defaults.removeObject(forKey: "planner.mode") } }
        let s = try makeStore()
        defaults.set(PlannerMode.month.rawValue, forKey: "planner.mode")
        s.run(.goToday)
        #expect(defaults.integer(forKey: "planner.mode") == PlannerMode.day.rawValue)
        defaults.set(PlannerMode.week.rawValue, forKey: "planner.mode")
        s.run(.goToday)
        #expect(defaults.integer(forKey: "planner.mode") == PlannerMode.week.rawValue)   // other modes stay
    }

    @Test func openingAnItemClosesThePaletteAndOpensIt() throws {
        let s = try makeStore()
        let t = try #require(s.quickAdd("Report taxes", default: .day(saturday)))
        s.paletteOpen = true
        s.screen = .notes
        s.runPalette(try #require(s.paletteItems(for: "report", today: friday).first))
        #expect(!s.paletteOpen && s.screen == .planner && s.selectedTaskId == t.id && s.selectedDay == saturday)
    }

    @Test func newTaskFocusesTheQuickAddField() throws {
        let s = try makeStore()
        s.screen = .notes
        s.paletteOpen = true
        let before = s.quickAddRequest
        s.run(.newTask)
        #expect(s.screen == .planner && s.quickAddRequest == before + 1 && !s.paletteOpen)
    }

    @Test func newNoteMakesOneAndShowsIt() throws {
        let s = try makeStore()
        s.paletteOpen = true
        s.run(.newNote)
        #expect(s.screen == .notes && !s.paletteOpen)
        #expect(try s.repos.notes.all().count == 1)
        #expect(s.selectedNoteId != nil)
    }

    @Test func todaysNoteOpensTheDailyNote() throws {
        let s = try makeStore()
        s.run(.todayNote)
        let note = try #require(s.selectedNoteId.flatMap { s.note($0) })
        #expect(note.kind == .daily && note.date == .today() && s.screen == .notes)
    }

    @Test func goToTodayMovesThePlanner() throws {
        let s = try makeStore()
        s.selectedDay = DayKey.today().adding(days: 9)
        s.screen = .notes
        s.run(.goToday)
        #expect(s.selectedDay == .today() && s.screen == .planner)
    }

    @Test func planMyDayAsksTheTodayPlannerToOpenItsPlan() throws {
        let s = try makeStore()
        s.selectedDay = DayKey.today().adding(days: 3)
        s.screen = .notes
        let before = s.planMyDayRequest
        s.run(.planMyDay)
        #expect(s.screen == .planner && s.selectedDay == .today() && s.planMyDayRequest == before + 1 && !s.paletteOpen)
    }

    @Test func theScreenCommandsSwitchScreens() throws {
        let s = try makeStore()
        s.run(.showNotes)
        #expect(s.screen == .notes)
        s.run(.showPlanner)
        #expect(s.screen == .planner)
    }

    @Test func goToDateKeepsThePaletteOpenAndAsksForADay() throws {
        let s = try makeStore()
        s.paletteOpen = true
        s.run(.goToDate)
        #expect(s.paletteOpen && s.paletteText == "go to ")
        #expect(PaletteRules.asksForDay(s.paletteText))
    }

    // MARK: Opening and closing

    @Test func togglingOpensItEmptyAndClosesIt() throws {
        let s = try makeStore()
        s.paletteText = "old words"
        s.togglePalette()
        #expect(s.paletteOpen && s.paletteText == "")
        s.togglePalette()
        #expect(!s.paletteOpen)
    }
}
