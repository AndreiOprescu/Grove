import 'dart:math';

import 'goal_graph.dart';

/// A place on the map. The map has no Flutter types: this is pure Dart.
class MapPoint {
  const MapPoint(this.x, this.y);

  final double x;
  final double y;
}

/// One link as a line, from the right side of the child to the left side of
/// the parent. A link across layers has more points, so it goes around the
/// squares between.
class MapEdge {
  const MapEdge(this.childId, this.parentId, this.points);

  final String childId;
  final String parentId;
  final List<MapPoint> points;

  String get id => '$childId>$parentId';
}

/// The places of all squares, worked out from the graph. Nothing is stored,
/// so no device can disagree (ADR 0008).
///
/// The method is a layered drawing: a layer per longest path to the root
/// (loose squares on the left, see [_columns]),
/// hidden points where a link skips a layer, the order in a layer from the
/// average place of the neighbours, then each height from the same average.
class GoalMapLayout {
  GoalMapLayout._(this._places, this.edges, this.width, this.height);

  static const squareWidth = 232.0;
  static const squareHeight = 68.0;
  static const _gapX = 76.0;
  static const _gapY = 22.0;
  static const _hiddenHeight = 6.0;
  static const _sweeps = 4;

  final Map<String, MapPoint> _places;
  final List<MapEdge> edges;
  final double width;
  final double height;

  /// The top left corner of a square.
  MapPoint at(String id) => _places[id]!;

  Iterable<String> get ids => _places.keys;

  factory GoalMapLayout.of(GoalGraph graph) {
    final ranks = _columns(graph);
    final maxRank = ranks.values.fold(0, (a, b) => a > b ? a : b);

    int bySort(String a, String b) {
      final s = graph.square(a).sort.compareTo(graph.square(b).sort);
      return s != 0 ? s : a.compareTo(b);
    }

    // Layers, in the order of a walk from the root, then from each loose
    // square with no parent.
    final layers = [for (var r = 0; r <= maxRank; r++) <_Item>[]];
    final items = <String, _Item>{};
    void visit(String id) {
      if (items.containsKey(id)) return;
      final item = _Item(id, GoalMapLayout.squareHeight);
      items[id] = item;
      layers[ranks[id]!].add(item);
      final children = [...graph.childrenOf(id)]..sort(bySort);
      children.forEach(visit);
    }

    visit(graph.rootId);
    final tops = [
      for (final id in graph.ids)
        if (graph.parentsOf(id).isEmpty && id != graph.rootId) id,
    ]..sort(bySort);
    tops.forEach(visit);

    // Hidden points on links that skip a layer.
    final parentIds = graph.ids.toList()..sort();
    final chains = <String, List<_Item>>{};
    for (final parent in parentIds) {
      for (final child in graph.childrenOf(parent)) {
        var upper = items[parent]!;
        final chain = <_Item>[];
        for (var r = ranks[parent]! + 1; r < ranks[child]!; r++) {
          final hidden = _Item('$child>$parent:$r', _hiddenHeight);
          layers[r].add(hidden);
          chain.add(hidden);
          upper.down.add(hidden);
          hidden.up.add(upper);
          upper = hidden;
        }
        upper.down.add(items[child]!);
        items[child]!.up.add(upper);
        chains['$child>$parent'] = chain;
      }
    }

    _order(layers);
    _heights(layers);

    // Every place is at least 0.
    var top = double.infinity;
    var bottom = double.negativeInfinity;
    for (final layer in layers) {
      for (final item in layer) {
        if (item.y - item.height / 2 < top) top = item.y - item.height / 2;
        if (item.y + item.height / 2 > bottom) {
          bottom = item.y + item.height / 2;
        }
      }
    }
    double xOf(int rank) => (maxRank - rank) * (squareWidth + _gapX);
    final places = <String, MapPoint>{
      for (final e in items.entries)
        e.key: MapPoint(xOf(ranks[e.key]!), e.value.y - squareHeight / 2 - top),
    };

    final edges = <MapEdge>[];
    for (final parent in parentIds) {
      for (final child in graph.childrenOf(parent)) {
        final from = places[child]!;
        final to = places[parent]!;
        final points = <MapPoint>[
          MapPoint(from.x + squareWidth, from.y + squareHeight / 2),
        ];
        final chain = chains['$child>$parent']!;
        for (var i = chain.length - 1; i >= 0; i--) {
          final rank = ranks[parent]! + 1 + i;
          final y = chain[i].y - top;
          points
            ..add(MapPoint(xOf(rank), y))
            ..add(MapPoint(xOf(rank) + squareWidth, y));
        }
        points.add(MapPoint(to.x, to.y + squareHeight / 2));
        edges.add(MapEdge(child, parent, points));
      }
    }

    return GoalMapLayout._(places, edges, xOf(0) + squareWidth, bottom - top);
  }

