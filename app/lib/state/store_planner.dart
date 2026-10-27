part of 'app_store.dart';

/// One step of the "Plan my day" plan.
typedef PlanStep = ({TaskItem task, int start});

/// A day of a repeating event before and after an edit.
typedef OccurrenceEdit = ({EventItem old, EventItem changed});

/// What "Reorganise rest of day" reads: the input of the rule and the
/// stored items behind it. [tasks] are the open tasks, [taskBlocks] their
/// open blocks today (by task id), [goalBlocks] the open goal blocks (by
/// event id), [events] every timed event of the day.
typedef _ReplanSources = ({
  ReplanInput input,
  Map<String, TaskItem> tasks,
  Map<String, List<EventItem>> taskBlocks,
  Map<String, EventItem> goalBlocks,
  List<EventItem> events,
});

/// Highest priority first, then the order of the list.
int _byPriority(TaskItem a, TaskItem b) => a.priority != b.priority
    ? b.priority.compareTo(a.priority)
    : a.sort.compareTo(b.sort);

/// A sort that keeps equal items in their order.
List<T> _sorted<T>(Iterable<T> items, int Function(T a, T b) compare) {
  final indexed = items.indexed.toList()
    ..sort((x, y) {
      final c = compare(x.$2, y.$2);
      return c != 0 ? c : x.$1.compareTo(y.$1);
    });
  return [for (final x in indexed) x.$2];
}

/// The planner: reading blocks and writing changes to them (PLAN §5.1).
extension AppStorePlanner on AppStore {
  // Reading for the planner

  /// A stored event, or one occurrence of a repeating event (its id is an
  /// [OccurrenceId]). Null when that day is not part of the series.
  EventItem? event(String id) {
    final p = OccurrenceId.parse(id);
    if (p == null) return _try(() => repos.events.get(id));
    final series = _try(() => repos.events.get(p.series));
    final rule = series?.recurrence;
    if (series == null || rule == null) return null;
    final gone = {...?_try(() => repos.events.exdates(series.id))};
    final days = RecurrenceEngine.occurrences(
      rule: rule,
      seriesStart: series.start.day,
      from: p.day,
      to: p.day,
      exdates: gone,
    );
    if (!days.contains(p.day)) return null;
    return RecurrenceEngine.occurrence(of: series, on: p.day);
  }

  TaskItem? task(String id) => _try(() => repos.tasks.get(id));

  List<PlannerBlock> blocks(DayRange days) {
    final tasks = <String, TaskItem?>{};
    final taskSubs = <String, List<BlockSubtask>>{};
    final out = <PlannerBlock>[];
    final events = eventItems(days);
    // Subtasks of blocks without a task: goal blocks, and old goal blocks
    // whose goal was deleted.
    final blockSubs =
        _try(
          () => repos.blockSubtasks.forEvents([
            for (final e in events)
              if (e.taskId == null && !e.allDay) e.id,
          ]),
        ) ??
        const <String, List<BlockSubtaskItem>>{};
    // Subtasks of a goal that are planned in a block of the goal.
    final goalSubs =
        _try(
          () => repos.goalSubtasks.forEvents([
            for (final e in events)
              if (e.goalId != null && !e.allDay) e.id,
          ]),
        ) ??
        const <String, List<GoalSubtaskItem>>{};
    // The blocks with a linked note (their meeting note), in one query.
    final noted = withMeetingNote(events.where((e) => !e.allDay));
    for (final e in events) {
      if (e.allDay) continue;
      final tid = e.taskId;
      final task = tid == null
          ? null
          : tasks.putIfAbsent(tid, () => _try(() => repos.tasks.get(tid)));
      final rows = task != null
          ? taskSubs.putIfAbsent(
              task.id,
              () => [
                for (final s in subtasks(task.id))
                  if (s.status != TaskStatus.cancelled)
                    BlockSubtask(id: s.id, title: s.title, isDone: s.isDone),
              ],
            )
          : [
              // The ones from the goal first, in the order of the goal.
              for (final s in goalSubs[e.id] ?? const <GoalSubtaskItem>[])
                BlockSubtask(
                  id: s.id,
                  title: s.title,
                  isDone: s.isDone,
                  fromGoal: true,
                ),
              for (final s in blockSubs[e.id] ?? const <BlockSubtaskItem>[])
                BlockSubtask(id: s.id, title: s.title, isDone: s.isDone),
            ];
      final day = e.start.day;
      if (!days.contains(day)) continue;
      final end = e.end.day == day ? e.end.minute : 1440;
      final taskColor = task == null || task.color.isEmpty ? null : task.color;
      out.add(
        PlannerBlock(
          id: e.id,
          title: task?.title ?? e.title,
          summary: task?.summary ?? '',
          day: day,
          startMinute: e.start.minute,
          endMinute: max(end, e.start.minute + 1),
          kind: e.kind,
          taskId: e.taskId,
          isDone: e.goalId != null || e.isDeadline
              ? e.doneAt != null
              : (task?.isDone ?? false),
          color: taskColor ?? e.color,
          isRecurring: e.seriesId != null,
          hasNote: noted.contains(e.id),
          priority: task?.priority ?? 0,
          goalId: e.goalId,
          isDeadline: e.isDeadline,
          subtasks: rows,
        ),
      );
    }
    return out;
  }

