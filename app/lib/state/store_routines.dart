part of 'app_store.dart';

/// A routine in the list: the task, where it stands today, and its done days
/// (oldest first).
typedef RoutineEntry = ({
  TaskItem task,
  RoutineStatus status,
  List<RoutineDone> done,
});

/// Routines: tasks that come back a set time after the day they were last
/// done. `RoutineRules` has the rules. A routine task stays open; each tick
/// is a row of `routine_done`, and each one pays the reward of the task.
extension AppStoreRoutines on AppStore {
  /// The done days of one routine, oldest first.
  List<RoutineDone> routineDones(String taskId) =>
      _try(() => repos.routineDones.forTask(taskId)) ?? const [];

  /// Where a routine stands today, or null for a task that is no routine.
  RoutineStatus? routineStatus(TaskItem task, {List<RoutineDone>? done}) {
    final rule = task.routine;
    if (rule == null) return null;
    final days = [for (final x in done ?? routineDones(task.id)) x.day];
    final today = clockToday;
    final last = RoutineRules.lastDone(task.routineSince ?? today, days);
    return RoutineRules.status(rule, last, today);
  }

  /// True when the routine has a done day today.
  bool routineDoneToday(String taskId) {
    final today = clockToday;
    return routineDones(taskId).any((x) => x.day == today);
  }

  /// Every open routine, late first, then the least time left.
  List<RoutineEntry> routineEntries() {
    final tasks = _try(repos.tasks.routines) ?? const <TaskItem>[];
    if (tasks.isEmpty) return const [];
    final dones =
        _try(() => repos.routineDones.forTasks(tasks.map((t) => t.id))) ??
        const <String, List<RoutineDone>>{};
    final out = <RoutineEntry>[
      for (final t in tasks)
        (
          task: t,
          status: routineStatus(t, done: dones[t.id] ?? const [])!,
          done: dones[t.id] ?? const [],
        ),
    ];
    out.sort(
      (a, b) => RoutineRules.compare(
        a.status.daysLeft,
        a.task.title,
        b.status.daysLeft,
        b.task.title,
      ),
    );
    return out;
  }

  /// Turns a task into a routine, changes its step, or turns it off (null).
  /// A routine has no repeat, no due date and no plan day: turning it on
  /// clears them. Its clock starts today. Turning it off keeps the done days.
  void setRoutine(String taskId, RoutineRule? rule) {
    final old = task(taskId);
    if (old == null || old.parentId != null) return;
    if (rule == null) {
      if (old.routine == null) return;
      commit(
        Mutation('Turn Off Routine')
          ..tasks.add((
            before: old,
            after: old.copyWith(routine: null, routineSince: null),
          )),
      );
      return;
    }
    if (old.status != TaskStatus.open || old.routine == rule) return;
    final t = old.copyWith(
      routine: rule,
      routineSince: old.routineSince ?? clockToday,
      recurrence: null,
      due: null,
      bucket: TaskBucket.inbox,
      planDate: null,
      planWeek: null,
    );
    commit(
      Mutation(old.routine == null ? 'Make Routine' : 'Change Routine')
        ..tasks.add((before: old, after: t)),
    );
  }

  /// A tick of a routine in a task list: done today, or not done today when
  /// it already is. Taking the tick away brings back the day before.
  void toggleRoutineToday(String taskId) {
    final t = task(taskId);
    if (t == null || t.routine == null) return;
    final today = clockToday;
    final todays = [
      for (final x in routineDones(taskId))
        if (x.day == today) x,
    ];
    final m = Mutation(todays.isEmpty ? 'Complete Routine' : 'Undo Routine');
    if (todays.isEmpty) {
      m.routineDones.add((
        before: null,
        after: RoutineDone(taskId: taskId, day: today, doneAt: clockStamp()),
      ));
    } else {
      for (final x in todays) {
        m.routineDones.add((before: x, after: null));
      }
    }
    commit(m);
  }

  /// Marks a routine done today and never takes a tick away: the end of a
  /// focus session. With [eventId], the tick is the tick of that block.
  void markRoutineDone(String taskId, {String? eventId}) {
    final today = clockToday;
    final all = routineDones(taskId);
    if (eventId != null && event(eventId)?.taskId == taskId) {
      if (all.any((x) => x.eventId == eventId)) return;
      return toggleRoutineBlock(eventId);
    }
    if (all.any((x) => x.day == today)) return;
    toggleRoutineToday(taskId);
  }

  /// A tick of a routine's block on the planner: done today, whatever the
  /// day of the block (the owner's rule). A block that is ticked already is unticked. A tick in the
  /// list on the same day joins the block, so it is not paid twice.
  void toggleRoutineBlock(String eventId) {
    final e = event(eventId);
    final taskId = e?.taskId;
    if (e == null || taskId == null) return;
    final t = task(taskId);
    if (t == null || t.routine == null) return;
    final all = routineDones(taskId);
    final mine = all.where((x) => x.eventId == eventId).toList();
    final m = Mutation(mine.isEmpty ? 'Complete Routine' : 'Undo Routine');
    if (mine.isNotEmpty) {
      for (final x in mine) {
        m.routineDones.add((before: x, after: null));
      }
    } else {
      final day = clockToday;
      final loose = all
          .where((x) => x.day == day && x.eventId == null)
          .firstOrNull;
      if (loose != null) {
        m.routineDones.add((
          before: loose,
          after: loose.copyWith(eventId: e.id),
        ));
      } else {
        m.routineDones.add((
          before: null,
          after: RoutineDone(
            taskId: taskId,
            day: day,
            eventId: e.id,
            doneAt: clockStamp(),
          ),
        ));
      }
    }
    commit(m);
  }

  /// The routines that are not late, for the reminders: one at 09:00 on
  /// the due day.
  List<({String id, String title, DayKey due})> _routineDueDays() => [
    for (final r in routineEntries())
      if (!r.status.late)
        (id: r.task.id, title: r.task.title, due: r.status.due),
  ];
}
