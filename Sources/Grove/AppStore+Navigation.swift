import Foundation
import GroveCore

/// Moving around the window. The menu and the screen switch call these.
extension AppStore {
    /// View ▸ Today (⌘T). The Planner and the Calendar stay where they are and move to today.
    /// Every other screen goes to the Today screen. The timeline scrolls to the current time.
    func showToday() {
        selectedDay = .today()
        if screen != .planner && screen != .calendar { screen = .today }
        todayRequest += 1
    }

    /// The panel open on the left of the Today and Planner screens, or nil when none is. Saved in `shell.leftPane`;
    /// the buttons of `LeftDock` and the screens read the same setting.
    var leftPane: LeftPane? {
        get { LeftPane(saved: UserDefaults.standard.string(forKey: LeftPane.storageKey) ?? "") }
        set { UserDefaults.standard.set(LeftPane.savedText(newValue), forKey: LeftPane.storageKey) }
    }

    /// View ▸ Tasks (⌘2): the Planner screen with the Tasks panel open.
    func showTasks() {
        leftPane = .tasks
        screen = .planner
    }

    /// View ▸ Notes Panel and Goals Panel: the panel on the screen the user is on. The Calendar, the Notes and the Garden
    /// have no left side, so they go to the Planner first.
    func showLeftPane(_ pane: LeftPane) {
        leftPane = pane
        if !LeftPane.isAvailable(on: screen) { screen = .planner }
    }

    /// Opens `day` where it can be seen. Today goes to the Today screen, which only ever shows today.
    /// Any other day opens the Planner on its week.
    func showDay(_ day: DayKey) {
        selectedDay = day
        screen = day == .today() ? .today : .planner
    }

    /// View ▸ Zoom In and Zoom Out. The planner reads the new height from the same setting.
    func zoomPlanner(by factor: Double) {
        let defaults = UserDefaults.standard
        let now = defaults.object(forKey: "planner.hourHeight") as? Double ?? 64
        let range = PlannerGeometry.zoomRange
        defaults.set(min(Double(range.upperBound), max(Double(range.lowerBound), now * factor)), forKey: "planner.hourHeight")
    }

    /// File ▸ New Event (⇧⌘N): an event of the default length (Settings ▸ Planner, one hour at first)
    /// at the next free time of the chosen day. Its editor opens.
    func newEventNow() {
        if screen != .planner { showDay(selectedDay) }   // the Calendar and the Notes have no time grid
        let defaults = UserDefaults.standard
        let workStart = defaults.object(forKey: "planner.workStart") as? Int ?? 9 * 60
        let length = defaults.object(forKey: "planner.defaultLength") as? Int ?? SettingsRules.defaultEventLength
        let day = selectedDay
        guard let start = nextFreeSlot(day: day, length: length, workStart: workStart, step: PlannerMath.step), start + length <= 1440 else {
            showToast("No free time left on this day.")
            return
        }
        createFromDraft(title: "New event", day: day, start: start, end: start + length, asEvent: true)
        if let id = selection.first, let e = event(id) { editEvent(e) }
    }
}
