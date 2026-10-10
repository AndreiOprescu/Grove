import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The real plugin, with the Android side replaced by a list of the calls.
void main() {
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');

  late List<MethodCall> log;
  late Map<String, Object?> answers;
  late LocalNotificationsGateway gateway;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    log = [];
    answers = {'initialize': true};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          log.add(call);
          return answers[call.method];
        });
    gateway = LocalNotificationsGateway();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  Map<Object?, Object?> args(String method) =>
      log.lastWhere((c) => c.method == method).arguments
          as Map<Object?, Object?>;

  test('start uses the leaf icon', () async {
    await gateway.start((_) {});
    expect(args('initialize')['defaultIcon'], 'ic_notification');
  });

  test('a notification is asked for at the right moment, in UTC', () async {
    final at = DateTime(2031, 3, 14, 15, 9);
    await gateway.schedule(
      NoteRequest(
        id: 4242,
        title: 'Standup',
        body: 'In 5 min',
        payload: '{"id":"e1"}',
        at: at,
      ),
    );
    final sent = args('zonedSchedule');
    expect(sent['id'], 4242);
    expect(sent['title'], 'Standup');
    expect(sent['body'], 'In 5 min');
    expect(sent['payload'], '{"id":"e1"}');
    // The same moment, whatever the time zone of this computer is.
    expect(
      DateTime.parse(sent['scheduledDateTimeISO8601']! as String),
      at.toUtc(),
    );
    // Android and Apple systems know this name with no time zone list.
    expect(sent['timeZoneName'], 'Etc/UTC');
    expect(
      '${sent['scheduledDateTime']}Z',
      at.toUtc().toIso8601String().replaceAll('.000', ''),
    );

    final android = sent['platformSpecifics']! as Map<Object?, Object?>;
    expect(android['channelId'], 'reminders');
    expect(
      android['scheduleMode'],
      AndroidScheduleMode.inexactAllowWhileIdle.name,
    );
    expect(android['actions'], isEmpty);
  });

  test('the focus notification has the "Mark done" button', () async {
    await gateway.schedule(
      NoteRequest(
        id: 1,
        title: 'Focus time is up',
        body: 'Write report. Mark it done?',
        payload: '{}',
        donePayload: '{"action":"focus-done"}',
        at: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    final android =
        args('zonedSchedule')['platformSpecifics']! as Map<Object?, Object?>;
    final action =
        (android['actions']! as List<Object?>).single as Map<Object?, Object?>;
    expect(action['id'], 'focus-done');
    expect(action['title'], 'Mark done');
    expect(action['showsUserInterface'], isTrue);
  });

  test('cancel names the notification', () async {
    await gateway.cancel(4242);
    expect(args('cancel')['id'], 4242);
  });

  test('the pending list keeps the text', () async {
    answers['pendingNotificationRequests'] = [
      {'id': 7, 'title': 'T', 'body': 'B', 'payload': 'P'},
    ];
    final p = (await gateway.pending()).single;
    expect([p.id, p.title, p.body, p.payload], [7, 'T', 'B', 'P']);
  });

  test('the permission comes from the system', () async {
    answers['areNotificationsEnabled'] = false;
    expect(await gateway.permitted(), isFalse);
    answers['areNotificationsEnabled'] = true;
    expect(await gateway.permitted(), isTrue);

    answers['requestNotificationsPermission'] = true;
    expect(await gateway.requestPermission(), isTrue);
    answers['requestNotificationsPermission'] = false;
    expect(await gateway.requestPermission(), isFalse);
  });

  test('the click that started the app comes back', () async {
    expect(await gateway.launchResponse(), isNull);

    answers['getNotificationAppLaunchDetails'] = {
      'notificationLaunchedApp': false,
    };
    expect(await gateway.launchResponse(), isNull);

    answers['getNotificationAppLaunchDetails'] = {
      'notificationLaunchedApp': true,
      'notificationResponse': {
        'notificationId': 1,
        'actionId': 'focus-done',
        'payload': '{"taskId":"t1"}',
        'notificationResponseType': 1,
      },
    };
    final r = (await gateway.launchResponse())!;
    expect(r.payload, '{"taskId":"t1"}');
    expect(r.actionId, 'focus-done');
  });

  test('with the notifier: a reminder goes to the system and back', () async {
    final notifier = SystemNotifier(gateway: gateway, prefs: MemoryPrefs());
    final opened = <String>[];
    notifier.onOpen = (day, ref) => opened.add('${day.string} ${ref.id}');
    answers['pendingNotificationRequests'] = <Object?>[];
    final day = DayKey.today().adding(days: 1);
    await notifier.replaceAll([
      Reminder(
        id: 'ev-1',
        title: 'Standup',
        body: '09:00 – 10:00',
        fireAt: WallTime(day: day, minute: 9 * 60),
        day: day,
        ref: const ItemRef(ItemType.event, 'e1'),
      ),
    ]);
    final sent = args('zonedSchedule');
    expect(sent['id'], SystemNotifier.idFor('ev-1'));

    // Android tells the plugin about the click; the plugin tells Grove.
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(
            MethodCall('didReceiveNotificationResponse', {
              'notificationId': sent['id'],
              'payload': sent['payload'],
              'notificationResponseType': 0,
            }),
          ),
          (_) {},
        );
    expect(opened, ['${day.string} e1']);
  });
}
