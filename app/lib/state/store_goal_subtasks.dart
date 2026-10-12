part of 'app_store.dart';

/// Subtasks of a goal. They belong to the goal, so every block of the goal
/// has the same list. The subtasks of one block are another list
/// (`AppStoreBlockSubtasks`).
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
}
