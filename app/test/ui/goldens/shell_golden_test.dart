// Golden screenshots of the app shell: 4 themes x light/dark x desktop/phone.
// CI runs this file on macOS, Windows and Linux against the same pictures
// (docs/cross-platform-plan.md, milestone F6).
//
// Make the pictures again after a wanted change of the look:
//   cd app && flutter test --update-goldens test/ui/goldens
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/app.dart';
import 'package:grove/ui/shell/shell_model.dart';
import 'package:grove/ui/theme/theme_spec.dart';

import '../support.dart';

/// A 20 x 20 picture in one colour. `dot` paints 2 pixels at the top left.
/// `bar` paints the columns from `barFrom` (`barWidth` wide) in a colour.
Future<Uint8List> _png(
  Color color, {
  Color? dot,
  Color? bar,
  double barFrom = 0,
  double barWidth = 1,
  Color? rightOfBar,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 20, 20), Paint()..color = color);
  if (dot != null) {
    canvas.drawRect(const Rect.fromLTWH(0, 0, 2, 1), Paint()..color = dot);
  }
  if (rightOfBar != null) {
    canvas.drawRect(
      Rect.fromLTWH(barFrom, 0, 20 - barFrom, 20),
      Paint()..color = rightOfBar,
    );
  }
  if (bar != null) {
    canvas.drawRect(
      Rect.fromLTWH(barFrom, 0, barWidth, 20),
      Paint()..color = bar,
    );
  }
  final image = await recorder.endRecording().toImage(20, 20);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  setUpAll(() async {
    TolerantGoldenComparator.install();
    await loadIconFont();
  });

  for (final id in ThemeId.values) {
    for (final mode in [AppearanceMode.light, AppearanceMode.dark]) {
      final name = '${id.name}_${mode.name}';

      testWidgets('desktop $name', (tester) async {
        await withRealShadows(() async {
          await pumpApp(
            tester,
            still(
              themeId: id,
              appearance: mode,
              screen: Screen.planner,
              leftPane: LeftPane.tasks,
            ),
            size: desktopSize,
          );
          await expectLater(
            find.byType(GroveApp),
            matchesGoldenFile('desktop_$name.png'),
          );
        });
      });

      testWidgets('phone $name', (tester) async {
        await withRealShadows(() async {
          await pumpApp(
            tester,
            still(themeId: id, appearance: mode),
            size: phoneSize,
          );
          await expectLater(
            find.byType(GroveApp),
            matchesGoldenFile('phone_$name.png'),
          );
        });
      });
    }
  }

  group('the comparator', () {
    const grey = Color(0xFF808080);

    testWidgets('lets a hair of difference pass', (tester) async {
      await tester.runAsync(() async {
        final a = await _png(grey);
        // 10 of 255 lighter everywhere: under the tolerance of 12
        final b = await _png(const Color(0xFF8A8A8A));
        expect(await TolerantGoldenComparator.differentShare(a, b), 0);
      });
    });

    testWidgets('counts the pixels that are clearly different', (tester) async {
      await tester.runAsync(() async {
        final a = await _png(grey);
        final b = await _png(grey, dot: const Color(0xFFFF0000));
        // 2 of 400 pixels
        expect(await TolerantGoldenComparator.differentShare(a, b), 0.005);
        final c = await _png(const Color(0xFF202020));
        expect(await TolerantGoldenComparator.differentShare(a, c), 1);
      });
    });

    testWidgets('a softer or harder edge is not a difference', (tester) async {
      await tester.runAsync(() async {
        const black = Color(0xFF000000);
        const white = Color(0xFFFFFFFF);
        // black | one soft column | white. Each OS gives the soft column
        // another grey.
        final a = await _png(
          black,
          rightOfBar: white,
          bar: const Color(0xFFB4B4B4),
          barFrom: 10,
        );
        final b = await _png(
          black,
          rightOfBar: white,
          bar: const Color(0xFF5A5A5A),
          barFrom: 10,
        );
        expect(await TolerantGoldenComparator.differentShare(a, b), 0);
        expect(await TolerantGoldenComparator.differentShare(b, a), 0);
      });
    });

    testWidgets('a thin line that is missing is a difference', (tester) async {
      await tester.runAsync(() async {
        final a = await _png(grey, bar: const Color(0xFF000000), barFrom: 10);
        final b = await _png(grey);
        // the 20 pixels of the line
        expect(await TolerantGoldenComparator.differentShare(a, b), 0.05);
        expect(await TolerantGoldenComparator.differentShare(b, a), 0.05);
      });
    });

    testWidgets('a shape that moved by 3 pixels is a difference', (
      tester,
    ) async {
      await tester.runAsync(() async {
        const black = Color(0xFF000000);
        final a = await _png(grey, bar: black, barFrom: 5, barWidth: 6);
        final b = await _png(grey, bar: black, barFrom: 8, barWidth: 6);
        final share = await TolerantGoldenComparator.differentShare(a, b);
        expect(share, greaterThan(TolerantGoldenComparator.pixelBudget));
      });
    });

    test('allows 0.2 % of the pixels, 12 of 255 per channel, 1 pixel of '
        'edge', () {
      expect(TolerantGoldenComparator.pixelBudget, 0.002);
      expect(TolerantGoldenComparator.channelTolerance, 12);
      expect(TolerantGoldenComparator.edgeRadius, 1);
    });
  });
}
