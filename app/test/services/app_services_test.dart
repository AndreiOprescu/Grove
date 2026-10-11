import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/helpers.dart' show tempDir;
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the window channel', () {
    const channel = MethodChannel('grove/window');
    late List<String> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'broken') throw PlatformException(code: 'x');
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
    });

    test('show asks the native window to come to the front', () async {
      await const AppWindow().show();
      expect(calls, ['show']);
    });

    test('a system with no native side: nothing is thrown', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await const AppWindow().show();
      await const AppWindow(method: 'broken').show();
    });
  });

  group('the notifier of this device', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('the four systems of Grove get the real one', () {
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(AppServices.notifier(MemoryPrefs()), isA<SystemNotifier>());
      }
    });

    test('another system gets the one that does nothing', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(AppServices.notifier(MemoryPrefs()), isA<NullNotifier>());
    });
  });

  group('start', () {
    late FakeGateway gateway;
    late FakeTray tray;
    late AppStore store;
    AppServices? running;
    var closed = false;

    AppServices services({bool withTray = true}) => running = AppServices(
      store: store,
      tray: withTray ? tray : null,
      showWindow: () {},
      quit: () {},
    );

    /// A widget test must end with no timer that waits. So each test closes
    /// the services and the store itself.
    void close() {
      if (closed) return;
      closed = true;
      running?.dispose();
      store.dispose();
      store.repos.db.close();
    }

    /// The user goes to another app and comes back. The system tells each
    /// step on the way.
    void awayAndBack(WidgetTester tester) {
      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
    }

    setUp(() {
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      gateway = FakeGateway();
      tray = FakeTray();
      running = null;
      closed = false;
      store = AppStore.open(
        dataDir: tempDir('grove-services').path,
        notifier: SystemNotifier(gateway: gateway, prefs: MemoryPrefs()),
        prefs: MemoryPrefs(),
      );
      addTearDown(close);
    });

    testWidgets('sends the reminders, shows the tray, gives the launch click', (
      tester,
    ) async {
      final day = DayKey.today().adding(days: 1);
      store.repos.events.save(
        EventItem(
          id: 'E1',
          title: 'Dentist',
          start: WallTime(day: day, minute: 15 * 60),
          end: WallTime(day: day, minute: 16 * 60),
          color: 'accent3',
        ),
      );
      gateway.launch = NoteResponse(
        payload: '{"day":"${day.string}","kind":"event","id":"E1"}',
      );

      services().start();
      await tester.pump();

      expect(gateway.scheduled.values.map((r) => r.title), contains('Dentist'));
      expect(tray.visible, isTrue);
      expect(running!.trayShown, isTrue);
      expect(store.selectedDay, day);
      expect(store.notifyStatus, NotifyAuthorization.allowed);
      close();
    });

    testWidgets('a phone has no tray', (tester) async {
      services(withTray: false).start();
      await tester.pump();
      expect(tray.visible, isFalse);
      expect(running!.trayShown, isFalse);
      close();
    });

    testWidgets('when the app comes back: backup check and new reminders', (
      tester,
    ) async {
      services().start();
      await tester.pump();
      File(store.backupFiles().single.path).deleteSync();
      gateway.scheduled.clear();
      store.quickAdd('Call mum tomorrow 6pm for 20m');
      gateway.takeCalls();

      awayAndBack(tester);
      await tester.pump(store.reminderDelay + const Duration(seconds: 1));

      expect(store.backupFiles().length, 1);
      expect(
        gateway.scheduled.values.map((r) => r.title),
        contains('Call mum'),
      );
      close();
    });

    testWidgets('after dispose nothing runs', (tester) async {
      final s = services()..start();
      await tester.pump();
      s.dispose();
      expect(tray.visible, isFalse);
      File(store.backupFiles().single.path).deleteSync();
      awayAndBack(tester);
      await tester.pump(const Duration(hours: 2));
      expect(store.backupFiles(), isEmpty);
      close();
    });
  });
}
