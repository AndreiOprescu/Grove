part of 'app_store.dart';

final _tagEdges = RegExp(r'^[#\s]+|[#\s]+$');

/// Task writes. Every one is a single undo step.
extension AppStoreTasks on AppStore {
  // Reading

  /// Open top-level tasks that live in [placement], in the order they are shown.
  List<TaskItem> openTasks(TaskPlacement placement) {
    final list = _try(
      () => switch (placement) {
        InboxPlacement() => repos.tasks.inbox(),
        SomedayPlacement() => repos.tasks.someday(),
        DayPlacement(:final day) => repos.tasks.forDay(day),
        WeekPlacement(:final day) => repos.tasks.forWeek(day.weekStart()),
      },
    );
    return [
      for (final t in list ?? const <TaskItem>[])
        if (t.status == TaskStatus.open || _lingering.contains(t.id)) t,
    ];
  }

  /// Every open top-level task, in list order. A task that was just checked
  /// off is already done in the database, so it is put back in its place while
  /// it lingers.
  List<TaskItem> _openTopLevelWithLingering() {
    final list = [...?_try(repos.tasks.openTopLevel)];
    for (final id in _lingering) {
      if (list.any((t) => t.id == id)) continue;
      final t = task(id);
      if (t == null || t.parentId != null || t.status == TaskStatus.cancelled) {
        continue;
      }
      final i = list.indexWhere(
        (x) =>
            x.sort > t.sort ||
            (x.sort == t.sort && x.createdAt.compareTo(t.createdAt) > 0),
      );
      list.insert(i < 0 ? list.length : i, t);
    }
    return list;
  }

  /// Every open top-level task, split for the Planner screen's list (see
  /// `AllTasksRules`).
  ({List<TaskItem> noDay, List<TaskItem> byDay}) allOpenTasks() =>
      AllTasksRules.split(_openTopLevelWithLingering());

  /// The tasks for the side list that feeds the calendar: overdue ones first,
  /// then the ones with no day. A task planned for today or later is on the
  /// calendar already, so it is in neither list.
  ({List<TaskItem> overdue, List<TaskItem> unscheduled}) unscheduledTasks({
    DayKey? today,
  }) => AllTasksRules.unscheduled(
    _openTopLevelWithLingering(),
    today: today ?? DayKey.today(),
  );

  List<TaskItem> subtasks(String parentId) =>
      _try(() => repos.tasks.subtasks(parentId)) ?? const [];

  List<String> tagNames(String taskId) =>
      _try(() => repos.tags.tagsForTask(taskId)) ?? const [];

  List<EventItem> blocksOfTask(String taskId) =>
      _try(() => repos.events.blocksForTask(taskId)) ?? const [];

  /// Sort value that puts a new task after every existing one.
  double _nextSort() =>
      (_try(
            () => repos.db.queryOne(
              'SELECT COALESCE(MAX(sort), 0) FROM tasks',
              const [],
              (r) => r.asDouble(0),
            ),
          ) ??
          0) +
      1;

  TaskItem placed(TaskItem task, TaskPlacement placement) =>
      switch (placement) {
        InboxPlacement() => task.copyWith(
          bucket: TaskBucket.inbox,
          planDate: null,
          planWeek: null,
        ),
        SomedayPlacement() => task.copyWith(
          bucket: TaskBucket.someday,
          planDate: null,
          planWeek: null,
        ),
        DayPlacement(:final day) => task.copyWith(
          bucket: TaskBucket.day,
          planDate: day,
          planWeek: null,
        ),
        WeekPlacement(:final day) => task.copyWith(
          bucket: TaskBucket.week,
          planDate: null,
          planWeek: day.weekStart(),
        ),
      };

  // Quick add

  /// Makes a task from one line of text ("Call mum tomorrow 6pm for 20m #home
  /// !2"). [placement] is used when the text names no date. A clock time on a
  /// day makes a time block too.
  TaskItem? quickAdd(
    String text, {
    TaskPlacement placement = TaskPlacement.inbox,
  }) {
    final made = quickAddChange(text, placement: placement);
    if (made == null) return null;
    return commit(made.change) ? made.task : null;
  }

