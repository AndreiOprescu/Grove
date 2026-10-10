// Port of the plain maths in Sources/Grove/Theme/AmbientBackground.swift,
// ThemeDecor.swift and `MotionRules` (AppStore+Appearance.swift).
// No widgets here, so the tests need none.
import 'dart:math' as math;
import 'dart:ui' show Offset;

/// Where one blob of the ambient background is at a time (PLAN §6.3).
abstract final class AmbientMath {
  /// The three periods in seconds.
  static const periods = [22.0, 28.0, 34.0];

  /// Centre of blob `index` in 0...1 of the window, at `time` seconds.
  /// A slow Lissajous path.
  static Offset centre({required int index, required double time}) {
    final period = periods[index % periods.length];
    final phase = index * 2.1;
    final w = 2 * math.pi / period;
    final x = 0.5 + 0.2 * math.sin(w * time + phase);
    final y = 0.5 + 0.2 * math.sin(w * time * 1.15 + phase * 1.7 + 1);
    return Offset(x, y);
  }

  /// How strong the circles are: the theme's strength times the Accent
  /// intensity setting, kept between 0 and 1.
  static double strength({required double base, required double intensity}) =>
      math.min(1, math.max(0, base * intensity));

  /// Blob diameter: 46% of the longer side of the window.
  static double diameter({required double width, required double height}) =>
      0.46 * math.max(width, height);
}

/// When the moving parts may move (PLAN §6.3).
abstract final class MotionRules {
  /// The Motion switch must be on, and the device must not ask to reduce
  /// motion.
  static bool isOn({required bool setting, required bool reduceMotion}) =>
      setting && !reduceMotion;

  /// The ambient background only draws while the window is in front, to
  /// save energy.
  static bool ambientRuns({
    required bool motionOn,
    required bool windowIsKey,
  }) => motionOn && windowIsKey;
}

/// The now-line pulse: opacity goes from 1 down to 0.45 and back, once
/// every 3.2 s.
abstract final class PulseMath {
  static const period = 3.2;
  static const lowest = 0.45;

  static double opacity(double seconds) =>
      1 - (1 - lowest) * (1 - math.cos(2 * math.pi * seconds / period)) / 2;
}

/// Where the lines of a grid go.
abstract final class GridMath {
  /// Futuristic: a faint grid on the background, one line every 32 pt.
  static const spacing = 32.0;

  /// Vintage: the ruled lines of the note editor, one every 28 pt.
  static const ruledPitch = 28.0;

  /// Positions `0, spacing, 2*spacing ...` up to `length`.
  static List<double> lines(double length, {double spacing = spacing}) {
    if (length < 0 || spacing <= 0) return const [];
    return [for (var i = 0; i * spacing <= length; i++) i * spacing];
  }

  /// Y positions of ruled lines that fall in `minY...maxY`. The first line
  /// is one pitch below `top`.
  static List<double> ruledRows({
    required double top,
    double pitch = ruledPitch,
    required double minY,
    required double maxY,
  }) {
    if (pitch <= 0 || maxY < minY) return const [];
    final first = math.max(1, ((minY - top) / pitch).ceil());
    final last = ((maxY - top) / pitch).floor();
    if (last < first) return const [];
    return [for (var i = first; i <= last; i++) top + i * pitch];
  }
}

/// Vintage paper: the dots of the noise, the same every time.
abstract final class NoiseMath {
  static List<Offset> dots({
    required int count,
    required double size,
    required int seed,
  }) {
    var state = seed;
    double next() {
      // SplitMix64: small, fast, and the same on every run. Dart ints wrap
      // at 64 bits like Swift's `&+` and `&*`; `>>>` is the unsigned shift.
      state += 0x9E3779B97F4A7C15;
      var z = state;
      z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9;
      z = (z ^ (z >>> 27)) * 0x94D049BB133111EB;
      z ^= z >>> 31;
      return (z >>> 11) / (1 << 53);
    }

    return [
      for (var i = 0; i < count; i++) Offset(next() * size, next() * size),
    ];
  }
}
