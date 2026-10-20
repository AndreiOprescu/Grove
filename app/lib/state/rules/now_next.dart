import 'planner_block.dart';

/// The two lines at the top of the menu bar (or tray) window.
class NowNext {
  const NowNext({required this.now, required this.next});

  final String now;
  final String next;

  @override
  bool operator ==(Object other) =>
      other is NowNext && other.now == now && other.next == next;

  @override
  int get hashCode => Object.hash(now, next);

  @override
  String toString() => 'NowNext($now, $next)';
}

/// "Now: block" and "Next: block in 25 min" (PLAN §5.7). Plain rules, so a test can check them.
abstract final class NowNextRules {
  static int _order(PlannerBlock a, PlannerBlock b) {
    final start = a.startMinute.compareTo(b.startMinute);
    return start != 0 ? start : a.id.compareTo(b.id);
  }

  /// [blocks] are the timed blocks of today. A block of a finished task is left
  /// out: it is not what you do now.
  static NowNext make({
    required List<PlannerBlock> blocks,
    required int minute,
  }) {
    final open = blocks.where((b) => !b.isDone);
    // When blocks overlap, "now" is the one that started last.
    PlannerBlock? running, coming;
    for (final b in open) {
      if (b.startMinute <= minute && minute < b.endMinute) {
        if (running == null || _order(running, b) < 0) running = b;
      }
      if (b.startMinute > minute) {
        if (coming == null || _order(b, coming) < 0) coming = b;
      }
    }
    return NowNext(
      now: running == null
          ? 'Nothing planned right now'
          : 'Now: ${running.title}',
      next: coming == null
          ? 'Nothing else today'
          : 'Next: ${coming.title} ${inText(coming.startMinute - minute)}',
    );
  }

  /// 25 → "in 25 min", 60 → "in 1 h", 90 → "in 1 h 30 min"
  static String inText(int minutes) {
    final h = minutes ~/ 60, m = minutes % 60;
    if (h == 0) return 'in $m min';
    return m == 0 ? 'in $h h' : 'in $h h $m min';
  }
}
