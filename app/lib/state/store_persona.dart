part of 'app_store.dart';

/// The persona: its skills, the rewards on tasks and goals, and the log of
/// earned points. Ticking a task or a goal block done pays the points of its
/// reward; un-ticking takes them back. Every change is one undo step.
extension AppStorePersona on AppStore {
  String get personaName {
    final name = _try(() => repos.settings.get(PersonaRules.nameKey));
    return name == null || name.isEmpty ? PersonaRules.defaultName : name;
  }

  /// An empty name gives the default name back.
  void renamePersona(String name) {
    final clean = PersonaRules.cleanName(name);
    final before = _try(() => repos.settings.get(PersonaRules.nameKey));
    final after = clean.isEmpty ? null : clean;
    if (before == after) return;
    commit(
      Mutation('Rename Persona')
        ..settings.add((
          key: PersonaRules.nameKey,
          before: before,
          after: after,
        )),
    );
  }

  // The days

  /// The key of the span of the day bars in the settings of this device.
  static const daySpanKey = 'persona.daySpan';

  /// How many good, okay and rough days are in [span], from the moods of
  /// the daily notes.
  DayCounts dayCounts(DaySpan span) {
    final range = span.range(clockToday);
    final counts = _try(
      () => repos.notes.moodCounts(from: range?.first, to: range?.last),
    );
    return counts == null ? DayCounts.empty : DayCounts.from(counts);
  }

  /// Which days the bars count. This month at first.
  DaySpan get daySpan => DaySpan.fromName(prefs.getString(daySpanKey));

  void setDaySpan(DaySpan span) {
    if (span == daySpan) return;
    prefs.set(daySpanKey, span.name);
    _changed();
  }

  /// The mood of today's daily note.
  Mood? get todayMood => Mood.fromValue(existingDailyNote(clockToday)?.mood);

  /// Sets the mood of today. The same mood again clears it. Today's note is
  /// made when there is none.
  void setTodayMood(Mood mood) => setMood(dailyNote(clockToday).id, mood);

  /// All skills, hidden ones too, in list order.
  List<SkillItem> get skills => _try(() => repos.skills.all()) ?? const [];

  /// The skills with a bar on the Persona screen.
  List<SkillItem> get visibleSkills => [
    for (final s in skills)
      if (!s.hidden) s,
  ];

  /// The points of each skill. A skill with no points has no entry.
  Map<String, int> get skillPoints =>
      _try(() => repos.earnings.pointsBySkill()) ?? const {};

  SkillLevel skillLevel(String skillId) =>
      SkillLevel.of(skillPoints[skillId] ?? 0);

  /// The level of the persona, from the points of all skills.
  SkillLevel get personaLevel =>
      SkillLevel.persona(skillPoints.values.fold(0, (a, b) => a + b));

  /// The newest lines of the log first.
  List<EarningItem> recentEarnings({int limit = 20}) =>
      _try(() => repos.earnings.recent(limit: limit)) ?? const [];

  /// Adds a skill at the end of the list. Gives its id, or null when the
  /// name is empty.
  String? addSkill(String name) {
    final clean = PersonaRules.cleanName(name);
    if (clean.isEmpty) return null;
    final last = skills.fold<double>(0, (m, s) => max(m, s.sort));
    final skill = SkillItem(name: clean, sort: last + 1);
    final m = Mutation('New Skill')..skills.add((before: null, after: skill));
    return commit(m) ? skill.id : null;
  }

  void renameSkill(String id, String name) {
    final clean = PersonaRules.cleanName(name);
    final old = _try(() => repos.skills.get(id));
    if (old == null || clean.isEmpty || clean == old.name) return;
    commit(
      Mutation('Rename Skill')
        ..skills.add((before: old, after: old.copyWith(name: clean))),
    );
  }

  /// A hidden skill keeps its points and still earns from its rewards.
  void setSkillHidden(String id, {required bool hidden}) {
    final old = _try(() => repos.skills.get(id));
    if (old == null || old.hidden == hidden) return;
    commit(
      Mutation(hidden ? 'Hide Skill' : 'Show Skill')
        ..skills.add((before: old, after: old.copyWith(hidden: hidden))),
    );
  }

  List<RewardItem> taskRewards(String taskId) =>
      _try(() => repos.rewards.forTask(taskId)) ?? const [];

  List<RewardItem> goalRewards(String goalId) =>
      _try(() => repos.rewards.forGoal(goalId)) ?? const [];

  /// Sets how many points [skillId] gets when the task is ticked done. 0
  /// removes the skill from the reward. Points already earned stay.
  void setTaskReward({
    required String taskId,
    required String skillId,
    required int points,
  }) {
    if (task(taskId) == null) return;
    _setReward(
      RewardItem(
        id: PersonaRules.taskRewardId(taskId, skillId),
        taskId: taskId,
        skillId: skillId,
        points: points,
      ),
    );
  }

