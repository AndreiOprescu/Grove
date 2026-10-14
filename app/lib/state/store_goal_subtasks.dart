part of 'app_store.dart';

/// Subtasks of a goal. They belong to the goal, so every block of the goal
/// has the same list. The subtasks of one block are another list
/// (`AppStoreBlockSubtasks`).
///
/// A subtask of the goal can be planned in one block of the goal. It is
/// still one subtask of the goal: the block and the goal show the same row.
extension AppStoreGoalSubtasks on AppStore {
  List<GoalSubtaskItem> goalSubtasks(String goalId) =>
      _try(() => repos.goalSubtasks.forGoal(goalId)) ?? const [];

  /// The lists of many goals in one query, by goal id. A goal with no
  /// subtasks has no entry.
  Map<String, List<GoalSubtaskItem>> goalSubtasksOf(Iterable<String> goalIds) =>
      _try(() => repos.goalSubtasks.forGoals(goalIds)) ?? const {};

  /// Adds a subtask at the end of the goal's list. Gives the new id, or null
  /// when nothing was added.
  String? addGoalSubtask({required String to, required String title}) {
    final name = title.trim();
    if (name.isEmpty) return null;
    if (_try(() => repos.goals.get(to)) == null) return null;
    final last = goalSubtasks(to).fold<double>(0, (m, s) => max(m, s.sort));
    final sub = GoalSubtaskItem(goalId: to, title: name, sort: last + 1);
    final m = Mutation('New Subtask')
      ..goalSubtasks.add((before: null, after: sub));
    return commit(m) ? sub.id : null;
  }

  /// Ticks an open subtask, or opens a ticked one. No block changes.
  void toggleGoalSubtask(String id) {
    final old = _try(() => repos.goalSubtasks.get(id));
    if (old == null) return;
    final next = old.copyWith(doneAt: old.isDone ? null : Stamp.now());
    final m = Mutation(old.isDone ? 'Reopen Subtask' : 'Complete Subtask')
      ..goalSubtasks.add((before: old, after: next));
    commit(m);
  }

  void renameGoalSubtask(String id, {required String to}) {
    final old = _try(() => repos.goalSubtasks.get(id));
    if (old == null) return;
    final name = SubtaskRules.renamed(to, from: old.title);
    if (name == null) return;
    final m = Mutation('Rename Subtask')
      ..goalSubtasks.add((before: old, after: old.copyWith(title: name)));
    commit(m);
  }

  void deleteGoalSubtask(String id) {
    final old = _try(() => repos.goalSubtasks.get(id));
    if (old == null) return;
    commit(
      Mutation('Delete Subtask')..goalSubtasks.add((before: old, after: null)),
    );
  }

  // A subtask in a block of the goal

  /// The subtasks of the goal that are planned in this block, in the order
  /// of the goal's list.
  List<GoalSubtaskItem> plannedGoalSubtasks(String eventId) =>
      _try(() => repos.goalSubtasks.forEvents([eventId]))?[eventId] ?? const [];

  /// The subtasks that this block can take from its goal: the open ones
  /// that are in no block. Empty for a block with no goal.
  List<GoalSubtaskItem> freeGoalSubtasks(String eventId) {
    final goalId = _try(() => repos.events.get(eventId))?.goalId;
    if (goalId == null) return const [];
    return [
      for (final s in goalSubtasks(goalId))
        if (!s.isDone && !s.isPlanned) s,
    ];
  }

  /// The subtask, when this block can take it: the subtask is open, it is
  /// not in this block already, and the block is a block of its goal.
  GoalSubtaskItem? _plannable(String id, String blockId) {
    final sub = _try(() => repos.goalSubtasks.get(id));
    if (sub == null || sub.isDone || sub.eventId == blockId) return null;
    final block = _try(() => repos.events.get(blockId));
    return block != null && block.goalId == sub.goalId ? sub : null;
  }

  /// Plans an open subtask in a block of its goal. A subtask is in one block
  /// at most, so this takes it out of the block it was in. False when
  /// nothing changed. One undo step.
  bool assignGoalSubtask(String id, {required String to}) {
    final old = _plannable(id, to);
    if (old == null) return false;
    final m = Mutation('Plan Subtask')
      ..goalSubtasks.add((before: old, after: old.copyWith(eventId: to)));
    return commit(m);
  }

  /// Takes a subtask out of its block. It stays in the goal, open or done
  /// as it was.
  void unassignGoalSubtask(String id) {
    final old = _try(() => repos.goalSubtasks.get(id));
    if (old == null || !old.isPlanned) return;
    final m = Mutation('Unplan Subtask')
      ..goalSubtasks.add((before: old, after: old.copyWith(eventId: null)));
    commit(m);
  }

  /// True when a drop of the dragged text [raw] on this block plans a
  /// subtask there.
  bool canDropGoalSubtask({required String raw, required String blockId}) {
    final id = DragPayload.goalSubtaskId(raw);
    return id != null && _plannable(id, blockId) != null;
  }

  /// A subtask of a goal dragged onto a block. False when the text is not
  /// such a subtask, or the block is not a block of its goal.
  bool dropGoalSubtaskOnBlock({required String raw, required String blockId}) {
    final id = DragPayload.goalSubtaskId(raw);
    return id != null && assignGoalSubtask(id, to: blockId);
  }

  /// The mark of the block on each planned subtask, by subtask id: the day
  /// and the start of the block ("Tue 14:00"). A subtask in no block has no
  /// entry.
  Map<String, String> goalSubtaskMarks(Iterable<GoalSubtaskItem> subs) {
    final planned = [
      for (final s in subs)
        if (s.isPlanned) s,
    ];
    if (planned.isEmpty) return const {};
    final blocks =
        _try(() => repos.events.byIds({for (final s in planned) s.eventId!})) ??
        const <String, EventItem>{};
    final today = clockToday;
    return {
      for (final s in planned)
        if (blocks[s.eventId] case final block?)
          s.id: GoalSubtaskRules.planMark(block.start, today: today),
    };
  }
}
