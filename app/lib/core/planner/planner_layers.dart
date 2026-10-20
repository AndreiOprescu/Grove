import 'planner_math.dart';

/// How one block sits among the blocks it overlaps.
/// Overlapping blocks never share the width. A block that starts later is
/// drawn on top of the one under it, moved a little to the right, so both
/// titles stay readable. Port of `PlannerLayers.swift`.
class Layer {
  const Layer({
    required this.order,
    required this.depth,
    required this.parent,
    required this.tight,
    required this.units,
  });

  /// Paint order. 0 is painted first (lowest). Later start = on top.
  final int order;

  /// 0 when the block lies on nothing.
  final int depth;

  /// The block this one sits on.
  final String? parent;

  /// True when the block starts so close to its parent's start that it
  /// would cover the parent's title row. Such a block moves further right.
  final bool tight;

  /// Indent in steps. A far block adds 1, a tight block adds
  /// [tightUnits]. Used to pick the parent.
  final int units;

  @override
  bool operator ==(Object other) =>
      other is Layer &&
      other.order == order &&
      other.depth == depth &&
      other.parent == parent &&
      other.tight == tight &&
      other.units == units;

  @override
  int get hashCode => Object.hash(order, depth, parent, tight, units);

  @override
  String toString() =>
      'Layer(order: $order, depth: $depth, parent: $parent, tight: $tight, units: $units)';
}

class _Placed {
  const _Placed(
    this.id,
    this.start,
    this.visualEnd,
    this.depth,
    this.units,
    this.order,
  );

  final String id;
  final int start;
  final int visualEnd;
  final int depth;
  final int units;
  final int order;

  /// Swift compares the tuple (units, start, order).
  bool beats(_Placed o) {
    if (units != o.units) return units > o.units;
    if (start != o.start) return start > o.start;
    return order > o.order;
  }
}

/// How many "far" steps one "tight" step counts for when a block picks its
/// parent.
const tightUnits = 4;

/// Works out which block sits on which. Spans that only touch
/// (end == start) do not overlap.
/// - [minLength]: the shortest length a block is drawn at, in minutes.
/// - [tightWithin]: a block that starts less than this many minutes after
///   its parent is "tight".
/// - [tightWithinById]: a different limit for chosen parents, by id.
Map<String, Layer> computeLayers(
  List<Span> spans, {
  int minLength = 0,
  int tightWithin = 0,
  Map<String, int> tightWithinById = const {},
}) {
  final sorted = [...spans]
    ..sort((a, b) {
      if (a.start != b.start) return a.start.compareTo(b.start);
      if (a.length != b.length) return b.length.compareTo(a.length);
      return a.id.compareTo(b.id);
    });
  final placed = <_Placed>[];
  final result = <String, Layer>{};
  for (var order = 0; order < sorted.length; order++) {
    final s = sorted[order];
    _Placed? parent;
    for (final p in placed) {
      if (p.visualEnd <= s.start) continue;
      if (parent == null || p.beats(parent)) parent = p;
    }
    var layer = Layer(
      order: order,
      depth: 0,
      parent: null,
      tight: false,
      units: 0,
    );
    if (parent != null) {
      final tight =
          s.start - parent.start < (tightWithinById[parent.id] ?? tightWithin);
      layer = Layer(
        order: order,
        depth: parent.depth + 1,
        parent: parent.id,
        tight: tight,
        units: parent.units + (tight ? tightUnits : 1),
      );
    }
    result[s.id] = layer;
    final drawnEnd = s.start + minLength;
    placed.add(
      _Placed(
        s.id,
        s.start,
        s.end > drawnEnd ? s.end : drawnEnd,
        layer.depth,
        layer.units,
        order,
      ),
    );
  }
  return result;
}

/// Left indent in points for every block. A block sits [far] points right
/// of its parent, or `tight(parentId)` points when it is tight. No indent
/// goes past [maxIndent].
Map<String, double> computeIndents(
  Map<String, Layer> layers, {
  required double far,
  required double Function(String parentId) tight,
  required double maxIndent,
}) {
  final out = <String, double>{};
  final byOrder = layers.entries.toList()
    ..sort((a, b) => a.value.order.compareTo(b.value.order));
  for (final MapEntry(key: id, value: layer) in byOrder) {
    final parent = layer.parent;
    final base = parent == null ? null : out[parent];
    if (parent != null && base != null) {
      final indent = base + (layer.tight ? tight(parent) : far);
      out[id] = indent < maxIndent ? indent : maxIndent;
    } else {
      out[id] = 0;
    }
  }
  return out;
}
