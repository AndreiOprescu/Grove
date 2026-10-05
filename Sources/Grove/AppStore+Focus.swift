import Foundation
import GroveCore

/// One focus session: a count down to the end of a block.
struct FocusSession: Equatable {
    var blockId: String
    var taskId: String?
    var title: String
    var day: DayKey
    var start: Date
    var end: Date
    /// The time ran out. The card asks "Mark done?".
    var finished = false
}

/// Focus mode (PLAN §5.1.7). `FocusRules` has the arithmetic.
extension AppStore {
    /// Starts the count down to the end of `block`. A running session is replaced.
    func startFocus(_ block: EventItem) {
        let now = Date()
        guard FocusRules.canStart(block, now: now), let end = FocusRules.endDate(block.end) else {
            showToast("This block is over.")
            return
        }
        focus = FocusSession(blockId: block.id, taskId: block.taskId, title: block.title.isEmpty ? "Focus" : block.title,
                             day: block.start.day, start: now, end: end)
        guard let f = focus else { return }
        let ref = f.taskId.map { ItemRef(.task, $0) } ?? ItemRef(.event, f.blockId)
        let ending = FocusEnd(title: f.title, at: end, day: f.day, ref: ref, taskId: f.taskId)
        let notifier = notifier
        let previous = focusNotify
        let enabled = notifyEnabled   // the Settings switch for notifications covers this one too
        focusNotify = Task {
            await previous?.value
            if enabled { await notifier.scheduleFocusEnd(ending) } else { await notifier.cancelFocusEnd() }
        }
    }

    /// Ends the session and takes the "time is up" notification away. The task stays as it is.
    func stopFocus() {
        guard focus != nil else { return }
        focus = nil
        let notifier = notifier
        let previous = focusNotify
        focusNotify = Task {
            await previous?.value
            await notifier.cancelFocusEnd()
        }
    }

    /// The count down reached zero. The card asks "Mark done?".
    func focusTimeUp() {
        guard focus != nil else { return }
        focus?.finished = true
    }

    /// "Mark done": checks the task off (when the block has one) and ends the session.
    func markFocusDone() {
        guard let f = focus else { return }
        if let id = f.taskId, task(id)?.status == .open { toggleDone(taskId: id) }
        stopFocus()
    }

    /// The "Mark done" button on the notification.
    func focusDoneFromNotification(_ taskId: String) {
        if task(taskId)?.status == .open { toggleDone(taskId: taskId) }
        if focus?.taskId == taskId { stopFocus() }
    }
}