  /// A click on a block. A click on a task block also opens that task in the
  /// panel at the right, and a click on a goal block opens the goal panel.
  /// With [extend] the click adds or removes a block and leaves the panel
  /// alone.
  void selectBlock(PlannerBlock block, {required bool extend}) {
    if (extend) {
      final next = {..._selection};
      if (!next.remove(block.id)) next.add(block.id);
      selection = next;
      return;
    }
    selection = {block.id};
    final taskId = block.taskId;
    if (taskId != null) {
      selectedTaskId = taskId;
    } else if (block.isGoalBlock) {
      openGoalPanel(block.id);
    } else if (block.kind != EventKind.block) {
      final e = event(block.id);
      if (e != null) editEvent(e);
    }
  }

  List<EventItem> allDayEvents(DayRange days) =>
      eventItems(days).where((e) => e.allDay).toList();

  /// Open tasks for this day, then this week, then the inbox, that have no
  /// block on [day].
  List<TaskItem> unscheduled(DayKey day) {
    final scheduled = {
      for (final b in _blockedTaskIds(DayRange.single(day))) b.task,
    };
    List<TaskItem> open(List<TaskItem>? list) => _sorted(
      (list ?? const <TaskItem>[]).where(
        (t) =>
            t.status == TaskStatus.open &&
            t.parentId == null &&
            !scheduled.contains(t.id),
      ),
      _byPriority,
    );
    return [
      ...open(_try(() => repos.tasks.forDay(day))),
      ...open(_try(() => repos.tasks.forWeek(day.weekStart()))),
      ...open(_try(() => repos.tasks.inbox())),
    ];
  }

  /// Open tasks planned for each day that have no block on that day: the
  /// sticky notes under the day numbers.
  Map<DayKey, List<TaskItem>> timeless(List<DayKey> days) {
    if (days.isEmpty) return {};
    final first = days.reduce((a, b) => a < b ? a : b);
    final last = days.reduce((a, b) => a > b ? a : b);
    final blocked = {
      for (final b in _blockedTaskIds(DayRange(first, last)))
        '${b.day.string}|${b.task}',
    };
    final tasks = (_try(() => repos.tasks.inRange(first, last)) ?? const [])
        .where((t) {
          final day = t.planDate;
          return t.status == TaskStatus.open &&
              t.bucket == TaskBucket.day &&
              day != null &&
              !blocked.contains('${day.string}|${t.id}');
        });
    final out = {for (final day in days) day: <TaskItem>[]};
    for (final t in _sorted(tasks, _byPriority)) {
      out[t.planDate]?.add(t);
    }
    return out;
  }

  /// Which task has a block on which day, for the days in the range. A
  /// worked record of "Reorganise rest of day" (a task block with `doneAt`)
  /// does not count: the rest of that task is still to plan.
  List<({DayKey day, String task})> _blockedTaskIds(DayRange days) =>
      _try(
        () => repos.db.query(
          'SELECT DISTINCT substr(start, 1, 10), task_id FROM events '
          'WHERE task_id IS NOT NULL AND start >= ? AND start < ? '
          'AND (done_at IS NULL OR goal_id IS NOT NULL OR is_deadline = 1)',
          [
            '${days.first.string}T00:00',
            '${days.last.adding(days: 1).string}T00:00',
          ],
          (r) => (day: DayKey(r.text(0)), task: r.text(1)),
        ),
      ) ??
      const [];

