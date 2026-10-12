// The small plant of the day (PLAN §6.3). Port of the view rules of
// Sources/Grove/Theme/GrowingPlant.swift.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/state/state.dart' show PlantProgress;
import 'package:grove/ui/theme/grove_theme.dart';
import 'package:grove/ui/theme/growing_plant.dart';
import 'package:grove/ui/theme/theme_spec.dart';

import '../support.dart';

Future<void> pumpPlant(
  WidgetTester tester,
  PlantProgress progress, {
  bool motion = false,
  double? height,
  bool reduceMotion = false,
}) async {
  final theme = GroveTheme.make(ThemeId.grove, Brightness.light);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: GroveThemeScope(
          theme: theme,
          child: Center(
            child: height == null
                ? GrowingPlant(progress: progress, motion: motion)
                : GrowingPlant(
                    progress: progress,
                    motion: motion,
                    height: height,
                  ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the plant is 40 points high and 0.8 times as wide', (
    tester,
  ) async {
    await pumpPlant(tester, const PlantProgress(done: 0, total: 0));
    expect(tester.getSize(find.byType(GrowingPlant)), const Size(32, 40));
    await pumpPlant(tester, const PlantProgress(done: 0, total: 0), height: 44);
    expect(
      tester.getSize(find.byType(GrowingPlant)).height,
      moreOrLessEquals(44),
    );
    expect(
      tester.getSize(find.byType(GrowingPlant)).width,
      moreOrLessEquals(35.2),
    );
  });

  testWidgets('a screen reader hears the growth of the day', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpPlant(tester, const PlantProgress(done: 0, total: 0));
    expect(
      tester.getSemantics(find.byType(GrowingPlant)),
      matchesSemantics(label: 'Plant', value: 'Nothing planned today'),
    );
    await pumpPlant(tester, const PlantProgress(done: 1, total: 2));
    expect(
      tester.getSemantics(find.byType(GrowingPlant)),
      matchesSemantics(label: 'Plant', value: '50 percent of today grown'),
    );
    handle.dispose();
  });

  testWidgets('the picture gets the leaves and the flower of the rules', (
    tester,
  ) async {
    PlantPainter painter() => tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(GrowingPlant),
            matching: find.byType(CustomPaint),
          ),
        )
        .map((p) => p.painter)
        .whereType<PlantPainter>()
        .single;

    await pumpPlant(tester, const PlantProgress(done: 0, total: 4));
    expect(painter().amount, 0);
    expect(painter().flower, isFalse);

    await pumpPlant(tester, const PlantProgress(done: 2, total: 4));
    expect(painter().amount, 3);
    expect(painter().flower, isFalse);

    await pumpPlant(tester, const PlantProgress(done: 4, total: 4));
    expect(painter().amount, 6);
    expect(painter().flower, isTrue);
  });

  testWidgets('with motion off nothing moves', (tester) async {
    await pumpPlant(tester, const PlantProgress(done: 1, total: 4));
    expect(tester.hasRunningAnimations, isFalse);
    await pumpPlant(tester, const PlantProgress(done: 3, total: 4));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('with motion on the plant sways; "reduce motion" stops it', (
    tester,
  ) async {
    double angle() {
      final t = tester.widget<Transform>(
        find.descendant(
          of: find.byType(GrowingPlant),
          matching: find.byType(Transform),
        ),
      );
      // sin of the turn
      return t.transform.storage[1];
    }

    await pumpPlant(
      tester,
      const PlantProgress(done: 1, total: 4),
      motion: true,
    );
    // The sway runs on a timer, not on a ticker: it asks for a frame 11
    // times a second (a small plant moves little), not at every refresh of
    // the screen.
    expect(tester.hasRunningAnimations, isFalse);
    expect(await framesAsked(tester), 11);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 40));
    // a quarter of the 5 seconds: about 3 degrees
    expect(angle(), closeTo(0.052, 0.004));

    await pumpPlant(
      tester,
      const PlantProgress(done: 1, total: 4),
      motion: true,
      reduceMotion: true,
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.hasRunningAnimations, isFalse);
    expect(angle(), 0);
    await tester.pumpWidget(const SizedBox());
  });
}
