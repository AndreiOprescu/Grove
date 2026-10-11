// Data for the speed check of milestone F12: a store that looks like some
// months of real use. 1 000 tasks (PLAN §10 names that number), about 400
// events, 270 notes, 4 goals and a full planner week around today.
//
// The same data is made each time: the choices come from a fixed seed. Only
// the days move, because the planner shows the week of today.
//
// Used by `tool/perf_start.dart` and `integration_test/perf_test.dart`.
// Run them with `./scripts/flutter_perf.sh macos`.
import 'dart:math';

import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/event.dart';
import 'package:grove/core/model/goal.dart';
import 'package:grove/core/model/note.dart';
import 'package:grove/core/model/recurrence.dart';
import 'package:grove/core/model/task.dart';
import 'package:grove/core/model/task_color.dart';
import 'package:grove/data/data.dart';

abstract final class PerfData {
  /// Set in the `settings` table when the data is in.
  static const seededKey = 'perf.seeded';

  static bool isSeeded(Repos repos) => repos.settings.get(seededKey) != null;

  /// What [seed] put in, to show next to the numbers.
  static Map<String, int> counts(Repos repos) => {
    'tasks': repos.tasks.all().length,
    'events': repos.events.all().length,
    'notes': repos.notes.all().length,
    'goals': repos.goals.all().length,
    'lists': repos.lists.all().length,
  };

  static const _verbs = [
    'Write',
    'Review',
    'Call',
    'Plan',
    'Fix',
    'Send',
    'Read',
    'Prepare',
    'Book',
    'Clean',
    'Draft',
    'Check',
    'Update',
    'Order',
    'Sort',
  ];
  static const _things = [
    'the quarterly report',
    'slides for Monday',
    'the dentist',
    'the trip to Cluj',
    'the kitchen tap',
    'the invoice for March',
    'chapter 4',
    'the team offsite',
    'flights for December',
    'the garage',
    'the budget sheet',
    'the release notes',
    'the insurance papers',
    'new running shoes',
    'the photo backups',
    'the garden plan',
    'the onboarding guide',
    'birthday gift for Ana',
  ];
  static const _meetings = [
    'Standup',
    'Design review',
    '1:1 with Maria',
    'Lunch',
    'Gym',
    'Deep work',
    'Client call',
    'Planning',
    'School run',
    'Reading',
    'Language class',
    'Dinner with friends',
  ];
  static const _sentences = [
    'The first draft is rough but the shape is right.',
    'Ask about the deadline before the next meeting.',
    'Three things went well today and one did not.',
    'The numbers for last month are in the shared folder.',
    'Remember to water the plants on the balcony.',
    'A short walk after lunch made the afternoon easier.',
    'The new layout needs a second look on a small screen.',
    'Call back on Thursday, after ten.',
    'Keep the list short: two big things and three small ones.',
    'This idea could become a goal for the next quarter.',
  ];

