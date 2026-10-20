// On a Mac the window of Grove has no title bar (PLAN §5.8: the screens
// reach the top edge, the three window buttons are over them). The empty
// parts of the top strip take the place of the title bar: a drag on them
// moves the window.
//
// The native side is small: `MainFlutterWindow.swift` answers the method
// `drag` of the channel `grove/window` and gives the mouse to the system.
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class WindowDragArea extends StatelessWidget {
  const WindowDragArea({super.key});

  static const _channel = MethodChannel('grove/window');

  /// True on the system where the window has no title bar.
  static bool get isUsed =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static Future<void> _move() async {
    try {
      await _channel.invokeMethod<void>('drag');
    } on PlatformException {
      // The window stays where it is.
    } on MissingPluginException {
      // A test, or a build with no native side.
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    supportedDevices: const {PointerDeviceKind.mouse},
    onPanStart: (_) => _move(),
  );
}
