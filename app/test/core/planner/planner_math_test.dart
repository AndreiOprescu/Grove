// Port of Tests/GroveCoreTests/PlannerMathTests.swift and PlannerSummaryTightTests.swift.
import 'package:grove/core/planner/planner_math.dart';
import 'package:flutter_test/flutter_test.dart';

Span span(String id, int s, int e) => Span(id: id, start: s, end: e);

Map<String, Layer> layers(
  List<Span> spans, {
  int minLength = 0,
  int tightWithin = 30,
}) => PlannerMath.layoutLayers(
  spans,
  minLength: minLength,
  tightWithin: tightWithin,
);

void main() {
  group('snap', () {
    test('snaps to nearest step both ways', () {
      expect(PlannerMath.snap(62, step: 5), 60);
      expect(PlannerMath.snap(63, step: 5), 65);
      expect(PlannerMath.snap(67, step: 15), 60);
      expect(PlannerMath.snap(68, step: 15), 75);
      expect(PlannerMath.snap(63, step: 1), 63);
    });
  });

  group('clamp', () {
    test('clampMove keeps block inside day', () {
      expect(PlannerMath.clampMove(start: -30, length: 60), 0);
      expect(PlannerMath.clampMove(start: 1430, length: 60), 1380);
      expect(PlannerMath.clampMove(start: 600, length: 60), 600);
    });
  });

  group('resize', () {
    test('resizeTop has five minute minimum', () {
      expect(
        PlannerMath.resizeTop(start: 600, end: 660, newStart: 640, step: 5),
        (640, 660),
      );
      expect(
        PlannerMath.resizeTop(start: 600, end: 660, newStart: 700, step: 5),
        (655, 660),
      );
      expect(
        PlannerMath.resizeTop(start: 600, end: 660, newStart: -20, step: 5),
        (0, 660),
      );
      expect(
        PlannerMath.resizeTop(start: 600, end: 660, newStart: 612, step: 5),
        (610, 660),
      );
    });

    test('resizeBottom has five minute minimum', () {
      expect(
        PlannerMath.resizeBottom(start: 600, end: 660, newEnd: 700, step: 5),
        (600, 700),
      );
      expect(
        PlannerMath.resizeBottom(start: 600, end: 660, newEnd: 500, step: 5),
        (600, 605),
      );
      expect(
        PlannerMath.resizeBottom(start: 600, end: 660, newEnd: 1500, step: 5),
        (600, 1440),
      );
    });
  });

  group('the 15 minute grid', () {
    test('the grid step and the shortest block are fifteen minutes', () {
      expect(PlannerMath.step, 15);
      expect(PlannerMath.minLength, 15);
    });

    test('resize keeps a fifteen minute minimum on both edges', () {
      expect(
        PlannerMath.resizeTop(
          start: 600,
          end: 660,
          newStart: 700,
          step: 15,
          minLen: 15,
        ),
        (645, 660),
      );
      expect(
        PlannerMath.resizeTop(
          start: 600,
          end: 660,
          newStart: 622,
          step: 15,
          minLen: 15,
        ),
        (615, 660),
      );
      expect(
        PlannerMath.resizeBottom(
          start: 600,
          end: 660,
          newEnd: 500,
          step: 15,
          minLen: 15,
        ),
        (600, 615),
      );
      expect(
        PlannerMath.resizeBottom(
          start: 600,
          end: 660,
          newEnd: 668,
          step: 15,
          minLen: 15,
        ),
        (600, 675),
      );
    });

    test('a task length rounds up to the grid', () {
      expect(PlannerMath.blockLength(0), 15);
      expect(PlannerMath.blockLength(10), 15);
      expect(PlannerMath.blockLength(15), 15);
      expect(PlannerMath.blockLength(20), 30);
      expect(PlannerMath.blockLength(60), 60);
      expect(PlannerMath.blockLength(61), 75);
    });

    test('stepping goes to the next grid line', () {
      expect(PlannerMath.stepped(600, by: 1, step: 15), 615);
      expect(PlannerMath.stepped(600, by: -1, step: 15), 585);
      // A block from before the grid lands on the grid line next to it.
      expect(PlannerMath.stepped(605, by: 1, step: 15), 615);
      expect(PlannerMath.stepped(605, by: -1, step: 15), 600);
      expect(PlannerMath.stepped(614, by: -1, step: 15), 600);
    });
  });

  group('layout (overlaps cascade, they never share the width)', () {
    test('no overlap means no layers', () {
      final l = layers([span('a', 0, 60), span('b', 120, 180)]);
      expect(l['a']!.depth, 0);
      expect(l['a']!.parent, isNull);
      expect(l['b']!.depth, 0);
      expect(l['b']!.parent, isNull);
    });

    test('touching blocks do not overlap', () {
      final l = layers([span('a', 0, 60), span('b', 60, 120)]);
      expect(l['a']!.depth, 0);
      expect(l['b']!.depth, 0);
    });

    test('short block inside a long one sits on top of it', () {
      // 09:00-14:00 with a 5 minute block at 11:00. The long block keeps the whole width.
      final l = layers([span('short', 660, 665), span('long', 540, 840)]);
      expect(l['long']!.depth, 0);
      expect(l['long']!.parent, isNull);
      expect(l['short']!.depth, 1);
      expect(l['short']!.parent, 'long');
      expect(l['short']!.tight, isFalse);
      // Painted first = underneath.
      expect(l['long']!.order, lessThan(l['short']!.order));
    });

    test('blocks starting together put the long one under', () {
      final l = layers([span('short', 540, 545), span('long', 540, 840)]);
      expect(l['long']!.depth, 0);
      expect(l['short']!.parent, 'long');
      // Would hide the long block's title, so it is pushed right.
      expect(l['short']!.tight, isTrue);
    });

    test('a block starting just after another is tight', () {
      final l = layers([span('a', 540, 600), span('b', 550, 610)]);
      expect(l['b']!.tight, isTrue);
      final far = layers([span('a', 540, 600), span('b', 580, 640)]);
      expect(far['b']!.tight, isFalse);
    });

    test('chain of overlaps steps down one level each', () {
      final l = layers([
        span('a', 0, 60),
        span('b', 30, 90),
        span('c', 60, 120),
      ], tightWithin: 10);
      expect(l['a']!.depth, 0);
      expect(l['b']!.depth, 1);
      expect(l['b']!.parent, 'a');
      expect(l['c']!.depth, 2);
      expect(l['c']!.parent, 'b');
    });

    test('a block sits on the most indented block under it', () {
      // c overlaps both a and b. b is already indented on a, so c must sit on b.
      final l = layers([
        span('a', 0, 300),
        span('b', 60, 120),
        span('c', 90, 150),
      ], tightWithin: 10);
      expect(l['b']!.parent, 'a');
      expect(l['c']!.parent, 'b');
      expect(l['c']!.depth, 2);
    });

    test('tiny blocks count as tall as they are drawn', () {
      // A 10 minute block drawn 20 minutes tall covers a block that starts at minute 12.
      final spans = [span('a', 0, 10), span('b', 12, 60)];
      expect(layers(spans, minLength: 0)['b']!.depth, 0);
      final drawn = layers(spans, minLength: 20);
      expect(drawn['b']!.parent, 'a');
      expect(drawn['b']!.tight, isTrue);
    });

    test('paint order is start time then longest first', () {
      final l = layers([
        span('late', 100, 130),
        span('short', 0, 10),
        span('long', 0, 90),
      ]);
      expect(l.values.map((e) => e.order).toList()..sort(), [0, 1, 2]);
      expect(l['long']!.order, 0);
      expect(l['short']!.order, 1);
      expect(l['late']!.order, 2);
    });

    test('layout is stable for empty input', () {
      expect(layers([]), isEmpty);
    });

    test('indents add up along the chain and stop at the maximum', () {
      final l = layers([
        span('a', 0, 300),
        span('b', 100, 200),
        span('c', 150, 250),
        span('d', 160, 240),
      ]);
      final ind = PlannerMath.indents(
        l,
        far: 14,
        tight: (_) => 60,
        maxIndent: 100,
      );
      expect(ind['a'], 0);
      expect(ind['b'], 14); // far from a
      expect(ind['c'], 28); // far from b (start 50 minutes later)
      expect(ind['d'], 88); // tight on c (starts 10 minutes after it)
      final capped = PlannerMath.indents(
        l,
        far: 14,
        tight: (_) => 60,
        maxIndent: 50,
      );
      expect(capped['d'], 50);
    });

    test('a long block that nothing covers has no indent', () {
      final l = layers([span('long', 0, 600), span('x', 100, 105)]);
      expect(
        PlannerMath.indents(
          l,
          far: 14,
          tight: (_) => 60,
          maxIndent: 100,
        )['long'],
        0,
      );
    });

    test('tight shift can depend on the block underneath', () {
      // The shift reveals the title of the block below, so a longer title can ask for more.
      final l = layers([
        span('wide', 0, 300),
        span('a', 0, 10),
        span('b', 5, 15),
      ]);
      final ind = PlannerMath.indents(
        l,
        far: 14,
        tight: (id) => id == 'wide' ? 40 : 90,
        maxIndent: 500,
      );
      expect(ind['a'], 40); // sits on "wide"
      expect(ind['b'], 130); // sits on "a": 40 + 90
    });

    test('a parent can have its own tight limit', () {
      // A block that shows a short description has three text rows, so it stays tight longer.
      final spans = [
        const Span(id: 'p', start: 0, end: 120),
        const Span(id: 'c', start: 40, end: 60),
      ];
      // Same limit for everyone: 40 minutes is not less than 30.
      expect(
        PlannerMath.layoutLayers(
          spans,
          minLength: 0,
          tightWithin: 30,
        )['c']!.tight,
        isFalse,
      );
      // The parent has a short description, so it keeps 45 minutes for itself.
      expect(
        PlannerMath.layoutLayers(
          spans,
          minLength: 0,
          tightWithin: 30,
          tightWithinById: {'p': 45},
        )['c']!.tight,
        isTrue,
      );
      // A limit for another block changes nothing.
      expect(
        PlannerMath.layoutLayers(
          spans,
          minLength: 0,
          tightWithin: 30,
          tightWithinById: {'x': 45},
        )['c']!.tight,
        isFalse,
      );
    });
  });

  group('ripple', () {
    test('ripple cascades through three blocks', () {
      final out = PlannerMath.ripple(
        moved: span('m', 600, 660),
        others: [span('a', 630, 690), span('b', 690, 750), span('c', 750, 780)],
      );
      final byId = {for (final s in out) s.id: s};
      expect(byId['a'], span('a', 660, 720));
      expect(byId['b'], span('b', 720, 780));
      expect(byId['c'], span('c', 780, 810));
    });

    test('ripple returns only changed blocks', () {
      final out = PlannerMath.ripple(
        moved: span('m', 600, 660),
        others: [
          span('before', 540, 600),
          span('hit', 630, 690),
          span('far', 900, 960),
        ],
      );
      expect(out.map((s) => s.id).toList(), ['hit']);
    });

    test('ripple clamps at end of day', () {
      final out = PlannerMath.ripple(
        moved: span('m', 1380, 1440),
        others: [span('a', 1400, 1430)],
      );
      expect(out, [span('a', 1410, 1440)]);
    });
  });

  group('free slot', () {
    test('first free slot finds gap', () {
      final busy = [span('a', 540, 600), span('b', 630, 700)];
      expect(
        PlannerMath.firstFreeSlot(
          length: 30,
          busy: busy,
          from: 540,
          until: 1080,
          step: 5,
        ),
        600,
      );
      expect(
        PlannerMath.firstFreeSlot(
          length: 45,
          busy: busy,
          from: 540,
          until: 1080,
          step: 5,
        ),
        700,
      );
      expect(
        PlannerMath.firstFreeSlot(
          length: 30,
          busy: [],
          from: 543,
          until: 1080,
          step: 5,
        ),
        545,
      );
    });

    test('first free slot returns null when full', () {
      expect(
        PlannerMath.firstFreeSlot(
          length: 30,
          busy: [span('a', 540, 1080)],
          from: 540,
          until: 1080,
          step: 5,
        ),
        isNull,
      );
      expect(
        PlannerMath.firstFreeSlot(
          length: 30,
          busy: [],
          from: 1060,
          until: 1080,
          step: 5,
        ),
        isNull,
      );
    });
  });

  group('label', () {
    test('label formats duration', () {
      expect(PlannerMath.label(start: 675, end: 765), '11:15 – 12:45 · 1h 30m');
      expect(PlannerMath.label(start: 540, end: 585), '09:00 – 09:45 · 45m');
      expect(PlannerMath.label(start: 540, end: 600), '09:00 – 10:00 · 1h');
      expect(PlannerMath.label(start: 1380, end: 1440), '23:00 – 24:00 · 1h');
    });
  });
}
