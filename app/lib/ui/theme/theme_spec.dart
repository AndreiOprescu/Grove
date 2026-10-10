// Port of Sources/Grove/Theme/ThemeSpec.swift.
import 'dart:math' as math;
import 'dart:ui' show Brightness;

import '../../state/theme_id.dart';

// One set of enums for the engine and the screens (docs/tracks.md).
export '../../state/theme_id.dart' show AppearanceMode, ThemeId;

/// One colour in its light and its dark form, each with an opacity.
/// Colours are 0xRRGGBB.
class Tone {
  const Tone(this.light, this.dark, {this.lightAlpha = 1, this.darkAlpha = 1});

  /// One colour for both modes.
  const Tone.fixed(int hex, {double alpha = 1})
    : light = hex,
      dark = hex,
      lightAlpha = alpha,
      darkAlpha = alpha;

  final int light;
  final int dark;
  final double lightAlpha;
  final double darkAlpha;

  int rgb({required bool dark}) => dark ? this.dark : light;
  double alpha({required bool dark}) => dark ? darkAlpha : lightAlpha;

  @override
  bool operator ==(Object other) =>
      other is Tone &&
      other.light == light &&
      other.dark == dark &&
      other.lightAlpha == lightAlpha &&
      other.darkAlpha == darkAlpha;

  @override
  int get hashCode => Object.hash(light, dark, lightAlpha, darkAlpha);
}

/// What light or dark means for the widgets. The enum is in the state
/// layer, which has no Flutter types.
extension AppearanceBrightness on AppearanceMode {
  /// The look the app is forced into. null follows the device.
  Brightness? get brightness => switch (this) {
    AppearanceMode.system => null,
    AppearanceMode.light => Brightness.light,
    AppearanceMode.dark => Brightness.dark,
  };
}

/// The numbers of one theme (PLAN §6.1). Plain data, so the tests can check
/// it without any widget. Every theme has a light and a dark form;
/// [AppearanceMode] picks one.
class ThemeSpec {
  const ThemeSpec({
    required this.id,
    required this.name,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.accent2,
    required this.accent3,
    required this.line,
    required this.blobs,
    required this.radius,
    required this.blobOpacity,
  });

  final ThemeId id;
  final String name;
  final Tone bg;
  final Tone surface;
  final Tone surface2;
  final Tone ink;
  final Tone muted;
  final Tone accent;
  final Tone accent2;
  final Tone accent3;
  final Tone line;
  final List<Tone> blobs;
  final double radius;

  /// How strong the three ambient circles are.
  final double blobOpacity;

  List<Tone> get allTones => [
    bg,
    surface,
    surface2,
    ink,
    muted,
    accent,
    accent2,
    accent3,
    line,
    ...blobs,
  ];

  /// Swift: `ThemeSpec.spec(_:)`.
  static ThemeSpec of(ThemeId id) => all[id.index];

  static const all = [grove, minimal, futuristic, vintage];

  static const grove = ThemeSpec(
    id: ThemeId.grove,
    name: 'Grove',
    bg: Tone(0xF3EEE3, 0x171C16),
    surface: Tone(0xFBF8F1, 0x1F261D),
    surface2: Tone(0xECE5D4, 0x2A3327),
    ink: Tone(0x2F3A2C, 0xE6E9DF),
    muted: Tone(0x7D8574, 0x8E9886),
    accent: Tone(0x5E7F4F, 0x8DB57A),
    accent2: Tone(0xC77B4E, 0xE09A6E),
    accent3: Tone(0xD9B44A, 0xE3C567),
    line: Tone(0xDDD3BF, 0x333D30),
    blobs: [
      Tone(0xA9C79A, 0x3F5E35),
      Tone(0xF2C6A0, 0x6E4A33),
      Tone(0xE8DC9A, 0x5E5630),
    ],
    radius: 16,
    blobOpacity: 0.55,
  );