  /// Open tasks with a title that contains [text], not yet blocked on [day].
  /// For the "schedule existing" hint.
  List<TaskItem> matchingTasks(String text, {required DayKey on}) {
    final q = trimSpaces(text).toLowerCase();
    if (q.runes.length < 2) return [];
    return unscheduled(on)
        .where((t) => t.title.toLowerCase().contains(q))
        .take(3)
        .toList();
  }

  /// Minutes of open time and planned time for a day's header.
  ({int planned, int free, int done, int total}) dayTotals(
    DayKey day, {
    required List<PlannerBlock> blocks,
    required int workStart,
    required int workEnd,
  }) {
    final dayBlocks = blocks.where((b) => b.day == day).toList();
    final minutes = <int>{
      for (final b in dayBlocks)
        for (var i = b.startMinute; i < b.endMinute; i++) i,
    };
    final busyInWork = minutes
        .where((m) => m >= workStart && m < workEnd)
        .length;
    final withTask = dayBlocks.where((b) => b.isTaskBlock).toList();
    return (
      planned: minutes.length,
      free: max(0, workEnd - workStart - busyInWork),
      done: withTask.where((b) => b.isDone).length,
      total: withTask.length,
    );
  }

  // Writing from the planner

  EventItem blockEvent(
    TaskItem task, {
    required DayKey day,
    required int start,
    required int end,
  }) => EventItem(
    title: task.title,
    start: WallTime(day: day, minute: start),
    end: WallTime(day: day, minute: end),
    kind: EventKind.block,
    taskId: task.id,
    color: 'accent',
  );

  /// A task moved onto a day: bucket day, plan date set.
  TaskItem planned(TaskItem task, {required DayKey on}) =>
      task.copyWith(bucket: TaskBucket.day, planDate: on, planWeek: null);

  /// Adds the removal of the time blocks of a task to [into], so a task that
  /// is put on a day or time has one block only. [except] is the id of a
  /// block that stays.
  void removeBlocks(String taskId, {String? except, required Mutation into}) {
    for (final b in blocksOfTask(taskId)) {
      if (b.id != except) into.events.add((before: b, after: null));
    }
  }

  /// New task and block together, a plain event, or an activity: reserved
  /// time with no task. [asActivity] wins over [asEvent].
  void createFromDraft({
    required String title,
    required DayKey day,
    required int start,
    required int end,
    required bool asEvent,
    bool asActivity = false,
  }) {
    final name = title.trim();
    if (name.isEmpty) return;
    final m = Mutation('New Block');
    if (asEvent || asActivity) {
      final e = EventItem(
        title: name,
        start: WallTime(day: day, minute: start),
        end: WallTime(day: day, minute: end),
        kind: asActivity ? EventKind.activity : EventKind.event,
      );
      m.events.add((before: null, after: e));
    } else {
      final t = TaskItem(
        title: name,
        bucket: TaskBucket.day,
        planDate: day,
        estimateMin: end - start,
      );
      m.tasks.add((before: null, after: t));
      m.events.add((
        before: null,
        after: blockEvent(t, day: day, start: start, end: end),
      ));
    }
    final id = m.events.first.after?.id;
    if (commit(m) && id != null) selection = {id};
  }

  /// Puts an existing task on the grid. Length is [length], or the task estimate.
  void schedule({
    required String taskId,
    required DayKey day,
    required int start,
    int? length,
  }) {
    final t = task(taskId);
    if (t == null) return;
    final len = PlannerMath.blockLength(length ?? t.estimateMin);
    final s = PlannerMath.clampMove(start: start, length: len);
    final m = Mutation('Schedule Task');
    m.tasks.add((before: t, after: planned(t, on: day)));
    // One block only: the old time is gone.
    removeBlocks(t.id, into: m);
    final e = blockEvent(t, day: day, start: s, end: s + len);
    m.events.add((before: null, after: e));
    if (commit(m)) selection = {e.id};
  }

