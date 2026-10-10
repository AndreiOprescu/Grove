// Port of Sources/Grove/Theme/Theme.swift: the colours, fonts and shape of
// one theme in light or dark, and how widgets get it.
import 'dart:ui' show FontFeature, FontVariation, lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'theme_spec.dart';

/// Colour, font and shape tokens of one theme (PLAN §6), in light or dark.
/// Built from a [ThemeSpec]. Read it with [GroveTheme.of].
@immutable
class GroveTheme {
  const GroveTheme._({
    required this.kind,
    required this.name,
    required this.brightness,
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
    required this.blobOpacity,
    required this.radius,
  });

  /// The theme `id` in its light or dark form.
  factory GroveTheme.make(ThemeId id, Brightness brightness) {
    final spec = ThemeSpec.of(id);
    final dark = brightness == Brightness.dark;
    Color color(Tone tone) =>
        Color(0xFF000000 | tone.rgb(dark: dark))
            .withValues(alpha: tone.alpha(dark: dark));
    return GroveTheme._(
      kind: id,
      name: spec.name,
      brightness: brightness,
      bg: color(spec.bg),
      surface: color(spec.surface),
      surface2: color(spec.surface2),
      ink: color(spec.ink),
      muted: color(spec.muted),
      accent: color(spec.accent),
      accent2: color(spec.accent2),
      accent3: color(spec.accent3),
      line: color(spec.line),
      blobs: List.unmodifiable(spec.blobs.map(color)),
      blobOpacity: spec.blobOpacity,
      radius: spec.radius,
    );
  }

  final ThemeId kind;
  final String name;
  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color ink;
  final Color muted;
  final Color accent;
  final Color accent2;
  final Color accent3;
  final Color line;
  final List<Color> blobs;
  final double blobOpacity;
  final double radius;

  /// The theme of the widgets above `context`. Grove light when there is
  /// no [GroveThemeScope].
  static GroveTheme of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GroveThemeScope>()?.theme ??
      _fallback;

  static final _fallback = GroveTheme.make(ThemeId.initial, Brightness.light);

  // Personality (PLAN §6.2)

  /// Panels are glass: they blur what is behind them (Futuristic).
  bool get glass => kind == ThemeId.futuristic;

  /// Square check boxes (Futuristic, Vintage).
  bool get squareChecks =>
      kind == ThemeId.futuristic || kind == ThemeId.vintage;

  /// Paper noise and a vignette (Vintage).
  bool get paper => kind == ThemeId.vintage;

  /// Faint 32 pt grid lines on the background (Futuristic).
  bool get gridLines => kind == ThemeId.futuristic;

  /// Headings in capitals with wide spacing and a glow (Futuristic).
  bool get upperHeadings => kind == ThemeId.futuristic;

  /// Thin borders and no shadows (Minimal).
  bool get hairlines => kind == ThemeId.minimal;

  /// Neon glow on the now line and check boxes (Futuristic).
  bool get glow => kind == ThemeId.futuristic;

  /// Dashed borders on chips (Vintage).
  bool get dashedChips => kind == ThemeId.vintage;

  /// Lines under the text of a note (Vintage), as tall as one line.
  bool get ruledLines => kind == ThemeId.vintage;

  /// The ink stamp on a finished task (Vintage).
  bool get stampOnDone => kind == ThemeId.vintage;

  /// The surface with nothing showing through, for menus and pop-ups.
  Color get solidSurface => Color.alphaBlend(surface, bg);

  // Fonts. No font files are bundled: each list names the font of the Mac
  // app first, then the nearest font that ships with Windows and Android.

