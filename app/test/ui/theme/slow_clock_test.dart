// The slow clock, and how often the slow movements ask for a frame. An idle
// window must cost near nothing (docs/acceptance/F12-shell-gaps.md).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/state/rules/plant_math.dart';
import 'package:grove/ui/garden/garden_view.dart';
import 'package:grove/ui/theme/grove_theme.dart';
import 'package:grove/ui/theme/growing_plant.dart';
import 'package:grove/ui/theme/slow_clock.dart';
import 'package:grove/ui/theme/sway_clock.dart';
import 'package:grove/ui/theme/theme_math.dart';
import 'package:grove/ui/theme/theme_spec.dart';

/// Runs one second, one millisecond at a time. The answer is the number of
/// milliseconds in which `changes` went up.
Future<int> moments(WidgetTester tester, int Function() changes) async {
  var moments = 0;
  for (var ms = 0; ms < 1000; ms++) {
    final before = changes();
    await tester.binding.delayed(const Duration(milliseconds: 1));
    if (changes() != before) moments++;
  }
  return moments;
}

void main() {
  group('the slow clock', () {
    testWidgets('steps as often as it says, and counts the seconds', (
      tester,
    ) async {
      final clock = SlowClock(framesPerSecond: 10);
      var steps = 0;
      clock.seconds.addListener(() => steps++);

      expect(await moments(tester, () => steps), 0);
      clock.isRunning = true;
      expect(await moments(tester, () => steps), 10);
      expect(clock.seconds.value, closeTo(1, 1e-9));

      clock.isRunning = false;
      expect(await moments(tester, () => steps), 0);
      expect(clock.seconds.value, closeTo(1, 1e-9));
      clock.reset();
      expect(clock.seconds.value, 0);
      clock.dispose();
    });

    testWidgets('two clocks step together, as often as the faster one needs: '
        'one frame for both', (tester) async {
      final slow = SlowClock(framesPerSecond: 10);
      final fast = SlowClock(framesPerSecond: 30);
      var steps = 0;
      slow.seconds.addListener(() => steps++);
      fast.seconds.addListener(() => steps++);
      slow.isRunning = true;
      fast.isRunning = true;

      // 30 moments, not 40: each moment is one frame of the window.
      expect(await moments(tester, () => steps), 30);
      expect(steps, 60);
      expect(slow.seconds.value, closeTo(1, 1e-9));
      expect(fast.seconds.value, closeTo(1, 1e-9));

      // The fast one stops: the slow one goes back to its own pace.
      fast.isRunning = false;
      steps = 0;
      expect(await moments(tester, () => steps), 10);
      expect(steps, 10);
      expect(fast.seconds.value, closeTo(1, 1e-9));
      slow.dispose();
      fast.dispose();
    });

    testWidgets('a clock can change its pace while it runs', (tester) async {
      final clock = SlowClock(framesPerSecond: 30);
      var steps = 0;
      clock.seconds.addListener(() => steps++);
      clock.isRunning = true;
      clock.framesPerSecond = 5;
      expect(await moments(tester, () => steps), 5);
      clock.dispose();
    });

    testWidgets('a clock that is thrown away stops', (tester) async {
      final clock = SlowClock(framesPerSecond: 30)..isRunning = true;
      clock.dispose();
      expect(clock.isRunning, isFalse);
      // No timer is left: the test would fail with a pending timer.
    });
  });

  group('how often the circles of the background are drawn', () {
    int rate(GroveTheme theme, {double intensity = 1}) =>
        AmbientMath.framesPerSecond(
          strength: AmbientMath.strength(
            base: theme.blobOpacity,
            intensity: intensity,
          ),
          background: theme.bg,
          colors: theme.blobs,
        );

    test('never more than the 30 of PLAN §6.3, never fewer than 5', () {
      expect(AmbientMath.mostFrames, 30);
      for (final id in ThemeId.values) {
        for (final brightness in Brightness.values) {
          final frames = rate(GroveTheme.make(id, brightness));
          expect(frames, inInclusiveRange(5, 30), reason: '$id $brightness');
        }
      }
    });

    test('pale circles need fewer frames than strong ones', () {
      final minimal = GroveTheme.make(ThemeId.minimal, Brightness.light);
      final grove = GroveTheme.make(ThemeId.grove, Brightness.light);
      expect(rate(minimal), lessThan(rate(grove)));
      expect(rate(grove, intensity: 0.2), lessThan(rate(grove)));
      // No circles to see: the fewest.
      expect(rate(grove, intensity: 0), AmbientMath.fewestFrames);
    });

    test('at that rate no circle changes a colour of the window by more '
        'than one step of 255 from one frame to the next', () {
      // How strong a circle is at `d` radii from its centre.
      double fade(double d) {
        if (d >= 1) return 0;
        final f = AmbientMath.fade;
        return d < 0.5
            ? f[0] + (f[1] - f[0]) * d / 0.5
            : f[1] + (f[2] - f[1]) * (d - 0.5) / 0.5;
      }

      var checked = 0;
      for (final id in ThemeId.values) {
        for (final brightness in Brightness.values) {
          final theme = GroveTheme.make(id, brightness);
          final strength = theme.blobOpacity;
          final needs = AmbientMath.stepsPerSecond(
            strength: strength,
            background: theme.bg,
            colors: theme.blobs,
          );
          // Above the 30 of the plan the rule can not hold.
          if (needs > AmbientMath.mostFrames) continue;
          checked++;
          final frames = rate(theme);
          for (final size in const [Size(800, 800), Size(1280, 800)]) {
            final radius =
                AmbientMath.diameter(width: size.width, height: size.height) /
                2;
            for (var i = 0; i < theme.blobs.length; i++) {
              final c = theme.blobs[i];
              final contrast =
                  255 *
                  [
                    (c.r - theme.bg.r).abs(),
                    (c.g - theme.bg.g).abs(),
                    (c.b - theme.bg.b).abs(),
                  ].reduce(math.max);
              var most = 0.0;
              // One whole round of the slowest circle, in steps of a frame.
              for (var step = 0; step < 34 * frames; step += 7) {
                final a = AmbientMath.centre(index: i, time: step / frames);
                final b = AmbientMath.centre(
                  index: i,
                  time: (step + 1) / frames,
                );
                for (var x = 0.0; x <= size.width; x += size.width / 24) {
                  for (var y = 0.0; y <= size.height; y += size.height / 24) {
                    double at(Offset centre) => fade(
                      (Offset(x, y) -
                                  Offset(
                                    centre.dx * size.width,
                                    centre.dy * size.height,
                                  ))
                              .distance /
                          radius,
                    );
                    most = math.max(
                      most,
                      contrast * strength * (at(a) - at(b)).abs(),
                    );
                  }
                }
              }
              expect(most, lessThanOrEqualTo(1), reason: '$id $brightness $i');
              expect(most, greaterThan(0));
            }
          }
        }
      }
      // The rule holds for most of the themes, not for one by luck.
      expect(checked, greaterThanOrEqualTo(6));
    });
  });

  group('how often a plant that sways is drawn', () {
    test('the tip never moves more than a quarter of a point in a step', () {
      expect(SwayClock.longestStep, 0.25);
      for (final reach in [10.0, 40.0, 64.0, 90.0, 240.0]) {
        final frames = SwayClock.framesFor(
          reach: reach,
          degreesPerSecond: GrowingPlant.swaySpeed,
        );
        // The fewest and the most frames are limits, not the rule.
        if (frames == SwayClock.fewestFrames) continue;
        if (frames == SwayClock.mostFrames) continue;
        final perStep = reach * GrowingPlant.swaySpeed * math.pi / 180 / frames;
        expect(perStep, lessThanOrEqualTo(0.25));
        // ... and not many more frames than that needs.
        expect(perStep, greaterThan(0.25 * (frames - 1) / frames - 0.01));
      }
    });

    test(
      'the sway is 3 degrees in 5 seconds: at most 3.8 degrees a second',
      () {
        expect(
          GrowingPlant.swaySpeed,
          closeTo(
            PlantMath.swayAmplitude * 2 * math.pi / PlantMath.swayPeriod,
            0,
          ),
        );
        expect(GrowingPlant.swaySpeed, closeTo(3.77, 0.01));
      },
    );

    test('the small plant of the day needs 11 frames a second, the big one '
        'of the Garden the most there is', () {
      expect(
        SwayClock.framesFor(
          reach: 40,
          degreesPerSecond: GrowingPlant.swaySpeed,
        ),
        11,
      );
      expect(
        SwayClock.framesFor(
          reach: GardenView.plantHeight * 0.88,
          degreesPerSecond: GrowingPlant.swaySpeed,
        ),
        SwayClock.mostFrames,
      );
      expect(
        SwayClock.framesFor(reach: 1, degreesPerSecond: 1),
        SwayClock.fewestFrames,
      );
    });
  });
}