  /// The change that [quickAdd] would commit, and the task in it. Null when
  /// the text has no words for a title. [notes] is the text of the task's
  /// notes field.
  ({TaskItem task, Mutation change})? quickAddChange(
    String text, {
    required TaskPlacement placement,
    String notes = '',
  }) {
    final lists = _try(repos.lists.all) ?? const <ListItem>[];
    final today = DayKey.today();
    final r = QuickAddParser(
      today: today,
      lists: [for (final l in lists) l.name],
    ).parse(text);
    if (r.title.trim().isEmpty) return null;

    var t = TaskItem(
      title: r.title,
      notes: notes,
      priority: r.priority,
      due: r.due,
      estimateMin: r.blockMinutes,
      recurrence: r.recurrence,
      sort: _nextSort(),
    );
    t = placed(t, switch (r.bucket) {
      TaskBucket.day => TaskPlacement.day(r.planDate ?? today),
      TaskBucket.week => TaskPlacement.week(r.planWeek ?? today),
      TaskBucket.someday => TaskPlacement.someday,
      TaskBucket.inbox => placement,
    });
    final listName = r.listName;
    if (listName != null) {
      final wanted = listName.toLowerCase();
      for (final l in lists) {
        if (l.name.toLowerCase() == wanted) {
          t = t.copyWith(listId: l.id);
          break;
        }
      }
    }

    final m = Mutation('New Task')..tasks.add((before: null, after: t));
    if (r.tags.isNotEmpty) {
      m.tags.add((taskId: t.id, before: const [], after: r.tags));
    }
    final day = t.planDate, start = r.startMinute, end = r.blockEnd;
    if (t.bucket == TaskBucket.day &&
        day != null &&
        start != null &&
        end != null) {
      m.events.add((
        before: null,
        after: blockEvent(t, day: day, start: start, end: end),
      ));
    }
    return (task: t, change: m);
  }

  // Completing

  /// Checks a task off, or reopens it. Completing a repeating task also makes
  /// its next copy. With [linger], a task that was just checked off stays in
  /// the open list for 0.7 s, so the check burst can play.
  void toggleDone({required String taskId, bool linger = false}) {
    final old = task(taskId);
    if (old == null) return;
    if (linger && !old.isDone) _holdInList(taskId);
    final t = old.isDone
        ? old.copyWith(status: TaskStatus.open, completedAt: null)
        : old.copyWith(status: TaskStatus.done, completedAt: Stamp.now());
    final m = Mutation(t.isDone ? 'Complete Task' : 'Reopen Task');
    m.tasks.add((before: old, after: t));
    final rule = old.recurrence;
    if (t.isDone && rule != null) _appendNextInstance(old, rule, m);
    commit(m);
  }

  void _holdInList(String id) {
    lingering = {..._lingering, id};
    late final Timer timer;
    timer = Timer(const Duration(milliseconds: 700), () {
      _lingerTimers.remove(timer);
      lingering = {..._lingering}..remove(id);
    });
    _lingerTimers.add(timer);
  }