  /// The column of each square, counted from the right. A linked square
  /// sits by its longest path to the root. A loose square sits one column
  /// right of its nearest child, and one with no child sits in the column
  /// left of all linked squares, so a new loose square is on the far left.
  static Map<String, int> _columns(GoalGraph graph) {
    final out = <String, int>{graph.rootId: 0};
    int linked(String id) {
      final known = out[id];
      if (known != null) return known;
      var rank = 0;
      for (final p in graph.parentsOf(id)) {
        if (!graph.isLoose(p)) rank = max(rank, linked(p) + 1);
      }
      return out[id] = rank;
    }

    for (final id in graph.ids) {
      if (!graph.isLoose(id)) linked(id);
    }
    final left = out.values.fold(0, max) + 1;
    int loose(String id) {
      final known = out[id];
      if (known != null) return known;
      final children = graph.childrenOf(id);
      return out[id] = children.isEmpty
          ? left
          : children.map(loose).reduce(min) - 1;
    }

    for (final id in graph.ids) {
      loose(id);
    }
    // A loose square over a linked child can land right of the root.
    final shift = out.values.fold(0, min);
    return {for (final e in out.entries) e.key: e.value - shift};
  }

  static void _order(List<List<_Item>> layers) {
    void number() {
      for (final layer in layers) {
        for (var i = 0; i < layer.length; i++) {
          layer[i].index = i;
        }
      }
    }

    number();
    var best = [
      for (final l in layers) [...l],
    ];
    var bestCrossings = _crossings(layers);
    for (var sweep = 0; sweep < _sweeps && bestCrossings > 0; sweep++) {
      for (var r = 1; r < layers.length; r++) {
        _sortBy(layers[r], (i) => i.up);
      }
      number();
      for (var r = layers.length - 2; r >= 0; r--) {
        _sortBy(layers[r], (i) => i.down);
      }
      number();
      final crossings = _crossings(layers);
      if (crossings < bestCrossings) {
        bestCrossings = crossings;
        best = [
          for (final l in layers) [...l],
        ];
      }
    }
    for (var r = 0; r < layers.length; r++) {
      layers[r]
        ..clear()
        ..addAll(best[r]);
    }
    number();
  }

  static void _sortBy(
    List<_Item> layer,
    List<_Item> Function(_Item) neighbours,
  ) {
    final keys = <_Item, double>{};
    for (final item in layer) {
      final n = neighbours(item);
      keys[item] = n.isEmpty
          ? item.index.toDouble()
          : n.map((o) => o.index).reduce((a, b) => a + b) / n.length;
    }
    final before = {for (final item in layer) item: item.index};
    layer.sort((a, b) {
      final k = keys[a]!.compareTo(keys[b]!);
      return k != 0 ? k : before[a]!.compareTo(before[b]!);
    });
    for (var i = 0; i < layer.length; i++) {
      layer[i].index = i;
    }
  }

  static int _crossings(List<List<_Item>> layers) {
    var total = 0;
    for (var r = 0; r + 1 < layers.length; r++) {
      final lines = <(int, int)>[
        for (final item in layers[r])
          for (final d in item.down) (item.index, d.index),
      ];
      for (var i = 0; i < lines.length; i++) {
        for (var j = i + 1; j < lines.length; j++) {
          final a = lines[i];
          final b = lines[j];
          if ((a.$1 - b.$1) * (a.$2 - b.$2) < 0) total++;
        }
      }
    }
    return total;
  }

  static void _heights(List<List<_Item>> layers) {
    for (final layer in layers) {
      var y = 0.0;
      for (var i = 0; i < layer.length; i++) {
        if (i > 0) y += _space(layer[i - 1], layer[i]);
        layer[i].y = y;
      }
    }
    // The last pass goes toward the root, so a parent ends in the middle of
    // its children.
    for (var sweep = 0; sweep < _sweeps; sweep++) {
      for (var r = 1; r < layers.length; r++) {
        _place(layers[r], (i) => i.up);
      }
      for (var r = layers.length - 2; r >= 0; r--) {
        _place(layers[r], (i) => i.down);
      }
    }
  }

  static double _space(_Item a, _Item b) => (a.height + b.height) / 2 + _gapY;

  /// Moves each item as near to the middle of its neighbours as the order and
  /// the spaces let it: the smallest total move, by joining items that push
  /// each other into one block at their average.
  static void _place(
    List<_Item> layer,
    List<_Item> Function(_Item) neighbours,
  ) {
    if (layer.isEmpty) return;
    final offsets = <double>[0];
    for (var i = 1; i < layer.length; i++) {
      offsets.add(offsets[i - 1] + _space(layer[i - 1], layer[i]));
    }
    final blocks = <_Block>[];
    for (var i = 0; i < layer.length; i++) {
      final n = neighbours(layer[i]);
      final want = n.isEmpty
          ? layer[i].y
          : n.map((o) => o.y).reduce((a, b) => a + b) / n.length;
      var block = _Block(want - offsets[i], 1, i);
      while (blocks.isNotEmpty && blocks.last.value >= block.value) {
        final last = blocks.removeLast();
        block = _Block(
          (last.value * last.count + block.value * block.count) /
              (last.count + block.count),
          last.count + block.count,
          last.first,
        );
      }
      blocks.add(block);
    }
    for (final block in blocks) {
      for (var i = block.first; i < block.first + block.count; i++) {
        layer[i].y = block.value + offsets[i];
      }
    }
  }
}

class _Item {
  _Item(this.id, this.height);

  final String id;
  final double height;
  final List<_Item> up = [];
  final List<_Item> down = [];
  int index = 0;
  double y = 0;
}

class _Block {
  const _Block(this.value, this.count, this.first);

  final double value;
  final int count;
  final int first;
}
