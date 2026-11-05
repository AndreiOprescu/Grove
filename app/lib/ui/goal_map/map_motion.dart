// Where each square is at each moment of a move on the goal map. It holds no
// widget, so a test can read every place. One controller drives all of it:
// the view gives [t] and paints.
import 'dart:math' as math;
import 'dart:ui' show Offset, lerpDouble;

import 'package:flutter/animation.dart' show Curves;
import 'package:grove/core/goals/goal_graph.dart';
import 'package:grove/core/goals/goal_map_layout.dart';

/// A square that left the map and shrinks into its parent.
class LeavingSquare {
  const LeavingSquare(this.id, this.start, this.end);

  final String id;
  final Offset start;
  final Offset end;
}

class MapMotion {
  /// Time of the move, 0 to 1. The view sets it from its controller.
  double t = 1;

  Map<String, Offset> _from = const {};
  Map<String, Offset> _to = const {};
  Map<String, List<Offset>> _edgesFrom = const {};
  Map<String, List<Offset>> _edgesTo = const {};
  Map<String, LeavingSquare> _leaving = const {};
  Set<String> _entering = const {};
  Map<String, double> _growDelay = const {};
  List<MapEdge> _edges = const [];
  Offset? _growFrom;

  /// How much of the move a square waits for at most when a map grows.
  static const _maxDelay = 0.55;

  double get _eased => Curves.easeInOutCubic.transform(t.clamp(0.0, 1.0));

  bool get isMoving => t < 1;

  /// The squares to draw that are in the map now.
  Iterable<String> get ids => _to.keys;

  /// The squares that shrink away in this move.
  Iterable<LeavingSquare> get leaving => _leaving.values;

  List<MapEdge> get edges => _edges;

  /// Shows [next] at once.
  void jump(GoalMapLayout next) {
    _set(next);
    _from = _to;
    _edgesFrom = _edgesTo;
    _leaving = const {};
    _entering = const {};
    _growDelay = const {};
    _growFrom = null;
    t = 1;
  }

  /// Starts a move from where every square is now to [next]. A move that is
  /// going on gives way: nothing jumps. [graph] is the map before [next], for
  /// the parents of a square that leaves.
  void moveTo(GoalMapLayout next, GoalGraph before) {
    final places = {for (final id in _to.keys) id: place(id)};
    final edgesNow = {for (final e in _edges) e.id: pointsOf(e)};
    final leavingNow = <String, LeavingSquare>{};
    final nextIds = next.ids.toSet();
    for (final l in _leaving.values) {
      if (!nextIds.contains(l.id)) {
        leavingNow[l.id] = LeavingSquare(l.id, _leavingPlace(l), l.end);
      }
    }
    _set(next);
    for (final entry in places.entries) {
      if (!nextIds.contains(entry.key)) {
        final parents = before.contains(entry.key)
            ? before.parentsOf(entry.key)
            : const <String>[];
        final parent = parents.isEmpty ? null : _to[parents.first];
        leavingNow[entry.key] = LeavingSquare(
          entry.key,
          entry.value,
          parent ?? entry.value,
        );
      }
    }
    _from = {
      for (final id in _to.keys)
        id: places[id] ?? _leaving[id]?.start ?? _to[id]!,
    };
    _entering = {
      for (final id in _to.keys)
        if (!places.containsKey(id)) id,
    };
    _edgesFrom = edgesNow;
    _leaving = leavingNow;
    _growDelay = const {};
    _growFrom = null;
    t = 0;
  }

  /// Starts a new map that grows out of its root: the root first, then each
  /// layer.
  void growInto(GoalMapLayout next, GoalGraph graph) {
    _set(next);
    final root = _to[graph.rootId]!;
    final maxRank = graph.ranks.values.fold<int>(0, math.max);
    _from = _to;
    _edgesFrom = _edgesTo;
    _leaving = const {};
    _entering = const {};
    _growFrom = root;
    _growDelay = {
      for (final id in _to.keys)
        id: maxRank == 0 ? 0 : graph.ranks[id]! / maxRank * _maxDelay,
    };
    t = 0;
  }

  /// A move is over: the squares that left are gone.
  void settle() {
    t = 1;
    _leaving = const {};
    _entering = const {};
    _growDelay = const {};
    _growFrom = null;
    _from = _to;
    _edgesFrom = _edgesTo;
  }

  void _set(GoalMapLayout next) {
    _to = {for (final id in next.ids) id: _offset(next.at(id))};
    _edges = next.edges;
    _edgesTo = {
      for (final e in next.edges) e.id: [for (final p in e.points) _offset(p)],
    };
  }

  static Offset _offset(MapPoint p) => Offset(p.x, p.y);

  double _grown(String id) {
    final delay = _growDelay[id] ?? 0;
    return ((t - delay) / (1 - _maxDelay)).clamp(0.0, 1.0);
  }

  /// The top left corner of a square now.
  Offset place(String id) {
    final origin = _growFrom;
    if (origin != null) {
      final grown = Curves.easeOutCubic.transform(_grown(id));
      return Offset.lerp(origin, _to[id] ?? origin, grown)!;
    }
    final to = _to[id];
    if (to == null) return Offset.zero;
    return Offset.lerp(_from[id] ?? to, to, _eased)!;
  }

  Offset _leavingPlace(LeavingSquare l) => Offset.lerp(l.start, l.end, _eased)!;

  Offset leavingPlace(LeavingSquare l) => _leavingPlace(l);

  /// How big a square is now, 0 to 1.
  double scaleOf(String id) {
    if (_growFrom != null) return lerpDouble(0.7, 1, _grown(id))!;
    if (_entering.contains(id)) return lerpDouble(0.85, 1, _entering01)!;
    return 1;
  }

  /// How solid a square is now, 0 to 1.
  double alphaOf(String id) {
    if (_growFrom != null) return _grown(id);
    if (_entering.contains(id)) return _entering01;
    return 1;
  }

  /// A new square waits for the others to make room.
  double get _entering01 => ((t - 0.35) / 0.65).clamp(0.0, 1.0);

  double leavingScale() => lerpDouble(1, 0.55, _eased)!;

  double leavingAlpha() => (1 - _eased * 1.4).clamp(0.0, 1.0);

  /// The points of a line now. When the line has no earlier shape of the same
  /// length, it goes straight between its two squares as they move.
  List<Offset> pointsOf(MapEdge edge) {
    final to = _edgesTo[edge.id];
    if (to == null) return const [];
    if (_growFrom != null) return _endsOnly(edge);
    final from = _edgesFrom[edge.id];
    if (identical(from, to)) return to;
    if (from == null || from.length != to.length) return _endsOnly(edge);
    final e = _eased;
    return [
      for (var i = 0; i < to.length; i++) Offset.lerp(from[i], to[i], e)!,
    ];
  }

  List<Offset> _endsOnly(MapEdge edge) {
    final c = place(edge.childId);
    final p = place(edge.parentId);
    const w = GoalMapLayout.squareWidth, h = GoalMapLayout.squareHeight;
    return [c + const Offset(w, h / 2), p + const Offset(0, h / 2)];
  }

  /// How solid a line is now.
  double edgeAlpha(MapEdge edge) =>
      math.min(alphaOf(edge.childId), alphaOf(edge.parentId));
}
