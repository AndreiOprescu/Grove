/// One subtask row in a block: a subtask of the block's task, or a subtask of
/// a goal block.
class BlockSubtask {
  const BlockSubtask({
    required this.id,
    required this.title,
    required this.isDone,
  });

  final String id;
  final String title;
  final bool isDone;

  @override
  bool operator ==(Object other) =>
      other is BlockSubtask &&
      other.id == id &&
      other.title == title &&
      other.isDone == isDone;

  @override
  int get hashCode => Object.hash(id, title, isDone);
}
