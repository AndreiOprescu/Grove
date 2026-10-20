/// One subtask row in a block: a subtask of the block's task, or a subtask of
/// a goal block.
class BlockSubtask {
  const BlockSubtask({
    required this.id,
    required this.title,
    required this.isDone,
    this.fromGoal = false,
  });

  final String id;
  final String title;
  final bool isDone;

  /// True for a subtask of the goal that is planned in this block. False for
  /// a subtask of the block itself, and for a subtask of a task.
  final bool fromGoal;

  @override
  bool operator ==(Object other) =>
      other is BlockSubtask &&
      other.id == id &&
      other.title == title &&
      other.isDone == isDone &&
      other.fromGoal == fromGoal;

  @override
  int get hashCode => Object.hash(id, title, isDone, fromGoal);
}
