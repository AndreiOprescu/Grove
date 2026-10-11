import 'dart:ui' show AppExitType;

import 'package:flutter/services.dart';

/// The window of Grove on a computer. The tray uses it.
///
/// The native side is small: `MainFlutterWindow.swift` on the Mac and
/// `flutter_window.cpp` on Windows answer the method `show`.
class AppWindow {
  const AppWindow({this.method = 'show'});

  static const _channel = MethodChannel('grove/window');

  /// The name of the native method. A test changes it.
  final String method;

  /// Brings the window to the front, also when it is small in the Dock or the
  /// taskbar. A system with no native side does nothing.
  Future<void> show() async {
    try {
      await _channel.invokeMethod<void>(method);
    } on PlatformException {
      // The window stays where it is.
    } on MissingPluginException {
      // A phone, or a test.
    }
  }

  /// Quits Grove the polite way: the system can say no.
  Future<void> quit() async {
    await ServicesBinding.instance.exitApplication(AppExitType.cancelable);
  }
}
