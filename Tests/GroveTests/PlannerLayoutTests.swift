import Testing
import SwiftUI
import AppKit
import GroveCore
@testable import Grove

/// Layout checks that draw the real planner in an off-screen window.
@MainActor
@Suite(.serialized)
struct PlannerLayoutTests {
    /// Smallest width the Planner screen (week mode, sticky strip open) asks for, with `notesPerDay` timeless tasks on each day.
    private func idealWidth(notesPerDay: Int) throws -> CGFloat {
        let defaults = UserDefaults.standard
        defaults.set(7, forKey: "planner.mode")
        defaults.set(true, forKey: "planner.stickyOpen")
        defer {
            defaults.removeObject(forKey: "planner.mode")
            defaults.removeObject(forKey: "planner.stickyOpen")
        }
        let store = AppStore(repos: Repos(db: try Database.inMemory()))
        store.screen = .planner
        let monday = DayKey.today().weekStart()
        for d in 0..<7 {
            for n in 0..<notesPerDay {
                try store.repos.tasks.save(TaskItem(title: "A rather long task title that needs to wrap \(d)-\(n)",
                                                    bucket: .day, planDate: monday.adding(days: d)))
            }
        }
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: RootView().environment(store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.width
    }

    @Test func stickyNotesDoNotWidenThePlanner() throws {
        let empty = try idealWidth(notesPerDay: 0)
        let full = try idealWidth(notesPerDay: 6)
        // Notes wrap and scroll inside their day column. They must never push the grid wider.
        #expect(abs(empty - full) < 1, "empty \(empty) vs full \(full)")
    }
}
