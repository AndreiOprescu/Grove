// Port of Tests/GroveCoreTests/ReminderPlannerTests.swift.
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/event.dart';
import 'package:grove/core/model/link.dart';
import 'package:grove/core/model/task.dart';
import 'package:grove/core/services/reminder_planner.dart';

const day = DayKey('2026-10-05');

WallTime at(int minute, [DayKey? d]) => WallTime(day: d ?? day, minute: minute);

EventItem event(
  String id,
  String title, {
  required int from,
  required int to,
  DayKey? on,
  bool allDay = false,
  EventKind kind = EventKind.event,
  String? taskId,
}) => EventItem(
  id: id,
  title: title,
  start: at(from, on),
  end: at(to, on),
  allDay: allDay,
  kind: kind,
  taskId: taskId,
);

List<Reminder> plan(
  List<EventItem> events, {
  List<TaskItem> due = const [],
  Set<String> finished = const {},
  int now = 8 * 60,
  int lead = 5,
  int limit = ReminderPlanner.limit,
}) => ReminderPlanner.plan(
  events: events,
  dueTasks: due,
  finishedTaskIds: finished,
  now: at(now),
  lead: lead,
  limit: limit,
);

void main() {
  group('one event', () {
    test('an event reminds on the lead time before it starts', () {
      final r = plan([event('E1', 'Stand-up', from: 9 * 60 + 30, to: 10 * 60)]);
      expect(r.length, 1);
      expect(r[0].fireAt, at(9 * 60 + 25));
      expect(r[0].title, 'Stand-up');
      expect(r[0].body, '09:30 – 10:00');
      expect(r[0].day, day);
      expect(r[0].ref, const ItemRef(ItemType.event, 'E1'));
    });

    test('the id has the event and its start', () {
      final r = plan([event('E1', 'Stand-up', from: 570, to: 600)]);
      expect(r[0].id, 'ev-E1-2026-10-05T09:30');
    });

    test('lead time zero reminds at the start', () {
      final e = event('E1', 'x', from: 600, to: 660);
      expect(plan([e], lead: 0)[0].fireAt, at(600));
      expect(plan([e], lead: 15)[0].fireAt, at(585));
    });

    test('a reminder can fall on the day before', () {
      final early = event('E1', 'Flight', from: 3, to: 120);
      final r = ReminderPlanner.plan(
        events: [early],
        dueTasks: [],
        finishedTaskIds: {},
        now: at(20 * 60, const DayKey('2026-10-04')),
        lead: 10,
      );
      expect(r, isNotEmpty);
      expect(r[0].fireAt, at(24 * 60 - 7, const DayKey('2026-10-04')));
      // Clicking it still opens the day of the event.
      expect(r[0].day, day);
    });
  });

  group('what is left out', () {
    test('all-day events are left out', () {
      expect(
        plan([event('E1', 'Holiday', from: 0, to: 1440, allDay: true)]),
        isEmpty,
      );
    });

    test('a reminder that is already past is left out', () {
      // 08:00 now, event at 08:03, lead 5: the reminder time (07:58) has passed.
      expect(plan([event('E1', 'x', from: 8 * 60 + 3, to: 9 * 60)]), isEmpty);
      // Exactly now is past too. The system can only fire in the future.
      expect(plan([event('E1', 'x', from: 8 * 60 + 5, to: 9 * 60)]), isEmpty);
      expect(plan([event('E1', 'x', from: 8 * 60 + 6, to: 9 * 60)]).length, 1);
    });

    test('a block of a finished task is left out', () {
      final block = event(
        'B1',
        'Write report',
        from: 600,
        to: 660,
        kind: EventKind.block,
        taskId: 'T1',
      );
      expect(plan([block], finished: {'T1'}), isEmpty);
      expect(plan([block], finished: {'T2'}).length, 1);
    });

    test('a block opens its task', () {
      final r = plan([
        event(
          'B1',
          'Write report',
          from: 600,
          to: 660,
          kind: EventKind.block,
          taskId: 'T1',
        ),
      ]);
      expect(r[0].ref, const ItemRef(ItemType.task, 'T1'));
      expect(r[0].id, 'ev-B1-2026-10-05T10:00');
    });
  });

  group('due times', () {
    test('a task due at a time reminds', () {
      final t = TaskItem(
        id: 'T1',
        title: 'Send invoice',
        due: '2026-10-05T17:00',
      );
      final r = plan([], due: [t], lead: 10);
      expect(r.length, 1);
      expect(r[0].fireAt, at(16 * 60 + 50));
      expect(r[0].body, 'Due 17:00');
      expect(r[0].ref, const ItemRef(ItemType.task, 'T1'));
      expect(r[0].day, day);
      expect(r[0].id, 'due-T1-2026-10-05T17:00');
    });

    test('a due date with no time is left out', () {
      expect(
        plan(
          [],
          due: [TaskItem(id: 'T1', title: 'x', due: '2026-10-05')],
        ),
        isEmpty,
      );
    });

    test('a done or cancelled task does not remind', () {
      final done = TaskItem(
        id: 'T1',
        title: 'x',
        due: '2026-10-05T17:00',
        status: TaskStatus.done,
      );
      final gone = TaskItem(
        id: 'T2',
        title: 'y',
        due: '2026-10-05T18:00',
        status: TaskStatus.cancelled,
      );
      expect(plan([], due: [done, gone]), isEmpty);
    });
  });

  group('the list', () {
    test('the list is in time order and the earliest win the limit', () {
      final events = [
        for (var i = 0; i < 5; i++)
          event('E$i', 'e$i', from: 600 + (4 - i) * 60, to: 700 + (4 - i) * 60),
      ];
      final r = plan(events, limit: 3);
      expect(r.map((x) => x.title), ['e4', 'e3', 'e2']);
      final times = r.map((x) => x.fireAt).toList();
      expect(times, [...times]..sort());
    });

    test('the default limit is sixty because the system keeps sixty-four', () {
      expect(ReminderPlanner.limit, 60);
      final many = [
        for (var i = 0; i < 100; i++)
          event('E$i', 'e', from: 600, to: 660, on: day.adding(days: i + 1)),
      ];
      expect(plan(many).length, 60);
    });

    test('two things at the same time both remind', () {
      final r = plan([
        event('E1', 'a', from: 600, to: 660),
        event('E2', 'b', from: 600, to: 660),
      ]);
      expect(r.length, 2);
      expect(r.map((x) => x.id).toSet().length, 2);
    });

    test('a repeating event keeps one id per day', () {
      final a = event('S@2026-10-05', 'Daily', from: 600, to: 630);
      final b = event(
        'S@2026-10-06',
        'Daily',
        from: 600,
        to: 630,
        on: day.adding(days: 1),
      );
      expect(plan([a, b]).map((x) => x.id).toSet().length, 2);
    });

    test('the lead choices are the four in the plan', () {
      expect(ReminderPlanner.leadChoices, [0, 5, 10, 15]);
      expect(ReminderPlanner.defaultLead, 5);
    });
  });
}
