import '../core/model/day_key.dart';
import '../core/model/event.dart';
import '../core/model/ids.dart';
import '../core/model/task.dart';
import 'repos.dart';

/// A task that had time blocks yesterday and is still open, with those blocks.
class RollOverItem {
  const RollOverItem({required this.task, required this.blocks});

  final TaskItem task;
  final List<EventItem> blocks;

  String get id => task.id;

  @override
  bool operator ==(Object other) =>
      other is RollOverItem &&
      other.task == task &&
      sameList(other.blocks, blocks);

  @override
  int get hashCode => Object.hash(task, Object.hashAll(blocks));
}

/// The end-of-day card (PLAN §5.1.7): "3 things from yesterday — Move to
/// today / Leave". Only blocks that start yesterday count. The answer is kept
/// per day in the `settings` table.
abstract final class RollOver {
  static const handledKey = 'rollover.handled';

  /// Open tasks with a block that starts on the day before [today], in the
  /// order of their first block.
  static List<RollOverItem> items(Repos r, {required DayKey today}) {
    final yesterday = today.adding(days: -1);
    final byTask = <String, List<EventItem>>{};
    for (final b in r.events.inRange(yesterday, yesterday)) {
      final id = b.taskId;
      if (b.kind != EventKind.block || id == null || b.start.day != yesterday) {
        continue;
      }
      (byTask[id] ??= []).add(b);
    }
    return [
      for (final MapEntry(key: id, value: blocks) in byTask.entries)
        if (r.tasks.get(id) case final task?
            when task.status == TaskStatus.open)
          RollOverItem(task: task, blocks: blocks),
    ];
  }

  /// True once the person answered the card on [today] ("Move" or "Leave").
  static bool isHandled(Repos r, {required DayKey today}) =>
      r.settings.get(handledKey) == today.string;

  static void markHandled(Repos r, {required DayKey today}) =>
      r.settings.set(handledKey, today.string);
}
