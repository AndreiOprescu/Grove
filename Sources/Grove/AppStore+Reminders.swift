import SwiftUI
import GroveCore

/// Reminders before events and due times (PLAN §5.6). `ReminderPlanner` has the rules.
/// This file reads the data, sends the list to the notification centre, and opens what the user clicks.
extension AppStore {
    /// How many days ahead Grove sets reminders.
    static let reminderDays = 14

    func reminderNow() -> WallTime { clockOverride ?? WallTime(day: .today(), minute: nowMinute()) }

    /// The reminders for the coming days, from the data now.
    func buildReminders() -> [Reminder] {
        let now = reminderNow()
        let events = eventItems(in: now.day...now.day.adding(days: Self.reminderDays))
        var finished: Set<String> = []
        for id in Set(events.compactMap(\.taskId)) {
            if let t = task(id), t.status != .open { finished.insert(id) }
        }
        let due = (try? repos.tasks.openWithTimedDue()) ?? []
        return ReminderPlanner.plan(events: events, dueTasks: due, finishedTaskIds: finished, now: now, lead: notifyLead)
    }

    /// Makes the reminders again now. Does nothing until the user has allowed notifications.
    func refreshReminders() async {
        let status = await notifier.authorization()
        notifyStatus = status
        guard status == .allowed else { return }
        await notifier.replaceAll(notifyEnabled ? buildReminders() : [])
    }

    /// Makes the reminders again after a short wait. A new call during the wait restarts the wait.
    func scheduleReminderRefresh() {
        guard !(notifier is NullNotifier) else { return }
        let previous = reminderTask
        previous?.cancel()
        let delay = reminderDelay
        reminderTask = Task { [weak self] in
            await previous?.value   // never two refreshes at the same time
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await self.refreshReminders()
        }
    }

    /// Runs from launch to quit. Makes the reminders again each hour, so the 14 days move forward when no edit happens.
    func keepRemindersFresh() async {
        while !Task.isCancelled {
            await refreshReminders()
            try? await Task.sleep(for: .seconds(3600))
        }
    }

    func refreshNotifyStatus() async { notifyStatus = await notifier.authorization() }

    /// Shows the system question. Grove asks after the welcome card, and from Settings.
    func askForNotifications() async {
        notifyStatus = await notifier.requestAuthorization()
        await refreshReminders()
    }

    func setNotifyEnabled(_ on: Bool) {
        notifyEnabled = on
        UserDefaults.standard.set(on, forKey: "notifications.enabled")
        scheduleReminderRefresh()
    }

    /// Only the choices on the list count (0, 5, 10, 15).
    func setNotifyLead(_ minutes: Int) {
        guard ReminderPlanner.leadChoices.contains(minutes) else { return }
        notifyLead = minutes
        UserDefaults.standard.set(minutes, forKey: "notifications.lead")
        scheduleReminderRefresh()
    }

    /// A click on a notification: open the item on its day, and bring Grove to the front.
    func openFromNotification(day: DayKey, ref: ItemRef) {
        open(ref)
        selectedDay = day   // also when the item is gone: the day still opens
        screen = .today
        NSApp?.activate(ignoringOtherApps: true)
    }
}
