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

    /// View ▸ Tasks (⌘2): the Planner screen with the task list open.
    func showTasks() {
        UserDefaults.standard.set(true, forKey: "shell.tasksOpen")
        screen = .planner
    }

    /// One day back or forward.
    func stepDay(_ days: Int) {
        selectedDay = selectedDay.adding(days: days)
    }

    /// View ▸ Day, 3 Days, Week. The Calendar keeps its own mode. Any other screen goes to the Planner.
    /// "Day" on the Today screen stays there, because that screen is one day already.
    func showMode(_ mode: PlannerMode) {
        if screen == .today && mode == .day { return }
        if screen != .calendar { screen = .planner }
        if let key = PlannerMode.storageKey(for: screen) { UserDefaults.standard.set(mode.rawValue, forKey: key) }
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
        if screen != .planner { screen = .today }   // the Calendar and the Notes have no time grid
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
