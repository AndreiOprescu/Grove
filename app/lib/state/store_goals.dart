part of 'app_store.dart';

/// Goals: repeating work with a weekly target of hours or sessions, and no
/// date. A goal is dragged into a day as a block. Every block is planned time
/// for the goal that week; a block ticked done is done time too. The goal
/// itself is never done: it stays for the next week. Progress is worked out
/// from the blocks each time, never stored. Every write is a single undo step.
extension AppStoreGoals on AppStore {
  // Reading

  /// The goals in list order. Archived goals only when asked.
  List<GoalItem> goals({bool includeArchived = false}) =>
      _try(() => repos.goals.all(includeArchived: includeArchived)) ?? const [];

  GoalItem? goal(String id) => _try(() => repos.goals.get(id));

  /// The planner's setting: does the week start on Sunday?
  bool get weekStartsSunday =>
      prefs.getBool('calendar.weekStartsSunday') ?? false;

  /// The goal's week: done and planned (done blocks included), and the weekly
  /// target. Minutes for an hours goal, blocks for a sessions goal. The week is
  /// the one that holds [weekOf], the same week the planner shows.
  /// [sundayFirst] defaults to the planner setting.
  GoalProgress goalProgress(
    String id, {
    required DayKey weekOf,
    bool? sundayFirst,
  }) {
    final g = goal(id);
    if (g == null) {
      return const GoalProgress(
        kind: GoalKind.hours,
        done: 0,
        planned: 0,
        target: 0,
      );
    }
    final week = GoalRules.week(
      weekOf,
      sundayFirst: sundayFirst ?? weekStartsSunday,
    );
    int tally({required bool doneOnly}) =>
        _try(
          () => switch (g.kind) {
            GoalKind.hours => repos.goals.minutes(
              id,
              from: week.first,
              to: week.last,
              doneOnly: doneOnly,
            ),
            GoalKind.sessions => repos.goals.sessions(
              id,
              from: week.first,
              to: week.last,
              doneOnly: doneOnly,
            ),
          },
        ) ??
        0;
    return GoalProgress(
      kind: g.kind,
      done: tally(doneOnly: true),
      planned: tally(doneOnly: false),
      target: GoalRules.target(g),
    );
  }

  // Writing

  /// Sort value that puts a new goal after every existing one.
  double _nextGoalSort() =>
      (_try(
            () => repos.db.queryOne(
              'SELECT COALESCE(MAX(sort), 0) FROM goals',
              const [],
              (r) => r.asDouble(0),
            ),
          ) ??
          0) +
      1;

  /// A new goal. [target] is in the kind's unit (minutes or sessions); null
  /// gives the default. Null when the title is empty.
  GoalItem? addGoal({
    required String title,
    GoalKind kind = GoalKind.hours,
    int? target,
  }) {
    final name = GoalRules.cleanTitle(title);
    if (name.isEmpty) return null;
    final value = GoalRules.clamp(
      target ?? GoalRules.defaultTargetFor(kind),
      kind: kind,
    );
    var g = GoalItem(title: name, sort: _nextGoalSort(), kind: kind);
    g = kind == GoalKind.hours
        ? g.copyWith(targetMin: value)
        : g.copyWith(targetCount: value);
    final m = Mutation('New Goal')..goals.add((before: null, after: g));
    return commit(m) ? g : null;
  }

  /// Changes the fields that are given. An empty title or a colour that is not
  /// one of the eight is ignored. Blocks that are already in the planner keep
  /// the title and colour they had. A new kind keeps the blocks and only
  /// changes what is counted.
  void updateGoal(
    String id, {
    String? title,
    String? notes,
    String? color,
    GoalKind? kind,
    int? targetMin,
    int? targetCount,
    bool? archived,
  }) {
    final old = goal(id);
    if (old == null) return;
    var g = old;
    if (title != null && GoalRules.cleanTitle(title).isNotEmpty) {
      g = g.copyWith(title: GoalRules.cleanTitle(title));
    }
    if (notes != null) g = g.copyWith(notes: notes);
    if (color != null && TaskColor.isValid(color)) g = g.copyWith(color: color);
    if (kind != null) g = g.copyWith(kind: kind);
    if (targetMin != null) {
      g = g.copyWith(targetMin: GoalRules.clampTarget(targetMin));
    }
    if (targetCount != null) {
      g = g.copyWith(targetCount: GoalRules.clampCount(targetCount));
    }
    if (archived != null) g = g.copyWith(archived: archived);
    if (g == old) return;
    commit(Mutation('Edit Goal')..goals.add((before: old, after: g)));
  }

  /// Deletes the goal. Its blocks stay in the planner as plain blocks. Undo
  /// brings both back.
  void deleteGoal(String id) {
    final old = goal(id);
    if (old == null) return;
    final m = Mutation('Delete Goal')..goals.add((before: old, after: null));
    for (final e
        in _try(() => repos.events.blocksForGoal(id)) ?? const <EventItem>[]) {
      m.events.add((before: e, after: e.copyWith(goalId: null, doneAt: null)));
    }
    commit(m);
  }

  /// Puts a block of the goal on the grid and selects it. It is a plain block
  /// with no task. It keeps the goal's title and colour (the accent colour
  /// when the goal has none). The goal stays, so more blocks can be added.
  void scheduleGoal({
    required String goalId,
    required DayKey day,
    required int start,
    int length = GoalRules.defaultBlockLength,
  }) {
    final g = goal(goalId);
    if (g == null) return;
    final len = min(PlannerMath.dayEnd, PlannerMath.blockLength(length));
    final s = PlannerMath.clampMove(start: start, length: len);
    final e = EventItem(
      title: g.title,
      start: WallTime(day: day, minute: s),
      end: WallTime(day: day, minute: s + len),
      kind: EventKind.block,
      color: GoalRules.blockColor(g),
      goalId: g.id,
    );
    final m = Mutation('Schedule Goal')..events.add((before: null, after: e));
    if (commit(m)) selection = {e.id};
  }

  /// A goal dragged onto the grid. [raw] is the dragged text, [minute] the
  /// snapped minute under the pointer. Adds a block of the default length.
  /// False when the text is not a goal or the goal is gone.
  bool dropGoalOnPlanner({
    required String raw,
    required DayKey day,
    required int minute,
  }) {
    final id = DragPayload.goalId(raw);
    if (id == null || goal(id) == null) return false;
    scheduleGoal(goalId: id, day: day, start: minute);
    return true;
  }

  /// Ticks a goal block done, or back to planned. A done block adds to the
  /// goal's done tally. One undo step.
  void toggleGoalBlockDone({required String eventId}) {
    final old = _try(() => repos.events.get(eventId));
    if (old == null || old.goalId == null) return;
    final changed = old.copyWith(
      doneAt: old.doneAt == null ? Stamp.now() : null,
    );
    final m = Mutation(
      changed.doneAt == null ? 'Reopen Goal Block' : 'Complete Goal Block',
    )..events.add((before: old, after: changed));
    commit(m);
  }
}
