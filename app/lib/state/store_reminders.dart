part of 'app_store.dart';

/// Reminders before events and due times (PLAN §5.6). `ReminderPlanner` has the
/// rules. This file reads the data, sends the list to the notification centre,
/// and opens what the user clicks.
extension AppStoreReminders on AppStore {
  WallTime reminderNow() =>
      clockOverride ?? WallTime(day: DayKey.today(), minute: nowMinute());

  /// The reminders for the coming days, from the data now.
  List<Reminder> buildReminders() {
    final now = reminderNow();
    final events = eventItems(
      DayRange(now.day, now.day.adding(days: AppStore.reminderDays)),
    );
    final finished = <String>{};
    for (final id in {for (final e in events) ?e.taskId}) {
      final t = task(id);
      if (t != null && t.status != TaskStatus.open) finished.add(id);
    }
    return ReminderPlanner.plan(
      events: events,
      dueTasks: _try(repos.tasks.openWithTimedDue) ?? const [],
      finishedTaskIds: finished,
      now: now,
      lead: notifyLead,
    );
  }

  /// Makes the reminders again now. Does nothing until the user has allowed
  /// notifications.
  Future<void> refreshReminders() async {
    final status = await notifier.authorization();
    _notifyStatus = status;
    _changed();
    if (status != NotifyAuthorization.allowed) return;
    await notifier.replaceAll(notifyEnabled ? buildReminders() : const []);
  }

  /// Makes the reminders again after a short wait. A new call during the wait
  /// restarts the wait.
  void scheduleReminderRefresh() {
    if (notifier is NullNotifier || _disposed) return;
    final previous = reminderTask;
    _reminderSleep?.cancel();
    final sleep = _reminderSleep = _Sleep(reminderDelay);
    reminderTask = () async {
      // Never two refreshes at the same time.
      await previous;
      await sleep.done;
      if (!identical(sleep, _reminderSleep) || _disposed) return;
      await refreshReminders();
    }();
  }

  /// Runs from launch to quit. Makes the reminders again each hour, so the 14
  /// days move forward when no edit happens.
  Future<void> keepRemindersFresh() async {
    while (!_disposed) {
      await refreshReminders();
      final sleep = _freshSleep = _Sleep(const Duration(hours: 1));
      await sleep.done;
    }
  }

  Future<void> refreshNotifyStatus() async {
    _notifyStatus = await notifier.authorization();
    _changed();
  }

  /// Shows the system question. Grove asks after the welcome card, and from Settings.
  Future<void> askForNotifications() async {
    _notifyStatus = await notifier.requestAuthorization();
    _changed();
    await refreshReminders();
  }

  void setNotifyEnabled(bool on) {
    _notifyEnabled = on;
    prefs.set('notifications.enabled', on);
    _changed();
    scheduleReminderRefresh();
  }

  /// Only the choices on the list count (0, 5, 10, 15).
  void setNotifyLead(int minutes) {
    if (!ReminderPlanner.leadChoices.contains(minutes)) return;
    _notifyLead = minutes;
    prefs.set('notifications.lead', minutes);
    _changed();
    scheduleReminderRefresh();
  }

  /// A click on a notification: open the item on its day.
  void openFromNotification({required DayKey day, required ItemRef ref}) {
    open(ref);
    // Also when the item is gone: the day still opens.
    showDay(day);
  }
}
