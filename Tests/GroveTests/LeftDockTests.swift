import Testing
import Foundation
import GroveCore
@testable import Grove

/// The three left panels (Notes, Tasks, Goals): one open at a time, set by the buttons at the top left.
struct LeftPaneTests {
    @Test func theRawValuesAreWhatIsSavedInTheSetting() {
        #expect(LeftPane.allCases.map(\.rawValue) == ["notes", "tasks", "goals"])
        #expect(LeftPane.storageKey == "shell.leftPane")
    }

    @Test func aTapOpensThePanelWhenNoneIsOpen() {
        for pane in LeftPane.allCases { #expect(LeftPane.toggled(current: nil, tapped: pane) == pane) }
    }

    @Test func aTapOnTheOpenPanelClosesIt() {
        for pane in LeftPane.allCases { #expect(LeftPane.toggled(current: pane, tapped: pane) == nil) }
    }

    @Test func aTapOnAnotherPanelSwitchesToItSoOnlyOneIsOpen() {
        #expect(LeftPane.toggled(current: .notes, tapped: .goals) == .goals)
        #expect(LeftPane.toggled(current: .goals, tapped: .tasks) == .tasks)
        #expect(LeftPane.toggled(current: .tasks, tapped: .notes) == .notes)
    }

    @Test func savedTextBecomesAPanelAndEmptyOrUnknownTextMeansClosed() {
        #expect(LeftPane(saved: "notes") == .notes)
        #expect(LeftPane(saved: "tasks") == .tasks)
        #expect(LeftPane(saved: "goals") == .goals)
        #expect(LeftPane(saved: "") == nil)
        #expect(LeftPane(saved: "inbox") == nil)
        #expect(LeftPane.savedText(nil) == "")
        #expect(LeftPane.savedText(.goals) == "goals")
    }

    @Test func onlyTodayAndThePlannerHaveTheButtons() {
        for screen in Screen.allCases {
            #expect(LeftPane.isAvailable(on: screen) == (screen == .today || screen == .planner))
        }
    }

    @Test func everyPanelHasATitleASymbolAndAHelpText() {
        #expect(LeftPane.allCases.map(\.icon) == ["note.text", "checklist", "target"])
        #expect(LeftPane.allCases.map(\.title) == ["Notes", "Tasks", "Goals"])
        for pane in LeftPane.allCases { #expect(!pane.help.isEmpty) }
    }
}

@MainActor
@Suite(.serialized)
struct LeftPaneStoreTests {
    private func makeStore() throws -> AppStore { AppStore(repos: Repos(db: try Database.inMemory())) }

    /// Runs `body` and puts the saved panel back.
    private func keepingTheSetting(_ body: () throws -> Void) rethrows {
        let key = LeftPane.storageKey
        let saved = UserDefaults.standard.object(forKey: key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        try body()
    }

    @Test func theStoreReadsAndWritesTheSavedPanel() throws {
        try keepingTheSetting {
            let s = try makeStore()
            s.leftPane = .notes
            #expect(UserDefaults.standard.string(forKey: LeftPane.storageKey) == "notes")
            #expect(s.leftPane == .notes)
            s.leftPane = nil
            #expect(UserDefaults.standard.string(forKey: LeftPane.storageKey) == "")
            #expect(s.leftPane == nil)
        }
    }

    @Test func theViewMenuOpensAPanelOnTodayAndThePlannerAndMovesOtherScreensToThePlanner() throws {
        try keepingTheSetting {
            UserDefaults.standard.set("", forKey: LeftPane.storageKey)
            let s = try makeStore()
            s.screen = .today
            s.showLeftPane(.notes)
            #expect(s.screen == .today && s.leftPane == .notes)
            s.screen = .garden
            s.showLeftPane(.goals)
            #expect(s.screen == .planner && s.leftPane == .goals)
        }
    }

    @Test func newTaskOnThePlannerOpensTheTasksPanel() throws {
        try keepingTheSetting {
            UserDefaults.standard.set("notes", forKey: LeftPane.storageKey)
            let s = try makeStore()
            s.screen = .planner
            let before = s.quickAddRequest
            s.run(.newTask)
            #expect(s.screen == .planner && s.leftPane == .tasks && s.quickAddRequest == before + 1)
            #expect(s.quickAddHandled < s.quickAddRequest)   // the field that appears takes the request
        }
    }

    @Test func newTaskOnTodayShowsTodaysListSoAnotherPanelIsClosed() throws {
        try keepingTheSetting {
            for open in ["notes", "goals", "tasks"] {
                UserDefaults.standard.set(open, forKey: LeftPane.storageKey)
                let s = try makeStore()
                s.screen = .today
                s.run(.newTask)
                #expect(s.screen == .today && s.leftPane == nil)
            }
        }
    }
}
