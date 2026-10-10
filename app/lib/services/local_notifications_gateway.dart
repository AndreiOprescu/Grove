import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' show TZDateTime, UTC;

import 'notification_gateway.dart';
import 'system_notifier.dart';

/// The system notification centre, through `flutter_local_notifications`.
/// It works on Android, iOS, macOS and Windows.
class LocalNotificationsGateway implements NotificationGateway {
  LocalNotificationsGateway({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// The Android drawable `ic_notification.xml`.
  static const androidIcon = 'ic_notification';

  /// The Darwin category that has the "Mark done" button.
  static const focusCategory = 'focus-end';
  static const doneTitle = 'Mark done';

  /// Windows knows Grove by these two. Do not change them: Windows would see a
  /// new app.
  static const windowsAppId = 'local.grove.Grove';
  static const windowsGuid = '86d6657b-93ec-4764-9e41-23fcc66ed766';

  static bool get _windows => defaultTargetPlatform == TargetPlatform.windows;

  AndroidFlutterLocalNotificationsPlugin? get _androidPlugin => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  IOSFlutterLocalNotificationsPlugin? get _iosPlugin => _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();
  MacOSFlutterLocalNotificationsPlugin? get _macPlugin => _plugin
      .resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin
      >();

  @override
  Future<void> start(void Function(NoteResponse response) onResponse) async {
    // Grove asks for the permission later, after the welcome card.
    final darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestSoundPermission: false,
      requestBadgePermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          focusCategory,
          actions: [
            // In the foreground: the store lives in the app, so the app must
            // run to mark the task done.
            DarwinNotificationAction.plain(
              SystemNotifier.doneAction,
              doneTitle,
              options: {DarwinNotificationActionOption.foreground},
            ),
          ],
        ),
      ],
    );
    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings(androidIcon),
        iOS: darwin,
        macOS: darwin,
        windows: const WindowsInitializationSettings(
          appName: 'Grove',
          appUserModelId: windowsAppId,
          guid: windowsGuid,
        ),
      ),
      onDidReceiveNotificationResponse: (r) =>
          onResponse(NoteResponse(payload: r.payload, actionId: r.actionId)),
    );
  }

  @override
  Future<bool> permitted() async {
    final android = _androidPlugin;
    if (android != null) {
      return await android.areNotificationsEnabled() ?? false;
    }
    final ios = _iosPlugin;
    if (ios != null) {
      return (await ios.checkPermissions())?.isEnabled ?? false;
    }
    final mac = _macPlugin;
    if (mac != null) {
      return (await mac.checkPermissions())?.isEnabled ?? false;
    }
    // Windows has no question: an app can always show notifications.
    return _windows;
  }

  @override
  Future<bool> requestPermission() async {
    final android = _androidPlugin;
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _iosPlugin;
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }
    final mac = _macPlugin;
    if (mac != null) {
      return await mac.requestPermissions(alert: true, sound: true) ?? false;
    }
    return _windows;
  }

  @override
  Future<List<PendingNote>> pending() async => [
    for (final p in await _plugin.pendingNotificationRequests())
      PendingNote(id: p.id, title: p.title, body: p.body, payload: p.payload),
  ];

  @override
  Future<void> schedule(NoteRequest request) {
    final done = request.donePayload;
    final darwin = DarwinNotificationDetails(
      // Show it also when Grove is the front app.
      presentBanner: true,
      presentList: true,
      presentSound: true,
      categoryIdentifier: done == null ? null : focusCategory,
    );
    return _plugin.zonedSchedule(
      id: request.id,
      title: request.title,
      body: request.body,
      payload: request.payload,
      // A moment in time, written in UTC. Grove needs no time zone list then.
      scheduledDate: TZDateTime.from(request.at, UTC),
      // No "Alarms & reminders" permission. Android can be a little late.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'reminders',
          'Reminders',
          channelDescription:
              'Events, time blocks, due times and the end of a focus session.',
          importance: Importance.high,
          priority: Priority.high,
          actions: [
            if (done != null)
              const AndroidNotificationAction(
                SystemNotifier.doneAction,
                doneTitle,
                showsUserInterface: true,
              ),
          ],
        ),
        iOS: darwin,
        macOS: darwin,
        windows: WindowsNotificationDetails(
          actions: [
            // Windows gives back only this text, so the action is in it.
            if (done != null)
              WindowsAction(content: doneTitle, arguments: done),
          ],
        ),
      ),
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<NoteResponse?> launchResponse() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    final response = details?.notificationResponse;
    if (details == null ||
        !details.didNotificationLaunchApp ||
        response == null) {
      return null;
    }
    return NoteResponse(payload: response.payload, actionId: response.actionId);
  }
}
