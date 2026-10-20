import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
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
        if let window = self {
          NSApp.activate(ignoringOtherApps: true)
          if window.isMiniaturized {
            window.deminiaturize(nil)
          }
          window.makeKeyAndOrderFront(nil)
        }
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

    super.awakeFromNib()
  }
}
