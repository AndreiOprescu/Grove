// Port of Tests/GroveTests/DayRulesTests.swift.
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

const monday = DayKey('2026-09-28');
const tuesday = DayKey('2026-09-29');

WallTime at(DayKey day, int minute) => WallTime(day: day, minute: minute);

TaskItem task(String title, {String? id, bool done = false, DayKey? plan}) =>
    TaskItem(
      id: id ?? title,
      title: title,
      status: done ? TaskStatus.done : TaskStatus.open,
      bucket: plan == null ? TaskBucket.week : TaskBucket.day,
      planDate: plan,
    );

EventItem event(
  String title,
  WallTime start,
  WallTime end, {
  bool allDay = false,
}) =>
    EventItem(id: title, title: title, start: start, end: end, allDay: allDay);

EventItem blockOf(TaskItem t, WallTime start, WallTime end) => EventItem(
  id: 'block-${t.id}',
  title: t.title,
  start: start,
  end: end,
  kind: EventKind.block,
  taskId: t.id,
);

TaskItem? Function(String) lookup(List<TaskItem> tasks) => (id) {
  for (final t in tasks) {
    if (t.id == id) return t;
  }
  return null;
};

TaskItem? nobody(String _) => null;

String finishedLine(WeekReview r) =>
    DayRules.summary(r)
        .split('\n')
        .firstWhere((l) => l.startsWith('- Finished:'), orElse: () => '');