  /// The next copy of a repeating task: new id, next date, subtasks unchecked,
  /// one block copied. The date never lands in the past, even when the task is
  /// finished late.
  void _appendNextInstance(TaskItem old, RecurrenceRule rule, Mutation m) {
    DayKey later(DayKey a, DayKey b) => a > b ? a : b;
    final today = DayKey.today();
    final TaskPlacement placement;
    if (old.bucket == TaskBucket.week) {
      final base = later(old.planWeek ?? today, today.weekStart());
      final n = RecurrenceEngine.next(after: base, rule: rule);
      if (n == null) return;
      placement = TaskPlacement.week(
        later(n.weekStart(), base.adding(days: 7)),
      );
    } else {
      final base = later(old.planDate ?? today, today);
      final n = RecurrenceEngine.next(after: base, rule: rule);
      if (n == null) return;
      placement = TaskPlacement.day(n);
    }
    if (placement is DayPlacement &&
        openTasks(
          placement,
        ).any((t) => t.title == old.title && t.recurrence == old.recurrence)) {
      return;
    }

    final next = placed(old, placement).copyWith(
      id: newId(),
      status: TaskStatus.open,
      completedAt: null,
      createdAt: Stamp.now(),
      sort: _nextSort(),
    );
    m.tasks.add((before: null, after: next));
    final names = tagNames(old.id);
    if (names.isNotEmpty) {
      m.tags.add((taskId: next.id, before: const [], after: names));
    }

    for (final (i, sub) in subtasks(old.id).indexed) {
      m.tasks.add((
        before: null,
        after: sub.copyWith(
          id: newId(),
          parentId: next.id,
          status: TaskStatus.open,
          completedAt: null,
          createdAt: Stamp.now(),
          sort: next.sort + (i + 1) / 1000,
        ),
      ));
    }
    final blocks = blocksOfTask(old.id);
    if (blocks.length == 1 && placement is DayPlacement) {
      final b = blocks.first;
      m.events.add((
        before: null,
        after: blockEvent(
          next,
          day: placement.day,
          start: b.start.minute,
          end: b.end.minute,
        ),
      ));
    }
  }

  // Editing

  /// Adds a subtask under [parentId]. Returns its id, or null when the name is
  /// empty or the parent is gone.
  String? addSubtask({required String to, required String title}) {
    final name = title.trim();
    if (name.isEmpty || task(to) == null) return null;
    final sub = TaskItem(title: name, parentId: to, sort: _nextSort());
    commit(Mutation('New Subtask')..tasks.add((before: null, after: sub)));
    return sub.id;
  }

  /// Changes any fields of a task in one undo step. Does nothing when [change]
  /// leaves the task as it was.
  void editTask(
    String id,
    TaskItem Function(TaskItem t) change, {
    required String name,
  }) {
    final old = task(id);
    if (old == null) return;
    final t = change(old);
    if (t == old) return;
    commit(Mutation(name)..tasks.add((before: old, after: t)));
  }

  /// Gives a task one of the eight colours, or none (""). A name that is not
  /// on the list is ignored.
  void setTaskColor(String id, String name) {
    if (!TaskColor.isValid(name)) return;
    editTask(id, name: 'Set Colour', (t) => t.copyWith(color: name));
  }

  /// Saves the body of a task. Many saves in a row while typing make one undo step.
  void setNotes(String id, String text, {DateTime? now}) {
    final old = task(id);
    if (old == null || old.notes == text) return;
    final m = Mutation('Edit Notes', mergeKey: 'notes:$id', at: now)
      ..tasks.add((before: old, after: old.copyWith(notes: text)));
    commit(m);
  }

  /// Saves the short description of a task. Many saves in a row while typing
  /// make one undo step.
  void setSummary(String id, String text, {DateTime? now}) {
    final clean = SummaryText.clean(text);
    final old = task(id);
    if (old == null || old.summary == clean) return;
    final m = Mutation(
      'Edit Short Description',
      mergeKey: 'summary:$id',
      at: now,
    )..tasks.add((before: old, after: old.copyWith(summary: clean)));
    commit(m);
  }

  void setTags({required String taskId, required List<String> to}) {
    final seen = <String>{};
    final clean = [
      for (final raw in to)
        if (raw.replaceAll(_tagEdges, '') case final name
            when name.isNotEmpty && seen.add(name.toLowerCase()))
          name,
    ];
    final old = tagNames(taskId);
    final sorted = [...clean]
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (task(taskId) == null || sameList(sorted, old)) return;
    commit(
      Mutation('Edit Tags')
        ..tags.add((taskId: taskId, before: old, after: clean)),
    );
  }

  // Moving and ordering

