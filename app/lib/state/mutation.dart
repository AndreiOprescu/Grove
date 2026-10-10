import '../core/model/block_subtask.dart';
import '../core/model/day_key.dart';
import '../core/model/event.dart';
import '../core/model/goal.dart';
import '../core/model/note.dart';
import '../core/model/task.dart';

/// One item before and after a change. A null `before` means "created". A
/// null `after` means "deleted".
typedef Change<T> = ({T? before, T? after});

/// A day taken out of (`add`) or put back into a repeating event.
typedef ExdateChange = ({String eventId, DayKey day, bool add});

/// Tag names of a task before and after.
typedef TagChange = ({String taskId, List<String> before, List<String> after});

/// One undoable change. Holds the before and after state of every item it touches.
class Mutation {
  Mutation(this.name, {this.mergeKey, DateTime? at})
    : at = at ?? DateTime.now();

  String name;
  final List<Change<TaskItem>> tasks = [];
  final List<Change<EventItem>> events = [];
  final List<Change<Note>> notes = [];
  final List<Change<GoalItem>> goals = [];

  /// Subtasks of goal blocks.
  final List<Change<BlockSubtaskItem>> blockSubtasks = [];

  /// Undo does the opposite, in reverse order.
  final List<ExdateChange> exdates = [];

  /// Tags live in their own table, so they are tracked here.
  final List<TagChange> tags = [];

  /// Typing makes many small changes. Changes with the same key, close in
  /// time, become one undo step.
  String? mergeKey;
  DateTime at;

  bool get isEmpty =>
      tasks.isEmpty &&
      events.isEmpty &&
      notes.isEmpty &&
      goals.isEmpty &&
      blockSubtasks.isEmpty &&
      tags.isEmpty &&
      exdates.isEmpty;

  Mutation _copy() => Mutation(name, mergeKey: mergeKey, at: at)..append(this);

  /// Joins [next] (a later change of the same one task or note) into this one.
  /// Null when the two do not belong together.
  Mutation? merged(Mutation next) {
    final key = mergeKey;
    if (key == null ||
        key != next.mergeKey ||
        next.at.difference(at) >= const Duration(seconds: 60) ||
        events.isNotEmpty ||
        next.events.isNotEmpty ||
        goals.isNotEmpty ||
        next.goals.isNotEmpty ||
        blockSubtasks.isNotEmpty ||
        next.blockSubtasks.isNotEmpty ||
        tags.isNotEmpty ||
        next.tags.isNotEmpty ||
        exdates.isNotEmpty ||
        next.exdates.isNotEmpty) {
      return null;
    }
    final m = _copy();
    if (tasks.length == 1 &&
        next.tasks.length == 1 &&
        notes.isEmpty &&
        next.notes.isEmpty &&
        tasks[0].after?.id == next.tasks[0].before?.id) {
      m.tasks[0] = (before: tasks[0].before, after: next.tasks[0].after);
    } else if (notes.length == 1 &&
        next.notes.length == 1 &&
        tasks.isEmpty &&
        next.tasks.isEmpty &&
        notes[0].after?.id == next.notes[0].before?.id) {
      m.notes[0] = (before: notes[0].before, after: next.notes[0].after);
    } else {
      return null;
    }
    m.at = next.at;
    return m;
  }

  /// Adds everything in [other] to this change.
  void append(Mutation other) {
    tasks.addAll(other.tasks);
    events.addAll(other.events);
    notes.addAll(other.notes);
    goals.addAll(other.goals);
    blockSubtasks.addAll(other.blockSubtasks);
    tags.addAll(other.tags);
    exdates.addAll(other.exdates);
  }
}
