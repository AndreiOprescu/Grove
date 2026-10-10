// The Flutter theme: colours of a spec in light or dark, personality, fonts,
// the cross-fade and the panel. Ports the "SwiftUI theme" tests of
// Tests/GroveTests/ThemeSpecTests.swift and the personality test of
// ThemeMotionTests.swift.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/theme/grove_theme.dart';
import 'package:grove/ui/theme/panel.dart';
import 'package:grove/ui/theme/theme_spec.dart';

GroveTheme light(ThemeId id) => GroveTheme.make(id, Brightness.light);
GroveTheme dark(ThemeId id) => GroveTheme.make(id, Brightness.dark);

Widget themed(GroveTheme theme, Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: GroveThemeScope(
    theme: theme,
    child: Center(child: child),
  ),
);

void main() {
  group('a theme', () {
    test('carries its spec', () {
      for (final id in ThemeId.values) {
        final t = light(id);
        expect(t.kind, id);
        expect(t.name, ThemeSpec.of(id).name);
        expect(t.radius, ThemeSpec.of(id).radius);
        expect(t.blobs, hasLength(3));
        expect(t.blobOpacity, ThemeSpec.of(id).blobOpacity);
      }
    });

    test('takes the light or the dark colour of each tone', () {
      expect(light(ThemeId.grove).bg, const Color(0xFFF3EEE3));
      expect(dark(ThemeId.grove).bg, const Color(0xFF171C16));
      expect(light(ThemeId.grove).ink, const Color(0xFF2F3A2C));
      expect(dark(ThemeId.vintage).accent, const Color(0xFFD9735E));
      expect(light(ThemeId.grove).brightness, Brightness.light);
      expect(dark(ThemeId.grove).brightness, Brightness.dark);
    });

    test('keeps the opacity of see-through tones', () {
      final f = dark(ThemeId.futuristic);
      expect(f.surface.toARGB32() & 0xFFFFFF, 0x161E3A);
      expect(f.surface.a, closeTo(0.55, 0.003));
      expect(f.line.a, closeTo(0.20, 0.003));
      expect(light(ThemeId.futuristic).surface.a, closeTo(0.6, 0.003));
      expect(light(ThemeId.grove).surface.a, 1);
    });

    test('personality follows the plan', () {
      final g = light(ThemeId.grove);
      final m = light(ThemeId.minimal);
      final f = light(ThemeId.futuristic);
      final v = light(ThemeId.vintage);
      expect(
        [g.squareChecks, m.squareChecks, f.squareChecks, v.squareChecks],
        [false, false, true, true],
      );
      expect([g.glass, m.glass, f.glass, v.glass], [false, false, true, false]);
      expect([v.paper, g.paper], [true, false]);
      expect([f.gridLines, v.gridLines], [true, false]);
      expect([f.upperHeadings, g.upperHeadings], [true, false]);
      expect([m.hairlines, g.hairlines], [true, false]);
      expect([f.glow, g.glow], [true, false]);
    });

    test('only Vintage has ruled lines, dashed chips and the stamp', () {
      for (final id in ThemeId.values) {
        final t = light(id);
        expect(t.ruledLines, id == ThemeId.vintage);
        expect(t.dashedChips, id == ThemeId.vintage);
        expect(t.stampOnDone, id == ThemeId.vintage);
        expect(t.gridLines, id == ThemeId.futuristic);
      }
    });

    test('two themes of the same kind and mode are equal', () {
      expect(light(ThemeId.grove), light(ThemeId.grove));
      expect(light(ThemeId.grove), isNot(dark(ThemeId.grove)));
      expect(light(ThemeId.grove), isNot(light(ThemeId.minimal)));
    });
  });

  group('fonts', () {
    test('headings are semibold and body text is regular', () {
      for (final id in ThemeId.values) {
        expect(light(id).heading(28).fontWeight, FontWeight.w600);
        expect(light(id).heading(28).fontSize, 28);
        expect(light(id).body(13).fontWeight, FontWeight.w400);
        expect(
          light(id).body(13, weight: FontWeight.w600).fontWeight,
          FontWeight.w600,
        );
      }
    });

    test('every font names a family and other families to fall back on', () {
      for (final id in ThemeId.values) {
        final t = light(id);
        for (final style in [t.heading(20), t.body(13), t.number(12)]) {
          expect(style.fontFamily, isNotEmpty);
          expect(style.fontFamilyFallback, isNotEmpty);
        }
      }
    });

    test('each theme uses its font files', () {
      String? family(TextStyle style) => style.fontFamily;
      final grove = light(ThemeId.grove);
      expect(family(grove.heading(20)), 'Newsreader');
      expect(family(grove.body(13)), 'Nunito');
      expect(family(grove.number(12)), 'Nunito');

      final minimal = light(ThemeId.minimal);
      expect(family(minimal.heading(20)), 'Inter');
      expect(family(minimal.body(13)), 'Inter');
      expect(family(minimal.number(12)), 'Inter');

      final futuristic = light(ThemeId.futuristic);
      expect(family(futuristic.heading(20)), 'Archivo');
      expect(family(futuristic.body(13)), 'Inter');
      expect(family(futuristic.number(12)), 'JetBrains Mono');

      final vintage = light(ThemeId.vintage);
      expect(family(vintage.heading(20)), 'Libre Baskerville');
      expect(family(vintage.body(13)), 'Courier Prime');
      expect(family(vintage.number(12)), 'Courier Prime');
    });

    test('Futuristic titles are wide', () {
      expect(
        light(ThemeId.futuristic).heading(20).fontVariations,
        contains(const FontVariation.width(125)),
      );
    });

    test('fonts with an optical size get the size of the text', () {
      for (final style in [
        light(ThemeId.grove).heading(28),
        light(ThemeId.minimal).heading(28),
        light(ThemeId.minimal).body(28),
      ]) {
        expect(
          style.fontVariations,
          contains(const FontVariation.opticalSize(28)),
        );
      }
    });

    test('Vintage titles are italic', () {
      expect(light(ThemeId.vintage).heading(20).fontStyle, FontStyle.italic);
      expect(
        light(ThemeId.grove).heading(20).fontStyle,
        isNot(FontStyle.italic),
      );
    });

    test('numbers keep one width per digit', () {
      for (final id in ThemeId.values) {
        final style = light(id).number(12);
        final mono = id == ThemeId.futuristic;
        expect(
          style.fontFeatures?.contains(const FontFeature.tabularFigures()) ??
              false,
          !mono,
          reason: '$id',
        );
      }
    });

    test('heading spacing: wide in Futuristic, tight in Minimal', () {
      expect(light(ThemeId.futuristic).headingTracking, 1.5);
      expect(light(ThemeId.minimal).headingTracking, -0.2);
      expect(light(ThemeId.grove).headingTracking, 0);
      expect(light(ThemeId.vintage).headingTracking, 0);
    });

    test('Futuristic headings are in capitals', () {
      expect(light(ThemeId.futuristic).headingText('Planner'), 'PLANNER');
      expect(light(ThemeId.grove).headingText('Planner'), 'Planner');
    });
  });

  group('the cross-fade', () {
    test('starts at the old theme and ends at the new one', () {
      final a = light(ThemeId.grove);
      final b = dark(ThemeId.futuristic);
      expect(GroveTheme.lerp(a, b, 0), a);
      expect(GroveTheme.lerp(a, b, 1), b);
    });

    test('mixes the colours half way', () {
      final a = light(ThemeId.grove);
      final b = dark(ThemeId.grove);
      final mid = GroveTheme.lerp(a, b, 0.5);
      expect(mid.bg, Color.lerp(a.bg, b.bg, 0.5));
      expect(mid.ink, Color.lerp(a.ink, b.ink, 0.5));
      expect(mid.blobs[1], Color.lerp(a.blobs[1], b.blobs[1], 0.5));
    });

    test('mixes the corner radius', () {
      final mid = GroveTheme.lerp(
        light(ThemeId.grove),
        light(ThemeId.vintage),
        0.5,
      );
      expect(mid.radius, closeTo(9.5, 1e-9));
    });

    testWidgets('the animated theme takes 0.35 s', (tester) async {
      GroveTheme? seen;
      Widget app(GroveTheme theme) => AnimatedGroveTheme(
        theme: theme,
        child: Builder(
          builder: (context) {
            seen = GroveTheme.of(context);
            return const SizedBox();
          },
        ),
      );
      final a = light(ThemeId.grove);
      final b = light(ThemeId.vintage);
      await tester.pumpWidget(app(a));
      expect(seen, a);
      await tester.pumpWidget(app(b));
      await tester.pump(const Duration(milliseconds: 175));
      expect(seen!.bg, isNot(a.bg));
      expect(seen!.bg, isNot(b.bg));
      await tester.pump(const Duration(milliseconds: 176));
      expect(seen, b);
      expect(AnimatedGroveTheme.crossFade, const Duration(milliseconds: 350));
    });
  });

  group('the scope', () {
    testWidgets('gives the theme to the widgets below', (tester) async {
      late GroveTheme seen;
      await tester.pumpWidget(
        themed(
          dark(ThemeId.minimal),
          Builder(
            builder: (context) {
              seen = GroveTheme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen, dark(ThemeId.minimal));
    });

    testWidgets('without a scope the theme is Grove light', (tester) async {
      late GroveTheme seen;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            seen = GroveTheme.of(context);
            return const SizedBox();
          },
        ),
      );
      expect(seen, light(ThemeId.grove));
    });
  });

  group('the panel', () {
    BoxDecoration decorationOf(WidgetTester tester) {
      final box = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(Panel),
          matching: find.byType(DecoratedBox),
        ),
      );
      return box.decoration as BoxDecoration;
    }

    Future<void> pumpPanel(WidgetTester tester, GroveTheme theme) =>
        tester.pumpWidget(
          themed(theme, const Panel(child: SizedBox(width: 100, height: 60))),
        );

    testWidgets('Grove: surface, line, round corners, a soft shadow', (
      tester,
    ) async {
      final t = light(ThemeId.grove);
      await pumpPanel(tester, t);
      final d = decorationOf(tester);
      expect(d.color, t.surface);
      expect(d.border, Border.all(color: t.line));
      expect(d.borderRadius, BorderRadius.circular(16));
      expect(d.boxShadow, hasLength(1));
      expect(d.boxShadow!.single.offset, const Offset(0, 10));
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('Minimal: a hairline and no shadow', (tester) async {
      await pumpPanel(tester, light(ThemeId.minimal));
      final d = decorationOf(tester);
      expect((d.border! as Border).top.width, 0.5);
      expect(d.boxShadow, anyOf(isNull, isEmpty));
    });

    testWidgets('Vintage: a hard shadow down and to the right', (tester) async {
      await pumpPanel(tester, light(ThemeId.vintage));
      final shadow = decorationOf(tester).boxShadow!.single;
      expect(shadow.blurRadius, 0);
      expect(shadow.offset, const Offset(2, 3));
    });

    testWidgets('Futuristic: glass, a blur of what is behind', (tester) async {
      final t = dark(ThemeId.futuristic);
      await pumpPanel(tester, t);
      expect(find.byType(BackdropFilter), findsOneWidget);
      final d = decorationOf(tester);
      expect(d.color, t.surface);
      expect(d.boxShadow, anyOf(isNull, isEmpty));
    });

    testWidgets('takes its own radius and border when asked', (tester) async {
      await tester.pumpWidget(
        themed(
          light(ThemeId.grove),
          const Panel(
            radius: 4,
            border: Color(0xFF112233),
            borderWidth: 2,
            child: SizedBox(width: 10, height: 10),
          ),
        ),
      );
      final d = decorationOf(tester);
      expect(d.borderRadius, BorderRadius.circular(4));
      expect(d.border, Border.all(color: const Color(0xFF112233), width: 2));
    });
  });

  group('the heading', () {
    testWidgets('Futuristic: capitals, wide spacing and a glow', (
      tester,
    ) async {
      final t = dark(ThemeId.futuristic);
      await tester.pumpWidget(themed(t, const ThemedHeading('Planner', 20)));
      final text = tester.widget<Text>(find.byType(Text));
      expect(text.data, 'PLANNER');
      expect(text.style!.letterSpacing, 1.5);
      expect(text.style!.shadows, hasLength(1));
      expect(text.style!.color, t.ink);
    });

    testWidgets('Grove: as written, no glow', (tester) async {
      await tester.pumpWidget(
        themed(light(ThemeId.grove), const ThemedHeading('Planner', 20)),
      );
      final text = tester.widget<Text>(find.byType(Text));
      expect(text.data, 'Planner');
      expect(text.style!.shadows, anyOf(isNull, isEmpty));
    });
  });

  group('the chip', () {
    testWidgets('Vintage chips have a dashed border', (tester) async {
      await tester.pumpWidget(
        themed(
          light(ThemeId.vintage),
          const ThemedChip(tint: Color(0xFF8C3B2E), child: Text('tag')),
        ),
      );
      expect(find.byType(DashedBorder), findsOneWidget);
    });

    testWidgets('other chips are a soft capsule', (tester) async {
      await tester.pumpWidget(
        themed(
          light(ThemeId.grove),
          const ThemedChip(tint: Color(0xFF5E7F4F), child: Text('tag')),
        ),
      );
      expect(find.byType(DashedBorder), findsNothing);
    });
  });
}
