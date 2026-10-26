import Cocoa
import CoreGraphics

/// Writes down when this Mac is used: the screen comes on or goes off, the
/// Mac sleeps or wakes, the screen is locked or unlocked. Grove learns the
/// nights from these times (lib/core/sleep). Only times are kept, no app
/// names. The Mac tells an app only while it runs, so the log also says when
/// Grove began and stopped listening.
///
/// The log lives in UserDefaults under `grove.activity`, as pairs
/// [ms since 1970 (Double), code (Int)]. It keeps 14 days and at most 5000
/// pairs. The channel `grove/activity` reads it (MainFlutterWindow.swift).
final class ActivityRecorder {
  static let shared = ActivityRecorder()

  /// The codes of the log. Dart reads the same numbers
  /// (lib/services/device_activity_source.dart).
  enum Code: Int {
    case useStart = 0
    case useEnd = 1
    case recordStart = 2
    case recordStop = 3
  }

  static let defaultsKey = "grove.activity"
  static let keepSeconds: TimeInterval = 14 * 24 * 60 * 60
  static let maxPairs = 5000

  /// A use ends when the person last touched the Mac, not when the screen
  /// went off later. The idle time moves the end back, at most this much.
  static let longestIdle: TimeInterval = 30 * 60

  /// Called on the main thread each time the Mac is used again.
  var onUseStart: (() -> Void)?

  private var observers: [(NotificationCenter, NSObjectProtocol)] = []
  private var started = false
  private let defaults = UserDefaults.standard

  private init() {}

  /// Begins to listen. A second call does nothing.
  func start() {
    if started { return }
    started = true

    let workspace = NSWorkspace.shared.notificationCenter
    listen(workspace, NSWorkspace.willSleepNotification, .useEnd)
    listen(workspace, NSWorkspace.didWakeNotification, .useStart)
    listen(workspace, NSWorkspace.screensDidSleepNotification, .useEnd)
    listen(workspace, NSWorkspace.screensDidWakeNotification, .useStart)
    listen(workspace, NSWorkspace.sessionDidResignActiveNotification, .useEnd)
    listen(workspace, NSWorkspace.sessionDidBecomeActiveNotification, .useStart)

    let distributed = DistributedNotificationCenter.default()
    listen(distributed, Notification.Name("com.apple.screenIsLocked"), .useEnd)
    listen(distributed, Notification.Name("com.apple.screenIsUnlocked"), .useStart)

    record(.recordStart, at: Date())
  }

  /// Stops listening. Grove quits.
  func stop() {
    if !started { return }
    started = false
    for (center, token) in observers {
      center.removeObserver(token)
    }
    observers.removeAll()
    record(.recordStop, at: Date())
  }

  /// The events from [from] to [to] (ms since 1970), oldest first, as one
  /// flat list [ms, code, ms, code, …].
  func events(from: Int64, to: Int64) -> [Int64] {
    var flat: [Int64] = []
    for (ms, code) in load() {
      let at = Int64(ms)
      if at < from || at > to { continue }
      flat.append(at)
      flat.append(Int64(code))
    }
    return flat
  }

  private func listen(_ center: NotificationCenter, _ name: Notification.Name, _ code: Code) {
    let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
      self?.heard(code)
    }
    observers.append((center, token))
  }

  private func heard(_ code: Code) {
    var at = Date()
    if code == .useEnd {
      // The Mac went idle first: the use ended at the last key or mouse event.
      let anyEvent = CGEventType(rawValue: ~0)!
      let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyEvent)
      if idle.isFinite && idle > 0 {
        at = at.addingTimeInterval(-min(idle, ActivityRecorder.longestIdle))
      }
    }
    record(code, at: at)
    if code == .useStart {
      onUseStart?()
    }
  }

  private func record(_ code: Code, at date: Date) {
    var log = load()
    var ms = (date.timeIntervalSince1970 * 1000).rounded()
    // A use that ends back in time never ends before the last thing heard.
    if let last = log.last, ms < last.0 {
      ms = last.0
    }
    log.append((ms, code.rawValue))

    let oldest = (Date().timeIntervalSince1970 - ActivityRecorder.keepSeconds) * 1000
    log.removeAll { $0.0 < oldest }
    if log.count > ActivityRecorder.maxPairs {
      log.removeFirst(log.count - ActivityRecorder.maxPairs)
    }
    save(log)
  }

  private func load() -> [(Double, Int)] {
    guard let raw = defaults.array(forKey: ActivityRecorder.defaultsKey) else { return [] }
    var log: [(Double, Int)] = []
    log.reserveCapacity(raw.count)
    for item in raw {
      guard let pair = item as? [Any], pair.count == 2,
        let ms = (pair[0] as? NSNumber)?.doubleValue,
        let code = (pair[1] as? NSNumber)?.intValue,
        Code(rawValue: code) != nil
      else { continue }
      log.append((ms, code))
    }
    return log
  }

  private func save(_ log: [(Double, Int)]) {
    let raw: [[Any]] = log.map { [$0.0, $0.1] }
    defaults.set(raw, forKey: ActivityRecorder.defaultsKey)
  }
}
