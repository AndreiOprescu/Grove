// The box of a task and its burst (PLAN §6.2, §6.3). Port of the view rules
// of Sources/Grove/Theme/CheckBox.swift. The numbers of the burst are in
// `BurstMath`; test/state/theme_motion_test.dart tests them.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/state/state.dart' show BurstMath, BurstStyle;
import 'package:grove/ui/theme/check_box.dart';
import 'package:grove/ui/theme/grove_theme.dart';
import 'package:grove/ui/theme/theme_spec.dart';

final box = find.byType(CheckBox);
final burst = find.byType(CheckBurst);
final leaves = find.descendant(of: burst, matching: find.byType(Icon));

/// Shows one box. A second call with a new `isOn` is a click on it.
Future<void> pumpBox(
  WidgetTester tester, {
  required bool isOn,
  bool motion = true,
  bool reduceMotion = false,
  ThemeId themeId = ThemeId.grove,
  double size = 17,
}) => tester.pumpWidget(
  MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: GroveThemeScope(
        theme: GroveTheme.make(themeId, Brightness.light),
        child: Center(
          child: CheckBox(isOn: isOn, size: size, motion: motion),
        ),
      ),
    ),
  ),
);

/// Turns the box on, as a click does.
Future<void> check(
  WidgetTester tester, {
  bool motion = true,
  bool reduceMotion = false,
  ThemeId themeId = ThemeId.grove,
}) async {
  await pumpBox(
    tester,
    isOn: false,
    motion: motion,
    reduceMotion: reduceMotion,
    themeId: themeId,
  );
  await pumpBox(
    tester,
    isOn: true,
    motion: motion,
    reduceMotion: reduceMotion,
    themeId: themeId,
  );
  await tester.pump();
}

