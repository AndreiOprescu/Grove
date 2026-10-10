part of 'app_store.dart';

/// What a daily or weekly note shows beside its text: the day, the finished
/// tasks, the week review and the mood.
extension AppStoreDaily on AppStore {
  // The day

  /// Everything on [day], live from the database. See `DayRules.agenda`.
  List<AgendaRow> agenda(DayKey day) => DayRules.agenda(
    day: day,
    events: eventItems(DayRange.single(day)),
    dayTasks: _try(() => repos.tasks.forDay(day)) ?? const [],
    taskFor: task,
  );

  /// Tasks finished on [day], first to last.
  List<TaskItem> completedTasks(DayKey day) =>
      _try(() => repos.tasks.completedOn(day)) ?? const [];

  // The week

  WeekReview weekReview(DayKey monday) {
    final sunday = monday.adding(days: 6);
    return DayRules.review(
      monday: monday,
      done:
          _try(() => repos.tasks.completed(from: monday, to: sunday)) ??
          const [],
      openCandidates: [
        ...?_try(() => repos.tasks.inRange(monday, sunday)),
        ...?_try(() => repos.tasks.forWeek(monday)),
      ],
      events: eventItems(DayRange(monday, sunday)),
      taskFor: task,
    );
  }

  /// Writes the week summary under `## Review` of a weekly note. A summary
  /// that is there is replaced.
  void insertWeekSummary(String noteId) {
    final n = note(noteId);
    final monday = n?.date;
    if (n == null || n.kind != NoteKind.weekly || monday == null) return;
    final text = DayRules.insert(
      DayRules.summary(weekReview(monday)),
      into: n.body,
    );
    if (text == n.body) return;
    // Its own undo step. `setNoteBody` would join it to the typing before it.
    commit(
      Mutation('Insert Week Summary')
        ..notes.add((before: n, after: n.copyWith(body: text))),
    );
    showToast('Summary added to the note.');
  }

  // Mood

  /// Sets the mood of a daily note. The same mood again clears it.
  void setMood(String noteId, Mood mood) {
    final old = note(noteId);
    if (old == null || old.kind != NoteKind.daily) return;
    final n = old.copyWith(mood: old.mood == mood.value ? null : mood.value);
    commit(Mutation('Set Mood')..notes.add((before: old, after: n)));
  }
}
