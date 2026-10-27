import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/planner/planner_math.dart';
import 'package:grove/state/rules/replan_rules.dart';

final today = DayKey('2026-10-26');

Span span(String id, int s, int e) => Span(id: id, start: s, end: e);

ReplanItem item(
  String id, {
  ReplanGroup group = ReplanGroup.task,
  int base = 60,
  List<Span> blocks = const [],
  String? title,
}) => ReplanItem(
  id: id,
  title: title ?? id,
  group: group,
  base: base,
  blocks: blocks,
);

List<ReplanStep> plan(
  List<ReplanItem> items, {
  int now = 600,
  int until = 1380,
  List<Span> fixed = const [],
  Map<String, int> pct = const {},
}) => ReplanRules.plan(
  ReplanInput(day: today, items: items, fixed: fixed, now: now, until: until),
  pct,
);

ReplanStep step(List<ReplanStep> steps, String id) =>
    steps.firstWhere((s) => s.item.id == id);

List<String> order(List<ReplanStep> steps) => [
  for (final s in steps) s.item.id,
];

void main() {
  group('remaining', () {
    test('rounds the part left up to the grid of 15 minutes', () {
      expect(ReplanRules.remaining(30, 40), 30);
      expect(ReplanRules.remaining(45, 50), 30);
      expect(ReplanRules.remaining(60, 80), 15);
      expect(ReplanRules.remaining(60, 99), 15);
      expect(ReplanRules.remaining(60, 100), 0);
      expect(ReplanRules.remaining(60, 0), 60);
      expect(ReplanRules.remaining(50, 0), 60);
    });

    test('a percent stays inside 0 to 100', () {
      expect(ReplanRules.clampPct(-5), 0);
      expect(ReplanRules.clampPct(40), 40);
      expect(ReplanRules.clampPct(250), 100);
    });
  });

  group('the start', () {
    test('now goes up to the next step of 15 minutes', () {
      expect(plan([item('A')], now: 601).single.placedAt, 615);
      expect(plan([item('A')], now: 615).single.placedAt, 615);
      expect(plan([item('A')], now: 600).single.placedAt, 600);
    });

    test('the input says where the plan starts and ends', () {
      final input = ReplanInput(
        day: today,
        items: const [],
        fixed: const [],
        now: 601,
        until: 1380,
      );
      expect(input.from, 615);
      expect(input.end, 1380);
    });
  });

  group('order', () {
    test('deadlines first, then goals, then other tasks', () {
      final steps = plan([
        item('T', group: ReplanGroup.task, base: 15),
        item('G', group: ReplanGroup.goal, base: 15),
        item('D', group: ReplanGroup.deadline, base: 15),
      ]);
      expect(order(steps), ['D', 'G', 'T']);
      expect(step(steps, 'D').placedAt, 600);
      expect(step(steps, 'G').placedAt, 615);
      expect(step(steps, 'T').placedAt, 630);
    });

    test('in a group the shortest rest goes first', () {
      final steps = plan(
        [item('Long', base: 60), item('Short', base: 60)],
        pct: {'Short': 50},
      );
      expect(order(steps), ['Short', 'Long']);
      expect(step(steps, 'Short').placedAt, 600);
      expect(step(steps, 'Long').placedAt, 630);
    });

    test('a tie goes by the first block, then by the title', () {
      final steps = plan([
        item('None', base: 30),
        item('Late', base: 30, blocks: [span('late', 900, 930)]),
        item('Early', base: 30, blocks: [span('early', 700, 730)]),
        item('b', title: 'B', base: 30),
        item('a', title: 'A', base: 30),
      ]);
      expect(order(steps), ['Early', 'Late', 'a', 'b', 'None']);
    });
  });

  group('placing', () {
    test('nothing is placed before now', () {
      final steps = plan([item('A', base: 30)], now: 700);
      expect(step(steps, 'A').placedAt, 705);
    });

    test('fixed items are busy', () {
      final steps = plan(
        [item('A', base: 30)],
        fixed: [span('E', 600, 660), span('F', 675, 690)],
      );
      expect(step(steps, 'A').placedAt, 690);
    });

    test('items do not overlap each other', () {
      final steps = plan([item('A', base: 30), item('B', base: 45)]);
      expect(step(steps, 'A').placedAt, 600);
      expect(step(steps, 'B').placedAt, 630);
    });

    test('the plan stops at the sleep line', () {
      final steps = plan(
        [item('A', base: 60), item('B', base: 30)],
        until: 690,
        fixed: [span('E', 600, 630)],
      );
      expect(step(steps, 'B').placedAt, 630);
      expect(step(steps, 'A').placedAt, isNull);
      expect(step(steps, 'A').overflow, isTrue);
      expect(step(steps, 'B').overflow, isFalse);
    });

    test('a sleep line at or before now gives the whole day', () {
      final steps = plan([item('A', base: 60)], now: 1380, until: 1380);
      expect(step(steps, 'A').placedAt, 1380);
      final input = ReplanInput(
        day: today,
        items: const [],
        fixed: const [],
        now: 1380,
        until: 1300,
      );
      expect(input.end, 1440);
    });

    test('a task that does not fit overflows', () {
      final steps = plan([item('A', base: 60)], now: 1400, until: 1440);
      expect(step(steps, 'A').overflow, isTrue);
      expect(step(steps, 'A').done, isFalse);
    });

    test('100% is done and not placed', () {
      final steps = plan(
        [
          item('A', blocks: [span('a', 540, 600)]),
        ],
        pct: {'A': 100},
      );
      final a = step(steps, 'A');
      expect(a.done, isTrue);
      expect(a.overflow, isFalse);
      expect(a.placedAt, isNull);
      expect(a.remaining, 0);
      expect(a.kept, isEmpty);
    });

    test('0% moves the whole length and keeps nothing', () {
      final steps = plan([
        item('A', base: 60, blocks: [span('a', 600, 660)]),
      ], now: 630);
      final a = step(steps, 'A');
      expect(a.kept, isEmpty);
      expect(a.remaining, 60);
      expect(a.placedAt, 630);
    });
  });

  group('the worked part', () {
    test('a running block is cut at now', () {
      final steps = plan(
        [
          item('A', base: 60, blocks: [span('a', 600, 660)]),
        ],
        now: 630,
        pct: {'A': 50},
      );
      final a = step(steps, 'A');
      expect(a.kept, [span('a', 600, 630)]);
      expect(a.remaining, 30);
      expect(a.placedAt, 630);
    });

    test('a block in the past keeps its place, cut to the worked share', () {
      final steps = plan(
        [
          item(
            'A',
            base: 90,
            blocks: [span('a', 480, 540), span('b', 700, 730)],
          ),
        ],
        now: 630,
        pct: {'A': 50},
      );
      final a = step(steps, 'A');
      // 90 minutes, 50% done: 45 worked, 45 left.
      expect(a.kept, [span('a', 480, 525)]);
      expect(a.remaining, 45);
      expect(a.placedAt, 630);
    });

    test('a block still to come gives a worked part that ends at now', () {
      final steps = plan(
        [
          item('A', base: 60, blocks: [span('a', 700, 760)]),
        ],
        now: 625,
        pct: {'A': 50},
      );
      final a = step(steps, 'A');
      expect(a.kept, [span('a', 600, 630)]);
      expect(a.placedAt, 630);
    });

    test('more time gone than worked: the worked part is the share', () {
      // 09:00 to 10:00, half done, at 14:00: 30 minutes, not 60.
      final steps = plan(
        [
          item(
            'G',
            group: ReplanGroup.goal,
            base: 60,
            blocks: [span('G', 540, 600)],
          ),
        ],
        now: 840,
        pct: {'G': 50},
      );
      expect(step(steps, 'G').kept, [span('G', 540, 570)]);
      expect(step(steps, 'G').remaining, 30);
    });

    test('less time gone than worked: the worked part reaches back', () {
      // 13:00 to 15:00, 90% done at 13:15: 105 worked, 15 left.
      final steps = plan(
        [
          item(
            'G',
            group: ReplanGroup.goal,
            base: 120,
            blocks: [span('G', 780, 900)],
          ),
        ],
        now: 795,
        pct: {'G': 90},
      );
      expect(step(steps, 'G').kept, [span('G', 690, 795)]);
      expect(step(steps, 'G').remaining, 15);
    });

    test('a worked part that has to be made is put in free time', () {
      final steps = plan(
        [
          item('A', base: 60, blocks: [span('a', 960, 1020)]),
          item('B', base: 60, blocks: [span('b', 1020, 1080)]),
        ],
        now: 840,
        fixed: [span('Meeting', 780, 840)],
        pct: {'A': 50, 'B': 50},
      );
      // Not on the meeting, and not on each other.
      expect(step(steps, 'A').kept, [span('a', 750, 780)]);
      expect(step(steps, 'B').kept, [span('b', 720, 750)]);
    });

    test('the worked part does not start before midnight', () {
      List<Span> kept(int now) => step(
        plan(
          [
            item('A', base: 60, blocks: [span('a', 700, 760)]),
          ],
          now: now,
          pct: {'A': 80},
        ),
        'A',
      ).kept;
      expect(kept(15), [span('a', 0, 15)]);
      // At midnight there is no time before now: no worked part.
      expect(kept(0), isEmpty);
    });

    test('a task with no block keeps nothing', () {
      final steps = plan([item('A', base: 60)], pct: {'A': 50});
      final a = step(steps, 'A');
      expect(a.kept, isEmpty);
      expect(a.remaining, 30);
      expect(a.placedAt, 600);
    });

    test('a task that does not fit keeps nothing', () {
      final steps = plan(
        [
          item('A', base: 120, blocks: [span('a', 600, 720)]),
        ],
        now: 630,
        until: 645,
        pct: {'A': 25},
      );
      final a = step(steps, 'A');
      expect(a.overflow, isTrue);
      expect(a.kept, isEmpty);
    });

    test('a goal that does not fit keeps its worked part', () {
      final steps = plan(
        [
          item(
            'G',
            group: ReplanGroup.goal,
            base: 120,
            blocks: [span('G', 600, 720)],
          ),
        ],
        now: 630,
        until: 645,
        pct: {'G': 25},
      );
      final g = step(steps, 'G');
      expect(g.item.isGoal, isTrue);
      expect(g.overflow, isTrue);
      expect(g.kept, [span('G', 600, 630)]);
    });

    test('a worked task goes after a shorter rest', () {
      final steps = plan(
        [
          item('A', base: 60, blocks: [span('a', 700, 760)]),
          item('B', base: 15),
        ],
        now: 630,
        pct: {'A': 50},
      );
      expect(step(steps, 'B').placedAt, 630);
      expect(step(steps, 'A').placedAt, 645);
    });
  });
}