void main() {
  group('the burst', () {
    testWidgets('a box that turns on throws six leaves, and they fly out 18 '
        'points in half a second', (tester) async {
      await check(tester);
      expect(burst, findsOneWidget);
      final parts = BurstMath.particles(BurstStyle.leaves);
      expect(leaves, findsNWidgets(parts.length));
      final theme = GroveTheme.make(ThemeId.grove, Brightness.light);
      expect(tester.widget<Icon>(leaves.first).color, theme.accent);
      expect(tester.widget<Icon>(leaves.first).size, 7);

      // At the start the leaves are on the box.
      final middle = tester.getCenter(box);
      for (var i = 0; i < parts.length; i++) {
        expect((tester.getCenter(leaves.at(i)) - middle).distance, lessThan(1));
      }

      // Half of the time: each leaf is on its line, as far as the rule says.
      await tester.pump(const Duration(milliseconds: 250));
      final far = BurstMath.distance(
        BurstMath.reach,
        progress: Curves.easeOut.transform(0.5),
      );
      expect(far, greaterThan(9));
      for (final (i, part) in parts.indexed) {
        final angle = part.angle * math.pi / 180;
        final offset = tester.getCenter(leaves.at(i)) - middle;
        expect(offset.dx, moreOrLessEquals(math.cos(angle) * far, epsilon: .5));
        expect(offset.dy, moreOrLessEquals(math.sin(angle) * far, epsilon: .5));
      }

      // After half a second the burst is gone, and nothing moves.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(burst, findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('the leaves fade while they fly', (tester) async {
      await check(tester);
      double opacity() => tester
          .widget<Opacity>(
            find.descendant(of: burst, matching: find.byType(Opacity)).first,
          )
          .opacity;
      expect(opacity(), moreOrLessEquals(1));
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        opacity(),
        moreOrLessEquals(
          BurstMath.opacity(progress: Curves.easeOut.transform(0.5)),
          epsilon: 0.01,
        ),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('Minimal: a fade and no flying parts', (tester) async {
      await check(tester, themeId: ThemeId.minimal);
      expect(burst, findsOneWidget);
      expect(tester.widget<CheckBurst>(burst).style, BurstStyle.fade);
      expect(leaves, findsNothing);
      expect(
        find.descendant(of: burst, matching: find.byType(DecoratedBox)),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      expect(burst, findsNothing);
    });

    testWidgets('Futuristic: a ring and six sparks', (tester) async {
      await check(tester, themeId: ThemeId.futuristic);
      expect(tester.widget<CheckBurst>(burst).style, BurstStyle.ringAndSparks);
      expect(leaves, findsNothing);
      // The ring, and a square for each spark.
      expect(
        find.descendant(of: burst, matching: find.byType(DecoratedBox)),
        findsNWidgets(1 + BurstMath.particles(BurstStyle.ringAndSparks).length),
      );
      await tester.pumpAndSettle();
      expect(burst, findsNothing);
    });

    testWidgets('Vintage: the stamp "DONE"', (tester) async {
      await check(tester, themeId: ThemeId.vintage);
      expect(tester.widget<CheckBurst>(burst).style, BurstStyle.stamp);
      expect(
        find.descendant(of: burst, matching: find.text('DONE')),
        findsOneWidget,
      );
      // The stamp is at the right of the box.
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        tester.getCenter(find.text('DONE')).dx,
        greaterThan(tester.getRect(box).right),
      );
      await tester.pumpAndSettle();
      expect(burst, findsNothing);
    });

    testWidgets('with Motion off there is no burst', (tester) async {
      await check(tester, motion: false);
      expect(burst, findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('with "Reduce motion" on the device there is no burst', (
      tester,
    ) async {
      await check(tester, reduceMotion: true);
      expect(burst, findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a box with no word about motion plays no burst', (
      tester,
    ) async {
      Widget one(bool isOn) => Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: CheckBox(isOn: isOn)),
      );
      await tester.pumpWidget(one(false));
      await tester.pumpWidget(one(true));
      await tester.pump();
      expect(burst, findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a box that turns off plays no burst', (tester) async {
      await pumpBox(tester, isOn: true);
      await pumpBox(tester, isOn: false);
      await tester.pump();
      expect(burst, findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('a box that is on from the start plays no burst', (
      tester,
    ) async {
      await pumpBox(tester, isOn: true);
      await tester.pump();
      expect(burst, findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a second check while the burst plays starts it again', (
      tester,
    ) async {
      await check(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await pumpBox(tester, isOn: false);
      await pumpBox(tester, isOn: true);
      await tester.pump();
      // 400 ms after the first check the first burst would be near its end.
      await tester.pump(const Duration(milliseconds: 300));
      expect(burst, findsOneWidget);
      await tester.pumpAndSettle();
      expect(burst, findsNothing);
    });

    testWidgets('Motion goes off while the burst plays: the burst goes away', (
      tester,
    ) async {
      await check(tester);
      expect(burst, findsOneWidget);
      await pumpBox(tester, isOn: true, motion: false);
      await tester.pump();
      expect(burst, findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('the burst takes no room, no click and has no name', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      Widget one(bool isOn) => Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: CheckBox(isOn: isOn, motion: true),
          ),
        ),
      );
      await tester.pumpWidget(one(false));
      await tester.pumpWidget(one(true));
      await tester.pump(const Duration(milliseconds: 100));
      expect(burst, findsOneWidget);
      // The box is as big as before.
      expect(tester.getSize(box), const Size(17, 17));
      // A click on the box goes to the button around it.
      await tester.tap(box);
      expect(taps, 1);
      expect(
        find.descendant(of: box, matching: find.bySemanticsLabel(RegExp('.'))),
        findsNothing,
      );
      await tester.pumpAndSettle();
      handle.dispose();
    });
  });

  group('the box', () {
    testWidgets('with motion the box fills with a spring', (tester) async {
      await check(tester);
      final mark = find.descendant(of: box, matching: find.byIcon(Icons.check));
      final grow = find.descendant(
        of: box,
        matching: find.ancestor(of: mark, matching: find.byType(Transform)),
      );
      // On the way the check mark is smaller than at the end.
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.hasRunningAnimations, isTrue);
      expect(
        tester.widget<Transform>(grow).transform.entry(0, 0),
        inExclusiveRange(0.2, 1.0),
      );
      await tester.pumpAndSettle();
      // At the end nothing makes it small.
      expect(grow, findsNothing);
      expect(tester.getSize(mark).width, moreOrLessEquals(17 * 0.7));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('with Motion off the box is full at once', (tester) async {
      await check(tester, motion: false);
      expect(
        find.descendant(of: box, matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('an empty box has no check mark, a full box has one', (
      tester,
    ) async {
      await pumpBox(tester, isOn: false);
      expect(find.byIcon(Icons.check), findsNothing);
      await pumpBox(tester, isOn: true, motion: false);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });
  });
}
