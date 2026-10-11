import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  group('The timers of the tests', () {
    test('a timer runs when its time has passed, not before', () {
      final timers = ManualTimers();
      var runs = 0;
      final timer = timers.start(const Duration(seconds: 3), () => runs += 1);
      expect(timer.isActive, isTrue);
      expect(timers.waiting, 1);

      timers.pass(const Duration(milliseconds: 2999));
      expect(runs, 0);
      timers.pass(const Duration(milliseconds: 1));
      expect(runs, 1);
      expect(timer.isActive, isFalse);
      expect(timers.waiting, 0);

      timers.pass(const Duration(hours: 1));
      expect(runs, 1);
    });

    test('a timer that was stopped never runs', () {
      final timers = ManualTimers();
      var runs = 0;
      timers.start(const Duration(seconds: 1), () => runs += 1).cancel();
      expect(timers.waiting, 0);
      timers.pass(const Duration(seconds: 5));
      expect(runs, 0);
    });

    test('timers run in the order of their times', () {
      final timers = ManualTimers();
      final order = <String>[];
      timers
        ..start(const Duration(seconds: 2), () => order.add('late'))
        ..start(const Duration(seconds: 1), () => order.add('early'))
        ..start(const Duration(seconds: 2), () => order.add('late too'));
      timers.pass(const Duration(seconds: 2));
      expect(order, ['early', 'late', 'late too']);
    });

    test('a timer that a timer starts runs in the same step, '
        'when its time is in the step', () {
      final timers = ManualTimers();
      final order = <String>[];
      timers.start(const Duration(seconds: 1), () {
        order.add('first');
        timers
          ..start(const Duration(seconds: 1), () => order.add('second'))
          ..start(const Duration(seconds: 5), () => order.add('third'));
      });
      timers.pass(const Duration(seconds: 2));
      expect(order, ['first', 'second']);
      expect(timers.waiting, 1);
    });

    test('the store takes its waits from them', () async {
      final timers = ManualTimers();
      final notifier = FakeNotifier();
      final store = makeStore(notifier: notifier)..newTimer = timers.start;
      store.scheduleReminderRefresh();
      expect(timers.waiting, 1);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.sent, isEmpty);

      timers.pass(store.reminderDelay);
      await store.reminderTask;
      expect(notifier.sent, hasLength(1));
      expect(timers.waiting, 0);
    });

    test('a closed store stops its waits', () {
      final timers = ManualTimers();
      // Not `makeStore`: that one closes the store again after the test.
      final store = AppStore(
        repos: Repos(Database.inMemory()),
        notifier: FakeNotifier(),
      )..newTimer = timers.start;
      store.scheduleReminderRefresh();
      expect(timers.waiting, 1);
      store.dispose();
      expect(timers.waiting, 0);
    });
  });
}
