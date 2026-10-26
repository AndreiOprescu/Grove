import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/services/login_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('grove/login-test');
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

  const item = MethodChannelLoginItem(channel: channel);

  test('status maps each name the Mac sends', () async {
    for (final status in LoginItemStatus.values) {
      answer((_) => status.name);
      expect(await item.status(), status);
    }
    answer((_) => 'later');
    expect(await item.status(), LoginItemStatus.unsupported);
  });

  test('set sends on and returns the new status', () async {
    answer((_) => 'enabled');
    expect(await item.set(true), LoginItemStatus.enabled);
    expect(calls.single.method, 'set');
    expect(calls.single.arguments, {'on': true});

    answer((_) => 'notRegistered');
    expect(await item.set(false), LoginItemStatus.notRegistered);
    expect(calls.single.arguments, {'on': false});
  });

  test('a refusal of the Mac reaches the caller from set', () async {
    answer((_) => throw PlatformException(code: 'login', message: 'no'));
    await expectLater(item.set(true), throwsA(isA<PlatformException>()));
    expect(await item.status(), LoginItemStatus.unsupported);
  });

  test('no native side: unsupported', () async {
    expect(await item.status(), LoginItemStatus.unsupported);
    expect(await item.set(true), LoginItemStatus.unsupported);
  });

  group('WindowControl', () {
    const window = MethodChannel('grove/window');

    test('show calls the native show', () async {
      final methods = <String>[];
      messenger.setMockMethodCallHandler(window, (call) async {
        methods.add(call.method);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(window, null));
      await WindowControl.show();
      expect(methods, ['show']);
    });

    test('show does nothing on an error or with no native side', () async {
      await WindowControl.show();
      messenger.setMockMethodCallHandler(
        window,
        (call) async => throw PlatformException(code: 'window'),
      );
      addTearDown(() => messenger.setMockMethodCallHandler(window, null));
      await WindowControl.show();
    });
  });
}
