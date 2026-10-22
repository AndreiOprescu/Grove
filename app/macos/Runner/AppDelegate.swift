import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// The Mac opened Grove as a login item: the window stays hidden and the
  /// icon stays in the menu bar only.
  private var launchedAtLogin = false

  override func awakeFromNib() {
    super.awakeFromNib()
    // FlutterAppDelegate has its own launch and quit methods; Grove listens
    // to the notifications so those keep working.
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(willFinishLaunching(_:)),
      name: NSApplication.willFinishLaunchingNotification, object: nil)
    center.addObserver(
      self, selector: #selector(didFinishLaunching(_:)),
      name: NSApplication.didFinishLaunchingNotification, object: nil)
    center.addObserver(
      self, selector: #selector(willTerminate(_:)),
      name: NSApplication.willTerminateNotification, object: nil)
  }

  @objc private func willFinishLaunching(_ notification: Notification) {
    launchedAtLogin = AppDelegate.isLoginLaunch()
  }

  @objc private func didFinishLaunching(_ notification: Notification) {
    ActivityRecorder.shared.start()
    if launchedAtLogin {
      (mainFlutterWindow as? MainFlutterWindow)?.hideToMenuBar()
    }
  }

  @objc private func willTerminate(_ notification: Notification) {
    ActivityRecorder.shared.stop()
  }

  /// The Mac says so in the open event. A Mac that started less than two
  /// minutes ago counts too: SMAppService does not always say it.
  private static func isLoginLaunch() -> Bool {
    if let event = NSAppleEventManager.shared().currentAppleEvent,
      let property = event.paramDescriptor(forKeyword: keyAEPropData),
      property.enumCodeValue == keyAELaunchedAsLogInItem
    {
      return true
    }
    return ProcessInfo.processInfo.systemUptime < 120
  }

  /// A closed window hides; Grove keeps running in the menu bar. ⌘Q, "Quit
  /// Grove" in the tray menu and a quit from a script still quit.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  /// Grove is opened again (Finder, Spotlight, the Dock) while its window is
  /// hidden: the window comes back.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
    -> Bool
  {
    if !flag {
      (mainFlutterWindow as? MainFlutterWindow)?.bringBack()
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
