// Port of Tests/GroveTests/FocusStoreTests.swift.
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const future = DayKey('2099-03-04');
const past = DayKey('2020-03-04');

AppStore store([FakeNotifier? fake]) =>
    makeStore(notifier: fake ?? FakeNotifier());

EventItem addBlock(AppStore s, {required DayKey day, String? taskId = 'T1'}) {
  if (taskId != null) {
    s.repos.tasks.save(
      TaskItem(
        id: taskId,
        title: 'Write report',
        bucket: TaskBucket.day,
        planDate: day,
      ),
    );
  }
  final b = EventItem(
    title: 'Write report',
    start: WallTime(day: day, minute: 600),
    end: WallTime(day: day, minute: 660),
    kind: taskId == null ? EventKind.event : EventKind.block,
    taskId: taskId,
  );
  s.repos.events.save(b);
  return b;
}

void main() {
  test('starting focus counts down to the end of the block', () {
    final s = store();
    final b = addBlock(s, day: future);
    s.startFocus(b);
    final f = s.focus!;
    expect(f.blockId, b.id);
    expect(f.taskId, 'T1');
    expect(f.title, 'Write report');
    expect(f.end, FocusRules.endDate(b.end));
    expect(f.finished, isFalse);
  });

  test('starting focus sends the end notification', () async {
    final fake = FakeNotifier();
    final s = store(fake);
    final b = addBlock(s, day: future);
    s.startFocus(b);
    await s.focusNotify;
    final sent = fake.focusEnds.last;
    expect(sent.title, 'Write report');
    expect(sent.at, FocusRules.endDate(b.end));
    expect(sent.taskId, 'T1');
  });

  test('the notifications switch covers the end notification', () async {
    final fake = FakeNotifier();
    final s = store(fake);
    s.setNotifyEnabled(false);
    s.startFocus(addBlock(s, day: future));
    await s.focusNotify;
    expect(s.focus, isNotNull); // the timer still runs
    expect(fake.focusEnds, isEmpty); // but the system hears nothing
  });

  test('a block that is over cannot be focused', () {
    final s = store();
    final b = addBlock(s, day: past);
    s.startFocus(b);
    expect(s.focus, isNull);
    expect(s.toast, isNotNull);
  });

  group('the clock of the store', () {
    AppStore at(DayKey day, int minute) => makeStore(
      notifier: FakeNotifier(),
      clock: WallTime(day: day, minute: minute),
    );

    test('the session starts at the time of the clock of the store', () {
      // The real clock says that this block is over. The clock of the store
      // says that it runs.
      final s = at(past, 620);
      final b = addBlock(s, day: past);
      s.startFocus(b);
      final f = s.focus;
      expect(f, isNotNull);
      expect(s.toast, isNull);
      expect(f!.start, DateTime(2020, 3, 4, 10, 20));
      expect(f.end, DateTime(2020, 3, 4, 11));
    });

    test('a block that is over by the clock of the store cannot be '
        'focused', () {
      // The real clock says that this block is far away.
      final s = at(future, 661);
      s.startFocus(addBlock(s, day: future));
      expect(s.focus, isNull);
      expect(s.toast, 'This block is over.');
    });

    test('a block can be focused until its last minute, and not at its '
        'end', () {
      final s = at(future, 659);
      final b = addBlock(s, day: future);
      s.startFocus(b);
      expect(s.focus?.start, DateTime(2099, 3, 4, 10, 59));
      s.stopFocus();

      s.clockOverride = const WallTime(day: future, minute: 660);
      s.startFocus(b);
      expect(s.focus, isNull);
    });

    test('a block of tomorrow can be focused, a block of yesterday '
        'cannot', () {
      final s = at(future, 620);
      final next = addBlock(s, day: future.adding(days: 1));
      final before = addBlock(s, day: future.adding(days: -1), taskId: 'T2');
      s.startFocus(next);
      expect(s.focus?.blockId, next.id);
      expect(s.focus?.start, DateTime(2099, 3, 4, 10, 20));
      s.stopFocus();
      s.startFocus(before);
      expect(s.focus, isNull);
    });

    test('the test moves the clock and the session is that much further', () {
      final s = at(past, 600);
      s.startFocus(addBlock(s, day: past));
      final f = s.focus!;
      double done() =>
          FocusRules.progress(start: f.start, end: f.end, now: s.clockNow());
      int left() => FocusRules.remaining(until: f.end, now: s.clockNow());

      expect(done(), 0);
      expect(left(), 3600);
      s.clockOverride = const WallTime(day: past, minute: 630);
      expect(done(), 0.5);
      expect(left(), 1800);
      s.clockOverride = const WallTime(day: past, minute: 660);
      expect(done(), 1);
      expect(left(), 0);
    });

    test('with no fixed clock, "now" is the real clock', () {
      final s = store();
      expect(s.clockOverride, isNull);
      final before = DateTime.now();
      final now = s.clockNow();
      final after = DateTime.now();
      expect(now.isBefore(before), isFalse);
      expect(now.isAfter(after), isFalse);
      // A session starts at the real "now" then, as before.
      s.startFocus(addBlock(s, day: future));
      expect(s.focus!.start.isBefore(before), isFalse);
      expect(s.focus!.start.isAfter(DateTime.now()), isFalse);
    });

    test('a fixed clock gives its day and its minute', () {
      final s = at(const DayKey('2026-10-07'), 14 * 60 + 5);
      expect(s.clockNow(), DateTime(2026, 10, 7, 14, 5));
    });
  });

  test('stopping ends the session and cancels the notification', () async {
    final fake = FakeNotifier();
    final s = store(fake);
    s.startFocus(addBlock(s, day: future));
    await s.focusNotify;
    s.stopFocus();
    await s.focusNotify;
    expect(s.focus, isNull);
    expect(fake.focusCancels, greaterThanOrEqualTo(1));
  });

  test('a second session replaces the first', () {
    final s = store();
    final a = addBlock(s, day: future);
    final b = addBlock(s, day: future.adding(days: 1), taskId: 'T2');
    s.startFocus(a);
    s.startFocus(b);
    expect(s.focus?.blockId, b.id);
  });

  test('when the time is up the session asks to mark done', () {
    final s = store();
    s.startFocus(addBlock(s, day: future));
    s.focusTimeUp();
    expect(s.focus?.finished, isTrue);
  });

  test('mark done checks the task off and closes the session', () {
    final s = store();
    s.startFocus(addBlock(s, day: future));
    s.focusTimeUp();
    s.markFocusDone();
    expect(s.focus, isNull);
    expect(s.task('T1')?.status, TaskStatus.done);
  });

  test('"Not yet" closes the session and leaves the task open', () {
    final s = store();
    s.startFocus(addBlock(s, day: future));
    s.focusTimeUp();
    s.stopFocus();
    expect(s.focus, isNull);
    expect(s.task('T1')?.status, TaskStatus.open);
  });

  test('mark done on an event with no task just closes', () {
    final s = store();
    s.startFocus(addBlock(s, day: future, taskId: null));
    s.markFocusDone();
    expect(s.focus, isNull);
  });

  test('the notification button marks the task done', () {
    final fake = FakeNotifier();
    final s = store(fake);
    s.startFocus(addBlock(s, day: future));
    fake.onFocusDone?.call('T1');
    expect(s.task('T1')?.status, TaskStatus.done);
    expect(s.focus, isNull);
  });

  test('importing data closes the session', () {
    final s = store();
    s.startFocus(addBlock(s, day: future));
    s.resetAfterReplace();
    expect(s.focus, isNull);
  });
}
