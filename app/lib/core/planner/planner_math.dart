import 'planner_layers.dart';

export 'planner_layers.dart' show Layer, tightUnits;

/// A time range on one day, in minutes since midnight.
class Span {
  const Span({required this.id, required this.start, required this.end});

  final String id;
  final int start;
  final int end;

  int get length => end - start;

  @override
  bool operator ==(Object other) =>
      other is Span &&
      other.id == id &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(id, start, end);

  @override
  String toString() => 'Span($id, $start, $end)';
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Pure planner maths. No UI, no database. All values are minutes since
/// midnight. Port of `PlannerMath.swift`.
abstract final class PlannerMath {
  static const dayEnd = 1440;

  /// Blocks start, end and move on a 15 minute grid.
  static const step = 15;

  /// The shortest block the planner makes.
  static const minLength = 15;

  /// The length a task gets on the grid: its estimate, rounded up to the
  /// step, at least [minLength].
  static int blockLength(int estimate) {
    final rounded = (estimate + step - 1) ~/ step * step;
    return rounded < minLength ? minLength : rounded;
  }

  /// The next grid line after (`by` > 0) or before (`by` < 0) [minute].
  /// A minute off the grid goes to the grid line next to it, not a whole
  /// step away.
  static int stepped(int minute, {required int by, required int step}) {
    final s = step < 1 ? 1 : step;
    if (by >= 0) return (minute ~/ s + 1) * s;
    return minute > 0 ? (minute - 1) ~/ s * s : minute - s;
  }

  /// Round to the nearest step. Halves round up (away from zero).
  static int snap(int minute, {required int step}) {
    if (step <= 1) return minute;
    return (minute / step).round() * step;
  }

  /// Keep a block of [length] inside 00:00...24:00 when moving.
  static int clampMove({required int start, required int length}) {
    final latest = dayEnd - length;
    final s = start < latest ? start : latest;
    return s < 0 ? 0 : s;
  }

  /// Move the top edge. The end stays. The block keeps at least [minLen]
  /// minutes.
  static (int, int) resizeTop({
    required int start,
    required int end,
    required int newStart,
    required int step,
    int minLen = 5,
  }) {
    var s = snap(newStart, step: step);
    if (s > end - minLen) s = end - minLen;
    if (s < 0) s = 0;
    return (s, end);
  }

  /// Move the bottom edge. The start stays. The block keeps at least
  /// [minLen] minutes.
  static (int, int) resizeBottom({
    required int start,
    required int end,
    required int newEnd,
    required int step,
    int minLen = 5,
  }) {
    var e = snap(newEnd, step: step);
    if (e < start + minLen) e = start + minLen;
    if (e > dayEnd) e = dayEnd;
    return (start, e);
  }

  /// Push spans that overlap [moved] and start at or after `moved.start`
  /// down, cascading. Returns only the spans whose start changed. Clamps at
  /// 24:00 (may overlap there).
  static List<Span> ripple({required Span moved, required List<Span> others}) {
    final candidates =
        others.where((s) => s.id != moved.id && s.start >= moved.start).toList()
          ..sort(
            (a, b) => a.start != b.start
                ? a.start.compareTo(b.start)
                : a.id.compareTo(b.id),
          );
    var frontier = moved.end;
    final changed = <Span>[];
    for (final s in candidates) {
      if (s.start >= frontier) break;
      final latest = dayEnd - s.length;
      final newStart = frontier < latest ? frontier : latest;
      if (newStart != s.start) {
        changed.add(Span(id: s.id, start: newStart, end: newStart + s.length));
      }
      frontier = newStart + s.length;
    }
    return changed;
  }

  /// First start (on the step grid) with [length] free minutes before
  /// [until]. Null if none.
  static int? firstFreeSlot({
    required int length,
    required List<Span> busy,
    required int from,
    required int until,
    required int step,
  }) {
    final s = step < 1 ? 1 : step;
    int ceilStep(int m) => (m + s - 1) ~/ s * s;
    var candidate = ceilStep(from < 0 ? 0 : from);
    final sorted = [...busy]..sort((a, b) => a.start.compareTo(b.start));
    for (final b in sorted) {
      if (b.end <= candidate) continue;
      if (b.start >= candidate + length) break;
      candidate = ceilStep(b.end);
    }
    return candidate + length <= until ? candidate : null;
  }

  /// Which block sits on which. See [computeLayers].
  static Map<String, Layer> layoutLayers(
    List<Span> spans, {
    int minLength = 0,
    int tightWithin = 0,
    Map<String, int> tightWithinById = const {},
  }) => computeLayers(
    spans,
    minLength: minLength,
    tightWithin: tightWithin,
    tightWithinById: tightWithinById,
  );

  /// Left indent in points for every block. See [computeIndents].
  static Map<String, double> indents(
    Map<String, Layer> layers, {
    required double far,
    required double Function(String parentId) tight,
    required double maxIndent,
  }) => computeIndents(layers, far: far, tight: tight, maxIndent: maxIndent);

  /// "11:15 – 12:45 · 1h 30m"
  static String label({required int start, required int end}) =>
      '${clock(start)} – ${clock(end)} · ${duration(end - start)}';

  static String clock(int minute) =>
      '${_two(minute ~/ 60)}:${_two(minute % 60)}';

  static String duration(int minutes) {
    final h = minutes ~/ 60, m = minutes % 60;
    if (h == 0) return '${m}m';
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}
