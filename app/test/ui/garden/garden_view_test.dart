// The Garden screen (milestone F10): one plant that grows with each task
// you finish. Port of the view rules of Sources/Grove/Garden/.
import 'package:flutter/material.dart' hide Row;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/garden/garden_painter.dart';
import 'package:grove/ui/garden/garden_view.dart';
import 'package:grove/ui/theme/grove_theme.dart';
import 'package:grove/ui/theme/growing_plant.dart';

import '../planner/planner_support.dart';
import '../tasks/tasks_support.dart' show addTask;

AppStore gardenStore() => plannerStore()..screen = Screen.garden;

/// Adds `count` finished tasks.
void finish(AppStore store, int count) {
  for (var i = 0; i < count; i++) {
    addTask(store, 'Task $i', id: 'DONE-$i');
    store.toggleDone(taskId: 'DONE-$i');
  }
}

Finder card(int index) => find.byKey(ValueKey('garden-stage-$index'));

void main() {
  group('the picture', () {
    test('the "random" number is steady and from 0 to 1', () {
      for (var a = 0; a < 40; a++) {
        for (var b = 0; b < 60; b += 7) {
          final n = GardenPainter.noise(a, b);
          expect(n, greaterThanOrEqualTo(0));
          expect(n, lessThan(1));
          expect(GardenPainter.noise(a, b), n);
        }
      }
      expect(GardenPainter.noise(0), 0);
    });

    test('each level grows by small steps, the trunk first', () {
      GardenPainter at(double growth) => GardenPainter(
        growth: growth,
        leaf: const Color(0xFF00AA00),
        bark: const Color(0xFF6E4D33),
        petal: const Color(0xFFCC6677),
        heart: const Color(0xFFDDAA33),
        soil: const Color(0xFF5C402B),
      );
      expect(at(0).levelGrowth(0), 0);
      expect(at(1.5).levelGrowth(0), 0.5);
      expect(at(3).levelGrowth(0), 1);
      expect(at(11).levelGrowth(0), 1);
      // level 1 starts at 1.5 and is full 1.8 later
      expect(at(1.5).levelGrowth(1), 0);
      expect(at(2.4).levelGrowth(1), closeTo(0.5, 1e-9));
      expect(at(3.3).levelGrowth(1), closeTo(1, 1e-9));
      // each next level starts 1.8 later
      expect(at(8.7).levelGrowth(5), 0);
      expect(at(10.5).levelGrowth(5), closeTo(1, 1e-9));
      expect(GardenPainter.levels, 5);
      for (var k = 0; k <= 5; k++) {
        var last = 0.0;
        for (var g = 0.0; g <= 11; g += 0.25) {
          final now = at(g).levelGrowth(k);
          expect(now, greaterThanOrEqualTo(last));
          last = now;
        }
      }
    });
  });

  testWidgets('a new garden: a seed, and what the next step needs', (
    tester,
  ) async {
    final store = gardenStore();
    await pumpPlanner(tester, store);
    expect(tester.takeException(), isNull);
    expect(find.text('This screen is not built yet.'), findsNothing);
    expect(find.byType(GardenView), findsOneWidget);

    expect(find.text('Garden'), findsWidgets);
    expect(
      find.text('Your plant grows each time you finish a task.'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('garden-hero')),
        matching: find.text('Seed'),
      ),
      findsOneWidget,
    );
    expect(find.text('0 tasks finished'), findsOneWidget);
    expect(find.text('1 more task to become a sprout'), findsOneWidget);
    expect(find.text('Stages'), findsOneWidget);
  });

  testWidgets('the plant grows with each finished task', (tester) async {
    final store = gardenStore();
    await pumpPlanner(tester, store);
    GardenDrawing hero() => tester.widget<GardenDrawing>(
      find.descendant(
        of: find.byKey(const ValueKey('garden-hero')),
        matching: find.byType(GardenDrawing),
      ),
    );
    expect(hero().growth, 0);

    finish(store, 1);
    await tester.pumpAndSettle();
    expect(find.text('1 task finished'), findsOneWidget);
    expect(find.text('2 more tasks to become a seedling'), findsOneWidget);
    expect(hero().growth, 1);

    // an open task does not count
    addTask(store, 'Open', id: 'OPEN');
    await tester.pumpAndSettle();
    expect(find.text('1 task finished'), findsOneWidget);

    finish(store, 2);
    await tester.pumpAndSettle();
    expect(find.text('2 tasks finished'), findsOneWidget);
    expect(find.text('1 more task to become a seedling'), findsOneWidget);
    expect(hero().growth, 1.5);

    final bar = tester.getSize(find.byKey(const ValueKey('garden-bar')));
    final fill = tester.getSize(find.byKey(const ValueKey('garden-bar-fill')));
    expect(bar, const Size(360, 8));
    expect(fill.width, 180);
  });

  testWidgets('the bar of the next step is never shorter than 8 points', (
    tester,
  ) async {
    final store = gardenStore();
    await pumpPlanner(tester, store);
    expect(
      tester.getSize(find.byKey(const ValueKey('garden-bar-fill'))).width,
      8,
    );
  });

  testWidgets('a full tree has no next step', (tester) async {
    final store = gardenStore();
    finish(store, 120);
    await pumpPlanner(tester, store);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('garden-hero')),
        matching: find.text('Ancient tree'),
      ),
      findsOneWidget,
    );
    expect(find.text('120 tasks finished'), findsOneWidget);
    expect(
      find.text('Fully grown. Keep going. It likes company.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('garden-bar')), findsNothing);
  });

  testWidgets('the ladder shows the 12 stages; the one of now has a ring', (
    tester,
  ) async {
    final store = gardenStore();
    finish(store, 4);
    await pumpPlanner(tester, store, size: const Size(1100, 1400));
    for (final stage in Garden.stages) {
      expect(card(stage.index), findsOneWidget);
      expect(
        find.descendant(of: card(stage.index), matching: find.text(stage.name)),
        findsOneWidget,
      );
      final drawing = tester.widget<GardenDrawing>(
        find.descendant(
          of: card(stage.index),
          matching: find.byType(GardenDrawing),
        ),
      );
      expect(drawing.growth, stage.index);
    }
    Finder inCard(int i, String text) =>
        find.descendant(of: card(i), matching: find.text(text));
    expect(inCard(0, 'Start'), findsOneWidget);
    expect(inCard(1, '1 task'), findsOneWidget);
    expect(inCard(2, '3 tasks'), findsOneWidget);
    expect(inCard(11, '120 tasks'), findsOneWidget);

    BoxDecoration box(int i) =>
        tester.widget<DecoratedBox>(card(i)).decoration as BoxDecoration;
    final theme = GroveTheme.of(tester.element(card(0)));
    // 4 tasks: the seedling (from 3) is the stage of now
    expect((box(2).border! as Border).top.width, 2);
    expect((box(2).border! as Border).top.color, theme.accent);
    expect((box(1).border! as Border).top.width, 1);
    expect((box(1).border! as Border).top.color, theme.line);
    expect((box(3).border! as Border).top.width, 1);
    // a stage that is not reached is pale
    Opacity pale(int i) => tester.widget<Opacity>(
      find.descendant(of: card(i), matching: find.byType(Opacity)),
    );
    expect(pale(2).opacity, 1);
    expect(pale(3).opacity, 0.25);
  });

  testWidgets('the cards of the ladder sit on whole points, 118 wide or more', (
    tester,
  ) async {
    for (final size in [desktopSize, phoneSize, const Size(1500, 900)]) {
      final store = gardenStore();
      await pumpPlanner(tester, store, size: size);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        card(11),
        200,
        scrollable: find
            .descendant(
              of: find.byType(GardenView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final first = tester.getRect(card(0));
      expect(first.width, greaterThanOrEqualTo(118));
      expect(first.width, lessThanOrEqualTo(160));
      expect(first.left, first.left.roundToDouble());
      expect(first.width, first.width.roundToDouble());
      final second = tester.getRect(card(1));
      expect(second.left - first.right, 10);
      expect(second.size, first.size);
    }
  });

  testWidgets('a screen reader hears the plant and each stage', (tester) async {
    final handle = tester.ensureSemantics();
    final store = gardenStore();
    finish(store, 4);
    await pumpPlanner(tester, store, size: const Size(1100, 1400));
    expect(find.bySemanticsLabel('Garden plant, Seedling'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Garden plant, Seedling')),
      matchesSemantics(
        label: 'Garden plant, Seedling',
        value: '4 tasks finished',
      ),
    );
    SemanticsNode stage(String label) =>
        tester.getSemantics(find.bySemanticsLabel(label));
    expect(
      stage('Sprout, from 1 tasks'),
      matchesSemantics(label: 'Sprout, from 1 tasks', value: 'Reached'),
    );
    expect(
      stage('Seedling, from 3 tasks'),
      matchesSemantics(label: 'Seedling, from 3 tasks', value: 'Now'),
    );
    expect(
      stage('Young plant, from 6 tasks'),
      matchesSemantics(label: 'Young plant, from 6 tasks', value: 'Not yet'),
    );
    handle.dispose();
  });

  testWidgets('a big tree sways less than a sprout', (tester) async {
    expect(GardenView.sway(growth: 0, at: 1.25), closeTo(3, 1e-9));
    expect(GardenView.sway(growth: 11, at: 1.25), closeTo(1.5, 1e-9));
    expect(GardenView.sway(growth: 5.5, at: 3.75), closeTo(-2.25, 1e-9));
  });

  testWidgets('the Day Spread has the small plant of the day in its header', (
    tester,
  ) async {
    final store = plannerStore()..screen = Screen.today;
    addTask(store, 'One', id: 'ONE');
    addTask(store, 'Two', id: 'TWO');
    store.toggleDone(taskId: 'ONE');
    await pumpPlanner(tester, store, size: const Size(1280, 720));
    final plant = tester.widget<GrowingPlant>(find.byType(GrowingPlant));
    expect(plant.height, 44);
    expect(plant.progress, const PlantProgress(done: 1, total: 2));
    expect(plant.motion, isFalse);
    // at the right end of the header, level with the date
    final box = tester.getRect(find.byType(GrowingPlant));
    final date = tester.getRect(find.byKey(const ValueKey('spread-date')));
    expect(box.right, 1280 - 16);
    expect(box.left, greaterThan(date.right));
    expect(box.top, lessThanOrEqualTo(date.top));

    await pumpPlanner(tester, store, size: phoneSize);
    expect(tester.takeException(), isNull);
    expect(find.byType(GrowingPlant), findsOneWidget);
  });
}
