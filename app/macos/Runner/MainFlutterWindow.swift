import Cocoa
import FlutterMacOS
import ServiceManagement

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  /// The sizes of the window of the Mac app (Sources/Grove/GroveApp.swift,
  /// PLAN §5.8). The window buttons are over the screens, so the frame of
  /// the window and its content have the same size.
  static let smallestSize = NSSize(width: 1100, height: 620)
  static let firstSize = NSSize(width: 1280, height: 800)

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // A hidden title bar: the screens reach the top edge of the window. The
    // top strip of the app leaves the first 84 points to the window buttons
    // (lib/ui/shell/root_view.dart).
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)

    // The window opens at the first size, in the middle of the screen, each
    // time. Without this line the system puts back the frame of the last
    // run after the lines below, also a frame from before these sizes.
    self.isRestorable = false
    self.contentMinSize = MainFlutterWindow.smallestSize
    self.setContentSize(MainFlutterWindow.firstSize)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    // The tray menu asks for the window with this channel
    // (lib/services/app_window.dart). The top strip asks to move the window
    // (lib/ui/shell/window_drag.dart).
    let windowChannel = FlutterMethodChannel(
      name: "grove/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    windowChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "show":
        // Also after the window was closed (hidden) or Grove opened hidden
        // at login.
        self?.bringBack()
        result(nil)
      case "drag":
        // The mouse is down on an empty part of the top strip: the system
        // moves the window until the button goes up, as with a title bar.
        if let window = self, let event = window.currentEvent ?? NSApp.currentEvent {
          window.performDrag(with: event)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    registerActivityChannel(flutterViewController.engine.binaryMessenger)
    registerLoginChannel(flutterViewController.engine.binaryMessenger)

    // The red button and ⌘W hide the window; Grove stays in the menu bar.
    self.delegate = self

    super.awakeFromNib()
  }

  // MARK: Hide and show

  /// Set when the window leaves full screen only to hide after.
  private var hideAfterFullScreen = false

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    hideToMenuBar()
    return false
  }

  func windowDidExitFullScreen(_ notification: Notification) {
    if hideAfterFullScreen {
      hideAfterFullScreen = false
      hideToMenuBar()
    }
  }

  /// Hides the window and the Dock icon. Grove keeps running: the menu bar
  /// icon, the reminders and the activity log go on.
  func hideToMenuBar() {
    if styleMask.contains(.fullScreen) {
      // A hidden full-screen window leaves an empty space behind.
      hideAfterFullScreen = true
      toggleFullScreen(nil)
      return
    }
    orderOut(nil)
    NSApp.setActivationPolicy(.accessory)
  }

  /// Shows the window again, with the Dock icon, in front.
  func bringBack() {
    hideAfterFullScreen = false
    NSApp.setActivationPolicy(.regular)
    if isMiniaturized {
      deminiaturize(nil)
    }
    makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    // The menu bar of the app shows only after the switch to a regular app
    // is done; a second activate on the next turn brings it.
    DispatchQueue.main.async {
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  // MARK: Channels

  /// The use log of this Mac (ActivityRecorder.swift) for
  /// lib/services/device_activity_source.dart.
  private func registerActivityChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "grove/activity", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "access":
        result("granted")
      case "openAccessSettings":
        result(nil)
      case "events":
        let args = call.arguments as? [String: Any]
        guard let from = (args?["from"] as? NSNumber)?.int64Value,
          let to = (args?["to"] as? NSNumber)?.int64Value
        else {
          result(FlutterError(code: "args", message: "events needs from and to", details: nil))
          return
        }
        result(ActivityRecorder.shared.events(from: from, to: to))
      case "nextAlarm":
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    ActivityRecorder.shared.onUseStart = {
      channel.invokeMethod("changed", arguments: nil)
    }
  }

  /// "Open Grove at login" (lib/services/login_item.dart).
  private func registerLoginChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "grove/login", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard #available(macOS 13.0, *) else {
        switch call.method {
        case "status", "set":
          result("unsupported")
        default:
          result(FlutterMethodNotImplemented)
        }
        return
      }
      let service = SMAppService.mainApp
      switch call.method {
      case "status":
        result(MainFlutterWindow.loginStatus(service.status))
      case "set":
        let args = call.arguments as? [String: Any]
        guard let on = args?["on"] as? Bool else {
          result(FlutterError(code: "args", message: "set needs on", details: nil))
          return
        }
        do {
          if on {
            if service.status != .enabled {
              try service.register()
            }
          } else if service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
          }
          result(MainFlutterWindow.loginStatus(service.status))
        } catch {
          result(
            FlutterError(
              code: "login", message: error.localizedDescription,
              details: MainFlutterWindow.loginStatus(service.status)))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  @available(macOS 13.0, *)
  private static func loginStatus(_ status: SMAppService.Status) -> String {
    switch status {
    case .enabled: return "enabled"
    case .notRegistered: return "notRegistered"
    case .requiresApproval: return "requiresApproval"
    case .notFound: return "notFound"
    @unknown default: return "notFound"
    }
  }
}
