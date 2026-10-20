// Port of AmbientMotionTests (Tests/GroveTests/ThemeSpecTests.swift) and
// ThemeDecorTests (Tests/GroveTests/ThemeMotionTests.swift).
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/theme/theme_math.dart';

void main() {
  group('ambient background (PLAN §6.3)', () {
    test('the three periods are 22, 28 and 34 seconds', () {
      expect(AmbientMath.periods, [22.0, 28.0, 34.0]);
    });

    test('a blob stays near the window at any time', () {
      for (var i = 0; i < 3; i++) {
        for (var t = 0.0; t <= 200; t += 1.7) {
          final c = AmbientMath.centre(index: i, time: t);
          expect(c.dx, inExclusiveRange(0.1, 0.9));
          expect(c.dy, inExclusiveRange(0.1, 0.9));
        }
      }
    });

    test('a blob moves slowly', () {
      final a = AmbientMath.centre(index: 0, time: 10);
      final b = AmbientMath.centre(index: 0, time: 11);
      final step = (a - b).distance;
      // under 8% of the window in one second
      expect(step, inExclusiveRange(0, 0.08));
    });

    test('the blobs do not move together', () {
      final a = AmbientMath.centre(index: 0, time: 5);
      final b = AmbientMath.centre(index: 1, time: 5);
      expect(a, isNot(b));
    });

    test('a blob is 46 percent of the long side', () {
      expect(
        AmbientMath.diameter(width: 1000, height: 600),
        closeTo(460, 1e-3),
      );
      expect(
        AmbientMath.diameter(width: 600, height: 1000),
        closeTo(460, 1e-3),
      );
    });

    test('the strength is the theme times the setting, from 0 to 1', () {
      expect(AmbientMath.strength(base: 0.55, intensity: 1), 0.55);
      expect(AmbientMath.strength(base: 0.5, intensity: 0.5), 0.25);
      expect(AmbientMath.strength(base: 0.55, intensity: 3), 1);
      expect(AmbientMath.strength(base: 0.55, intensity: -1), 0);
    });

    test('motion needs the switch and no reduce motion', () {
      expect(MotionRules.isOn(setting: true, reduceMotion: false), isTrue);
      expect(MotionRules.isOn(setting: false, reduceMotion: false), isFalse);
      expect(MotionRules.isOn(setting: true, reduceMotion: true), isFalse);
      expect(MotionRules.isOn(setting: false, reduceMotion: true), isFalse);
    });

    test('the background only runs in the key window', () {
      expect(
        MotionRules.ambientRuns(motionOn: true, windowIsKey: true),
        isTrue,
      );
      expect(
        MotionRules.ambientRuns(motionOn: true, windowIsKey: false),
        isFalse,
      );
      expect(
        MotionRules.ambientRuns(motionOn: false, windowIsKey: true),
        isFalse,
      );
    });
  });

  group('theme decor (PLAN §6.2)', () {
    test('the now line pulses between 1 and 0.45 in 3.2 seconds', () {
      expect(PulseMath.period, 3.2);
      expect(PulseMath.opacity(0), closeTo(1, 1e-4));
      expect(PulseMath.opacity(1.6), closeTo(0.45, 1e-4));
      expect(PulseMath.opacity(3.2), closeTo(1, 1e-4));
      for (var t = 0.0; t <= 20; t += 0.13) {
        expect(PulseMath.opacity(t), inInclusiveRange(0.45 - 1e-4, 1 + 1e-4));
      }
    });

    test('the grid has a line every 32 points', () {
      expect(GridMath.spacing, 32);
      expect(GridMath.lines(100), [0.0, 32.0, 64.0, 96.0]);
      expect(GridMath.lines(0), [0.0]);
      expect(GridMath.lines(-1), isEmpty);
      expect(GridMath.lines(100, spacing: 0), isEmpty);
    });

    test('ruled lines are 28 points apart', () {
      expect(GridMath.ruledPitch, 28);
      expect(GridMath.ruledRows(top: 4, minY: 0, maxY: 100), [
        32.0,
        60.0,
        88.0,
      ]);
      expect(GridMath.ruledRows(top: 4, minY: 40, maxY: 70), [60.0]);
      expect(GridMath.ruledRows(top: 4, minY: 33, maxY: 59), isEmpty);
      expect(GridMath.ruledRows(top: 4, minY: 50, maxY: 10), isEmpty);
    });

    test('the noise is the same every time', () {
      final a = NoiseMath.dots(count: 50, size: 200, seed: 7);
      expect(a, NoiseMath.dots(count: 50, size: 200, seed: 7));
      expect(a, isNot(NoiseMath.dots(count: 50, size: 200, seed: 8)));
      expect(a, hasLength(50));
      for (final p in a) {
        expect(p.dx, inInclusiveRange(0, 200));
        expect(p.dy, inInclusiveRange(0, 200));
      }
      expect(NoiseMath.dots(count: -3, size: 10, seed: 1), isEmpty);
    });

    test('the noise is the SplitMix64 of the Mac app', () {
      // First value of SplitMix64 with seed 0 is 0xE220A8397B1DCDAF.
      // The Mac app takes the top 53 bits as a number from 0 to 1.
      final first = NoiseMath.dots(count: 1, size: 1, seed: 0).single.dx;
      expect(first, closeTo(0xE220A8397B1DC / math.pow(2, 52), 1e-12));
    });
  });
}