  /// Fills [repos]. `today` is the day the planner opens on.
  static void seed(Repos repos, {required DayKey today}) {
    final r = Random(12);
    String pick(List<String> from) => from[r.nextInt(from.length)];
    String taskTitle() => '${pick(_verbs)} ${pick(_things)}';
    String color() => r.nextInt(3) == 0 ? pick(TaskColor.names) : '';
    String stamp(DayKey day, int minute) =>
        '${day.string}T${'${minute ~/ 60}'.padLeft(2, '0')}:'
        '${'${minute % 60}'.padLeft(2, '0')}:00';

    repos.db.transaction(() {
      // The person has used Grove for a long time: no welcome card.
      repos.settings.set(FirstRun.doneKey, '1');
      repos.settings.set(FirstRun.dismissedKey, '1');

      var lists = repos.lists.all();
      if (lists.isEmpty) {
        const names = [('Home', '🌿'), ('Work', '💼'), ('Personal', '✨')];
        for (final (i, (name, emoji)) in names.indexed) {
          repos.lists.save(ListItem(name: name, emoji: emoji, sort: i));
        }
        lists = repos.lists.all();
      }
      var sort = 10.0;
      TaskItem task({
        required TaskBucket bucket,
        DayKey? planDate,
        DayKey? planWeek,
        TaskStatus status = TaskStatus.open,
        String? parentId,
        DayKey? made,
      }) {
        final day = made ?? today.adding(days: -r.nextInt(60) - 1);
        final item = TaskItem(
          title: taskTitle(),
          summary: r.nextInt(4) == 0 ? pick(_sentences) : '',
          notes: r.nextInt(3) == 0
              ? '${pick(_sentences)}\n\n${pick(_sentences)}'
              : '',
          listId: lists[r.nextInt(lists.length)].id,
          parentId: parentId,
          priority: r.nextInt(4),
          status: status,
          bucket: bucket,
          planDate: planDate,
          planWeek: planWeek,
          due: r.nextInt(6) == 0 && planDate != null ? planDate.string : null,
          estimateMin: const [15, 30, 30, 45, 60, 90, 120][r.nextInt(7)],
          sort: sort++,
          color: color(),
          createdAt: stamp(day, 8 * 60 + r.nextInt(600)),
          completedAt: status == TaskStatus.done
              ? stamp(planDate ?? day, 9 * 60 + r.nextInt(600))
              : null,
        );
        repos.tasks.save(item);
        return item;
      }

      // 1 000 tasks. 580 are done, over the last 120 days.
      for (var i = 0; i < 580; i++) {
        final day = today.adding(days: -1 - i % 120);
        task(
          bucket: TaskBucket.day,
          planDate: day,
          status: TaskStatus.done,
          made: day.adding(days: -r.nextInt(5)),
        );
      }
      // Open, on a day: 12 for today, 5 for each of the next 14 days.
      final byDay = <DayKey, List<TaskItem>>{};
      for (var offset = 0; offset <= 14; offset++) {
        final day = today.adding(days: offset);
        for (var i = 0; i < (offset == 0 ? 12 : 5); i++) {
          (byDay[day] ??= []).add(task(bucket: TaskBucket.day, planDate: day));
        }
      }
      // The days of this week that are over have their tasks too.
      final monday = today.weekStart();
      for (var day = monday; day < today; day = day.adding(days: 1)) {
        byDay[day] = [];
      }
      // Late: 40 open tasks on days that are over.
      for (var i = 0; i < 40; i++) {
        final day = today.adding(days: -1 - i % 20);
        final t = task(bucket: TaskBucket.day, planDate: day);
        byDay[day]?.add(t);
      }
      for (var i = 0; i < 18; i++) {
        task(bucket: TaskBucket.week, planWeek: monday);
      }
      for (var i = 0; i < 120; i++) {
        task(bucket: TaskBucket.inbox);
      }
      for (var i = 0; i < 100; i++) {
        task(bucket: TaskBucket.someday);
      }
      // 60 subtasks, 3 on each of 20 open tasks.
      final parents = [
        ...byDay[today]!,
        for (final day in byDay.keys)
          if (day != today) ...byDay[day]!.take(1),
      ].take(20).toList();
      for (final parent in parents) {
        for (var i = 0; i < 3; i++) {
          task(
            bucket: parent.bucket,
            planDate: parent.planDate,
            parentId: parent.id,
            status: i == 0 ? TaskStatus.done : TaskStatus.open,
          );
        }
      }

      void event(
        String title,
        DayKey day,
        int start,
        int minutes, {
        EventKind kind = EventKind.event,
        String? taskId,
        String? goalId,
        String color = 'accent2',
        RecurrenceRule? recurrence,
        bool allDay = false,
        bool done = false,
      }) => repos.events.save(
        EventItem(
          title: title,
          start: WallTime(day: day, minute: start),
          end: WallTime(day: day, minute: min(start + minutes, 1439)),
          allDay: allDay,
          kind: kind,
          taskId: taskId,
          goalId: goalId,
          color: color,
          location: r.nextInt(5) == 0 ? 'Room ${r.nextInt(9) + 1}' : '',
          notes: r.nextInt(6) == 0 ? pick(_sentences) : '',
          recurrence: recurrence,
          doneAt: done ? stamp(day, start + minutes) : null,
        ),
      );

      // Two series, as a real calendar has.
      event(
        'Standup',
        today.adding(days: -90).weekStart(),
        9 * 60 + 30,
        15,
        recurrence: RecurrenceRule(
          freq: Freq.weekly,
          weekdays: const [1, 2, 3, 4, 5],
        ),
      );
      event(
        'Weekly review',
        today.adding(days: -90).weekStart().adding(days: 4),
        16 * 60,
        45,
        recurrence: RecurrenceRule(freq: Freq.weekly),
      );
      // Single events, 45 days back and 30 days ahead: 5 on a work day, 2 on
      // a weekend day.
      for (var offset = -45; offset <= 30; offset++) {
        final day = today.adding(days: offset);
        final n = day.weekdayIndex >= 6 ? 2 : 5;
        for (var i = 0; i < n; i++) {
          event(
            pick(_meetings),
            day,
            (8 + i * 2) * 60 + r.nextInt(4) * 15,
            const [30, 45, 60, 60, 90][r.nextInt(5)],
            color: const ['accent', 'accent2', 'green', 'blue'][r.nextInt(4)],
          );
        }
        if (offset % 9 == 0) event('Holiday', day, 0, 1439, allDay: true);
      }

      // 4 goals, each with blocks in the last 4 weeks and in this week.
      const goals = ['Write the book', 'Run', 'Learn German', 'Side project'];
      for (final (i, title) in goals.indexed) {
        final goal = GoalItem(
          title: title,
          color: TaskColor.names[(i * 2) % TaskColor.names.length],
          targetMin: 180 + i * 60,
          sort: i.toDouble(),
          kind: i == 1 ? GoalKind.sessions : GoalKind.hours,
        );
        repos.goals.upsert(goal);
        for (var week = -4; week <= 0; week++) {
          for (final weekday in const [0, 2, 4]) {
            final day = monday.adding(days: week * 7 + (weekday + i) % 7);
            event(
              title,
              day,
              (18 + i % 3) * 60,
              60,
              kind: EventKind.block,
              goalId: goal.id,
              color: 'accent',
              done: day < today,
            );
          }
        }
      }

      // The week of today is full: each task of a day has a time block, some
      // at the same time as an event, so the columns of the grid split.
      for (final entry in byDay.entries) {
        if (entry.key < monday || entry.key > monday.adding(days: 6)) continue;
        var start = 7 * 60;
        for (final t in entry.value) {
          final length = max(30, t.estimateMin);
          if (start + length > 22 * 60) break;
          repos.events.save(
            EventItem(
              title: t.title,
              start: WallTime(day: entry.key, minute: start),
              end: WallTime(day: entry.key, minute: start + length),
              kind: EventKind.block,
              taskId: t.id,
              color: 'accent',
            ),
          );
          start += length + (r.nextBool() ? 0 : 15);
        }
      }

      // 200 notes, 60 daily notes and 10 weekly notes.
      String body(int paragraphs) => [
        for (var p = 0; p < paragraphs; p++)
          if (p % 4 == 1)
            '## ${pick(_things)}'
          else if (p % 4 == 2)
            [for (var b = 0; b < 4; b++) '- ${pick(_sentences)}'].join('\n')
          else
            [for (var s = 0; s < 3 + r.nextInt(4); s++) pick(_sentences)]
                .join(' '),
      ].join('\n\n');
      for (var i = 0; i < 200; i++) {
        final day = today.adding(days: -(i * 3) ~/ 5);
        final at = stamp(day, 9 * 60 + r.nextInt(600));
        repos.notes.save(
          Note(
            title: 'Notes on ${pick(_things)}',
            body: body(3 + r.nextInt(8)),
            pinned: i % 40 == 0,
            createdAt: at,
            updatedAt: at,
          ),
          touch: false,
        );
      }
      for (var i = 0; i < 60; i++) {
        final day = today.adding(days: -i);
        final at = stamp(day, 21 * 60);
        repos.notes.save(
          Note(
            title: day.string,
            body: body(2 + r.nextInt(4)),
            kind: NoteKind.daily,
            date: day,
            mood: r.nextInt(3) + 1,
            createdAt: at,
            updatedAt: at,
          ),
          touch: false,
        );
      }
      for (var i = 1; i <= 10; i++) {
        final day = monday.adding(days: -7 * i);
        final at = stamp(day.adding(days: 6), 18 * 60);
        repos.notes.save(
          Note(
            title: 'Week of ${day.string}',
            body: body(5),
            kind: NoteKind.weekly,
            date: day,
            createdAt: at,
            updatedAt: at,
          ),
          touch: false,
        );
      }

      repos.settings.set(seededKey, today.string);
    });
  }
}