  /// First free gap for a task: from now (today) or from work start (other days).
  void fit({
    required String taskId,
    required DayKey day,
    required int workStart,
    required int workEnd,
    required int step,
  }) {
    final t = task(taskId);
    if (t == null) return;
    final len = PlannerMath.blockLength(t.estimateMin);
    // Its own block is about to go.
    final busy = [
      for (final b in blocks(DayRange.single(day)))
        if (b.taskId != taskId) b.span,
    ];
    final from = day == clockToday ? max(workStart, nowMinute()) : workStart;
    final slot = PlannerMath.firstFreeSlot(
      length: len,
      busy: busy,
      from: from,
      until: 1440,
      step: step,
    );
    if (slot != null) {
      schedule(taskId: taskId, day: day, start: slot, length: len);
    } else {
      showToast('No free gap of ${PlannerMath.duration(len)} on this day.');
    }
  }

  /// The plan for "Plan my day": each unscheduled task gets a free
  /// working-hours slot, by priority.
  List<PlanStep> planMyDayPreview({
    required DayKey day,
    required int workStart,
    required int workEnd,
    required int step,
  }) {
    final busy = [for (final b in blocks(DayRange.single(day))) b.span];
    final from = PlannerMath.snap(
      day == clockToday ? max(workStart, nowMinute()) : workStart,
      step: step,
    );
    final out = <PlanStep>[];
    for (final t in unscheduled(day)) {
      final len = PlannerMath.blockLength(t.estimateMin);
      final slot = PlannerMath.firstFreeSlot(
        length: len,
        busy: busy,
        from: from,
        until: workEnd,
        step: step,
      );
      if (slot == null) continue;
      busy.add(Span(id: t.id, start: slot, end: slot + len));
      out.add((task: t, start: slot));
    }
    return out;
  }

  void applyPlan(List<PlanStep> plan, {required DayKey day}) {
    final m = Mutation('Plan My Day');
    for (final p in plan) {
      m.tasks.add((before: p.task, after: planned(p.task, on: day)));
      removeBlocks(p.task.id, into: m);
      m.events.add((
        before: null,
        after: blockEvent(
          p.task,
          day: day,
          start: p.start,
          end: p.start + PlannerMath.blockLength(p.task.estimateMin),
        ),
      ));
    }
    commit(m);
  }

  /// Moves and resizes. With [ripple], later overlapping blocks on the same day
  /// are pushed down. Returns how many other blocks were pushed. A block of a
  /// repeating event does not change until the user says "This event only" or
  /// "All events".
  int applyEdits(
    List<BlockEdit> edits, {
    required bool ripple,
    required String name,
  }) {
    final all = [...edits];
    var pushed = 0;
    if (ripple && edits.isNotEmpty) {
      final primary = edits.first;
      // Occurrences of a repeating event stay where they are. Only stored
      // blocks are pushed.
      final others = [
        for (final b in blocks(DayRange.single(primary.day)))
          if (OccurrenceId.parse(b.id) == null &&
              !edits.any((e) => e.id == b.id))
            b.span,
      ];
      final moved = Span(
        id: primary.id,
        start: primary.start,
        end: primary.end,
      );
      for (final s in PlannerMath.ripple(moved: moved, others: others)) {
        all.add(
          BlockEdit(id: s.id, day: primary.day, start: s.start, end: s.end),
        );
        pushed += 1;
      }
    }
    final m = Mutation(name);
    final repeating = <OccurrenceEdit>[];
    for (final edit in all) {
      final old = event(edit.id);
      if (old == null) continue;
      final changed = draft(old).copyWith(
        start: WallTime(day: edit.day, minute: edit.start),
        end: WallTime(day: edit.day, minute: edit.end),
      );
      if (OccurrenceId.parse(edit.id) != null) {
        if (changed != draft(old)) repeating.add((old: old, changed: changed));
        continue;
      }
      if (changed == old) continue;
      m.events.add((before: old, after: changed));
      final tid = old.taskId;
      final t = tid != null && edit.day != old.start.day ? task(tid) : null;
      if (t != null) m.tasks.add((before: t, after: planned(t, on: edit.day)));
    }
    if (commit(m) && pushed > 0) {
      showToast('Pushed $pushed block${pushed == 1 ? '' : 's'}');
    }
    changeOccurrences(
      repeating,
      verb: name.startsWith('Resize') ? 'Resize' : 'Move',
      name: name,
    );
    return pushed;
  }

