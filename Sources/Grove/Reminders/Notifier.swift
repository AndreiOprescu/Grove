import Foundation
import UserNotifications
import GroveCore

/// What the Mac says about notifications from Grove.
enum NotifyAuthorization: Equatable {
    case notAsked, allowed, denied
}

/// The "time is up" notification of a focus session.
struct FocusEnd: Equatable {
    var title: String
    var at: Date
    var day: DayKey
    var ref: ItemRef
    /// Set when the block belongs to a task. The notification then has a "Mark done" button.
    var taskId: String?
}

/// The door to the system notification centre. A test uses a fake one.
@MainActor
protocol Notifier: AnyObject {
    func authorization() async -> NotifyAuthorization
    func requestAuthorization() async -> NotifyAuthorization
    /// Takes away every reminder Grove asked for before, and asks for these.
    func replaceAll(_ reminders: [Reminder]) async
    /// Asks for the "time is up" notification of a focus session. It replaces the one before.
    func scheduleFocusEnd(_ end: FocusEnd) async
    func cancelFocusEnd() async
    /// Set by the store. Called when the user clicks a notification.
    var onOpen: ((DayKey, ItemRef) -> Void)? { get set }
    /// Set by the store. Called with the task id when the user taps "Mark done" on the focus notification.
    var onFocusDone: ((String) -> Void)? { get set }
}

/// Does nothing. Used when Grove does not run as an app (tests, `swift run`), because the system centre needs an app bundle.
@MainActor
final class NullNotifier: Notifier {
    var onOpen: ((DayKey, ItemRef) -> Void)?
    var onFocusDone: ((String) -> Void)?
    func authorization() async -> NotifyAuthorization { .notAsked }
    func requestAuthorization() async -> NotifyAuthorization { .notAsked }
    func replaceAll(_ reminders: [Reminder]) async {}
    func scheduleFocusEnd(_ end: FocusEnd) async {}
    func cancelFocusEnd() async {}
}

/// The real thing, on `UNUserNotificationCenter`.
@MainActor
final class SystemNotifier: NSObject, Notifier, UNUserNotificationCenterDelegate {
    var onOpen: ((DayKey, ItemRef) -> Void)?
    var onFocusDone: ((String) -> Void)?
    private let center = UNUserNotificationCenter.current()
    private static let focusId = "focus-end"
    private static let focusCategory = "focus-end"
    private static let doneAction = "focus-done"

    /// Nil when Grove does not run from its .app. Asking the system centre without a bundle crashes.
    static func ifAppBundle() -> SystemNotifier? {
        Bundle.main.bundleIdentifier == nil ? nil : SystemNotifier()
    }

    private override init() {
        super.init()
        center.delegate = self
        let done = UNNotificationAction(identifier: Self.doneAction, title: "Mark done", options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.focusCategory, actions: [done],
                                                                 intentIdentifiers: [])])
    }

    func authorization() async -> NotifyAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notAsked
        case .denied: .denied
        default: .allowed
        }
    }

    func requestAuthorization() async -> NotifyAuthorization {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        return await authorization()
    }

    func replaceAll(_ reminders: [Reminder]) async {
        // Only Grove's own reminders. Other requests (the focus timer) stay.
        let mine = await center.pendingNotificationRequests().map(\.identifier)
            .filter { $0.hasPrefix("ev-") || $0.hasPrefix("due-") }
        center.removePendingNotificationRequests(withIdentifiers: mine)
        for r in reminders {
            let content = UNMutableNotificationContent()
            content.title = r.title
            content.body = r.body
            content.sound = .default
            content.userInfo = ["day": r.day.string, "kind": r.ref.type.rawValue, "id": r.ref.id]
            var when = DateComponents()
            when.year = r.fireAt.day.year
            when.month = r.fireAt.day.month
            when.day = r.fireAt.day.day
            when.hour = r.fireAt.minute / 60
            when.minute = r.fireAt.minute % 60
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: r.id, content: content, trigger: trigger))
        }
    }

    func scheduleFocusEnd(_ end: FocusEnd) async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.focusId])
        let content = UNMutableNotificationContent()
        content.title = "Focus time is up"
        content.body = end.taskId == nil ? "\(end.title) is over." : "\(end.title). Mark it done?"
        content.sound = .default
        if let taskId = end.taskId {
            content.categoryIdentifier = Self.focusCategory
            content.userInfo = ["day": end.day.string, "kind": end.ref.type.rawValue, "id": end.ref.id, "taskId": taskId]
        } else {
            content.userInfo = ["day": end.day.string, "kind": end.ref.type.rawValue, "id": end.ref.id]
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.at.timeIntervalSinceNow), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: Self.focusId, content: content, trigger: trigger))
    }

    func cancelFocusEnd() async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.focusId])
        center.removeDeliveredNotifications(withIdentifiers: [Self.focusId])
    }

    // MARK: Delegate (the system calls these on its own queue)

    /// Show the banner even when Grove is the front app.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        if response.actionIdentifier == Self.doneAction, let taskId = info["taskId"] as? String {
            await MainActor.run { onFocusDone?(taskId) }
            return
        }
        guard let day = info["day"] as? String, let kind = info["kind"] as? String,
              let type = ItemType(rawValue: kind), let id = info["id"] as? String else { return }
        await MainActor.run { onOpen?(DayKey(day), ItemRef(type, id)) }
    }
}
