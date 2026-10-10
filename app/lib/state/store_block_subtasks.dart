part of 'app_store.dart';

/// Subtasks of one goal block. They belong to the block (an event), so they
/// stay on that one instance and never on the other blocks of the goal.
extension AppStoreBlockSubtasks on AppStore {
  List<BlockSubtaskItem> blockSubtasks(String eventId) =>
      _try(() => repos.blockSubtasks.forEvent(eventId)) ?? const [];

  /// Adds a subtask at the end of the block's list. Only a goal block takes
  /// one. Gives the new id, or null when nothing was added.
  String? addBlockSubtask({required String to, required String title}) {
    final name = title.trim();
    if (name.isEmpty) return null;
    final block = _try(() => repos.events.get(to));
    if (block == null || block.goalId == null) return null;
    final last = blockSubtasks(to).fold<double>(0, (m, s) => max(m, s.sort));
    final sub = BlockSubtaskItem(eventId: to, title: name, sort: last + 1);
    final m = Mutation('New Subtask')
      ..blockSubtasks.add((before: null, after: sub));
    return commit(m) ? sub.id : null;
  }

  /// Ticks an open subtask, or opens a ticked one. The block itself does not
  /// change.
  void toggleBlockSubtask(String id) {
    final old = _try(() => repos.blockSubtasks.get(id));
    if (old == null) return;
    final next = old.copyWith(doneAt: old.isDone ? null : Stamp.now());
    final m = Mutation(old.isDone ? 'Reopen Subtask' : 'Complete Subtask')
      ..blockSubtasks.add((before: old, after: next));
    commit(m);
  }

  void renameBlockSubtask(String id, {required String to}) {
    final old = _try(() => repos.blockSubtasks.get(id));
    if (old == null) return;
    final name = SubtaskRules.renamed(to, from: old.title);
    if (name == null) return;
    final m = Mutation('Rename Subtask')
      ..blockSubtasks.add((before: old, after: old.copyWith(title: name)));
    commit(m);
  }

  void deleteBlockSubtask(String id) {
    final old = _try(() => repos.blockSubtasks.get(id));
    if (old == null) return;
    commit(
      Mutation('Delete Subtask')..blockSubtasks.add((before: old, after: null)),
    );
  }

  /// Opens the subtask editor of a block. A task block has the subtasks of
  /// its task, so it has no editor here. A plain block opens only when it
  /// still has subtasks: it was a goal block and its goal was deleted.
  void openBlockSubtasks(String eventId) {
    final block = _try(() => repos.events.get(eventId));
    if (block == null || block.taskId != null) return;
    if (block.goalId == null && blockSubtasks(eventId).isEmpty) return;
    editingBlockSubtasks = eventId;
  }

  void closeBlockSubtasks() => editingBlockSubtasks = null;
}
