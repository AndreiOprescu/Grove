import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../state/state.dart';
import 'app_window.dart';
import 'backup_schedule.dart';
import 'claude_cli_runner.dart';
import 'device_activity_source.dart';
import 'local_notifications_gateway.dart';
import 'login_item.dart';
import 'sync_schedule.dart';
import 'system_notifier.dart';
import 'tray_gateway.dart';
import 'tray_manager_gateway.dart';
import 'tray_service.dart';
import 'update_check.dart';
import 'weather_check.dart';

/// The work that runs behind the screens from launch to quit: reminders, the
/// daily backup, the sync, the check for a new Grove, the weather, and the
/// tray icon on a computer.
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
  }) : _showWindow = showWindow ?? (() => unawaited(window.show())),
       _backup = BackupSchedule(store),
       _sync = SyncSchedule(store),
       _updates = UpdateSchedule(store),
       _weather = WeatherSchedule(store),
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

  /// The door to the `claude` command of the agent (ADR 0004). Only a
  /// computer can run it; a phone or the web gets null and only makes jobs.
  static AgentRunner? agentRunner() {
    if (kIsWeb) return null;
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return ClaudeCliRunner();
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return null;
    }
  }

  /// The use history of this device, for the bedtime reminder (ADR 0005):
  /// the phone (Android) and the Mac. Null on the others.
  static ActivitySource? activitySource() {
    if (kIsWeb) return null;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return MethodChannelActivitySource(name: 'android');
      case TargetPlatform.macOS:
        return MethodChannelActivitySource(name: 'mac');
      case TargetPlatform.iOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return null;
    }
  }

  /// "Open Grove at login". Only the Mac has it.
  static LoginItem? loginItem() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS
      ? const MethodChannelLoginItem()
      : null;

  final AppStore store;
  final void Function() _showWindow;
  final BackupSchedule _backup;
  final SyncSchedule _sync;
  final UpdateSchedule _updates;
  final WeatherSchedule _weather;
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
    // A click on a reminder brings the window of a computer to the front.
    if (_tray != null) store.bringToFront ??= _showWindow;
    // Before the reminders: they wait for the nights it learns.
    unawaited(store.startSleep());
    unawaited(store.keepRemindersFresh());
    final notifier = store.notifier;
    // A click on a notification that started Grove.
    if (notifier is SystemNotifier) unawaited(notifier.deliverLaunch());
    _backup.start();
    _sync.start();
    _updates.start();
    _weather.start();
    _trayShown = _tray?.start() ?? false;
    _lifecycle = AppLifecycleListener(onResume: resumed);
  }

  /// Grove is in front again. A phone stops the timers of an app in the
  /// background, so the checks run now.
  void resumed() {
    if (!_started) return;
    _backup.check();
    _sync.check();
    _updates.check();
    _weather.check();
    store.resumeSleep();
    store.scheduleReminderRefresh();
    _tray?.refresh();
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    _lifecycle?.dispose();
    _lifecycle = null;
    _backup.dispose();
    _sync.dispose();
    _updates.dispose();
    _weather.dispose();
    _tray?.dispose();
    _trayShown = false;
  }
}