void main() {
  group('the day panel', () {
    test('a day shows all-day first, then timed, then loose tasks', () {
      final loneOpen = task('Open one', plan: tuesday);
      final loneDone = task('Done one', done: true, plan: tuesday);
      final events = [
        event('Lunch', at(tuesday, 720), at(tuesday, 780)),
        event(
          'Holiday',
          at(tuesday, 0),
          at(tuesday.adding(days: 1), 0),
          allDay: true,
        ),
        event('Standup', at(tuesday, 540), at(tuesday, 555)),
      ];
      final rows = DayRules.agenda(
        day: tuesday,
        events: events,
        dayTasks: [loneDone, loneOpen],
        taskFor: lookup([loneOpen, loneDone]),
      );
      expect(
        [for (final r in rows) r.title],
        ['Holiday', 'Standup', 'Lunch', 'Open one', 'Done one'],
      );
      expect(
        [for (final r in rows) r.kind],
        [
          AgendaKind.event,
          AgendaKind.event,
          AgendaKind.event,
          AgendaKind.task,
          AgendaKind.task,
        ],
      );
    });

    test('a task with a block shows once as its block', () {
      final t = task('Write report', done: true, plan: tuesday);
      final rows = DayRules.agenda(
        day: tuesday,
        events: [blockOf(t, at(tuesday, 600), at(tuesday, 660))],
        dayTasks: [t],
        taskFor: lookup([t]),
      );
      expect(rows.length, 1);
      expect(rows[0].kind, AgendaKind.block);
      expect(rows[0].done, isTrue);
      expect(rows[0].title, 'Write report');
      expect(rows[0].ref, ItemRef(ItemType.task, t.id));
    });

    test('a block whose task is gone shows as an event', () {
      final ghost = task('Gone');
      final rows = DayRules.agenda(
        day: tuesday,
        events: [blockOf(ghost, at(tuesday, 600), at(tuesday, 660))],
        dayTasks: const [],
        taskFor: nobody,
      );
      expect([for (final r in rows) r.kind], [AgendaKind.event]);
      expect(rows[0].ref.type, ItemType.event);
    });

    test('events that cross midnight are clipped to the day', () {
      final late = event('Party', at(monday, 1380), at(tuesday, 90));
      final first = DayRules.agenda(
        day: monday,
        events: [late],
        dayTasks: const [],
        taskFor: nobody,
      );
      final second = DayRules.agenda(
        day: tuesday,
        events: [late],
        dayTasks: const [],
        taskFor: nobody,
      );
      expect(first[0].start, 1380);
      expect(first[0].end, 1440);
      expect(second[0].start, 0);
      expect(second[0].end, 90);
      expect(DayRules.timeLabel(first[0]), '23:00–23:59');
      expect(DayRules.timeLabel(second[0]), '00:00–01:30');
    });

    test('events of other days are left out', () {
      final other = event('Other', at(monday, 600), at(monday, 660));
      expect(
        DayRules.agenda(
          day: tuesday,
          events: [other],
          dayTasks: const [],
          taskFor: nobody,
        ),
        isEmpty,
      );
    });

    test('time labels', () {
      const allDay = AgendaRow(
        id: 'a',
        kind: AgendaKind.event,
        title: 'A',
        allDay: true,
        ref: ItemRef(ItemType.event, 'a'),
      );
      const range = AgendaRow(
        id: 'b',
        kind: AgendaKind.event,
        title: 'B',
        start: 540,
        end: 630,
        ref: ItemRef(ItemType.event, 'b'),
      );
      const point = AgendaRow(
        id: 'c',
        kind: AgendaKind.event,
        title: 'C',
        start: 540,
        end: 540,
        ref: ItemRef(ItemType.event, 'c'),
      );
      const loose = AgendaRow(
        id: 'd',
        kind: AgendaKind.task,
        title: 'D',
        ref: ItemRef(ItemType.task, 'd'),
      );
      expect(DayRules.timeLabel(allDay), 'All day');
      expect(DayRules.timeLabel(range), '09:00–10:30');
      expect(DayRules.timeLabel(point), '09:00');
      expect(DayRules.timeLabel(loose), '');
    });
  });

  test('finished clock reads the time of day', () {
    final t = task('A', done: true);
    expect(
      DayRules.finishedClock(t.copyWith(completedAt: '2026-10-02T14:35:10')),
      '14:35',
    );
    expect(DayRules.finishedClock(t.copyWith(completedAt: null)), '');
    expect(DayRules.finishedClock(t.copyWith(completedAt: '2026-10-02')), '');
  });

  group('the weekly review', () {
    test('counts open tasks once and puts tasks with a day first', () {
      final weekTask = task('Week goal');
      final dayTask = task('Day job', plan: tuesday);
      final finished = task('Finished', done: true, plan: monday);
      final cancelled = task(
        'Dropped',
        plan: monday,
      ).copyWith(status: TaskStatus.cancelled);
      final r = DayRules.review(
        monday: monday,
        done: [finished],
        openCandidates: [weekTask, dayTask, dayTask, finished, cancelled],
        events: const [],
        taskFor: lookup(const []),
      );
      expect(titles(r.open), ['Day job', 'Week goal']);
      expect(titles(r.done), ['Finished']);
    });

    test('adds up task block hours and the done share', () {
      final a = task('A', done: true, plan: monday);
      final b = task('B', plan: tuesday);
      final events = [
        blockOf(a, at(monday, 600), at(monday, 720)), // 2h, done
        blockOf(b, at(tuesday, 540), at(tuesday, 600)), // 1h, open
        // Not a task block.
        event('Standup', at(tuesday, 480), at(tuesday, 495)),
      ];
      final r = DayRules.review(
        monday: monday,
        done: [a],
        openCandidates: [b],
        events: events,
        taskFor: lookup([a, b]),
      );
      expect(r.plannedMinutes, 180);
      expect(r.doneMinutes, 120);
    });

    test('the busiest day counts timed events too', () {
      final a = task('A', plan: monday);
      final events = [
        blockOf(a, at(monday, 600), at(monday, 720)), // monday: 120
        event('Workshop', at(tuesday, 540), at(tuesday, 780)), // tuesday: 240
        // All day counts for nothing.
        event(
          'Holiday',
          at(monday, 0),
          at(monday.adding(days: 1), 0),
          allDay: true,
        ),
      ];
      final r = DayRules.review(
        monday: monday,
        done: const [],
        openCandidates: [a],
        events: events,
        taskFor: lookup([a]),
      );
      expect(r.busiest, const BusyDay(day: tuesday, minutes: 240));
    });

    test('a tie goes to the earlier day', () {
      final events = [
        event('One', at(tuesday, 540), at(tuesday, 600)),
        event('Two', at(monday, 540), at(monday, 600)),
      ];
      final r = DayRules.review(
        monday: monday,
        done: const [],
        openCandidates: const [],
        events: events,
        taskFor: lookup(const []),
      );
      expect(r.busiest, const BusyDay(day: monday, minutes: 60));
    });

    test('an event that crosses midnight counts on both days', () {
      // 2h before midnight, 2h after.
      final events = [event('Night', at(monday, 1320), at(tuesday, 120))];
      final r = DayRules.review(
        monday: monday,
        done: const [],
        openCandidates: const [],
        events: events,
        taskFor: lookup(const []),
      );
      expect(r.busiest, const BusyDay(day: monday, minutes: 120));
    });

    test('a week with no time has no busiest day', () {
      final r = DayRules.review(
        monday: monday,
        done: const [],
        openCandidates: const [],
        events: const [],
        taskFor: lookup(const []),
      );
      expect(r.busiest, isNull);
      expect(r.plannedMinutes, 0);
      expect(r.doneMinutes, 0);
    });
  });

  group('the summary text', () {
    WeekReview empty(List<TaskItem> done) => WeekReview(
      monday: monday,
      done: done,
      open: const [],
      plannedMinutes: 0,
      doneMinutes: 0,
    );

    test('the summary is plain lines with mentions', () {
      final sample = WeekReview(
        monday: monday,
        done: [task('Write report', id: 'T1', done: true)],
        open: [task('Call Sam', id: 'T2')],
        plannedMinutes: 150,
        doneMinutes: 60,
        busiest: const BusyDay(day: tuesday, minutes: 180),
      );
      expect(
        DayRules.summary(sample),
        '**Week summary**\n'
        '- Done: 1 task\n'
        '- Still open: 1 task\n'
        '- Time: 1h finished of 2h 30m planned\n'
        '- Busiest day: Tuesday, 3h\n'
        '- Finished: [[Write report|T1]]\n'
        '- Left open: [[Call Sam|T2]]',
      );
    });

    test('an empty week gets a small summary', () {
      expect(
        DayRules.summary(empty(const [])),
        '**Week summary**\n'
        '- Done: 0 tasks\n'
        '- Still open: 0 tasks\n'
        '- Time: no task blocks planned',
      );
    });

    test('a long list ends with "and N more"', () {
      final many = [
        for (var i = 1; i <= 10; i++) task('Task $i', id: 'T$i', done: true),
      ];
      final line = finishedLine(empty(many));
      expect(line, endsWith('[[Task 8|T8]] and 2 more'));
      expect(line, isNot(contains('Task 9')));
    });

    test('a title with brackets stays one mention', () {
      const id = '11111111-2222-3333-4444-555555555555';
      final line = finishedLine(
        empty([task('Fix [[odd]] | title', id: id, done: true)]),
      );
      expect(
        line,
        '- Finished: '
        '${ReferenceParser.mention(title: 'Fix [[odd]] | title', id: id)}',
      );
      expect([for (final m in ReferenceParser.mentions(line)) m.id], [id]);
    });
  });

  group('putting the summary in the note', () {
    const block = '**Week summary**\n- Done: 1 task';

    test('the summary goes under the Review heading', () {
      expect(
        DayRules.insert(block, into: '## Goals\n- x\n\n## Review\n'),
        '## Goals\n- x\n\n## Review\n$block\n',
      );
    });

    test('text under the heading stays below the summary', () {
      expect(
        DayRules.insert(block, into: '## Review\nGood week.'),
        '## Review\n$block\n\nGood week.',
      );
    });

    test('a second insert replaces the first and keeps the rest', () {
      final first = DayRules.insert(
        '**Week summary**\n- Done: 1 task\n- Still open: 3 tasks',
        into: '## Review\nGood week.',
      );
      final second = DayRules.insert(block, into: first);
      expect(second, '## Review\n$block\n\nGood week.');
      expect(DayRules.insert(block, into: second), second);
    });

    test('a note without the heading gets one at the end', () {
      expect(
        DayRules.insert(block, into: 'Some text\n'),
        'Some text\n\n## Review\n$block\n',
      );
      expect(DayRules.insert(block, into: ''), '## Review\n$block\n');
    });

    test('hasSummary finds the heading line', () {
      expect(DayRules.hasSummary('## Review\n$block'), isTrue);
      expect(DayRules.hasSummary('## Review\nNothing yet'), isFalse);
      expect(
        DayRules.hasSummary('text **Week summary** inside a line'),
        isFalse,
      );
    });
  });
}
