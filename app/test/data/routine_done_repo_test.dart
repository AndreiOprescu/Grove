import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/routine.dart';
import 'package:grove/core/model/task.dart';
import 'package:grove/data/data.dart';

import 'helpers.dart';

// Routines (shared migration 16): the rule on the task and the done days.

void main() {
  late Repos r;
  setUp(() => r = makeRepos());
  tearDown(() => r.db.close());

  test('a task keeps its routine rule and its start day', () {
    final t = TaskItem(
      id: 'T',
      title: 'Water plants',
      routine: RoutineRule(every: 3, unit: RoutineUnit.days),
      routineSince: const DayKey('2026-11-10'),
    );
    r.tasks.save(t);
    final back = r.tasks.get('T')!;
    expect(back.routine, RoutineRule(every: 3, unit: RoutineUnit.days));
    expect(back.routineSince, const DayKey('2026-11-10'));
    expect(r.tasks.routines().map((x) => x.id), ['T']);
  });

  test('a plain task has no routine and is not in the routines', () {
    r.tasks.save(TaskItem(id: 'P', title: 'Plain'));
    expect(r.tasks.get('P')!.routine, isNull);
    expect(r.tasks.routines(), isEmpty);
  });

  test('done days are kept, read by task and by block', () {
    r.tasks.save(TaskItem(id: 'T', title: 'Gym', routine: RoutineRule()));
    final a = RoutineDone(
      id: 'a',
      taskId: 'T',
      day: const DayKey('2026-11-01'),
    );
    final b = RoutineDone(
      id: 'b',
      taskId: 'T',
      day: const DayKey('2026-11-08'),
      eventId: 'E',
    );
    r.routineDones.save(b);
    r.routineDones.save(a);
    expect(r.routineDones.forTask('T').map((x) => x.id), ['a', 'b']);
    expect(r.routineDones.forTasks(['T', 'X']).keys, ['T']);
    expect(r.routineDones.forEvents(['E']).values.single, b);
    expect(r.routineDones.get('a'), a);
    r.routineDones.delete('a');
    expect(r.routineDones.forTask('T').map((x) => x.id), ['b']);
  });

  test('the done days go with their task', () {
    r.tasks.save(TaskItem(id: 'T', title: 'Gym', routine: RoutineRule()));
    r.routineDones.save(
      RoutineDone(id: 'a', taskId: 'T', day: const DayKey('2026-11-01')),
    );
    r.tasks.delete('T');
    expect(r.routineDones.forTask('T'), isEmpty);
  });
}