  void rename({required String blockId, required String to}) {
    final name = to.trim();
    final old = event(blockId);
    if (name.isEmpty || old == null) return;
    if (OccurrenceId.parse(blockId) != null) {
      changeOccurrences(
        [(old: old, changed: draft(old).copyWith(title: name))],
        verb: 'Rename',
        name: 'Rename',
      );
      return;
    }
    final m = Mutation('Rename');
    m.events.add((before: old, after: old.copyWith(title: name)));
    final tid = old.taskId;
    final t = tid == null ? null : task(tid);
    if (t != null) m.tasks.add((before: t, after: t.copyWith(title: name)));
    commit(m);
  }

  void setDuration({required List<String> blockIds, required int minutes}) {
    _edit(
      blockIds,
      verb: 'Change',
      name: 'Change Duration',
      (e) => e.copyWith(
        end: WallTime(
          day: e.start.day,
          minute: min(1440, e.start.minute + minutes),
        ),
      ),
    );
  }

  void setColor({required List<String> blockIds, required String name}) {
    _edit(
      blockIds,
      verb: 'Change',
      name: 'Change Colour',
      (e) => e.copyWith(color: name),
    );
  }

  /// Applies [change] to each block. Stored blocks change at once. Blocks of a
  /// repeating event ask first.
  void _edit(
    List<String> ids,
    EventItem Function(EventItem e) change, {
    required String verb,
    required String name,
  }) {
    final m = Mutation(name);
    final repeating = <OccurrenceEdit>[];
    for (final id in ids) {
      final old = event(id);
      if (old == null) continue;
      final changed = change(draft(old));
      if (OccurrenceId.parse(id) != null) {
        repeating.add((old: old, changed: changed));
      } else {
        m.events.add((before: old, after: changed));
      }
    }
    commit(m);
    changeOccurrences(repeating, verb: verb, name: name);
  }

  /// Removes blocks. The task stays and goes back to the unscheduled list. A
  /// block of a repeating event asks first: this day only, or the whole series.
  void deleteBlocks(List<String> ids, {String name = 'Delete Block'}) {
    final m = Mutation(name);
    final repeating = <EventItem>[];
    for (final id in ids) {
      final old = event(id);
      if (old == null) continue;
      if (OccurrenceId.parse(id) != null) {
        repeating.add(old);
      } else {
        m.events.add((before: old, after: null));
      }
    }
    if (commit(m)) selection = _selection.difference(ids.toSet());
    if (repeating.isEmpty) return;
    askScope('Delete', (scope) {
      final all = Mutation(name);
      final seenSeries = <String>{};
      for (final old in repeating) {
        final p = OccurrenceId.parse(old.id);
        if (scope == RecurringScope.all &&
            p != null &&
            !seenSeries.add(p.series)) {
          continue;
        }
        all.append(deletion(old, scope: scope, name: name));
      }
      if (commit(all)) selection = _selection.difference(ids.toSet());
    });
  }

  void duplicate({required List<String> blockIds}) {
    final m = Mutation('Duplicate');
    final newIds = <String>{};
    for (final id in blockIds) {
      final old = event(id);
      if (old == null) continue;
      if (old.seriesId != null) {
        showToast('A repeating event cannot be copied here yet.');
        continue;
      }
      final len = old.end.minute - old.start.minute;
      final s = PlannerMath.clampMove(start: old.end.minute, length: len);
      // A copy of a done goal block is planned, so it is not counted done twice.
      final copy = old.copyWith(
        id: newId(),
        doneAt: null,
        start: WallTime(day: old.start.day, minute: s),
        end: WallTime(day: old.start.day, minute: s + len),
      );
      m.events.add((before: null, after: copy));
      newIds.add(copy.id);
    }
    if (commit(m)) selection = newIds;
  }

  void split({required String blockId}) {
    final old = event(blockId);
    if (old == null) return;
    if (old.seriesId != null) {
      showToast('A repeating event cannot be split.');
      return;
    }
    final len = old.end.minute - old.start.minute;
    const half = PlannerMath.minLength;
    if (len < 2 * half) {
      showToast('Block is too short to split.');
      return;
    }
    final mid = max(
      old.start.minute + half,
      min(
        old.end.minute - half,
        PlannerMath.snap(old.start.minute + len ~/ 2, step: PlannerMath.step),
      ),
    );
    final at = WallTime(day: old.start.day, minute: mid);
    final m = Mutation('Split Block');
    m.events.add((before: old, after: old.copyWith(end: at)));
    m.events.add((before: null, after: old.copyWith(id: newId(), start: at)));
    commit(m);
  }

