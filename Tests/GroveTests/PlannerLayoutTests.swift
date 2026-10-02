import Testing
import SwiftUI
import AppKit
import GroveCore
@testable import Grove

/// Layout checks that draw the real planner in an off-screen window.
@MainActor
struct PlannerLayoutTests {
    /// Smallest width the planner asks for, with the tray open. Optionally the tray is closed and reopened first.
    private func idealWidth(closeAndReopenTray: Bool) throws -> CGFloat {
        let defaults = UserDefaults.standard
        defaults.set(7, forKey: "planner.mode")
        defaults.set(true, forKey: "planner.trayOpen")
        defer {
            defaults.removeObject(forKey: "planner.mode")
            defaults.removeObject(forKey: "planner.trayOpen")
        }
        let store = AppStore(repos: Repos(db: try Database.inMemory()))
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: RootView().environment(store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        func settle() {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            hosting.layoutSubtreeIfNeeded()
        }
        settle()
        if closeAndReopenTray {
            defaults.set(false, forKey: "planner.trayOpen"); settle()
            defaults.set(true, forKey: "planner.trayOpen"); settle()
        }
        return hosting.fittingSize.width
    }

    @Test func reopeningTheTrayDoesNotKeepTheGridWide() throws {
        let fresh = try idealWidth(closeAndReopenTray: false)
        let reopened = try idealWidth(closeAndReopenTray: true)
        // A stale grid width used to push the tray off the left edge after close + reopen.
        #expect(abs(fresh - reopened) < 1, "fresh \(fresh) vs reopened \(reopened)")
    }
}
