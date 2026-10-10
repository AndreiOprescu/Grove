part of 'app_store.dart';

/// One focus session: a count down to the end of a block.
class FocusSession {
  const FocusSession({
    required this.blockId,
    this.taskId,
    required this.title,
    required this.day,
    required this.start,
    required this.end,
    this.finished = false,
  });

  final String blockId;
  final String? taskId;
  final String title;
  final DayKey day;
  final DateTime start;
  final DateTime end;

  /// The time ran out. The card asks "Mark done?".
  final bool finished;

  FocusSession _finished() => FocusSession(
    blockId: blockId,
    taskId: taskId,
    title: title,
    day: day,
    start: start,
    end: end,
    finished: true,
  );

  @override
  bool operator ==(Object other) =>
      other is FocusSession &&
      other.blockId == blockId &&
      other.taskId == taskId &&
      other.title == title &&
      other.day == day &&
      other.start == start &&
      other.end == end &&
      other.finished == finished;

  @override
  int get hashCode =>
      Object.hash(blockId, taskId, title, day, start, end, finished);
}

/// Focus mode (PLAN §5.1.7). `FocusRules` has the arithmetic.
extension AppStoreFocus on AppStore {
  /// Starts the count down to the end of [block]. A running session is replaced.
  void startFocus(EventItem block) {
    final now = DateTime.now();
    if (!FocusRules.canStart(block, now: now)) {
      showToast('This block is over.');
      return;
    }
    final end = FocusRules.endDate(block.end);
    final f = FocusSession(
      blockId: block.id,
      taskId: block.taskId,
      title: block.title.isEmpty ? 'Focus' : block.title,
      day: block.start.day,
      start: now,
      end: end,
    );
    _focus = f;
    _changed();
    final taskId = f.taskId;
    final ending = FocusEnd(
      title: f.title,
      at: end,
      day: f.day,
      ref: taskId != null
          ? ItemRef(ItemType.task, taskId)
          : ItemRef(ItemType.event, f.blockId),
      taskId: taskId,
    );
    final previous = focusNotify;
    // The Settings switch for notifications covers this one too.
    final enabled = notifyEnabled;
    focusNotify = () async {
      await previous;
      if (enabled) {
        await notifier.scheduleFocusEnd(ending);
      } else {
        await notifier.cancelFocusEnd();
      }
    }();
  }

  /// Ends the session and takes the "time is up" notification away. The task
  /// stays as it is.
  void stopFocus() {
    if (_focus == null) return;
    _focus = null;
    _changed();
    final previous = focusNotify;
    focusNotify = () async {
      await previous;
      await notifier.cancelFocusEnd();
    }();
  }

  /// The count down reached zero. The card asks "Mark done?".
  void focusTimeUp() {
    final f = _focus;
    if (f == null) return;
    _focus = f._finished();
    _changed();
  }

  /// "Mark done": checks the task off (when the block has one) and ends the session.
  void markFocusDone() {
    final f = _focus;
    if (f == null) return;
    final id = f.taskId;
    if (id != null && task(id)?.status == TaskStatus.open) {
      toggleDone(taskId: id);
    }
    stopFocus();
  }

  /// The "Mark done" button on the notification.
  void focusDoneFromNotification(String taskId) {
    if (task(taskId)?.status == TaskStatus.open) toggleDone(taskId: taskId);
    if (_focus?.taskId == taskId) stopFocus();
  }
}