  int? nextFreeSlot({
    required DayKey day,
    required int length,
    required int workStart,
    required int step,
  }) => PlannerMath.firstFreeSlot(
    length: length,
    busy: [for (final b in blocks(DayRange.single(day))) b.span],
    from: day == clockToday ? max(nowMinute(), 0) : workStart,
    until: 1440,
    step: step,
  );

  // Reorganise rest of day

  /// The open tasks and goal blocks of today for "Reorganise rest of day",
  /// with the time that is taken, now and the sleep line.
  /// [now] is the minute to plan from (by default the clock).
  ReplanInput replanInput({int? now}) => _replanSources(now: now).input;

  _ReplanSources _replanSources({int? now}) {
    final day = clockToday;
    final events = <EventItem>[];
    final fixed = <Span>[];
    for (final e in eventItems(DayRange.single(day))) {
      if (e.allDay) continue;
      if (e.start.day == day) {
        events.add(e);
      } else if (e.start.day < day) {
        // It began on an earlier day and still runs today: busy, not moved.
        final end = e.end.day == day ? e.end.minute : PlannerMath.dayEnd;
        if (end > 0) fixed.add(Span(id: e.id, start: 0, end: end));
      }
    }
    final found = <String, TaskItem?>{};
    final tasks = <String, TaskItem>{};
    final taskBlocks = <String, List<EventItem>>{};
    final goalBlocks = <String, EventItem>{};
    for (final e in events) {
      final open =
          e.doneAt == null &&
          !e.isDeadline &&
          e.seriesId == null &&
          e.recurrence == null &&
          OccurrenceId.parse(e.id) == null;
      final tid = e.taskId;
      if (open && tid != null) {
        final t = found.putIfAbsent(tid, () => task(tid));
        if (t != null && t.status == TaskStatus.open) {
          tasks[tid] = t;
          (taskBlocks[tid] ??= []).add(e);
          continue;
        }
      } else if (open && e.goalId != null) {
        goalBlocks[e.id] = e;
        continue;
      }
      fixed.add(_daySpan(e, day));
    }
    for (final t in timeless([day])[day] ?? const <TaskItem>[]) {
      tasks.putIfAbsent(t.id, () => t);
    }
    final items = [
      for (final t in tasks.values)
        _replanTaskItem(t, [
          for (final e in taskBlocks[t.id] ?? const <EventItem>[])
            _daySpan(e, day),
        ]),
      for (final e in goalBlocks.values)
        ReplanItem(
          id: e.id,
          // The time tells two blocks of one goal apart.
          title:
              '${goal(e.goalId!)?.title ?? e.title} · '
              '${PlannerMath.clock(e.start.minute)}',
          group: ReplanGroup.goal,
          base: _daySpan(e, day).length,
          blocks: [_daySpan(e, day)],
        ),
    ];
    return (
      input: ReplanInput(
        day: day,
        items: items,
        fixed: fixed,
        now: now ?? nowMinute(),
        until: dayMarker(DayMarkerKind.sleep, day) ?? PlannerMath.dayEnd,
      ),
      tasks: tasks,
      taskBlocks: taskBlocks,
      goalBlocks: goalBlocks,
      events: events,
    );
  }

  /// The minutes of [e] on [day]: an event that runs past midnight ends at
  /// the end of the day.
  Span _daySpan(EventItem e, DayKey day) => Span(
    id: e.id,
    start: e.start.minute,
    end: e.end.day == day ? e.end.minute : PlannerMath.dayEnd,
  );

  /// A task with its open blocks of today. With no block, its estimate is
  /// the length.
  ReplanItem _replanTaskItem(TaskItem t, List<Span> blocks) => ReplanItem(
    id: t.id,
    title: t.title,
    group: (t.due ?? '').isEmpty ? ReplanGroup.task : ReplanGroup.deadline,
    base: blocks.isEmpty
        ? t.estimateMin
        : blocks.fold(0, (sum, b) => sum + b.length),
    blocks: blocks,
  );

