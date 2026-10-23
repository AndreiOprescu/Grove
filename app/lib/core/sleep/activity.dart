/// What a device says about its own use. Grove learns sleep times from these
/// (see `SleepNightRules`). Only times cross from the system; no app names.
enum ActivitySignal {
  /// The screen came on or the device was unlocked.
  useStart,

  /// The screen went off, the device was locked, or it went to sleep.
  useEnd,

  /// Grove began to listen (Mac only: it hears events only while it runs).
  recordStart,

  /// Grove stopped listening (Mac only).
  recordStop,
}

/// One thing the device did, at a local time.
class ActivityEvent {
  const ActivityEvent(this.at, this.signal);

  final DateTime at;
  final ActivitySignal signal;

  @override
  bool operator ==(Object other) =>
      other is ActivityEvent && other.at == at && other.signal == signal;

  @override
  int get hashCode => Object.hash(at, signal);

  @override
  String toString() => 'ActivityEvent(${signal.name}, $at)';
}

/// May Grove read the device's use history?
enum ActivityAccess {
  granted,

  /// The user must turn it on in the system settings (Android Usage access).
  needsGrant,

  /// This device cannot tell Grove anything.
  unsupported,
}

/// Where the use history of this device comes from.
abstract class ActivitySource {
  /// The part name in a night row: `android` or `mac`.
  String get name;

  Future<ActivityAccess> access();

  /// Opens the system page where the user allows access. Does nothing where
  /// no such page exists.
  Future<void> openAccessSettings();

  /// The events from [from] to [to], oldest first.
  Future<List<ActivityEvent>> events(DateTime from, DateTime to);

  /// When the next alarm on this device rings, or null. Android only.
  Future<DateTime?> nextAlarm();

  /// Fires when the device is used again, so Grove can learn the night that
  /// just ended.
  Stream<void> get changes;
}