  static const _serif = ['New York', 'Georgia', 'Noto Serif', 'serif'];
  static const _rounded = [
    'SF Pro Rounded',
    'Segoe UI Variable Text',
    'Segoe UI',
    'Roboto',
    'sans-serif',
  ];
  static const _sans = [
    'Segoe UI Variable Text',
    'Segoe UI',
    'Roboto',
    'sans-serif',
  ];
  static const _mono = [
    'Menlo',
    'Cascadia Mono',
    'Consolas',
    'Roboto Mono',
    'monospace',
  ];
  static const _baskerville = ['Georgia', 'Noto Serif', 'serif'];
  static const _typewriter = ['Courier New', 'Cutive Mono', 'monospace'];
  static const _tabular = [FontFeature.tabularFigures()];

  /// Titles and headings.
  TextStyle heading(double size, {FontWeight weight = FontWeight.w600}) =>
      switch (kind) {
        ThemeId.grove => TextStyle(
          fontFamily: '.AppleSystemUIFontSerif',
          fontFamilyFallback: _serif,
          fontSize: size,
          fontWeight: weight,
        ),
        ThemeId.minimal => TextStyle(
          fontFamily: '.AppleSystemUIFont',
          fontFamilyFallback: _sans,
          fontSize: size,
          fontWeight: weight,
        ),
        ThemeId.futuristic => TextStyle(
          fontFamily: '.AppleSystemUIFont',
          fontFamilyFallback: _sans,
          fontSize: size,
          fontWeight: weight,
          // wider letters where the font can do it (Swift: `.width(.expanded)`)
          fontVariations: const [FontVariation.width(125)],
        ),
        ThemeId.vintage => TextStyle(
          fontFamily: 'Baskerville',
          fontFamilyFallback: _baskerville,
          fontSize: size,
          fontWeight: weight,
          fontStyle: FontStyle.italic,
        ),
      };

  /// Text in lists, panels and notes.
  TextStyle body(double size, {FontWeight weight = FontWeight.w400}) =>
      switch (kind) {
        ThemeId.grove => TextStyle(
          fontFamily: '.AppleSystemUIFontRounded',
          fontFamilyFallback: _rounded,
          fontSize: size,
          fontWeight: weight,
        ),
        ThemeId.minimal || ThemeId.futuristic => TextStyle(
          fontFamily: '.AppleSystemUIFont',
          fontFamilyFallback: _sans,
          fontSize: size,
          fontWeight: weight,
        ),
        ThemeId.vintage => TextStyle(
          fontFamily: 'American Typewriter',
          fontFamilyFallback: _typewriter,
          fontSize: size,
          fontWeight: weight,
        ),
      };

  /// Times, counts and other numbers.
  TextStyle number(double size, {FontWeight weight = FontWeight.w400}) =>
      switch (kind) {
        ThemeId.futuristic => TextStyle(
          fontFamily: 'SF Mono',
          fontFamilyFallback: _mono,
          fontSize: size,
          fontWeight: weight,
        ),
        _ => body(size, weight: weight).copyWith(fontFeatures: _tabular),
      };

  /// Letter spacing of headings.
  double get headingTracking => switch (kind) {
    ThemeId.futuristic => 1.5,
    ThemeId.minimal => -0.2,
    _ => 0,
  };

  /// A heading in the case of the theme. Futuristic is in capitals.
  String headingText(String text) => upperHeadings ? text.toUpperCase() : text;

  /// The theme `t` of the way from `a` to `b`. Colours and the radius mix;
  /// the personality switches half way.
  static GroveTheme lerp(GroveTheme a, GroveTheme b, double t) {
    if (t <= 0) return a;
    if (t >= 1) return b;
    final near = t < 0.5 ? a : b;
    Color mix(Color x, Color y) => Color.lerp(x, y, t)!;
    return GroveTheme._(
      kind: near.kind,
      name: near.name,
      brightness: near.brightness,
      bg: mix(a.bg, b.bg),
      surface: mix(a.surface, b.surface),
      surface2: mix(a.surface2, b.surface2),
      ink: mix(a.ink, b.ink),
      muted: mix(a.muted, b.muted),
      accent: mix(a.accent, b.accent),
      accent2: mix(a.accent2, b.accent2),
      accent3: mix(a.accent3, b.accent3),
      line: mix(a.line, b.line),
      blobs: List.unmodifiable([
        for (var i = 0; i < a.blobs.length; i++) mix(a.blobs[i], b.blobs[i]),
      ]),
      blobOpacity: lerpDouble(a.blobOpacity, b.blobOpacity, t)!,
      radius: lerpDouble(a.radius, b.radius, t)!,
    );
  }

