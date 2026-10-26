import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/sleep/activity.dart';
import 'package:grove/services/device_activity_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('grove/activity-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  void answer(Object? Function(MethodCall call) reply) {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return reply(call);
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }

  MethodChannelActivitySource source() =>
      MethodChannelActivitySource(name: 'mac', channel: channel);

  final at = DateTime(2026, 10, 21, 23, 40);
  final ms = at.millisecondsSinceEpoch;

  test('access maps the three answers', () async {
    for (final (name, access) in [
      ('granted', ActivityAccess.granted),
      ('needsGrant', ActivityAccess.needsGrant),
      ('unsupported', ActivityAccess.unsupported),
      ('something new', ActivityAccess.unsupported),
    ]) {
      answer((_) => name);
      expect(await source().access(), access, reason: name);
    }
  });

  test('events sends the range in ms and decodes the flat list', () async {
    answer(
      (_) => Int64List.fromList([
        ms,
        1,
        ms + 60000,
        0,
        ms + 120000,
        2,
        ms + 180000,
        3,
      ]),
    );
    final to = at.add(const Duration(hours: 9));
    final events = await source().events(at, to);

    expect(calls.single.method, 'events');
    expect(calls.single.arguments, {
      'from': ms,
      'to': to.millisecondsSinceEpoch,
    });
    expect(events, [
      ActivityEvent(at, ActivitySignal.useEnd),
      ActivityEvent(
        at.add(const Duration(minutes: 1)),
        ActivitySignal.useStart,
      ),
      ActivityEvent(
        at.add(const Duration(minutes: 2)),
        ActivitySignal.recordStart,
      ),
      ActivityEvent(
        at.add(const Duration(minutes: 3)),
        ActivitySignal.recordStop,
      ),
    ]);
    expect(events.first.at.isUtc, isFalse);
  });

  test('a plain list of ints also decodes (the Mac sends one)', () async {
    answer((_) => <Object?>[ms, 0, ms + 1000, 1]);
    final events = await source().events(at, at.add(const Duration(days: 1)));
    expect(events.map((e) => e.signal), [
      ActivitySignal.useStart,
      ActivitySignal.useEnd,
    ]);
  });

  test('decode drops unknown codes and an odd tail, and sorts', () {
    final events = MethodChannelActivitySource.decode([
      ms + 5000,
      0,
      ms,
      9,
      ms,
      1,
      ms,
      3,
      ms + 9000,
    ]);
    expect(events, [
      ActivityEvent(at, ActivitySignal.useEnd),
      ActivityEvent(at, ActivitySignal.recordStop),
      ActivityEvent(
        at.add(const Duration(seconds: 5)),
        ActivitySignal.useStart,
      ),
    ]);
  });

  test('nextAlarm is a local time or null', () async {
    answer((_) => ms);
    expect(await source().nextAlarm(), at);
    answer((_) => null);
    expect(await source().nextAlarm(), isNull);
  });

  test('openAccessSettings calls the native side', () async {
    answer((_) => null);
    await source().openAccessSettings();
    expect(calls.single.method, 'openAccessSettings');
  });

  test('errors never throw', () async {
    answer((_) => throw PlatformException(code: 'activity'));
    final s = source();
    expect(await s.access(), ActivityAccess.unsupported);
    expect(await s.events(at, at), isEmpty);
    expect(await s.nextAlarm(), isNull);
    await s.openAccessSettings();
  });

  test('no native side: unsupported and empty', () async {
    final s = source();
    expect(await s.access(), ActivityAccess.unsupported);
    expect(await s.events(at, at), isEmpty);
    expect(await s.nextAlarm(), isNull);
    await s.openAccessSettings();
  });

  test('a wrong answer type never throws', () async {
    answer((_) => 'not a list');
    expect(await source().events(at, at), isEmpty);
  });

  test('changes fires on the native call "changed"', () async {
    final s = source();
    var heard = 0;
    final sub = s.changes.listen((_) => heard++);
    addTearDown(sub.cancel);

    Future<void> send(String method) async {
      final done = Completer<void>();
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
        (_) => done.complete(),
      );
      await done.future;
    }

    await send('changed');
    await send('changed');
    await send('somethingElse');
    expect(heard, 2);
  });

  test('the name is kept', () {
    expect(source().name, 'mac');
    expect(MethodChannelActivitySource(name: 'android').name, 'android');
  });
}