  /// Puts the open tasks and goal blocks of today after now (see
  /// [ReplanRules.plan]). [pct] is how much of each is done, by item id. A
  /// task at 100% is checked off, a goal block at 100% ticked. A part done
  /// keeps its worked part as a done record and gets a block for the rest.
  /// What does not fit before the sleep line goes back to today's list. One
  /// undo step. [now] is the minute the sheet planned from, so Apply does
  /// what the sheet showed (by default the clock).
  void applyReplan(Map<String, int> pct, {int? now}) {
    final src = _replanSources(now: now);
    if (src.input.from >= PlannerMath.dayEnd) return;
    final steps = ReplanRules.plan(src.input, pct);
    if (steps.isEmpty) return;
    final day = src.input.day;
    final stamp = clockStamp();
    final m = Mutation('Reorganise Day');
    final gone = <String>{};
    WallTime wall(int minute) => WallTime(day: day, minute: minute);
    void put(EventItem old, EventItem? after) {
      if (after == old) return;
      m.events.add((before: old, after: after));
      if (after == null) gone.add(old.id);
    }

    for (final s in steps) {
      final at = s.placedAt;
      final kept = {for (final k in s.kept) k.id: k};
      if (s.item.isGoal) {
        final e = src.goalBlocks[s.item.id]!;
        if (s.done) {
          put(e, e.copyWith(doneAt: stamp));
          continue;
        }
        final worked = kept[e.id];
        if (worked == null) {
          // Nothing done: the block moves, or goes when it does not fit.
          put(
            e,
            at == null
                ? null
                : e.copyWith(start: wall(at), end: wall(at + s.remaining)),
          );
          continue;
        }
        // The block becomes the done record of the worked part. Its open
        // subtasks go with the rest, or back to the goal.
        put(
          e,
          e.copyWith(
            start: wall(worked.start),
            end: wall(worked.end),
            doneAt: stamp,
          ),
        );
        final rest = at == null
            ? null
            : e.copyWith(
                id: newId(),
                doneAt: null,
                start: wall(at),
                end: wall(at + s.remaining),
              );
        if (rest != null) m.events.add((before: null, after: rest));
        for (final sub in plannedGoalSubtasks(e.id)) {
          if (sub.isDone) continue;
          m.goalSubtasks.add((
            before: sub,
            after: sub.copyWith(eventId: rest?.id),
          ));
        }
        if (rest == null) continue;
        for (final sub in blockSubtasks(e.id)) {
          if (sub.isDone) continue;
          m.blockSubtasks.add((
            before: sub,
            after: sub.copyWith(eventId: rest.id),
          ));
        }
        continue;
      }

      final t = src.tasks[s.item.id]!;
      final open = src.taskBlocks[t.id] ?? const <EventItem>[];
      if (s.done) {
        _completeTaskInto(t, m);
        continue;
      }
      var next = planned(t, on: day);
      if (s.pct > 0) next = next.copyWith(estimateMin: s.remaining);
      if (next != t) m.tasks.add((before: t, after: next));
      if (at == null) {
        // Back to today's list: no block today, worked ones too. A day of
        // a repeating event stays.
        for (final e in src.events) {
          if (e.taskId == t.id &&
              e.seriesId == null &&
              OccurrenceId.parse(e.id) == null) {
            put(e, null);
          }
        }
        continue;
      }
      if (kept.isEmpty) {
        // The first block moves and takes the length of the rest.
        final first = open.firstOrNull;
        if (first == null) {
          m.events.add((
            before: null,
            after: blockEvent(t, day: day, start: at, end: at + s.remaining),
          ));
        } else {
          put(
            first,
            first.copyWith(start: wall(at), end: wall(at + s.remaining)),
          );
        }
        for (final e in open.skip(1)) {
          put(e, null);
        }
        continue;
      }
      // The worked part stays as a done record (the task stays open), and a
      // new block of the task holds the rest.
      for (final e in open) {
        final k = kept[e.id];
        put(
          e,
          k == null
              ? null
              : e.copyWith(
                  start: wall(k.start),
                  end: wall(k.end),
                  doneAt: stamp,
                ),
        );
      }
      m.events.add((
        before: null,
        after: blockEvent(
          t,
          day: day,
          start: at,
          end: at + s.remaining,
        ).copyWith(color: open.first.color),
      ));
    }

    if (commit(m) && gone.isNotEmpty) {
      selection = _selection.difference(gone);
    }
    final placed = steps.where((s) => s.placedAt != null).length;
    final done = steps.where((s) => s.done).length;
    final missed = steps.where((s) => s.overflow).length;
    showToast(
      [
        if (placed > 0) 'Placed $placed',
        if (done > 0) '$done done',
        if (missed > 0) '$missed did not fit',
      ].join(' · '),
    );
  }
}
