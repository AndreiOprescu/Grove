part of 'app_store.dart';

/// The end-of-day card (PLAN §5.1.7). `RollOver` has the rules.
extension AppStoreRollOver on AppStore {
  /// The day the card is about. Uses the test clock when one is set.
  DayKey get _rollOverToday => reminderNow().day;

  /// What the card offers: open tasks that had a block yesterday. Empty once
  /// the person answered today.
  List<RollOverItem> rollOverItems() {
    final today = _rollOverToday;
    if (RollOver.isHandled(repos, today: today)) return const [];
    return _try(() => RollOver.items(repos, today: today)) ?? const [];
  }

  /// "Move to today": the tasks get today as their day and lose their blocks,
  /// so they show as sticky notes. One undo step.
  void moveRollOver() {
    final today = _rollOverToday;
    final m = Mutation('Move to Today');
    for (final item in rollOverItems()) {
      m.tasks.add((
        before: item.task,
        after: placed(item.task, TaskPlacement.day(today)),
      ));
      // Yesterday's and any other: it is a sticky note now.
      removeBlocks(item.task.id, into: m);
    }
    commit(m);
    RollOver.markHandled(repos, today: today);
    _bump();
  }

  /// "Leave": nothing changes. The card does not come back today.
  void leaveRollOver() {
    RollOver.markHandled(repos, today: _rollOverToday);
    _bump();
  }
}
