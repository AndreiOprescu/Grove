import '../../core/model/day_key.dart';
import '../../core/planner/planner_math.dart';

/// The two lines a day of the planner can have: when to wake up and when
/// to go to sleep.
enum DayMarkerKind {
  wake,
  sleep;

  /// "Wake up", "Sleep": the word next to the line.
  String get label => switch (this) {
    DayMarkerKind.wake => 'Wake up',
    DayMarkerKind.sleep => 'Sleep',
  };

  /// "wake-up line", "sleep line": the name in a menu.
  String get lineName => switch (this) {
    DayMarkerKind.wake => 'wake-up line',
    DayMarkerKind.sleep => 'sleep line',
  };

  /// "Wake-up Line", "Sleep Line": the name in an undo step.
  String get undoName => switch (this) {
    DayMarkerKind.wake => 'Wake-up Line',
    DayMarkerKind.sleep => 'Sleep Line',
  };

  /// The picture next to the time, as the SF Symbol name of the Mac app.
  String get symbol => switch (this) {
    DayMarkerKind.wake => 'sun.max',
    DayMarkerKind.sleep => 'moon',
  };
}

/// One line of one day, at a minute since midnight.
class DayMarker {
  const DayMarker({
    required this.kind,
    required this.day,
    required this.minute,
  });

  final DayMarkerKind kind;
  final DayKey day;
  final int minute;

  @override
  bool operator ==(Object other) =>
      other is DayMarker &&
      other.kind == kind &&
      other.day == day &&
      other.minute == minute;

  @override
  int get hashCode => Object.hash(kind, day, minute);

  @override
  String toString() => '${kind.name} ${day.string} $minute';
}

/// The rules of the wake-up and sleep lines. No UI, no database.
///
/// A line is one row of the `settings` table: the key names the kind and the
/// day, the value is the minute. So the lines sync and are in an export file
/// with no table of their own.
abstract final class DayMarkerRules {
  /// Where a line is when no other day has one yet: 07:00 and 23:00.
  static int firstMinute(DayMarkerKind kind) => switch (kind) {
    DayMarkerKind.wake => 7 * 60,
    DayMarkerKind.sleep => 23 * 60,
  };

  /// The latest time of a line: the last step of the day (23:45).
  static const latest = PlannerMath.dayEnd - PlannerMath.step;

  /// On the grid of the planner, and inside the day.
  static int snapped(int minute) {
    final m = PlannerMath.snap(minute, step: PlannerMath.step);
    return m < 0 ? 0 : (m > latest ? latest : m);
  }

  /// The start of the keys of one kind: "planner.wake.".
  static String prefix(DayMarkerKind kind) => 'planner.${kind.name}.';

  /// Just after the last key of one kind ("/" comes after ".").
  static String prefixEnd(DayMarkerKind kind) => 'planner.${kind.name}/';

  /// "planner.wake.2026-10-07"
  static String key(DayMarkerKind kind, DayKey day) =>
      '${prefix(kind)}${day.string}';

  /// The line of a settings row. Null for a key that names no real day and
  /// for a value that is not a number.
  static DayMarker? parse(DayMarkerKind kind, String key, String value) {
    final start = prefix(kind);
    if (!key.startsWith(start)) return null;
    final day = DayKey.parse(key.substring(start.length));
    final minute = int.tryParse(value);
    if (day == null || minute == null) return null;
    return DayMarker(kind: kind, day: day, minute: snapped(minute));
  }
}
