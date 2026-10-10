import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final _now = DateTime(2026, 10, 10, 9, 0);
final _today = DayKey.ymd(2026, 10, 10);

Reminder _reminder(
  String id, {
  String title = 'Standup',
  String body = 'In 10 min',
  int minute = 10 * 60,
  DayKey? day,
  ItemRef ref = const ItemRef(ItemType.event, 'e1'),
}) => Reminder(
  id: id,
  title: title,
  body: body,
  fireAt: WallTime(day: day ?? _today, minute: minute),
  day: day ?? _today,
  ref: ref,
);

void main() {
  late FakeGateway gateway;
  late MemoryPrefs prefs;
  late SystemNotifier notifier;
  late List<String> opened;
  late List<String> done;

  setUp(() {
    gateway = FakeGateway();
    prefs = MemoryPrefs();
    notifier = SystemNotifier(gateway: gateway, prefs: prefs, now: () => _now);
    opened = [];
    done = [];
    notifier.onOpen = (day, ref) =>
        opened.add('${day.string} ${ref.type.name} ${ref.id}');
    notifier.onFocusDone = done.add;
  });

  group('permission', () {
    test('allowed when the system says yes', () async {
      expect(await notifier.authorization(), NotifyAuthorization.allowed);
    });

    test('not asked when the system says no and Grove never asked', () async {
      gateway.allowed = false;
      expect(await notifier.authorization(), NotifyAuthorization.notAsked);
    });

    test('denied after the user said no', () async {
      gateway
        ..allowed = false
        ..answer = false;
      expect(await notifier.requestAuthorization(), NotifyAuthorization.denied);
      expect(await notifier.authorization(), NotifyAuthorization.denied);
      expect(prefs.getBool(SystemNotifier.askedKey), isTrue);
    });

    test('allowed after the user said yes', () async {
      gateway.allowed = false;
      expect(
        await notifier.requestAuthorization(),
        NotifyAuthorization.allowed,
      );
      expect(await notifier.authorization(), NotifyAuthorization.allowed);
    });

    test(
      'allowed again when the user turned it on in the system settings',
      () async {
        gateway
          ..allowed = false
          ..answer = false;
        await notifier.requestAuthorization();
        gateway.allowed = true;
        expect(await notifier.authorization(), NotifyAuthorization.allowed);
      },
    );

    test('the answer is remembered by the next launch', () async {
      gateway
        ..allowed = false
        ..answer = false;
      await notifier.requestAuthorization();
      final next = SystemNotifier(
        gateway: FakeGateway(allowed: false),
        prefs: prefs,
      );
      expect(await next.authorization(), NotifyAuthorization.denied);
    });

    test('a system that fails counts as "no", and nothing is thrown', () async {
      gateway.broken.addAll({'permitted', 'requestPermission'});
      expect(await notifier.authorization(), NotifyAuthorization.notAsked);
      expect(
        await notifier.requestAuthorization(),
        NotifyAuthorization.notAsked,
      );
      expect(prefs.getBool(SystemNotifier.askedKey), isNull);
    });

    test('the system centre is started one time only', () async {
      await notifier.authorization();
      await notifier.replaceAll([_reminder('ev-1')]);
      await notifier.cancelFocusEnd();
      expect(gateway.starts, 1);
    });
  });

  group('replaceAll', () {
    test('asks for each reminder at its local time', () async {
      await notifier.replaceAll([
        _reminder('ev-1', minute: 10 * 60 + 5),
        _reminder(
          'due-2',
          title: 'Pay rent',
          body: 'Due now',
          day: _today.adding(days: 2),
          minute: 18 * 60,
          ref: const ItemRef(ItemType.task, 't2'),
        ),
      ]);
      final all = gateway.scheduled.values.toList()
        ..sort((a, b) => a.at.compareTo(b.at));
      expect(all.map((r) => r.at), [
        DateTime(2026, 10, 10, 10, 5),
        DateTime(2026, 10, 12, 18, 0),
      ]);
      expect(all.map((r) => '${r.title} | ${r.body}'), [
        'Standup | In 10 min',
        'Pay rent | Due now',
      ]);
      expect(all.every((r) => r.donePayload == null), isTrue);
      expect(jsonDecode(all[1].payload), {
        'day': '2026-10-12',
        'kind': 'task',
        'id': 't2',
        'at': '2026-10-12T18:00',
      });
    });

    test(
      'the id of a reminder is the same in each run, and in range',
      () async {
        expect(SystemNotifier.idFor('ev-abc-2026-10-10 10:00'), 1617524313);
        for (final text in ['', 'a', 'ev-1', 'due-${'x' * 500}', 'ev-ö-日本']) {
          final id = SystemNotifier.idFor(text);
          expect(id, greaterThanOrEqualTo(SystemNotifier.firstReminderId));
          expect(id, lessThanOrEqualTo(0x7fffffff));
          expect(SystemNotifier.idFor(text), id);
        }
      },
    );

    test(
      'a reminder at a time that is not in the future is left out',
      () async {
        await notifier.replaceAll([
          _reminder('ev-past', minute: 8 * 60),
          _reminder('ev-now', minute: 9 * 60),
          _reminder('ev-soon', minute: 9 * 60 + 1),
        ]);
        expect(gateway.scheduled.keys, [SystemNotifier.idFor('ev-soon')]);
      },
    );

    test('the same list again makes no call', () async {
      final list = [_reminder('ev-1'), _reminder('ev-2', minute: 11 * 60)];
      await notifier.replaceAll(list);
      gateway.takeCalls();
      await notifier.replaceAll(list);
      expect(gateway.takeCalls(), isEmpty);
    });

    test('a reminder that left the list is cancelled', () async {
      await notifier.replaceAll([
        _reminder('ev-1'),
        _reminder('ev-2', minute: 11 * 60),
      ]);
      gateway.takeCalls();
      await notifier.replaceAll([_reminder('ev-2', minute: 11 * 60)]);
      expect(gateway.takeCalls(), ['cancel ${SystemNotifier.idFor('ev-1')}']);
      expect(gateway.scheduled.keys, [SystemNotifier.idFor('ev-2')]);
    });

    test('a changed reminder is asked for again', () async {
      await notifier.replaceAll([_reminder('ev-1')]);
      gateway.takeCalls();
      final id = SystemNotifier.idFor('ev-1');

      await notifier.replaceAll([_reminder('ev-1', title: 'Daily standup')]);
      expect(gateway.takeCalls(), ['cancel $id', 'schedule $id']);
      expect(gateway.scheduled[id]!.title, 'Daily standup');

      await notifier.replaceAll([
        _reminder('ev-1', title: 'Daily standup', minute: 10 * 60 + 30),
      ]);
      expect(gateway.takeCalls(), ['cancel $id', 'schedule $id']);
      expect(gateway.scheduled[id]!.at, DateTime(2026, 10, 10, 10, 30));
    });

    test('an empty list cancels all reminders', () async {
      await notifier.replaceAll([
        _reminder('ev-1'),
        _reminder('ev-2', minute: 11 * 60),
      ]);
      await notifier.replaceAll(const []);
      expect(gateway.scheduled, isEmpty);
    });

    test('the focus notification is not a reminder: it stays', () async {
      await notifier.scheduleFocusEnd(
        FocusEnd(
          title: 'Write report',
          at: _now.add(const Duration(minutes: 25)),
          day: _today,
          ref: const ItemRef(ItemType.event, 'b1'),
        ),
      );
      await notifier.replaceAll([_reminder('ev-1')]);
      await notifier.replaceAll(const []);
      expect(gateway.scheduled.keys, [SystemNotifier.focusId]);
    });

    test(
      'a system that lists only ids gets each reminder again, with no double',
      () async {
        gateway.listsText = false;
        final list = [_reminder('ev-1')];
        await notifier.replaceAll(list);
        gateway.takeCalls();
        await notifier.replaceAll(list);
        final id = SystemNotifier.idFor('ev-1');
        expect(gateway.takeCalls(), ['cancel $id', 'schedule $id']);
      },
    );

    test('two reminders with the same number both get a place', () async {
      final clash = SystemNotifier(
        gateway: gateway,
        prefs: prefs,
        now: () => _now,
        idOf: (_) => 0x7fffffff,
      );
      await clash.replaceAll([
        _reminder('ev-1'),
        _reminder('ev-2', minute: 11 * 60),
      ]);
      expect(gateway.scheduled.keys.toSet(), {
        0x7fffffff,
        SystemNotifier.firstReminderId,
      });
    });

    test('a call that fails does not stop the others', () async {
      final one = SystemNotifier.idFor('ev-1');
      final two = SystemNotifier.idFor('ev-2');

      // The list of pending ones fails: the reminder is still asked for.
      gateway.broken.add('pending');
      await notifier.replaceAll([_reminder('ev-1')]);
      expect(gateway.scheduled.keys, [one]);

      // A cancel fails: the new reminder is still asked for.
      gateway.broken
        ..clear()
        ..add('cancel');
      await notifier.replaceAll([_reminder('ev-2', minute: 11 * 60)]);
      expect(gateway.scheduled.keys.toSet(), {one, two});

      // A schedule fails: nothing is thrown, and the old one is still cancelled.
      gateway.broken
        ..clear()
        ..add('schedule');
      await notifier.replaceAll([_reminder('ev-3', minute: 12 * 60)]);
      expect(gateway.scheduled, isEmpty);
    });

    test('a system centre that does not start: nothing is thrown', () async {
      gateway.broken.addAll({'start', 'pending', 'schedule', 'cancel'});
      await notifier.replaceAll([_reminder('ev-1')]);
      await notifier.cancelFocusEnd();
      expect(gateway.scheduled, isEmpty);
    });
  });

  group('focus end', () {
    FocusEnd end({String? taskId, DateTime? at}) => FocusEnd(
      title: 'Write report',
      at: at ?? _now.add(const Duration(minutes: 25)),
      day: _today,
      ref: taskId != null
          ? ItemRef(ItemType.task, taskId)
          : const ItemRef(ItemType.event, 'b1'),
      taskId: taskId,
    );

    test('a block with no task: no "Mark done" button', () async {
      await notifier.scheduleFocusEnd(end());
      final r = gateway.scheduled[SystemNotifier.focusId]!;
      expect(r.title, 'Focus time is up');
      expect(r.body, 'Write report is over.');
      expect(r.at, DateTime(2026, 10, 10, 9, 25));
      expect(r.donePayload, isNull);
      expect(jsonDecode(r.payload), {
        'day': '2026-10-10',
        'kind': 'event',
        'id': 'b1',
      });
    });

    test('a block of a task: the text asks, and the button is there', () async {
      await notifier.scheduleFocusEnd(end(taskId: 't1'));
      final r = gateway.scheduled[SystemNotifier.focusId]!;
      expect(r.body, 'Write report. Mark it done?');
      expect(jsonDecode(r.payload), {
        'day': '2026-10-10',
        'kind': 'task',
        'id': 't1',
        'taskId': 't1',
      });
      expect(jsonDecode(r.donePayload!), {
        'day': '2026-10-10',
        'kind': 'task',
        'id': 't1',
        'taskId': 't1',
        'action': 'focus-done',
      });
    });

    test('a time that passed fires one second from now', () async {
      await notifier.scheduleFocusEnd(
        end(at: _now.subtract(const Duration(minutes: 1))),
      );
      expect(
        gateway.scheduled[SystemNotifier.focusId]!.at,
        _now.add(const Duration(seconds: 1)),
      );
    });

    test('a new one replaces the one before', () async {
      await notifier.scheduleFocusEnd(end());
      gateway.takeCalls();
      await notifier.scheduleFocusEnd(end(taskId: 't1'));
      expect(gateway.takeCalls(), ['cancel 1', 'schedule 1']);
      expect(gateway.scheduled.length, 1);
    });

    test('cancel takes it away and leaves the reminders', () async {
      await notifier.replaceAll([_reminder('ev-1')]);
      await notifier.scheduleFocusEnd(end());
      await notifier.cancelFocusEnd();
      expect(gateway.scheduled.keys, [SystemNotifier.idFor('ev-1')]);
    });
  });

  group('a click', () {
    Future<NoteRequest> scheduledReminder() async {
      await notifier.replaceAll([
        _reminder('ev-1', ref: const ItemRef(ItemType.note, 'n7')),
      ]);
      return gateway.scheduled.values.single;
    }

    Future<NoteRequest> scheduledFocus() async {
      await notifier.scheduleFocusEnd(
        FocusEnd(
          title: 'Write report',
          at: _now.add(const Duration(minutes: 25)),
          day: _today,
          ref: const ItemRef(ItemType.task, 't1'),
          taskId: 't1',
        ),
      );
      return gateway.scheduled[SystemNotifier.focusId]!;
    }

    test('on a reminder opens the item on its day', () async {
      gateway.click(payload: (await scheduledReminder()).payload);
      expect(opened, ['2026-10-10 note n7']);
      expect(done, isEmpty);
    });

    test('on the focus notification opens the task', () async {
      gateway.click(payload: (await scheduledFocus()).payload);
      expect(opened, ['2026-10-10 task t1']);
      expect(done, isEmpty);
    });

    test('on "Mark done" finishes the task and opens nothing', () async {
      gateway.click(
        payload: (await scheduledFocus()).payload,
        actionId: SystemNotifier.doneAction,
      );
      expect(done, ['t1']);
      expect(opened, isEmpty);
    });

    test(
      'on "Mark done" on a system that gives only the button text (Windows)',
      () async {
        final r = await scheduledFocus();
        gateway.click(payload: r.donePayload, actionId: r.donePayload);
        expect(done, ['t1']);
        expect(opened, isEmpty);
      },
    );

    test('on the text, where the action id is the payload (Windows)', () async {
      final r = await scheduledFocus();
      gateway.click(payload: r.payload, actionId: r.payload);
      expect(opened, ['2026-10-10 task t1']);
      expect(done, isEmpty);
    });

    test('with a payload Grove cannot read does nothing', () async {
      await notifier.authorization();
      for (final payload in [
        null,
        '',
        'hello',
        '[1,2]',
        '{"day":"2026-10-10"}',
        '{"day":"not a day","kind":"task","id":"t1"}',
        '{"day":"2026-10-10","kind":"plant","id":"t1"}',
        '{"day":"2026-10-10","kind":"task","id":7}',
        '{"action":"focus-done"}',
      ]) {
        gateway.click(payload: payload);
      }
      gateway.click(
        payload: '{"taskId":7}',
        actionId: SystemNotifier.doneAction,
      );
      expect(opened, isEmpty);
      expect(done, isEmpty);
    });

    test('that started the app is given one time', () async {
      gateway.launch = NoteResponse(
        payload: (await scheduledReminder()).payload,
      );
      await notifier.deliverLaunch();
      await notifier.deliverLaunch();
      expect(opened, ['2026-10-10 note n7']);
    });

    test(
      'that started the app and also came as a click counts one time',
      () async {
        final payload = (await scheduledFocus()).donePayload;
        gateway.click(payload: payload, actionId: payload);
        gateway.launch = NoteResponse(payload: payload, actionId: payload);
        await notifier.deliverLaunch();
        expect(done, ['t1']);
      },
    );

    test('no launch click, or a system that fails: nothing happens', () async {
      await notifier.deliverLaunch();
      final other = SystemNotifier(
        gateway: FakeGateway()..broken.add('launchResponse'),
        prefs: prefs,
      );
      await other.deliverLaunch();
      expect(opened, isEmpty);
    });
  });

  group('with the store', () {
    test('the store sends its reminders and opens a clicked one', () async {
      final tomorrow = _today.adding(days: 1);
      final store = makeStore(
        notifier: notifier,
        prefs: prefs,
        clock: WallTime(day: _today, minute: 9 * 60),
      );
      store.repos.events.save(
        EventItem(
          id: 'E1',
          title: 'Dentist',
          start: WallTime(day: tomorrow, minute: 15 * 60),
          end: WallTime(day: tomorrow, minute: 16 * 60),
          color: 'accent3',
        ),
      );
      await store.refreshReminders();

      final r = gateway.scheduled.values.single;
      expect(r.title, 'Dentist');
      expect(r.at, DateTime(2026, 10, 11, 14, 55));

      store.screen = Screen.notes;
      gateway.click(payload: r.payload);
      expect(store.selectedDay, tomorrow);
      expect(store.screen, isNot(Screen.notes));
    });

    test('the store marks the task done from the button', () async {
      final store = makeStore(notifier: notifier, prefs: prefs);
      final task = store.quickAdd('Write report')!;
      await notifier.deliverLaunch();
      gateway.click(
        payload:
            '{"day":"2026-10-10","kind":"task","id":"${task.id}","taskId":"${task.id}"}',
        actionId: SystemNotifier.doneAction,
      );
      expect(store.repos.tasks.get(task.id)!.status, TaskStatus.done);
    });
  });
}
