import Foundation
import GroveCore

/// What the menu bar window needs from the store.
extension AppStore {
    /// The "Now" and "Next" lines for today.
    func menuBarLines(minute: Int) -> NowNext {
        let today = DayKey.today()
        return NowNextRules.make(blocks: blocks(for: today...today), minute: minute)
    }

    /// The quick-add box in the menu bar. A task with no day in its text goes to today.
    @discardableResult
    func menuBarAdd(_ text: String) -> TaskItem? {
        quickAdd(text, default: .day(.today()))
    }
}
