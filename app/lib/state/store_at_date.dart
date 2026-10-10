part of 'app_store.dart';

/// A line with `@fri 3pm` in a note goes to the planner (PLAN §5.5 item 2),
/// and a note dragged onto the planner (PLAN §5.5 item 8).
extension AppStoreAtDate on AppStore {
  /// Makes the event, or the task and its block, that the line asks for. One
  /// undo step.
  /// - A line with no check box makes an event: one hour long, or all day when
  ///   the token has no time.
  /// - An open check box makes a task and a block of half an hour. A task the
  ///   box already has is moved there.
  /// - Returns the text the line becomes, or null when the line cannot go (no
  ///   token, a ticked box, no words). The editor writes the text into the
  ///   note. It keeps the link to the new item.
  String? addToPlanner({required String line, required String inNote}) {
    final source = note(inNote);
    if (source == null) return null;
    final plan = AtDatePlanner.plan(
      line,
      noteDay: source.kind == NoteKind.daily ? source.date : null,
    );
    if (plan == null) return null;
    final Mutation change;
    final String text;
    if (plan.isTask) {
      final made = _taskChange(plan, source);
      if (made == null) return null;
      change = made.change;
      text = made.text;
    } else {
      final span = AtDatePlanner.span(
        plan,
        defaultMinutes: AtDatePlan.eventMinutes,
      );
      final event = EventItem(
        title: plan.title,
        start: WallTime(day: plan.day, minute: span?.start ?? 0),
        end: WallTime(day: plan.day, minute: span?.end ?? 0),
        allDay: span == null,
        notes: ReferenceParser.mention(title: source.title, id: source.id),
      );
      change = Mutation('Add to Planner')
        ..events.add((before: null, after: event));
      text = AtDatePlanner.eventLine(
        plan,
        mention: ReferenceParser.mention(title: event.title, id: event.id),
        when: AtDatePlanner.whenLabel(
          plan.day,
          start: span?.start,
          end: span?.end,
        ),
      );
    }
    if (!commit(change)) return null;
    showToast('Added to the planner: ${plan.title}');
    return text;
  }

  /// The task and block of a check box line, as one change, and the new text
  /// of the line.
  ({Mutation change, String text})? _taskChange(AtDatePlan plan, Note source) {
    final Mutation change;
    TaskItem task;
    final id = plan.taskId;
    final old = id == null ? null : this.task(id);
    if (old != null) {
      task = old;
      change = Mutation('Add to Planner')..tasks.add((before: old, after: old));
    } else {
      final made = quickAddChange(
        plan.title,
        placement: TaskPlacement.day(plan.day),
        notes: originOf(source),
      );
      if (made == null) return null;
      // Words in the title may have asked for a block. The token decides.
      made.change.events.clear();
      change = made.change..name = 'Add to Planner';
      task = made.task;
    }
    // A block that is already there keeps its length unless the token gives one.
    final blocks = blocksOfTask(task.id);
    final existing = blocks.isEmpty ? null : blocks.first;
    final asked = plan.durationMin;
    final length = asked != null
        ? max(5, asked)
        : existing?.durationMinutes ?? task.estimateMin;
    final span = AtDatePlanner.span(plan, defaultMinutes: length);
    task = planned(task, on: plan.day);
    if (span != null && (asked != null || existing == null)) {
      task = task.copyWith(estimateMin: span.end - span.start);
    }
    final last = change.tasks.length - 1;
    change.tasks[last] = (before: change.tasks[last].before, after: task);

    // One block only: the existing one is moved, any other is removed. A day
    // with no time leaves no block.
    removeBlocks(
      task.id,
      except: span == null ? null : existing?.id,
      into: change,
    );
    if (span != null) {
      if (existing != null) {
        change.events.add((
          before: existing,
          after: existing.copyWith(
            start: WallTime(day: plan.day, minute: span.start),
            end: WallTime(day: plan.day, minute: span.end),
          ),
        ));
      } else {
        change.events.add((
          before: null,
          after: blockEvent(
            task,
            day: plan.day,
            start: span.start,
            end: span.end,
          ),
        ));
      }
    }
    return (
      change: change,
      text: AtDatePlanner.taskLine(
        plan,
        taskId: task.id,
        when: AtDatePlanner.whenLabel(
          plan.day,
          start: span?.start,
          end: span?.end,
        ),
      ),
    );
  }

  /// Puts a note on a day and time: an event of half an hour, "📝 note title",
  /// with a link to the note in its notes. One undo step. Returns the event.
  /// Null when the note is gone.
  EventItem? addNoteToPlanner(
    String noteId, {
    required DayKey on,
    required int at,
  }) {
    final source = note(noteId);
    if (source == null) return null;
    const length = AtDatePlan.blockMinutes;
    final start = PlannerMath.clampMove(start: at, length: length);
    final name = source.title.trim();
    final event = EventItem(
      title: '📝 ${name.isEmpty ? 'Untitled' : name}',
      start: WallTime(day: on, minute: start),
      end: WallTime(day: on, minute: start + length),
      notes: ReferenceParser.mention(title: source.title, id: source.id),
    );
    final change = Mutation('Add Note to Planner')
      ..events.add((before: null, after: event));
    if (!commit(change)) return null;
    selection = {event.id};
    return event;
  }
}
