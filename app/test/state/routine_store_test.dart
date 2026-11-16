import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// A routine: a task that comes back a set time after the day it was last
// done. Ticking it keeps it in the list and writes the day down. Each tick
// pays the reward; un-ticking takes it back.

// 2026-11-16 is a Monday.
const today = DayKey('2026-11-16');
const strength = 'skill-strength';

AppStore store({DayKey day = today, FakeNotifier? notifier}) => makeStore(
  clock: WallTime(day: day, minute: 8 * 60),
  notifier: notifier,
);

final weekly = RoutineRule(every: 1, unit: RoutineUnit.weeks);

TaskItem routine(AppStore s, String title, {RoutineRule? rule}) {
  final t = s.quickAdd(title)!;
  s.setRoutine(t.id, rule ?? weekly);
  return s.task(t.id)!;
}

void main() {
  group('turning it on', () {
    test('a routine has no repeat, no due date and no plan day', () {
      final s = store();
      final t = s.quickAdd('Water plants')!;
      s.repos.tasks.save(
        s
            .task(t.id)!
            .copyWith(
              due: '2026-11-20',
              recurrence: RecurrenceRule(freq: Freq.daily),
              bucket: TaskBucket.day,
              planDate: today,
            ),
      );
      s.setRoutine(t.id, weekly);
      final r = s.task(t.id)!;
      expect(r.isRoutine, isTrue);
      expect(r.routine, weekly);
      expect(r.routineSince, today);
      expect(r.due, isNull);
      expect(r.recurrence, isNull);
      expect(r.bucket, TaskBucket.inbox);
      expect(r.planDate, isNull);
      expect(s.undoName, 'Make Routine');
      s.undo();
      expect(s.task(t.id)!.isRoutine, isFalse);
      expect(s.task(t.id)!.due, '2026-11-20');
    });

    test('a new routine starts on the day it is turned on', () {
      final s = store();
      final t = routine(s, 'Water plants');
      final st = s.routineStatus(t)!;
      expect(st.due, const DayKey('2026-11-23'));
      expect(st.label, '7 days left');
      expect(st.fraction, 0);
    });

    test('turning it off keeps the done days', () {
      final s = store();
      final t = routine(s, 'Water plants');
      s.toggleDone(taskId: t.id);
      s.setRoutine(t.id, null);
      expect(s.task(t.id)!.isRoutine, isFalse);
      expect(s.task(t.id)!.routineSince, isNull);
      expect(s.routineDones(t.id).length, 1);
    });

    test('a subtask cannot be a routine', () {
      final s = store();
      final p = s.quickAdd('Parent')!;
      final c = TaskItem(title: 'Child', parentId: p.id);
      s.repos.tasks.save(c);
      s.setRoutine(c.id, weekly);
      expect(s.task(c.id)!.isRoutine, isFalse);
    });
  });

  group('ticking', () {
    test('a tick writes today down and the routine stays open', () {
      final s = store();
      final t = routine(s, 'Water plants');
      s.toggleDone(taskId: t.id);
      expect(s.task(t.id)!.status, TaskStatus.open);
      expect(s.routineDoneToday(t.id), isTrue);
      expect(s.routineDones(t.id).map((x) => x.day), [today]);
      expect(s.undoName, 'Complete Routine');
      expect(s.routineEntries().map((e) => e.task.id), [t.id]);
    });

    test('untick and undo bring back the day before', () {
      final s = store(day: const DayKey('2026-11-09'));
      final t = routine(s, 'Water plants');
      s.toggleDone(taskId: t.id);
      // A week later.
      s.clockOverride = const WallTime(day: today, minute: 480);
      expect(s.routineStatus(s.task(t.id)!)!.label, 'Due today');
      s.toggleDone(taskId: t.id);
      expect(s.routineStatus(s.task(t.id)!)!.label, '7 days left');
      expect(s.routineDones(t.id).length, 2);

      s.toggleDone(taskId: t.id); // untick
      expect(s.routineDones(t.id).length, 1);
      expect(s.routineStatus(s.task(t.id)!)!.label, 'Due today');

      s.undo(); // the tick again
      expect(s.routineDones(t.id).length, 2);
      s.undo(); // the tick gone
      expect(s.routineDones(t.id).length, 1);
      s.redo();
      expect(s.routineDones(t.id).length, 2);
    });

    test('late: full and says how many days', () {
      final s = store(day: const DayKey('2026-11-01'));
      final t = routine(s, 'Water plants');
      s.clockOverride = const WallTime(day: today, minute: 480);
      final st = s.routineStatus(s.task(t.id)!)!;
      expect(st.late, isTrue);
      expect(st.fraction, 1);
      expect(st.label, 'Late 8 days');
    });
  });

  group('rewards', () {
    test('each tick pays the reward and untick takes it back', () {
      final s = store(day: const DayKey('2026-11-09'));
      final t = routine(s, 'Gym');
      s.setTaskReward(taskId: t.id, skillId: strength, points: 10);
      s.toggleDone(taskId: t.id);
      expect(s.skillPoints[strength], 10);
      s.clockOverride = const WallTime(day: today, minute: 480);
      s.toggleDone(taskId: t.id);
      expect(s.skillPoints[strength], 20);
      s.toggleDone(taskId: t.id);
      expect(s.skillPoints[strength], 10);
      s.undo();
      expect(s.skillPoints[strength], 20);
    });
  });

  group('the lists', () {
    test('a routine is never in Overdue or Unscheduled', () {
      final s = store();
      final plain = s.quickAdd('Plain')!;
      final t = routine(s, 'Water plants');
      final lists = s.unscheduledTasks();
      final ids = [...lists.overdue, ...lists.unscheduled].map((x) => x.id);
      expect(ids, contains(plain.id));
      expect(ids, isNot(contains(t.id)));
    });

    test('late first, then the least time left', () {
      final s = store(day: const DayKey('2026-11-01'));
      final late = routine(s, 'Late one');
      s.clockOverride = const WallTime(day: today, minute: 480);
      final monthly = routine(
        s,
        'Monthly',
        rule: RoutineRule(every: 1, unit: RoutineUnit.months),
      );
      final daily = routine(
        s,
        'Daily',
        rule: RoutineRule(every: 1, unit: RoutineUnit.days),
      );
      expect(s.routineEntries().map((e) => e.task.id), [
        late.id,
        daily.id,
        monthly.id,
      ]);
    });

    test('a done routine (finished for good) leaves the list', () {
      final s = store();
      final t = routine(s, 'Water plants');
      s.repos.tasks.save(s.task(t.id)!.copyWith(status: TaskStatus.cancelled));
      expect(s.routineEntries(), isEmpty);
    });
  });

  group('blocks', () {
    test('ticking a block marks the routine done today', () {
      final s = store();
      final t = routine(s, 'Water plants');
      s.schedule(taskId: t.id, day: today, start: 600);
      final block = s.blocksOfTask(t.id).single;
      expect(s.task(t.id)!.isRoutine, isTrue);
      expect(s.task(t.id)!.planDate, isNull);
      s.toggleRoutineBlock(block.id);
      expect(s.routineDoneToday(t.id), isTrue);
      final b = s.blocks(const DayRange.single(today)).single;
      expect(b.isDone, isTrue);
      expect(s.task(t.id)!.status, TaskStatus.open);
      s.toggleRoutineBlock(block.id);
      expect(s.routineDones(t.id), isEmpty);
      expect(s.blocks(const DayRange.single(today)).single.isDone, isFalse);
    });

    test('a list tick and a block tick on one day pay once', () {
      final s = store();
      final t = routine(s, 'Gym');
      s.setTaskReward(taskId: t.id, skillId: strength, points: 10);
      s.schedule(taskId: t.id, day: today, start: 600);
      final block = s.blocksOfTask(t.id).single;
      s.toggleDone(taskId: t.id);
      s.toggleRoutineBlock(block.id);
      expect(s.routineDones(t.id).length, 1);
      expect(s.routineDones(t.id).single.eventId, block.id);
      expect(s.skillPoints[strength], 10);
    });

    test('scheduling again keeps a ticked block and moves an open one', () {
      final s = store();
      final t = routine(s, 'Water plants');
      s.schedule(taskId: t.id, day: today, start: 600);
      final ticked = s.blocksOfTask(t.id).single;
      s.toggleRoutineBlock(ticked.id);
      final next = today.adding(days: 7);
      s.schedule(taskId: t.id, day: next, start: 600);
      s.schedule(taskId: t.id, day: next, start: 720);
      final blocks = s.blocksOfTask(t.id);
      expect(blocks.length, 2);
      expect(blocks.map((b) => b.id), contains(ticked.id));
      expect(
        blocks.where((b) => b.id != ticked.id).single.start,
        WallTime(day: next, minute: 720),
      );
    });
  });

  group('deleting', () {
    test('undo of a delete brings the done days back', () {
      final s = store();
      final t = routine(s, 'Water plants');
      s.toggleDone(taskId: t.id);
      s.deleteTask(t.id);
      expect(s.task(t.id), isNull);
      expect(s.routineDones(t.id), isEmpty);
      s.undo();
      expect(s.task(t.id), isNotNull);
      expect(s.routineDones(t.id).length, 1);
    });
  });

  group('reminders', () {
    test('one reminder at 09:00 on the due day', () {
      final s = store(day: const DayKey('2026-11-10'), notifier: FakeNotifier())
        ..setBedtimeEnabled(false);
      final t = routine(s, 'Water plants');
      final list = s.buildReminders();
      final mine = list.where((r) => r.id.startsWith('routine-')).toList();
      expect(mine.length, 1);
      expect(mine.single.id, 'routine-${t.id}-2026-11-17');
      expect(
        mine.single.fireAt,
        const WallTime(day: DayKey('2026-11-17'), minute: 540),
      );
    });

    test('none for a late routine', () {
      final s = store(day: const DayKey('2026-11-01'), notifier: FakeNotifier())
        ..setBedtimeEnabled(false);
      routine(s, 'Water plants');
      s.clockOverride = const WallTime(day: today, minute: 480);
      expect(
        s.buildReminders().where((r) => r.id.startsWith('routine-')),
        isEmpty,
      );
    });
  });
}
