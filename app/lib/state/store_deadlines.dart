part of 'app_store.dart';

/// Deadlines: plain events with `isDeadline` set. They are due at their end,
/// show in the Deadlines panel and are ticked done there. A tick gives no
/// persona points: only goal blocks and tasks do. Every write is a single
/// undo step.
extension AppStoreDeadlines on AppStore {
  /// Every deadline, in the panel's three parts, for the time now.
  DeadlineSections get deadlineSections => DeadlineRules.sections(
    _try(() => repos.events.deadlines()) ?? const [],
    now: clockNow(),
  );

  /// Ticks a deadline done at the time now, or takes the tick away. The time
  /// of the tick says how early or late it was done. One undo step.
  void toggleDeadlineDone(String eventId) {
    final old = _try(() => repos.events.get(eventId));
    if (old == null || !old.isDeadline) return;
    final changed = old.copyWith(
      doneAt: old.doneAt == null ? clockStamp() : null,
    );
    final m = Mutation(
      changed.doneAt == null ? 'Reopen Deadline' : 'Complete Deadline',
    )..events.add((before: old, after: changed));
    commit(m);
  }
}
