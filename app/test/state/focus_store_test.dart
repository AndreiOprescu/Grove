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