  /// Sets how many points per hour [skillId] gets for each goal block that
  /// is ticked done. 0 removes the skill from the reward.
  void setGoalReward({
    required String goalId,
    required String skillId,
    required int points,
  }) {
    if (goal(goalId) == null) return;
    _setReward(
      RewardItem(
        id: PersonaRules.goalRewardId(goalId, skillId),
        goalId: goalId,
        skillId: skillId,
        points: points,
      ),
    );
  }

  void _setReward(RewardItem wanted) {
    if (_try(() => repos.skills.get(wanted.skillId)) == null) return;
    final old = _try(() => repos.rewards.get(wanted.id));
    final RewardItem? next = wanted.points <= 0
        ? null
        : wanted.copyWith(points: PersonaRules.clampPoints(wanted.points));
    if (old == next) return;
    commit(
      Mutation(next == null ? 'Remove Reward' : 'Set Reward')
        ..rewards.add((before: old, after: next)),
    );
  }

  /// Deleting a task or a goal also deletes its rewards (the database does
  /// that). This puts them in the change, so undo brings them back.
  void _addRewardsOfDeletedOwners(Mutation m) {
    final tasks = [
      for (final t in m.tasks)
        if (t.after == null) ?t.before?.id,
    ];
    final goals = [
      for (final g in m.goals)
        if (g.after == null) ?g.before?.id,
    ];
    if (tasks.isEmpty && goals.isEmpty) return;
    final found = [
      ...?_try(() => repos.rewards.forTasks(tasks))?.values.expand((x) => x),
      ...?_try(() => repos.rewards.forGoals(goals))?.values.expand((x) => x),
    ];
    final listed = {for (final c in m.rewards) ?(c.before ?? c.after)?.id};
    for (final r in found) {
      if (listed.add(r.id)) m.rewards.add((before: r, after: null));
    }
  }

  /// Pays the points of a task or goal block that the change ticks done, and
  /// takes back the points of one it un-ticks. A deleted task or block keeps
  /// its points: they are a log.
  void _addEarnings(Mutation m) {
    final listed = {for (final c in m.earnings) ?(c.before ?? c.after)?.id};
    final now = clockStamp();
    void pay(
      EarningSource source,
      String id,
      String title,
      RewardItem r,
      int n,
    ) {
      if (n <= 0) return;
      final e = EarningItem(
        id: PersonaRules.earningId(source, id, r.skillId),
        skillId: r.skillId,
        points: n,
        source: source,
        sourceId: id,
        title: title,
        earnedAt: now,
      );
      if (listed.add(e.id)) m.earnings.add((before: null, after: e));
    }

    void takeBack(EarningSource source, String id) {
      for (final e
          in _try(() => repos.earnings.forSource(source, id)) ??
              const <EarningItem>[]) {
        if (listed.add(e.id)) m.earnings.add((before: e, after: null));
      }
    }

    final ticked = <TaskItem>[];
    for (final t in m.tasks) {
      final (before, after) = (t.before, t.after);
      if (before == null || after == null) continue;
      if (!before.isDone && after.isDone) ticked.add(after);
      if (before.isDone && !after.isDone) {
        takeBack(EarningSource.task, after.id);
      }
    }
    if (ticked.isNotEmpty) {
      final rewards =
          _try(() => repos.rewards.forTasks(ticked.map((t) => t.id))) ??
          const {};
      for (final t in ticked) {
        for (final r in rewards[t.id] ?? const <RewardItem>[]) {
          pay(EarningSource.task, t.id, t.title, r, r.points);
        }
      }
    }

    for (final e in m.events) {
      final (before, after) = (e.before, e.after);
      if (before == null || after == null) continue;
      final goalId = after.goalId;
      // A deleted goal empties the goal and the tick of its blocks: they keep
      // their points.
      if (goalId == null) continue;
      if (before.doneAt == null && after.doneAt != null) {
        final title = goal(goalId)?.title ?? after.title;
        for (final r in goalRewards(goalId)) {
          final n = PersonaRules.blockPoints(
            perHour: r.points,
            minutes: after.durationMinutes,
          );
          pay(EarningSource.goalBlock, after.id, title, r, n);
        }
      } else if (before.doneAt != null && after.doneAt == null) {
        takeBack(EarningSource.goalBlock, after.id);
      }
    }
  }

  /// Shows the first skill that the last change took to a new level.
  void _announceLevelUp(Map<String, int> before) {
    final after = skillPoints;
    for (final s in skills) {
      final was = SkillLevel.of(before[s.id] ?? 0).level;
      final now = SkillLevel.of(after[s.id] ?? 0).level;
      if (now > was) {
        levelUp = LevelUp(skillId: s.id, skillName: s.name, level: now);
        _levelUpTimer?.cancel();
        _levelUpTimer = Timer(const Duration(seconds: 4), () => levelUp = null);
        return;
      }
    }
  }

  /// The rewards of [old] for its next copy [nextId] (a repeating task).
  void _copyRewards(TaskItem old, String nextId, Mutation m) {
    for (final r in taskRewards(old.id)) {
      m.rewards.add((
        before: null,
        after: RewardItem(
          id: PersonaRules.taskRewardId(nextId, r.skillId),
          taskId: nextId,
          skillId: r.skillId,
          points: r.points,
        ),
      ));
    }
  }
}
