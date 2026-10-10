import '../core/model/day_key.dart';
import '../core/model/link.dart';
import '../core/services/reminder_planner.dart';

/// What the system says about notifications from Grove.
enum NotifyAuthorization { notAsked, allowed, denied }

/// The "time is up" notification of a focus session.
class FocusEnd {
  const FocusEnd({
    required this.title,
    required this.at,
    required this.day,
    required this.ref,
    this.taskId,
  });

  final String title;
  final DateTime at;
  final DayKey day;
  final ItemRef ref;

  /// Set when the block belongs to a task. The notification then has a
  /// "Mark done" button.
  final String? taskId;

  @override
  bool operator ==(Object other) =>
      other is FocusEnd &&
      other.title == title &&
      other.at == at &&
      other.day == day &&
      other.ref == ref &&
      other.taskId == taskId;

  @override
  int get hashCode => Object.hash(title, at, day, ref, taskId);

  @override
  String toString() => 'FocusEnd($title, $at, $day, $ref, $taskId)';
}

/// The door to the system notification centre. A test uses a fake one.
abstract class Notifier {
  Future<NotifyAuthorization> authorization();
  Future<NotifyAuthorization> requestAuthorization();

  /// Takes away every reminder Grove asked for before, and asks for these.
  Future<void> replaceAll(List<Reminder> reminders);

  /// Asks for the "time is up" notification of a focus session. It replaces
  /// the one before.
  Future<void> scheduleFocusEnd(FocusEnd end);
  Future<void> cancelFocusEnd();

  /// Set by the store. Called when the user clicks a notification.
  void Function(DayKey day, ItemRef ref)? onOpen;

  /// Set by the store. Called with the task id when the user taps "Mark done"
  /// on the focus notification.
  void Function(String taskId)? onFocusDone;
}

/// Does nothing. Used in tests and on a system with no notification centre.
class NullNotifier extends Notifier {
  @override
  Future<NotifyAuthorization> authorization() async =>
      NotifyAuthorization.notAsked;

  @override
  Future<NotifyAuthorization> requestAuthorization() async =>
      NotifyAuthorization.notAsked;

  @override
  Future<void> replaceAll(List<Reminder> reminders) async {}

  @override
  Future<void> scheduleFocusEnd(FocusEnd end) async {}

  @override
  Future<void> cancelFocusEnd() async {}
}
