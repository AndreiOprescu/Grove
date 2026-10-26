import 'package:flutter/services.dart';

import 'app_window.dart';

/// May Grove open by itself when the user logs in to the Mac?
enum LoginItemStatus {
  /// Grove opens at login, hidden, with its icon in the menu bar.
  enabled,

  /// Grove does not open at login.
  notRegistered,

  /// Grove asked; the user must allow it in System Settings, Login Items.
  requiresApproval,

  /// The Mac cannot find this copy of Grove (for example a build that is not
  /// in a folder of apps).
  notFound,

  /// This system has no login items Grove can set (macOS before 13, a phone,
  /// Windows).
  unsupported,
}

/// "Open Grove at login".
abstract class LoginItem {
  Future<LoginItemStatus> status();

  /// Turns it on or off. Returns the status after.
  Future<LoginItemStatus> set(bool on);
}

/// The login item of the Mac (SMAppService in `MainFlutterWindow.swift`),
/// over the channel `grove/login`. A system with no native side is
/// `unsupported`. A refusal of the Mac comes back as a [PlatformException]
/// from [set], so the screen can say why.
class MethodChannelLoginItem implements LoginItem {
  const MethodChannelLoginItem({
    this.channel = const MethodChannel('grove/login'),
  });

  /// The native side. A test gives its own.
  final MethodChannel channel;

  @override
  Future<LoginItemStatus> status() async {
    try {
      return parse(await channel.invokeMethod<String>('status'));
    } on PlatformException {
      return LoginItemStatus.unsupported;
    } on MissingPluginException {
      return LoginItemStatus.unsupported;
    }
  }

  @override
  Future<LoginItemStatus> set(bool on) async {
    try {
      return parse(await channel.invokeMethod<String>('set', {'on': on}));
    } on MissingPluginException {
      return LoginItemStatus.unsupported;
    }
  }

  /// The name the native side sends. An unknown name is `unsupported`.
  static LoginItemStatus parse(String? name) {
    for (final status in LoginItemStatus.values) {
      if (status.name == name) return status;
    }
    return LoginItemStatus.unsupported;
  }
}

/// The window of Grove on a computer. On the Mac a closed window only hides
/// (Grove stays in the menu bar); [show] brings it back with its Dock icon.
class WindowControl {
  const WindowControl._();

  /// Shows the window in front. A system with no native side does nothing.
  static Future<void> show() => const AppWindow().show();
}
