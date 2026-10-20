/// One notification Grove asks the system for.
class NoteRequest {
  const NoteRequest({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
    required this.at,
    this.donePayload,
  });

  final int id;
  final String title;
  final String body;

  /// What comes back when the user clicks the notification.
  final String payload;

  /// When it shows.
  final DateTime at;

  /// Set when the notification has a "Mark done" button. This text comes back
  /// in place of [payload] on a system that cannot say which button was
  /// clicked (Windows).
  final String? donePayload;
}

/// A notification the system still holds for later.
class PendingNote {
  const PendingNote({required this.id, this.title, this.body, this.payload});

  final int id;
  final String? title;
  final String? body;
  final String? payload;
}

/// A click on a notification, or on a button of it.
class NoteResponse {
  const NoteResponse({this.payload, this.actionId});

  final String? payload;
  final String? actionId;
}

/// The small part of the system notification centre that Grove uses. The real
/// one is `LocalNotificationsGateway`. A test uses a fake one.
abstract class NotificationGateway {
  /// Connects to the system. [onResponse] gets each click from now on.
  Future<void> start(void Function(NoteResponse response) onResponse);

  /// True when the system shows notifications from Grove now.
  Future<bool> permitted();

  /// Shows the system question when the system has one. True when the user
  /// allows notifications.
  Future<bool> requestPermission();

  Future<List<PendingNote>> pending();
  Future<void> schedule(NoteRequest request);

  /// Takes a notification away, also when it is on the screen.
  Future<void> cancel(int id);

  /// The click that started the app, or null.
  Future<NoteResponse?> launchResponse();
}
