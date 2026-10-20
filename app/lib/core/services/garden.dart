/// One step on the way from a seed to an old tree.
class GardenStage {
  const GardenStage({
    required this.index,
    required this.name,
    required this.from,
  });

  final int index;
  final String name;

  /// The number of finished tasks at which the plant reaches this stage.
  final int from;

  @override
  bool operator ==(Object other) =>
      other is GardenStage &&
      other.index == index &&
      other.name == name &&
      other.from == from;

  @override
  int get hashCode => Object.hash(index, name, from);

  @override
  String toString() => 'GardenStage($index, $name, $from)';
}

/// How the garden plant grows with the tasks you finish.
/// `growth` is a smooth number, so every finished task changes the picture a
/// little.
abstract final class Garden {
  static const _steps = [
    ('Seed', 0),
    ('Sprout', 1),
    ('Seedling', 3),
    ('Young plant', 6),
    ('Leafy plant', 10),
    ('Bushy plant', 16),
    ('Budding plant', 24),
    ('Blooming plant', 34),
    ('Sapling', 48),
    ('Young tree', 66),
    ('Full tree', 90),
    ('Ancient tree', 120),
  ];

  static final List<GardenStage> stages = [
    for (final (i, (name, from)) in _steps.indexed)
      GardenStage(index: i, name: name, from: from),
  ];

  /// The growth of the last stage.
  static double get maxGrowth => (stages.length - 1).toDouble();

  static GardenStage stage({required int done}) =>
      stages.lastWhere((s) => s.from <= done, orElse: () => stages[0]);

  static GardenStage? next({required int after}) {
    final i = stage(done: after).index + 1;
    return i < stages.length ? stages[i] : null;
  }

  /// Finished tasks still needed for the next stage. Null at the top.
  static int? tasksToNext({required int done}) {
    final n = next(after: done);
    return n == null ? null : n.from - (done < 0 ? 0 : done);
  }

  /// How far through the current stage, from 0 up to just under 1. 1 at the
  /// top stage.
  static double progress({required int done}) {
    final current = stage(done: done);
    final n = next(after: done);
    if (n == null) return 1;
    return ((done < 0 ? 0 : done) - current.from) / (n.from - current.from);
  }

  /// 0 for no tasks. The stage number at the start of a stage. In between for
  /// the tasks in between.
  static double growth({required int done}) {
    final current = stage(done: done);
    if (next(after: done) == null) return current.index.toDouble();
    return current.index + progress(done: done);
  }
}
