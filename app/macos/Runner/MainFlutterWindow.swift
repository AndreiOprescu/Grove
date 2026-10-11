import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // The tray menu asks for the window with this channel.
    // See lib/services/app_window.dart.
    let windowChannel = FlutterMethodChannel(
      name: "grove/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    windowChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "show" else {
        result(FlutterMethodNotImplemented)
        return
      }
      if let window = self {
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized {
          window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
      }
      result(nil)
    }

    super.awakeFromNib()
  }
}
