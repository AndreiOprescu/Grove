import Testing
import SwiftUI
import AppKit
import GroveCore
@testable import Grove

/// Real mouse clicks on one task row in an off-screen window.
/// The middle of the check box must check the task off, not just select the row.
@MainActor
@Suite(.serialized)
struct CheckBoxClickTests {
    /// One open task row, pinned to the top-left of a window. The window must be ordered in, or SwiftUI ignores clicks.
    private func hostRow(theme: ThemeID) throws -> (store: AppStore, id: String, window: NSWindow, hosting: NSView) {
        let store = AppStore(repos: Repos(db: try Database.inMemory()))
        let task = TaskItem(title: "Water the plants", bucket: .day, planDate: DayKey.today())
        try store.repos.tasks.save(task)
        let row = TaskRow(task: task, lists: [:], isExpanded: false, toggleExpanded: {})
            .frame(width: 320)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .environment(store)
            .environment(\.theme, Theme.make(theme))
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: row)
        let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 400, height: 200),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        hosting.layoutSubtreeIfNeeded()
        return (store, task.id, window, hosting)
    }

    /// A left click (down, then up) at a point in the hosting view, measured from its top-left like SwiftUI.
    private func click(_ point: CGPoint, in hosting: NSView, window: NSWindow) throws {
        #expect(hosting.isFlipped)
        let at = hosting.convert(point, to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: at, modifierFlags: [],
                                                        timestamp: ProcessInfo.processInfo.systemUptime,
                                                        windowNumber: window.windowNumber, context: nil,
                                                        eventNumber: 0, clickCount: 1,
                                                        pressure: type == .leftMouseDown ? 1 : 0))
            window.sendEvent(event)
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    }

    // The row has 12 pt padding on the left and 8 pt on top. The box is 17 pt square.
    private let boxCentre = CGPoint(x: 12 + 8.5, y: 8 + 8.5)
    private let titlePoint = CGPoint(x: 12 + 17 + 8 + 30, y: 8 + 8)

    @Test(arguments: ThemeID.allCases)
    func clickInTheMiddleOfTheBoxChecksTheTaskOff(theme: ThemeID) throws {
        let r = try hostRow(theme: theme)
        defer { r.window.close() }
        try click(boxCentre, in: r.hosting, window: r.window)
        #expect(r.store.task(r.id)?.isDone == true, "theme \(theme)")
        #expect(r.store.selectedTaskId == nil, "the box took the click, not the row")
    }

    @Test func clickOnTheTitleSelectsAndDoesNotCheck() throws {
        let r = try hostRow(theme: .grove)
        defer { r.window.close() }
        try click(titlePoint, in: r.hosting, window: r.window)
        #expect(r.store.task(r.id)?.isDone == false)
        #expect(r.store.selectedTaskId == r.id)
    }
}
