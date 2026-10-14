part of 'app_store.dart';

/// The goal panel: one goal block at the right of the planner and of Today.
/// It shows the goal, the time of the block, the week of the goal and the
/// goal subtasks planned in the block. A goal block holds only goal
/// subtasks (ADR 0002).
extension AppStoreGoalPanel on AppStore {
  /// Shows the goal block [blockId] in the goal panel. The task panel
  /// closes. Nothing happens for a block that is not a goal block.
  void openGoalPanel(String blockId) {
    if (event(blockId)?.goalId == null) return;
    selectedGoalBlockId = blockId;
  }

  void closeGoalPanel() => selectedGoalBlockId = null;

  /// "Edit goal": the panel closes and the Goals panel opens the editor of
  /// the goal.
  void editGoalFromPanel(String goalId) {
    if (goal(goalId) == null) return;
    closeGoalPanel();
    showLeftPane(LeftPane.goals);
    goalToEdit = goalId;
  }

  /// A subtask of a goal dragged onto empty time. A new block of the goal,
  /// one hour long, holds it. A subtask that was in another block moves.
  /// One undo step. False when the text is not an open subtask.
  bool dropGoalSubtaskOnPlanner({
    required String raw,
    required DayKey day,
    required int minute,
  }) {
    final id = DragPayload.goalSubtaskId(raw);
    final sub = id == null ? null : _try(() => repos.goalSubtasks.get(id));
    if (sub == null) return false;
    if (sub.isDone) {
      showToast('${sub.title} is done. Open it again to plan it.');
      return false;
    }
    final g = goal(sub.goalId);
    if (g == null) return false;
    final block = _newGoalBlock(
      g,
      day: day,
      start: minute,
      length: GoalRules.defaultBlockLength,
    );
    final m = Mutation('Plan Subtask')
      ..events.add((before: null, after: block))
      ..goalSubtasks.add((before: sub, after: sub.copyWith(eventId: block.id)));
    if (!commit(m)) return false;
    selection = {block.id};
    return true;
  }

  /// Adds a subtask at the end of the goal's list and plans it in the
  /// block. Gives the new id, or null when nothing was added. One undo step.
  String? addGoalSubtaskToBlock(String blockId, {required String title}) {
    final name = title.trim();
    if (name.isEmpty) return null;
    final goalId = event(blockId)?.goalId;
    if (goalId == null || goal(goalId) == null) return null;
    final split = _ownBlock(blockId, name: 'New Subtask');
    if (split == null) return null;
    final last = goalSubtasks(goalId).fold<double>(0, (m, s) => max(m, s.sort));
    final sub = GoalSubtaskItem(
      goalId: goalId,
      title: name,
      sort: last + 1,
      eventId: split.id,
    );
    final m = split.mutation..goalSubtasks.add((before: null, after: sub));
    if (!commit(m)) return null;
    _followBlock(from: blockId, to: split.id);
    return sub.id;
  }

  /// A block of the goal that can hold a subtask: a goal subtask points at
  /// one stored block. A day of a repeating block becomes its own block
  /// first (the series stays). The change for that (empty for a stored
  /// block) and the id of the block. Null when the block is gone.
  ({Mutation mutation, String id})? _ownBlock(
    String blockId, {
    required String name,
  }) {
    final block = event(blockId);
    if (block == null) return null;
    if (OccurrenceId.parse(blockId) == null) {
      return (mutation: Mutation(name), id: blockId);
    }
    return change(block, to: block, scope: RecurringScope.only, name: name);
  }

  /// A day of a series became its own block: the panel and the selection
  /// go with it.
  void _followBlock({required String from, required String to}) {
    if (from == to) return;
    if (_selectedGoalBlockId == from) selectedGoalBlockId = to;
    if (_selection.contains(from)) {
      selection = {..._selection.where((id) => id != from), to};
    }
  }

  /// A new block of the goal. It keeps the goal's title and colour (the
  /// accent colour when the goal has none).
  EventItem _newGoalBlock(
    GoalItem g, {
    required DayKey day,
    required int start,
    required int length,
  }) {
    final len = min(PlannerMath.dayEnd, PlannerMath.blockLength(length));
    final s = PlannerMath.clampMove(start: start, length: len);
    return EventItem(
      title: g.title,
      start: WallTime(day: day, minute: s),
      end: WallTime(day: day, minute: s + len),
      kind: EventKind.block,
      color: GoalRules.blockColor(g),
      goalId: g.id,
    );
  }

  /// Moves the block subtasks of goal blocks into their goals (ADR 0002).
  /// Each one keeps its id, name, tick and order, after the subtasks the
  /// goal has. On a single block it stays planned in that block. On a
  /// repeating block it is not planned: a goal subtask is in one block at
  /// most. The same ids on each device give the same rows, not copies.
  ///
  /// Runs at the start, after rows come in and after an import. It is not
  /// an undo step. A second run finds nothing to do.
  void _adoptBlockSubtasks() {
    final old = _try(() => repos.blockSubtasks.onGoalBlocks()) ?? const [];
    if (old.isEmpty) return;
    final blocks =
        _try(() => repos.events.byIds({for (final s in old) s.eventId})) ??
        const <String, EventItem>{};
    final last = <String, double>{};
    try {
      repos.db.transaction(() {
        for (final s in old) {
          final block = blocks[s.eventId];
          final goalId = block?.goalId;
          if (block == null || goalId == null) continue;
          // Another device can have moved it already.
          if (repos.goalSubtasks.get(s.id) == null) {
            final sort = (last[goalId] ??= repos.goalSubtasks
                .forGoal(goalId)
                .fold<double>(0, (m, x) => max(m, x.sort)));
            last[goalId] = sort + 1;
            repos.goalSubtasks.save(
              GoalSubtaskItem(
                id: s.id,
                goalId: goalId,
                title: s.title,
                doneAt: s.doneAt,
                sort: sort + 1,
                eventId: block.recurrence == null ? block.id : null,
                createdAt: s.createdAt,
              ),
            );
          }
          repos.blockSubtasks.delete(s.id);
        }
      });
    } on Exception catch (e) {
      _errorMessage = 'Could not move the subtasks of goal blocks: $e';
      return;
    }
    _revision += 1;
  }
}
