// Port of Tests/GroveTests/AllTasksTests.swift (the store part).
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  final today = DayKey.today();
  const done = TaskStatus.done;
  const cancelled = TaskStatus.cancelled;
  const dayB = TaskBucket.day;

  void save(AppStore s, TaskItem t) => s.repos.tasks.save(t);

  test('every open task is in one of the two lists', () {
    final s = makeStore();
    save(s, TaskItem(title: 'someday', bucket: TaskBucket.someday, sort: 1));
    save(
      s,
      TaskItem(
        title: 'tomorrow',
        bucket: dayB,
        planDate: today.adding(days: 1),
        sort: 2,
      ),
    );
    save(s, TaskItem(title: 'inbox', sort: 3));
    save(
      s,
      TaskItem(
        title: 'week',
        bucket: TaskBucket.week,
        planWeek: today.weekStart(),
        sort: 4,
      ),
    );
    save(
      s,
      TaskItem(
        title: 'yesterday',
        bucket: dayB,
        planDate: today.adding(days: -1),
        sort: 5,
      ),
    );
    final all = s.allOpenTasks();
    expect(titles(all.noDay), ['inbox', 'week', 'someday']);
    expect(titles(all.byDay), ['yesterday', 'tomorrow']);
  });

  test('done, cancelled and subtasks are left out', () {
    final s = makeStore();
    final parent = TaskItem(
      title: 'parent',
      bucket: dayB,
      planDate: today,
      sort: 1,
    );
    save(s, parent);
    save(s, TaskItem(title: 'sub', parentId: parent.id, sort: 2));
    save(s, TaskItem(title: 'done', status: done, sort: 3));
    save(
      s,
      TaskItem(
        title: 'cancelled',
        status: cancelled,
        bucket: dayB,
        planDate: today,
        sort: 4,
      ),
    );
    final all = s.allOpenTasks();
    expect(all.noDay, isEmpty);
    expect(titles(all.byDay), ['parent']);
  });

  test('a task checked with linger stays in its place for a moment', () async {
    final s = makeStore();
    final place = TaskPlacement.day(today);
    final a = s.quickAdd('Alpha', placement: place)!;
    final b = s.quickAdd('Bravo', placement: place)!;
    final c = s.quickAdd('Charlie', placement: place)!;
    s.toggleDone(taskId: b.id, linger: true);
    expect(s.task(b.id)?.isDone, isTrue);
    expect(ids(s.allOpenTasks().byDay), [a.id, b.id, c.id]);
    await wait(1000);
    expect(ids(s.allOpenTasks().byDay), [a.id, c.id]);
  });

  test('without linger a done task leaves at once', () {
    final s = makeStore();
    final a = s.quickAdd('Alpha')!;
    s.toggleDone(taskId: a.id);
    expect(s.allOpenTasks().noDay, isEmpty);
  });

  test('a lingering subtask does not join the list', () {
    final s = makeStore();
    final parent = s.quickAdd('Parent')!;
    s.addSubtask(to: parent.id, title: 'Step');
    final sub = s.subtasks(parent.id).first;
    s.toggleDone(taskId: sub.id, linger: true);
    expect(ids(s.allOpenTasks().noDay), [parent.id]);
  });

  group('unscheduledTasks()', () {
    test('holds overdue first, then the tasks with no day', () {
      final s = makeStore();
      TaskItem onDay(String title, int offset, double sort) => TaskItem(
        title: title,
        bucket: dayB,
        planDate: today.adding(days: offset),
        sort: sort,
      );
      save(s, TaskItem(title: 'someday', bucket: TaskBucket.someday, sort: 1));
      save(s, onDay('today', 0, 2));
      save(s, TaskItem(title: 'inbox', sort: 3));
      save(s, onDay('tomorrow', 1, 4));
      save(s, onDay('yesterday', -1, 5));
      save(s, onDay('last week', -7, 6));
      final r = s.unscheduledTasks();
      expect(titles(r.overdue), ['last week', 'yesterday']);
      expect(titles(r.unscheduled), ['inbox', 'someday']);
    });

    test('a scheduled task with a block is not in either list', () {
      final s = makeStore();
      final t = TaskItem(title: 'Timed', estimateMin: 30);
      save(s, t);
      s.schedule(taskId: t.id, day: today.adding(days: 2), start: 600);
      final r = s.unscheduledTasks();
      expect(r.overdue, isEmpty);
      expect(r.unscheduled, isEmpty);
    });

    test('done, cancelled and subtasks are not unscheduled', () {
      final s = makeStore();
      final past = today.adding(days: -2);
      final late = TaskItem(
        title: 'late',
        bucket: dayB,
        planDate: past,
        sort: 1,
      );
      save(s, late);
      save(
        s,
        TaskItem(
          title: 'late sub',
          parentId: late.id,
          bucket: dayB,
          planDate: past,
          sort: 2,
        ),
      );
      save(
        s,
        TaskItem(
          title: 'late done',
          status: done,
          bucket: dayB,
          planDate: past,
          sort: 3,
        ),
      );
      save(s, TaskItem(title: 'inbox done', status: done, sort: 4));
      save(s, TaskItem(title: 'inbox cancelled', status: cancelled, sort: 5));
      final r = s.unscheduledTasks();
      expect(titles(r.overdue), ['late']);
      expect(r.unscheduled, isEmpty);
    });

    test('an overdue task checked with linger stays for a moment', () async {
      final s = makeStore();
      final past = today.adding(days: -3);
      final a = TaskItem(title: 'Alpha', bucket: dayB, planDate: past, sort: 1);
      final b = TaskItem(title: 'Bravo', bucket: dayB, planDate: past, sort: 2);
      save(s, a);
      save(s, b);
      s.toggleDone(taskId: a.id, linger: true);
      expect(ids(s.unscheduledTasks().overdue), [a.id, b.id]);
      await wait(1000);
      expect(ids(s.unscheduledTasks().overdue), [b.id]);
    });

    test('a no-day task checked with linger stays for a moment', () async {
      final s = makeStore();
      final a = s.quickAdd('Alpha')!;
      final b = s.quickAdd('Bravo')!;
      s.toggleDone(taskId: a.id, linger: true);
      expect(ids(s.unscheduledTasks().unscheduled), [a.id, b.id]);
      await wait(1000);
      expect(ids(s.unscheduledTasks().unscheduled), [b.id]);
    });
  });
}