  /// Moves a task to [to], in front of [before] (or last when null). Its
  /// blocks follow it to a new day, and are removed when it leaves the
  /// calendar. With [keepingBlocks] false (a drop on a day), the blocks are
  /// removed instead: the task is planned for the day with no time.
  void moveTask(
    String id, {
    required TaskPlacement to,
    String? before,
    bool keepingBlocks = true,
  }) {
    final old = task(id);
    if (old == null || old.parentId != null) return;
    final shown = openTasks(to);
    final siblings = [
      for (final t in shown)
        if (t.id != id) t,
    ];
    final found = before == null
        ? -1
        : siblings.indexWhere((t) => t.id == before);
    final index = found < 0 ? siblings.length : found;

    var t = placed(old, to);
    final m = Mutation('Move Task');

    final ids = [for (final s in siblings) s.id]..insert(index, id);
    if (t.bucket == old.bucket &&
        t.planDate == old.planDate &&
        t.planWeek == old.planWeek &&
        sameList(ids, [for (final s in shown) s.id])) {
      // Nothing moves in the list. A drop that clears the time still has
      // blocks to remove.
      if (!keepingBlocks) {
        removeBlocks(id, into: m);
        commit(m);
      }
      return;
    }

    final prev = index > 0 ? siblings[index - 1] : null;
    final next = index < siblings.length ? siblings[index] : null;
    if (prev != null && next != null) {
      if (next.sort - prev.sort > 1e-6) {
        t = t.copyWith(sort: (prev.sort + next.sort) / 2);
      } else {
        // The neighbours have no gap between them (equal values): number the
        // whole list again.
        siblings.insert(index, t);
        for (final (i, s) in siblings.indexed) {
          final sort = (i + 1).toDouble();
          if (s.id == id) {
            t = t.copyWith(sort: sort);
          } else if (sort != s.sort) {
            m.tasks.add((before: s, after: s.copyWith(sort: sort)));
          }
        }
      }
    } else if (prev != null) {
      t = t.copyWith(sort: prev.sort + 1);
    } else if (next != null) {
      t = t.copyWith(sort: next.sort - 1);
    }
    m.tasks.add((before: old, after: t));

    if (!keepingBlocks) {
      removeBlocks(id, into: m);
    } else {
      for (final b in blocksOfTask(id)) {
        if (to is DayPlacement) {
          final d = to.day;
          if (b.start.day == d) continue;
          m.events.add((
            before: b,
            after: b.copyWith(
              start: WallTime(day: d, minute: b.start.minute),
              end: WallTime(day: d, minute: b.end.minute),
            ),
          ));
        } else {
          m.events.add((before: b, after: null));
        }
      }
    }
    commit(m);
  }

  // Deleting

  /// Deletes a task with its subtasks and time blocks. Undo brings everything
  /// back, tags included. The right panel closes when it shows one of the
  /// deleted tasks; their blocks leave the selection.
  void deleteTask(String id) {
    final m = taskDeletion(id, name: 'Delete Task');
    if (m == null) return;
    final goneTasks = {for (final t in m.tasks) ?t.before?.id};
    final goneBlocks = {for (final e in m.events) ?e.before?.id};
    commit(m);
    if (goneTasks.contains(_selectedTaskId)) selectedTaskId = null;
    selection = _selection.difference(goneBlocks);
  }

  /// The change that deletes a task, its subtasks, their blocks and tags. Null
  /// when the task is gone.
  Mutation? taskDeletion(String id, {required String name}) {
    final root = task(id);
    if (root == null) return null;
    final all = [root];
    final queue = [root.id];
    while (queue.isNotEmpty) {
      final kids = subtasks(queue.removeLast());
      all.addAll(kids);
      queue.addAll(kids.map((k) => k.id));
    }
    final m = Mutation(name);
    for (final t in all) {
      m.tasks.add((before: t, after: null));
      for (final b in blocksOfTask(t.id)) {
        m.events.add((before: b, after: null));
      }
      final names = tagNames(t.id);
      if (names.isNotEmpty) {
        m.tags.add((taskId: t.id, before: names, after: const []));
      }
    }
    return m;
  }
}
