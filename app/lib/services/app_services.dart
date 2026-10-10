import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../state/state.dart';
import 'app_window.dart';
import 'backup_schedule.dart';
import 'local_notifications_gateway.dart';
import 'system_notifier.dart';
import 'tray_gateway.dart';
import 'tray_manager_gateway.dart';
import 'tray_service.dart';

/// The work that runs behind the screens from launch to quit: reminders, the
/// daily backup, and the tray icon on a computer.
///
/// `main.dart` makes the notifier, opens the store with it, then starts this:
///
/// ```dart
/// final notifier = AppServices.notifier(prefs);
/// final store = AppStore.open(dataDir: dir, notifier: notifier, prefs: prefs);
/// AppServices.forThisDevice(store).start();
/// ```
class AppServices {
  AppServices({
    required this.store,
    TrayGateway? tray,
    AppWindow window = const AppWindow(),
    void Function()? showWindow,
    void Function()? quit,
  }) : _backup = BackupSchedule(store),
       _tray = tray == null
           ? null
           : TrayService(
               store: store,
               gateway: tray,
               showWindow: showWindow ?? () => unawaited(window.show()),
               quit: quit ?? () => unawaited(window.quit()),
             );

  /// With the real tray on the Mac and on Windows. A phone has none.
  factory AppServices.forThisDevice(AppStore store) => AppServices(
    store: store,
    tray:
        !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.macOS ||
                defaultTargetPlatform == TargetPlatform.windows)
        ? TrayManagerGateway()
        : null,
  );

  /// The notification centre of this device. Grove has reminders on Android,
  /// iOS, macOS and Windows.
  static Notifier notifier(Prefs prefs) {
    if (kIsWeb) return NullNotifier();
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return SystemNotifier(
          gateway: LocalNotificationsGateway(),
          prefs: prefs,
        );
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return NullNotifier();
    }
  }

  final AppStore store;
  final BackupSchedule _backup;
  final TrayService? _tray;
  AppLifecycleListener? _lifecycle;
  bool _started = false;
  bool _trayShown = false;

  /// True after [start] when this device shows the tray icon.
  bool get trayShown => _trayShown;

  /// Call one time, after the Flutter binding is ready.
  void start() {
    if (_started) return;
    _started = true;
    unawaited(store.keepRemindersFresh());
    final notifier = store.notifier;
    // A click on a notification that started Grove.
    if (notifier is SystemNotifier) unawaited(notifier.deliverLaunch());
    _backup.start();
    _trayShown = _tray?.start() ?? false;
    _lifecycle = AppLifecycleListener(onResume: resumed);
  }

  /// Grove is in front again. A phone stops the timers of an app in the
  /// background, so the checks run now.
  void resumed() {
    if (!_started) return;
    _backup.check();
    store.scheduleReminderRefresh();
    _tray?.refresh();
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    _lifecycle?.dispose();
    _lifecycle = null;
    _backup.dispose();
    _tray?.dispose();
    _trayShown = false;
  }
}
