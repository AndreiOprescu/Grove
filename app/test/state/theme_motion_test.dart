// Port of Tests/GroveTests/ThemeMotionTests.swift, and the `MotionRules`
// tests of ThemeSpecTests.swift. The decor math (pulse, grid, noise) stays
// with the theme code (Track B).
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const today = DayKey('2026-10-04');

void main() {
  group('the plant', () {
    test('no tasks means no leaves', () {
      expect(PlantMath.leaves(done: 0, total: 0), 0);
      expect(PlantMath.leaves(done: 3, total: 0), 0);
    });

    test('nothing done means no leaves', () {
      expect(PlantMath.leaves(done: 0, total: 5), 0);
    });

    test('everything done means six leaves', () {
      expect(PlantMath.leaves(done: 5, total: 5), 6);
      expect(PlantMath.leaves(done: 1, total: 1), 6);
    });

    test('half done means three leaves', () {
      expect(PlantMath.leaves(done: 2, total: 4), 3);
    });

    test('any progress shows at least one leaf', () {
      expect(PlantMath.leaves(done: 1, total: 100), 1);
    });

    test('never more than six leaves', () {
      expect(PlantMath.leaves(done: 9, total: 3), 6);
    });

    test('more done never means fewer leaves', () {
      var last = 0;
      for (var done = 0; done <= 10; done++) {
        final n = PlantMath.leaves(done: done, total: 10);
        expect(n, greaterThanOrEqualTo(last));
        last = n;
      }
    });

    test('the stem grows with the leaves', () {
      expect(PlantMath.stemGrowth(0), greaterThan(0));
      expect(PlantMath.stemGrowth(0), lessThan(PlantMath.stemGrowth(3)));
      expect(PlantMath.stemGrowth(3), lessThan(PlantMath.stemGrowth(6)));
      expect(PlantMath.stemGrowth(6), 1);
    });

    test('the flower opens only when everything is done', () {
      expect(PlantMath.hasFlower(done: 4, total: 5), isFalse);
      expect(PlantMath.hasFlower(done: 5, total: 5), isTrue);
      expect(PlantMath.hasFlower(done: 0, total: 0), isFalse);
    });

    test('the sway is three degrees every five seconds', () {
      for (var t = 0.0; t <= 30; t += 0.37) {
        expect(PlantMath.swayDegrees(at: t).abs(), lessThanOrEqualTo(3.0001));
      }
      // A quarter of the period is the top.
      expect(PlantMath.swayDegrees(at: 1.25), closeTo(3, 0.001));
      expect(
        PlantMath.swayDegrees(at: 0),
        closeTo(PlantMath.swayDegrees(at: 5), 0.001),
      );
    });
  });

  group('the check-off burst', () {
    test('grove throws six leaves out 18 points', () {
      expect(BurstMath.style(ThemeId.grove), BurstStyle.leaves);
      final p = BurstMath.particles(BurstStyle.leaves);
      expect(p.length, 6);
      expect(p.every((x) => x.distance == 18), isTrue);
      final angles = [for (final x in p) x.angle]..sort();
      for (var i = 1; i < angles.length; i++) {
        expect(angles[i] - angles[i - 1], closeTo(60, 0.001));
      }
    });

    test('each theme has its own burst', () {
      expect(BurstMath.style(ThemeId.minimal), BurstStyle.fade);
      expect(BurstMath.style(ThemeId.futuristic), BurstStyle.ringAndSparks);
      expect(BurstMath.style(ThemeId.vintage), BurstStyle.stamp);
    });

    test('a fade and a stamp have no flying parts', () {
      expect(BurstMath.particles(BurstStyle.fade), isEmpty);
      expect(BurstMath.particles(BurstStyle.stamp), isEmpty);
      expect(BurstMath.particles(BurstStyle.ringAndSparks), isNotEmpty);
    });

    test('a particle flies out and fades', () {
      expect(BurstMath.distance(18, progress: 0), 0);
      expect(BurstMath.distance(18, progress: 1), 18);
      expect(BurstMath.opacity(progress: 0), 1);
      expect(BurstMath.opacity(progress: 1), 0);
      expect(BurstMath.duration, 0.5);
    });
  });

  test('the greeting follows the time of day', () {
    expect(Greeting.text(hour: 5), 'Good morning');
    expect(Greeting.text(hour: 11), 'Good morning');
    expect(Greeting.text(hour: 12), 'Good afternoon');
    expect(Greeting.text(hour: 17), 'Good afternoon');
    expect(Greeting.text(hour: 18), 'Good evening');
    expect(Greeting.text(hour: 23), 'Good evening');
    expect(Greeting.text(hour: 0), 'Good evening');
    expect(Greeting.text(hour: 4), 'Good evening');
  });

  group('motion', () {
    test('motion needs the switch and no reduce-motion', () {
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

  group('the plant on a real store', () {
    const place = TaskPlacement.day(today);

    test("the progress counts today's tasks", () {
      final s = makeStore();
      final a = s.quickAdd('A', placement: place)!;
      s.quickAdd('B', placement: place);
      // Another day.
      s.quickAdd('C', placement: const TaskPlacement.day(DayKey('2026-10-05')));
      expect(s.plantProgress(today), const PlantProgress(done: 0, total: 2));
      s.toggleDone(taskId: a.id);
      expect(s.plantProgress(today), const PlantProgress(done: 1, total: 2));
    });

    test('the text under the plant says how much is grown', () {
      expect(
        const PlantProgress(done: 0, total: 0).growthText,
        'Nothing planned today',
      );
      expect(
        const PlantProgress(done: 1, total: 4).growthText,
        '25% of today grown',
      );
      expect(
        const PlantProgress(done: 3, total: 3).growthText,
        '100% of today grown',
      );
      expect(const PlantProgress(done: 1, total: 3).percent, 33);
    });

    test(
      'a task checked off with linger stays in the open list a moment',
      () async {
        final s = makeStore();
        final a = s.quickAdd('A', placement: place)!;
        s.toggleDone(taskId: a.id, linger: true);
        expect(s.task(a.id)?.isDone, isTrue);
        expect(ids(s.openTasks(place)), [a.id]);
        await wait(1000);
        expect(s.openTasks(place), isEmpty);
      },
    );

    test('without linger a done task leaves the open list at once', () {
      final s = makeStore();
      final a = s.quickAdd('A', placement: place)!;
      s.toggleDone(taskId: a.id);
      expect(s.openTasks(place), isEmpty);
    });

    test('a day with no tasks is empty', () {
      expect(
        makeStore().plantProgress(today),
        const PlantProgress(done: 0, total: 0),
      );
    });
  });
}
