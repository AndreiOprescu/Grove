import Testing
import Foundation
import GroveCore
@testable import Grove

/// The numbers and the words of the Day Spread (PLAN §8, layout B).
struct SpreadRulesTests {
    @Test func theTaskListStaysBetween300And420() {
        #expect(SpreadRules.clampTasks(100) == 300)
        #expect(SpreadRules.clampTasks(340) == 340)
        #expect(SpreadRules.clampTasks(900) == 420)
    }

    @Test func theTaskListStartsInsideItsRange() {
        #expect(SpreadRules.tasksRange.contains(SpreadRules.tasksDefault))
    }

    @Test func threeColumnsFitTheSmallestWindow() {
        #expect(SpreadRules.minimumWindowWidth <= 1100)
    }

    /// The timeline takes what the task list and the note leave. In the first window (1280 pt) it is the widest column.
    @Test func theTimelineIsTheWideColumn() {
        let timeline = 1280 - 2 * SpreadRules.side - 2 * SpreadRules.gap - SpreadRules.tasksDefault - SpreadRules.noteWidth
        #expect(timeline > SpreadRules.tasksDefault)
        #expect(timeline > SpreadRules.noteWidth)
        #expect(timeline >= SpreadRules.timelineMinimum)
    }

    @Test func todayGetsAGreetingAndTheGrowth() {
        let text = SpreadRules.subtitle(isToday: true, greeting: "Good morning", progress: PlantProgress(done: 1, total: 2))
        #expect(text == "Good morning · 50% of today grown")
    }

    @Test func anotherDayGetsNoGreeting() {
        let text = SpreadRules.subtitle(isToday: false, greeting: "Good morning", progress: PlantProgress(done: 1, total: 4))
        #expect(text == "25% of the day grown")
    }

    @Test func aDayWithNoTasksSaysSo() {
        let none = PlantProgress(done: 0, total: 0)
        #expect(SpreadRules.subtitle(isToday: true, greeting: "Good evening", progress: none) == "Good evening · Nothing planned today")
        #expect(SpreadRules.subtitle(isToday: false, greeting: "Good evening", progress: none) == "Nothing planned")
    }
}

/// Which screen the window shows (PLAN §5.8).
@MainActor
struct ScreenStoreTests {
    private func makeStore() throws -> AppStore { AppStore(repos: Repos(db: try Database.inMemory())) }

    @Test func theScreensRunInTheOrderOfTheSwitch() {
        #expect(Screen.allCases == [.today, .planner, .calendar, .notes, .garden])
        #expect(Screen.allCases.map(\.title) == ["Today", "Planner", "Calendar", "Notes", "Garden"])
    }

    @Test func theWindowStartsOnToday() throws {
        #expect(try makeStore().screen == .today)
    }

    @Test func showTodayPicksTodayAndAsksTheTimelineToScrollToNow() throws {
        let s = try makeStore()
        s.selectedDay = DayKey.today().adding(days: 5)
        s.screen = .notes
        let before = s.todayRequest
        s.showToday()
        #expect(s.screen == .today && s.selectedDay == .today() && s.todayRequest == before + 1)
    }

    @Test func showTodayKeepsThePlannerAndTheCalendarWhereTheyAre() throws {
        let s = try makeStore()
        for screen in [Screen.planner, .calendar] {
            s.screen = screen
            s.selectedDay = DayKey.today().adding(days: 5)
            s.showToday()
            #expect(s.screen == screen && s.selectedDay == .today())
        }
    }

    @Test func showTasksOpensThePlannerWithTheTasksPanel() throws {
        let key = LeftPane.storageKey
        let saved = UserDefaults.standard.object(forKey: key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        UserDefaults.standard.set("", forKey: key)
        let s = try makeStore()
        s.screen = .notes
        s.showTasks()
        #expect(s.screen == .planner && UserDefaults.standard.string(forKey: key) == LeftPane.tasks.rawValue)
    }

    @Test func enteringTheTodayScreenPicksToday() throws {
        let s = try makeStore()
        for from in [Screen.planner, .calendar, .notes, .garden] {
            s.screen = from
            s.selectedDay = DayKey.today().adding(days: 5)
            s.screen = .today
            #expect(s.selectedDay == .today())
        }
    }

    @Test func otherScreensKeepTheDayThatWasPicked() throws {
        let s = try makeStore()
        let later = DayKey.today().adding(days: 5)
        s.selectedDay = later
        for screen in [Screen.planner, .calendar, .notes, .garden] {
            s.screen = screen
            #expect(s.selectedDay == later)
        }
    }

    @Test func showDayOpensTodayOnTheTodayScreenAndAnyOtherDayOnThePlanner() throws {
        let s = try makeStore()
        s.screen = .notes
        s.showDay(DayKey.today().adding(days: 3))
        #expect(s.screen == .planner && s.selectedDay == DayKey.today().adding(days: 3))
        s.showDay(.today())
        #expect(s.screen == .today && s.selectedDay == .today())
    }
}

/// The View menu: zoom and a new event. They write the same settings the planner reads.
@MainActor
@Suite(.serialized)
struct ViewMenuStoreTests {
    private let keys = ["planner.hourHeight", "planner.workStart"]
    private let defaults = UserDefaults.standard

    private func makeStore() throws -> AppStore { AppStore(repos: Repos(db: try Database.inMemory())) }
    private func keep(_ body: () throws -> Void) rethrows {
        let saved = keys.map { defaults.object(forKey: $0) }
        keys.forEach(defaults.removeObject(forKey:))
        defer { for (k, v) in zip(keys, saved) { if let v { defaults.set(v, forKey: k) } else { defaults.removeObject(forKey: k) } } }
        try body()
    }

    @Test func zoomStepsAndStaysInRange() throws {
        try keep {
            let s = try makeStore()
            s.zoomPlanner(by: 1.25)
            #expect(abs(defaults.double(forKey: "planner.hourHeight") - 80) < 0.001)
            for _ in 0..<30 { s.zoomPlanner(by: 1.25) }
            #expect(defaults.double(forKey: "planner.hourHeight") == Double(PlannerGeometry.zoomRange.upperBound))
            for _ in 0..<60 { s.zoomPlanner(by: 0.8) }
            #expect(defaults.double(forKey: "planner.hourHeight") == Double(PlannerGeometry.zoomRange.lowerBound))
        }
    }

    @Test func newEventMakesAnHourAtTheStartOfWorkAndOpensItsEditor() throws {
        try keep {
            let s = try makeStore()
            let day = DayKey.today().adding(days: 3)
            s.selectedDay = day
            s.screen = .notes
            s.newEventNow()
            let events = s.eventItems(in: day...day)
            #expect(events.count == 1)
            #expect(events.first?.start.minute == 9 * 60 && events.first?.end.minute == 10 * 60)
            #expect(s.screen == .planner && s.editingEvent?.item.id == events.first?.id)   // that day is not today, so the Planner shows it
        }
    }

    @Test func aSecondNewEventTakesTheNextFreeHour() throws {
        try keep {
            let s = try makeStore()
            let day = DayKey.today().adding(days: 3)
            s.selectedDay = day
            s.newEventNow()
            s.newEventNow()
            let starts = s.eventItems(in: day...day).map(\.start.minute).sorted()
            #expect(starts == [9 * 60, 10 * 60])
        }
    }
}