  /// Colours for the Material widgets the app uses (menus, tooltips, text
  /// selection), so they match the theme.
  ThemeData toMaterial() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: brightness,
        ).copyWith(
          primary: accent,
          onPrimary: solidSurface,
          secondary: accent2,
          tertiary: accent3,
          surface: solidSurface,
          onSurface: ink,
          onSurfaceVariant: muted,
          outline: line,
          outlineVariant: line,
        );
    final text = body(13);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      fontFamily: text.fontFamily,
      fontFamilyFallback: text.fontFamilyFallback,
      splashFactory: NoSplash.splashFactory,
      dividerTheme: DividerThemeData(color: line),
      popupMenuTheme: PopupMenuThemeData(
        color: solidSurface,
        surfaceTintColor: const Color(0x00000000),
        elevation: 6,
        textStyle: text.copyWith(color: ink),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: line),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          color: ink,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: body(11).copyWith(color: bg),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GroveTheme &&
      other.kind == kind &&
      other.brightness == brightness &&
      other.bg == bg &&
      other.surface == surface &&
      other.surface2 == surface2 &&
      other.ink == ink &&
      other.muted == muted &&
      other.accent == accent &&
      other.accent2 == accent2 &&
      other.accent3 == accent3 &&
      other.line == line &&
      listEquals(other.blobs, blobs) &&
      other.blobOpacity == blobOpacity &&
      other.radius == radius;

  @override
  int get hashCode => Object.hash(
    kind,
    brightness,
    bg,
    surface,
    surface2,
    ink,
    muted,
    accent,
    accent2,
    accent3,
    line,
    Object.hashAll(blobs),
    blobOpacity,
    radius,
  );
}

/// Gives a [GroveTheme] to the widgets below. Swift: `@Environment(\.theme)`.
class GroveThemeScope extends InheritedWidget {
  const GroveThemeScope({super.key, required this.theme, required super.child});

  final GroveTheme theme;

  @override
  bool updateShouldNotify(GroveThemeScope oldWidget) =>
      oldWidget.theme != theme;
}

/// A [GroveThemeScope] that cross-fades to a new theme in 0.35 s (PLAN §6).
class AnimatedGroveTheme extends ImplicitlyAnimatedWidget {
  const AnimatedGroveTheme({
    super.key,
    required this.theme,
    required this.child,
  }) : super(duration: crossFade, curve: Curves.easeInOut);

  /// How long the colours take to change.
  static const crossFade = Duration(milliseconds: 350);

  final GroveTheme theme;
  final Widget child;

  @override
  AnimatedWidgetBaseState<AnimatedGroveTheme> createState() =>
      _AnimatedGroveThemeState();
}

class _AnimatedGroveThemeState
    extends AnimatedWidgetBaseState<AnimatedGroveTheme> {
  _GroveThemeTween? _theme;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _theme = visitor(
      _theme,
      widget.theme,
      (dynamic value) => _GroveThemeTween(begin: value as GroveTheme),
    ) as _GroveThemeTween?;
  }

  @override
  Widget build(BuildContext context) =>
      GroveThemeScope(theme: _theme!.evaluate(animation), child: widget.child);
}

class _GroveThemeTween extends Tween<GroveTheme> {
  _GroveThemeTween({super.begin});

  @override
  GroveTheme lerp(double t) => GroveTheme.lerp(begin!, end!, t);
}
