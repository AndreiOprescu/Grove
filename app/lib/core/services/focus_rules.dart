import '../model/day_key.dart';
import '../model/event.dart';

/// The focus timer arithmetic (PLAN §5.1.7). A focus session counts down to
/// the end of a block.
abstract final class FocusRules {
  /// The moment a wall-clock time happens, in the user's time zone.
  static DateTime endDate(WallTime t) =>
      DateTime(t.day.year, t.day.month, t.day.day, 0, t.minute);

  /// Whole seconds left, rounded up, never below zero.
  static int remaining({required DateTime until, required DateTime now}) {
    final micros = until.difference(now).inMicroseconds;
    return micros <= 0 ? 0 : (micros / Duration.microsecondsPerSecond).ceil();
  }

  /// "24:07", or "1:02:05" from one hour.
  static String clock(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    final h = s ~/ 3600, m = s % 3600 ~/ 60, sec = s % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
  }

  /// How far a session is, 0 to 1. A span with no length is finished.
  static double progress({
    required DateTime start,
    required DateTime end,
    required DateTime now,
  }) {
    final total = end.difference(start).inMicroseconds;
    if (total <= 0) return 1;
    final p = now.difference(start).inMicroseconds / total;
    return p < 0 ? 0 : (p > 1 ? 1 : p);
  }

  /// A block can be focused on until its end.
  static bool canStart(EventItem block, {required DateTime now}) =>
      endDate(block.end).isAfter(now);
}
