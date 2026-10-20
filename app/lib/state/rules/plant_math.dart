import 'dart:math';

import '../theme_id.dart';

/// How much of a day is done. The plant and the "% grown" text read this.
class PlantProgress {
  const PlantProgress({required this.done, required this.total});

  final int done;
  final int total;

  double get fraction => total > 0 ? min(1.0, done / total) : 0;
  int get percent => (fraction * 100).round();

  /// The line under the plant.
  String get growthText =>
      total == 0 ? 'Nothing planned today' : '$percent% of today grown';

  @override
  bool operator ==(Object other) =>
      other is PlantProgress && other.done == done && other.total == total;

  @override
  int get hashCode => Object.hash(done, total);

  @override
  String toString() => 'PlantProgress($done of $total)';
}

/// The numbers behind the growing plant (PLAN §6.3). Plain maths, so the tests
/// need no view.
abstract final class PlantMath {
  static const maxLeaves = 6;

  /// The plant sways 3 degrees to each side, once every 5 seconds.
  static const swayAmplitude = 3.0;
  static const swayPeriod = 5.0;

  /// 0 for no progress. At least 1 for any progress. 6 when the day is done.
  static int leaves({required int done, required int total}) {
    if (total <= 0 || done <= 0) return 0;
    final n = _round(min(done, total) / total * maxLeaves);
    return max(1, min(maxLeaves, n));
  }

  /// Rounds half away from zero, as Swift's `rounded()` does.
  static int _round(double x) => x.round();

  /// How tall the stem is, from 0.25 (a seedling) to 1 (full height). [amount]
  /// can be in between two leaf counts while the spring moves.
  static double stemGrowth(num amount) =>
      0.25 +
      0.75 * max(0.0, min(maxLeaves.toDouble(), amount.toDouble())) / maxLeaves;

  static bool hasFlower({required int done, required int total}) =>
      total > 0 && done >= total;

  static double swayDegrees({required double at}) =>
      swayAmplitude * sin(2 * pi * at / swayPeriod);
}

enum BurstStyle { leaves, fade, ringAndSparks, stamp }

class BurstParticle {
  const BurstParticle({required this.angle, required this.distance});

  final double angle;
  final double distance;

  @override
  bool operator ==(Object other) =>
      other is BurstParticle &&
      other.angle == angle &&
      other.distance == distance;

  @override
  int get hashCode => Object.hash(angle, distance);
}

/// The little show when a task is checked off (PLAN §6.2, §6.3). One style per theme.
abstract final class BurstMath {
  static const duration = 0.5;
  static const reach = 18.0;

  static BurstStyle style(ThemeId theme) => switch (theme) {
    ThemeId.grove => BurstStyle.leaves,
    ThemeId.minimal => BurstStyle.fade,
    ThemeId.futuristic => BurstStyle.ringAndSparks,
    ThemeId.vintage => BurstStyle.stamp,
  };

  /// The flying parts. Angles are in degrees. A fade and a stamp have none.
  static List<BurstParticle> particles(BurstStyle style) => switch (style) {
    BurstStyle.leaves || BurstStyle.ringAndSparks => [
      for (var i = 0; i < 6; i++)
        BurstParticle(angle: i * 60.0, distance: reach),
    ],
    BurstStyle.fade || BurstStyle.stamp => const [],
  };

  /// How far a part has flown. It starts fast and slows down.
  static double distance(double full, {required double progress}) {
    final p = max(0.0, min(1.0, progress));
    return full * (1 - (1 - p) * (1 - p));
  }

  static double opacity({required double progress}) =>
      1 - max(0.0, min(1.0, progress));
}

abstract final class Greeting {
  static String text({required int hour}) {
    if (hour >= 5 && hour < 12) return 'Good morning';
    if (hour >= 12 && hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  static String now([DateTime? date]) =>
      text(hour: (date ?? DateTime.now()).hour);
}

abstract final class MotionRules {
  /// The Motion switch must be on, and the device must not ask to reduce motion.
  static bool isOn({required bool setting, required bool reduceMotion}) =>
      setting && !reduceMotion;

  /// The ambient background only draws while the window is the active window,
  /// to save energy.
  static bool ambientRuns({
    required bool motionOn,
    required bool windowIsKey,
  }) => motionOn && windowIsKey;
}