  static const minimal = ThemeSpec(
    id: ThemeId.minimal,
    name: 'Minimal',
    bg: Tone(0xF7F7F5, 0x121212),
    surface: Tone(0xFFFFFF, 0x1B1B1B),
    surface2: Tone(0xF0F0ED, 0x262626),
    ink: Tone(0x1B1B1A, 0xEDEDEA),
    muted: Tone(0x8C8C88, 0x8A8A86),
    accent: Tone(0x1B1B1A, 0xEDEDEA),
    accent2: Tone(0x7C9A7E, 0x93B596),
    accent3: Tone(0xB9B9B4, 0x6B6B67),
    line: Tone(0xE6E6E2, 0x2C2C2C),
    blobs: [
      Tone(0xE9EEE6, 0x1E241F),
      Tone(0xF1EEE8, 0x242220),
      Tone(0xEDEDED, 0x202020),
    ],
    radius: 10,
    blobOpacity: 0.35,
  );

  static const futuristic = ThemeSpec(
    id: ThemeId.futuristic,
    name: 'Futuristic',
    bg: Tone(0xEEF3FB, 0x070B16),
    surface: Tone(0xFFFFFF, 0x161E3A, lightAlpha: 0.6, darkAlpha: 0.55),
    surface2: Tone(0x3C508C, 0x3C508C, lightAlpha: 0.10, darkAlpha: 0.22),
    ink: Tone(0x0B1530, 0xE4F0FF),
    muted: Tone(0x56628A, 0x7F8DB4),
    accent: Tone(0x0B8F7A, 0x46F0D2),
    accent2: Tone(0x6A3FE0, 0xA27BFF),
    accent3: Tone(0xD43C86, 0xFF6FB5),
    line: Tone(0x3C64C8, 0x78A0FF, lightAlpha: 0.22, darkAlpha: 0.20),
    blobs: [
      Tone(0x7FE8D6, 0x1FD1B5),
      Tone(0xB9A2FF, 0x7B4DFF),
      Tone(0xFFA3CE, 0xFF4FA3),
    ],
    radius: 14,
    blobOpacity: 0.35,
  );

  static const vintage = ThemeSpec(
    id: ThemeId.vintage,
    name: 'Vintage',
    bg: Tone(0xE6D8BA, 0x221A12),
    surface: Tone(0xF3E9D2, 0x2E2318),
    surface2: Tone(0xE7D8B6, 0x3A2C1F),
    ink: Tone(0x3A2A1B, 0xEFE3C8),
    muted: Tone(0x87705A, 0xA8957A),
    accent: Tone(0x8C3B2E, 0xD9735E),
    accent2: Tone(0x3F5B4A, 0x8BAF97),
    accent3: Tone(0xB8862B, 0xD9AA4E),
    line: Tone(0xC8B38D, 0x4E3E2B),
    blobs: [
      Tone(0xF0D9A8, 0x5A4325),
      Tone(0xE2B98A, 0x6B4630),
      Tone(0xF5E6C0, 0x4D3F28),
    ],
    radius: 3,
    blobOpacity: 0.55,
  );
}

/// Colour arithmetic for the contrast test. Colours are 0xRRGGBB.
abstract final class ColorMath {
  /// `top` at `alpha` laid over `on`.
  static int over(int top, {required double alpha, required int on}) {
    int mix(int shift) {
      final t = (top >> shift) & 0xFF;
      final b = (on >> shift) & 0xFF;
      return (t * alpha + b * (1 - alpha)).round();
    }

    return mix(16) << 16 | mix(8) << 8 | mix(0);
  }

  /// WCAG relative luminance.
  static double luminance(int hex) {
    double channel(int shift) {
      final c = ((hex >> shift) & 0xFF) / 255;
      return c <= 0.03928
          ? c / 12.92
          : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0);
  }

  /// WCAG contrast ratio, 1 to 21.
  static double contrast(int a, int b) {
    final la = luminance(a);
    final lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }
}
