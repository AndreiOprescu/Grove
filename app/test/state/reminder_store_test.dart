// Port of Tests/GroveTests/ReminderStoreTests.swift.
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// 2026-10-05 is a Monday. "Now" is Sunday evening before it.
const sunday = DayKey('2026-10-04');
const monday = DayKey('2026-10-05');

AppStore store({FakeNotifier? notifier, Prefs? prefs}) => makeStore(
  notifier: notifier ?? FakeNotifier(),
  prefs: prefs,
  clock: const WallTime(day: sunday, minute: 20 * 60),
);

EventItem addEvent(
  AppStore s, {
  String id = 'E1',
  String title = 'Standup',
  DayKey day = monday,
  int start = 540,
  int end = 600,
  String? taskId,
  RecurrenceRule? rule,
  bool allDay = false,
}) {
  final e = EventItem(
    id: id,
    title: title,
    start: WallTime(day: day, minute: start),
    end: WallTime(day: day, minute: end),
    color: 'accent3',
    recurrence: rule,
    allDay: allDay,
    taskId: taskId,
    kind: taskId == null ? EventKind.event : EventKind.block,
  );
  s.repos.events.save(e);
  return e;
}

List<String> reminderIds(List<Reminder> list) => [for (final r in list) r.id];

void main() {
  group('building the list', () {
    test('a coming event reminds five minutes early', () {
      final s = store();
      addEvent(s);
      final list = s.buildReminders();
      expect(list.length, 1);
      expect(list[0].id, 'ev-E1-2026-10-05T09:00');
      expect(list[0].title, 'Standup');
      expect(list[0].body, '09:00 – 10:00');
      expect(list[0].fireAt, const WallTime(day: monday, minute: 535));
    });

    test('the lead time comes from the setting', () {
      final s = store();
      addEvent(s);
      s.setNotifyLead(15);
      expect(
        s.buildReminders()[0].fireAt,
        const WallTime(day: monday, minute: 525),
      );
      s.setNotifyLead(0);
      expect(
        s.buildReminders()[0].fireAt,
        const WallTime(day: monday, minute: 540),
      );
    });

    test('a lead that is not on the list is ignored', () {
      final s = store();
      s.setNotifyLead(7);
      expect(s.notifyLead, 5);
      s.setNotifyLead(10);
      expect(s.notifyLead, 10);
      s.setNotifyLead(99);
      expect(s.notifyLead, 10);
    });

    test('a block of a finished task does not remind', () {
      final s = store();
      final t = TaskItem(id: 'T1', title: 'Write report');
      s.repos.tasks.save(t);
      addEvent(s, id: 'B1', title: 'Write report', taskId: 'T1');
      expect(s.buildReminders().length, 1);
      expect(s.buildReminders()[0].ref, const ItemRef(ItemType.task, 'T1'));
      s.repos.tasks.save(t.copyWith(status: TaskStatus.done));
      expect(s.buildReminders(), isEmpty);
    });

    test('a task due at a time reminds and a due day alone does not', () {
      final s = store();
      s.repos.tasks.save(
        TaskItem(id: 'T1', title: 'Send invoice', due: '2026-10-05T17:00'),
      );
      s.repos.tasks.save(
        TaskItem(id: 'T2', title: 'Pay rent', due: '2026-10-05'),
      );
      final list = s.buildReminders();
      expect(reminderIds(list), ['due-T1-2026-10-05T17:00']);
      expect(list[0].body, 'Due 17:00');
      expect(list[0].ref, const ItemRef(ItemType.task, 'T1'));
    });

    test('a repeating event reminds on each day of the window', () {
      final s = store();
      addEvent(s, rule: RecurrenceRule(freq: Freq.daily));
      final list = s.buildReminders();
      // The window is today and the 14 days after it: 4 Oct to 18 Oct. The
      // series starts on 5 Oct.
      expect(list.length, 14);
      expect(list.first.day, monday);
      expect(list.last.day, const DayKey('2026-10-18'));
      expect(reminderIds(list).toSet().length, list.length);
    });

    test('an event past the window is left out', () {
      final s = store();
      addEvent(s, day: const DayKey('2026-11-20'));
      expect(s.buildReminders(), isEmpty);
    });

    test('an event that already started is left out', () {
      final s = store();
      // 3 minutes into it.
      s.clockOverride = const WallTime(day: monday, minute: 9 * 60 + 3);
      addEvent(s);
      expect(s.buildReminders(), isEmpty);
    });
  });

  group('sending the list', () {
    test('refresh sends the list when allowed', () async {
      final fake = FakeNotifier();
      final s = store(notifier: fake);
      addEvent(s);
      await s.refreshReminders();
      expect(fake.sent.length, 1);
      expect(reminderIds(fake.sent[0]), ['ev-E1-2026-10-05T09:00']);
      expect(s.notifyStatus, NotifyAuthorization.allowed);
    });

    test('switched off sends an empty list so old ones go away', () async {
      final fake = FakeNotifier();
      final s = store(notifier: fake);
      addEvent(s);
      s.setNotifyEnabled(false);
      await s.refreshReminders();
      expect(fake.sent.last, isEmpty);
    });

    test('nothing is sent when the user said no or was never asked', () async {
      for (final status in [
        NotifyAuthorization.denied,
        NotifyAuthorization.notAsked,
      ]) {
        final fake = FakeNotifier(status: status);
        final s = store(notifier: fake);
        addEvent(s);
        await s.refreshReminders();
        expect(fake.sent, isEmpty);
        expect(s.notifyStatus, status);
      }
    });

    test('asking for permission schedules at once when granted', () async {
      final fake = FakeNotifier(status: NotifyAuthorization.notAsked);
      final s = store(notifier: fake);
      addEvent(s);
      await s.askForNotifications();
      expect(s.notifyStatus, NotifyAuthorization.allowed);
      expect(fake.sent.length, 1);
    });

    test('asking for permission and getting no sends nothing', () async {
      final fake = FakeNotifier(
        status: NotifyAuthorization.notAsked,
        answer: NotifyAuthorization.denied,
      );
      final s = store(notifier: fake);
      addEvent(s);
      await s.askForNotifications();
      expect(s.notifyStatus, NotifyAuthorization.denied);
      expect(fake.sent, isEmpty);
    });

    test('many changes in a row make one refresh', () async {
      final fake = FakeNotifier();
      final s = store(notifier: fake);
      s.reminderDelay = const Duration(milliseconds: 40);
      addEvent(s);
      for (var i = 0; i < 5; i++) {
        s.scheduleReminderRefresh();
      }
      expect(fake.sent, isEmpty); // not yet: it waits
      await wait(400);
      expect(fake.sent.length, 1);
    });

    test('a saved change makes the reminders again', () async {
      final fake = FakeNotifier();
      final s = store(notifier: fake);
      s.reminderDelay = const Duration(milliseconds: 20);
      final t = TaskItem(
        id: 'T1',
        title: 'Send invoice',
        due: '2026-10-05T17:00',
      );
      expect(
        s.commit(Mutation('Add task')..tasks.add((before: null, after: t))),
        isTrue,
      );
      await wait(400);
      expect(fake.sent.length, 1);
      expect(reminderIds(fake.sent[0]), ['due-T1-2026-10-05T17:00']);
    });
  });

  test('the switch and the lead are saved', () {
    final prefs = MemoryPrefs();
    final a = store(prefs: prefs);
    expect(a.notifyEnabled, isTrue);
    expect(a.notifyLead, 5);
    a.setNotifyEnabled(false);
    a.setNotifyLead(15);
    final b = store(prefs: prefs);
    expect(b.notifyEnabled, isFalse);
    expect(b.notifyLead, 15);
  });

  group('a click on a notification', () {
    test('a click on a block reminder opens its task on its day', () {
      final fake = FakeNotifier();
      final s = store(notifier: fake);
      s.repos.tasks.save(
        TaskItem(id: 'T1', title: 'Write report', planDate: monday),
      );
      s.screen = Screen.notes;
      expect(fake.onOpen, isNotNull);
      fake.onOpen?.call(monday, const ItemRef(ItemType.task, 'T1'));
      expect(s.screen, Screen.planner); // that Monday is not today
      expect(s.selectedDay, monday);
      expect(s.selectedTaskId, 'T1');
    });

    test('a click on an event reminder opens its day even when the event is '
        'gone', () {
      final fake = FakeNotifier();
      final s = store(notifier: fake);
      s.screen = Screen.notes;
      fake.onOpen?.call(monday, const ItemRef(ItemType.event, 'gone'));
      expect(s.screen, Screen.planner); // that Monday is not today
      expect(s.selectedDay, monday);
    });
  });

  group('the words in the Notifications tab of Settings', () {
    test('lead choices read in plain words', () {
      expect(
        [
          for (final m in ReminderPlanner.leadChoices)
            SettingsRules.leadText(m),
        ],
        [
          'When it starts',
          '5 minutes before',
          '10 minutes before',
          '15 minutes before',
        ],
      );
      expect(SettingsRules.leadText(1), '1 minute before');
    });

    test('each status has a quiet note', () {
      expect(
        SettingsRules.notifyStatusText(NotifyAuthorization.allowed),
        'Notifications are allowed for Grove.',
      );
      expect(
        SettingsRules.notifyStatusText(NotifyAuthorization.notAsked),
        'Grove has not asked for permission yet.',
      );
      expect(
        SettingsRules.notifyStatusText(NotifyAuthorization.denied),
        contains('System Settings'),
      );
    });
  });
}
