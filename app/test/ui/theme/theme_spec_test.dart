// Port of Tests/GroveTests/ThemeSpecTests.swift (the plain numbers of PLAN §6.1).
import 'dart:ui' show Brightness;

import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/theme/theme_spec.dart';

void main() {
  group('the list', () {
    test('four themes in the order of the plan', () {
      expect(ThemeId.values, [
        ThemeId.grove,
        ThemeId.minimal,
        ThemeId.futuristic,
        ThemeId.vintage,
      ]);
      expect(ThemeSpec.all.map((s) => s.id), ThemeId.values);
      expect(ThemeId.initial, ThemeId.grove);
    });

    test('every theme has a name', () {
      expect(ThemeSpec.all.map((s) => s.name), [
        'Grove',
        'Minimal',
        'Futuristic',
        'Vintage',
      ]);
    });

    test('next theme walks the list and wraps around', () {
      var id = ThemeId.grove;
      final seen = <ThemeId>[];
      for (var i = 0; i < 5; i++) {
        id = id.next;
        seen.add(id);
      }
      expect(seen, [
        ThemeId.minimal,
        ThemeId.futuristic,
        ThemeId.vintage,
        ThemeId.grove,
        ThemeId.minimal,
      ]);
    });

    test('an unknown saved theme falls back to Grove', () {
      expect(ThemeId.fromSaved('vintage'), ThemeId.vintage);
      expect(ThemeId.fromSaved('neon-rainbow'), ThemeId.grove);
      expect(ThemeId.fromSaved(''), ThemeId.grove);
      expect(ThemeId.fromSaved(null), ThemeId.grove);
    });
  });

  group('tokens', () {
    test('Grove tokens match the plan', () {
      final s = ThemeSpec.of(ThemeId.grove);
      expect((s.bg.light, s.bg.dark), (0xF3EEE3, 0x171C16));
      expect((s.surface.light, s.surface.dark), (0xFBF8F1, 0x1F261D));
      expect((s.ink.light, s.ink.dark), (0x2F3A2C, 0xE6E9DF));
      expect((s.accent.light, s.accent.dark), (0x5E7F4F, 0x8DB57A));
      expect(s.radius, 16);
    });

    test('Minimal tokens match the plan', () {
      final s = ThemeSpec.of(ThemeId.minimal);
      expect((s.bg.light, s.bg.dark), (0xF7F7F5, 0x121212));
      expect((s.accent.light, s.accent.dark), (0x1B1B1A, 0xEDEDEA));
      expect((s.accent2.light, s.accent2.dark), (0x7C9A7E, 0x93B596));
      expect(s.radius, 10);
    });

    test('Futuristic tokens match the plan', () {
      final s = ThemeSpec.of(ThemeId.futuristic);
      expect(s.bg.dark, 0x070B16);
      expect(s.ink.dark, 0xE4F0FF);
      expect(
        (s.accent.dark, s.accent2.dark, s.accent3.dark),
        (0x46F0D2, 0xA27BFF, 0xFF6FB5),
      );
      expect((s.surface.dark, s.surface.darkAlpha), (0x161E3A, 0.55));
      expect((s.surface2.dark, s.surface2.darkAlpha), (0x3C508C, 0.22));
      expect((s.line.dark, s.line.darkAlpha), (0x78A0FF, 0.20));
      expect(s.radius, 14);
    });

    test('Vintage tokens match the plan', () {
      final s = ThemeSpec.of(ThemeId.vintage);
      expect((s.bg.light, s.surface.light), (0xE6D8BA, 0xF3E9D2));
      expect(
        (s.accent.light, s.accent2.light, s.accent3.light),
        (0x8C3B2E, 0x3F5B4A, 0xB8862B),
      );
      expect(s.line.light, 0xC8B38D);
      expect(s.radius, 3);
    });
  });

  group('light and dark', () {
    test('every theme has a light and a dark look', () {
      for (final s in ThemeSpec.all) {
        expect(s.bg.light, isNot(s.bg.dark), reason: '${s.name}: one look');
        expect(
          ColorMath.luminance(s.bg.light),
          greaterThan(ColorMath.luminance(s.bg.dark)),
          reason: '${s.name}: light is not lighter',
        );
        expect(
          ColorMath.luminance(s.ink.light),
          lessThan(ColorMath.luminance(s.ink.dark)),
          reason: '${s.name}: ink does not flip',
        );
      }
    });

    test('the new variants keep the theme colours', () {
      final v = ThemeSpec.of(ThemeId.vintage);
      final f = ThemeSpec.of(ThemeId.futuristic);
      expect(
        (v.bg.dark, v.ink.dark, v.accent.dark),
        (0x221A12, 0xEFE3C8, 0xD9735E),
      );
      expect(
        (f.bg.light, f.ink.light, f.accent.light),
        (0xEEF3FB, 0x0B1530, 0x0B8F7A),
      );
    });

    test('a theme does not choose light or dark', () {
      expect(AppearanceMode.values, [
        AppearanceMode.system,
        AppearanceMode.light,
        AppearanceMode.dark,
      ]);
      expect(AppearanceMode.system.brightness, isNull);
      expect(AppearanceMode.light.brightness, Brightness.light);
      expect(AppearanceMode.dark.brightness, Brightness.dark);
      expect(AppearanceMode.values.map((m) => m.label), [
        'System',
        'Light',
        'Dark',
      ]);
    });

    test('the saved text of a mode is its name', () {
      expect(AppearanceMode.values.map((m) => m.name), [
        'system',
        'light',
        'dark',
      ]);
      expect(AppearanceMode.fromSaved('dark'), AppearanceMode.dark);
      expect(AppearanceMode.fromSaved('sepia'), AppearanceMode.system);
      expect(AppearanceMode.fromSaved(null), AppearanceMode.system);
    });

    test('a tone gives the colour and the opacity of each mode', () {
      const t = Tone(0x112233, 0x445566, lightAlpha: 0.6, darkAlpha: 0.55);
      expect(t.rgb(dark: false), 0x112233);
      expect(t.rgb(dark: true), 0x445566);
      expect(t.alpha(dark: false), 0.6);
      expect(t.alpha(dark: true), 0.55);
      expect(
        const Tone.fixed(0xABCDEF, alpha: 0.5),
        const Tone(0xABCDEF, 0xABCDEF, lightAlpha: 0.5, darkAlpha: 0.5),
      );
    });
  });

  group('blobs', () {
    test('every theme has three blobs', () {
      for (final s in ThemeSpec.all) {
        expect(s.blobs, hasLength(3));
      }
    });

    test('blobs are fainter in Minimal and Futuristic', () {
      expect(ThemeSpec.of(ThemeId.grove).blobOpacity, 0.55);
      expect(ThemeSpec.of(ThemeId.vintage).blobOpacity, 0.55);
      expect(ThemeSpec.of(ThemeId.minimal).blobOpacity, 0.35);
      expect(ThemeSpec.of(ThemeId.futuristic).blobOpacity, 0.35);
    });
  });

  group('contrast (PLAN §10: ink on surface at least 4.5 to 1)', () {
    test('contrast math knows the extremes', () {
      expect(ColorMath.contrast(0x000000, 0xFFFFFF), closeTo(21, 0.001));
      expect(ColorMath.contrast(0x777777, 0x777777), closeTo(1, 0.001));
    });

    test('half white over black is grey', () {
      expect(ColorMath.over(0xFFFFFF, alpha: 0.5, on: 0x000000), 0x808080);
      expect(ColorMath.over(0x123456, alpha: 1, on: 0xFFFFFF), 0x123456);
      expect(ColorMath.over(0x123456, alpha: 0, on: 0xFFFFFF), 0xFFFFFF);
    });

    test('ink reads on every layer in every variant', () {
      for (final s in ThemeSpec.all) {
        for (final dark in [false, true]) {
          final bg = s.bg.rgb(dark: dark);
          final surface = ColorMath.over(
            s.surface.rgb(dark: dark),
            alpha: s.surface.alpha(dark: dark),
            on: bg,
          );
          final surface2 = ColorMath.over(
            s.surface2.rgb(dark: dark),
            alpha: s.surface2.alpha(dark: dark),
            on: surface,
          );
          final ink = s.ink.rgb(dark: dark);
          final layers = {'bg': bg, 'surface': surface, 'surface2': surface2};
          for (final MapEntry(key: name, value: layer) in layers.entries) {
            expect(
              ColorMath.contrast(ink, layer),
              greaterThanOrEqualTo(4.5),
              reason: '${s.name} ${dark ? 'dark' : 'light'}: ink on $name',
            );
          }
        }
      }
    });
  });
}
