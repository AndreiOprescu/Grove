part of 'app_store.dart';

/// Check box lines in notes and the tasks they make (PLAN §5.5 items 1 and 7).
/// A line and its task are tied by the hidden `⟦t:ID⟧` at the end of the line.
extension AppStoreNoteTasks on AppStore {
  /// Where a task made from a line of this note goes when the line names no day.
  TaskPlacement placementFor(Note note) {
    final date = note.date;
    if (date == null) return TaskPlacement.inbox;
    return switch (note.kind) {
      NoteKind.daily => TaskPlacement.day(date),
      NoteKind.weekly => TaskPlacement.week(date),
      NoteKind.note => TaskPlacement.inbox,
    };
  }

  /// The notes field of a task that came from [note]. It is a link back to the note.
  String originOf(Note note) =>
      'From ${ReferenceParser.mention(title: note.title, id: note.id)}';

  /// Brings the tasks in line with the saved text of a note.
  /// - A box that was ticked or cleared sets the task done or open.
  /// - An open box with words and no mark makes a task, and the mark is added
  ///   to the line. A box with an `@date` is left alone. "Add to planner"
  ///   makes its task. This needs [creating]. Pass it only when the user is
  ///   done typing, or half-typed words become tasks.
  ///
  /// Returns how many tasks it made. The saved text changes when it made some,
  /// so show it again.
  int syncNoteTasks(String noteId, {bool creating = true}) {
    final saved = note(noteId);
    if (saved == null) return 0;
    for (final box in NoteParser.checkboxes(saved.body)) {
      final id = box.taskId;
      if (id == null) continue;
      final t = task(id);
      if (t == null || t.isDone == box.checked) continue;
      toggleDone(taskId: id);
    }
    // Finishing a task can change the text of notes. Read this one again.
    final old = creating ? note(noteId) : null;
    if (old == null) return 0;

    var body = old.body;
    final change = Mutation('New Task from Note');
    var made = 0;
    for (final box in NoteParser.checkboxes(old.body)) {
      if (box.taskId != null || box.checked) continue;
      // A box with an @date waits for "Add to planner". A task made now would
      // keep the token in its title.
      if (AtDateParser.find(box.text) != null) continue;
      final q = quickAddChange(
        box.text,
        placement: placementFor(old),
        notes: originOf(old),
      );
      if (q == null) continue;
      // Each task is read from the database before it is saved, so they all
      // get the same sort. Keep their order.
      final first = q.change.tasks[0];
      q.change.tasks[0] = (
        before: first.before,
        after: first.after?.copyWith(sort: q.task.sort + made),
      );
      change.append(q.change);
      body = NoteParser.addingMarker(body, line: box.line, taskId: q.task.id);
      made += 1;
    }
    if (made == 0) return 0;
    change.notes.add((before: old, after: old.copyWith(body: body)));
    if (made > 1) change.name = 'New Tasks from Note';
    commit(change);
    return made;
  }

  /// Makes one task from words in a note. Returns its id. The editor writes
  /// the line.
  String? makeTask({required String from, required String inNote}) {
    final source = note(inNote);
    if (source == null) return null;
    final made = quickAddChange(
      from,
      placement: placementFor(source),
      notes: originOf(source),
    );
    if (made == null) return null;
    made.change.name = 'New Task from Note';
    if (!commit(made.change)) return null;
    showToast('Task made: ${made.task.title}');
    return made.task.id;
  }

  /// A task was finished or reopened, or came back by undo. The notes that
  /// hold its line show the same state. This runs inside the save, so it does
  /// not make an undo step of its own: undo changes the task, and the line
  /// follows.
  void _syncBoxes(TaskItem task) {
    for (final n in repos.notes.withTaskMarker(task.id)) {
      var body = n.body;
      for (final box in NoteParser.checkboxes(n.body)) {
        if (box.taskId == task.id && box.checked != task.isDone) {
          body = NoteParser.settingChecked(
            body,
            line: box.line,
            checked: task.isDone,
          );
        }
      }
      if (body != n.body) {
        repos.notes.save(n.copyWith(body: body), touch: false);
      }
    }
  }
}
