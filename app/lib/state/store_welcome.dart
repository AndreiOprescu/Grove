part of 'app_store.dart';

/// The welcome card and the sample tasks (PLAN §9). `FirstRun` has the rules.
extension AppStoreWelcome on AppStore {
  /// "Got it": hides the card. The sample tasks stay.
  void dismissWelcome() {
    FirstRun.dismissWelcome(repos);
    _welcomeVisible = false;
    _changed();
    _askForNotificationsAfterWelcome();
  }

  /// "Remove samples": deletes the sample tasks that are still there, as one
  /// undo step.
  void removeSamples() {
    final m = Mutation('Remove Samples');
    for (final id in FirstRun.sampleTaskIds(repos)) {
      final one = taskDeletion(id, name: 'Remove Samples');
      if (one != null) m.append(one);
    }
    commit(m);
    FirstRun.forgetSamples(repos);
    _welcomeVisible = false;
    _changed();
    _askForNotificationsAfterWelcome();
  }

  /// Grove asks the system for notifications after the welcome card, not at
  /// once (PLAN §5.6). It asks only when the system has not been asked before.
  void _askForNotificationsAfterWelcome() {
    welcomeAsk = () async {
      await refreshNotifyStatus();
      if (_notifyStatus == NotifyAuthorization.notAsked) {
        await askForNotifications();
      }
    }();
  }
}
