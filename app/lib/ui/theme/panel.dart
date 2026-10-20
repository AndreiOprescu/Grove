// Port of the panel, the heading and the chip of Sources/Grove/Theme/
// Theme.swift and ThemeDecor.swift.
import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import 'grove_theme.dart';
import 'theme_spec.dart';

/// A panel: the theme's surface, border and shadow. Futuristic panels are
/// glass: they blur what is behind them.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.radius,
    this.border,
    this.borderWidth,
  });

  final Widget child;

  /// Corner radius. The radius of the theme when null.
  final double? radius;

  /// Border colour. The line colour of the theme when null.
  final Color? border;

  /// Border width. 0.5 in Minimal and 1 in the other themes when null.
  final double? borderWidth;

  /// How strong the blur of a glass panel is.
  static const glassBlur = 18.0;

  // A SwiftUI shadow of radius r looks like a Flutter blur radius of 2 r.
  static List<BoxShadow>? _shadow(GroveTheme theme) => switch (theme.kind) {
    ThemeId.grove => const [
      BoxShadow(
        color: Color(0x1A3C4828),
        blurRadius: 30,
        offset: Offset(0, 10),
      ),
    ],
    ThemeId.vintage => const [
      BoxShadow(color: Color(0x2E3A2A1B), offset: Offset(2, 3)),
    ],
    ThemeId.minimal || ThemeId.futuristic => null,
  };

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final corners = BorderRadius.circular(radius ?? theme.radius);
    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border.all(
          color: border ?? theme.line,
          width: borderWidth ?? (theme.hairlines ? 0.5 : 1),
        ),
        borderRadius: corners,
        boxShadow: theme.glass ? null : _shadow(theme),
      ),
      child: child,
    );
    if (!theme.glass) return box;
    return ClipRRect(
      borderRadius: corners,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: glassBlur, sigmaY: glassBlur),
        child: box,
      ),
    );
  }
}

/// A heading in the font, case and spacing of the theme. Futuristic glows.
class ThemedHeading extends StatelessWidget {
  const ThemedHeading(
    this.text,
    this.size, {
    super.key,
    this.weight = FontWeight.w600,
    this.color,
  });

  final String text;
  final double size;
  final FontWeight weight;

  /// The ink colour of the theme when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return Text(
      theme.headingText(text),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme
          .heading(size, weight: weight)
          .copyWith(
            color: color ?? theme.ink,
            letterSpacing: theme.headingTracking,
            shadows: theme.glow
                ? [
                    Shadow(
                      color: theme.accent.withValues(alpha: 0.5),
                      blurRadius: 16,
                    ),
                  ]
                : null,
          ),
    );
  }
}

/// The background of a small tag: a soft capsule, or a box with a dashed
/// border where the theme asks for it (Vintage).
class ThemedChip extends StatelessWidget {
  const ThemedChip({
    super.key,
    required this.tint,
    required this.child,
    this.fill = 0.13,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  });

  final Color tint;
  final Widget child;

  /// How strong the tint of the background is, 0 to 1.
  final double fill;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final inside = Padding(padding: padding, child: child);
    final colour = tint.withValues(alpha: fill);
    if (!theme.dashedChips) {
      return DecoratedBox(
        decoration: ShapeDecoration(
          color: colour,
          shape: const StadiumBorder(),
        ),
        child: inside,
      );
    }
    return DashedBorder(
      color: tint.withValues(alpha: 0.7),
      radius: theme.radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colour,
          borderRadius: BorderRadius.circular(theme.radius),
        ),
        child: inside,
      ),
    );
  }
}

/// A dashed line around `child`, inside its edge.
class DashedBorder extends StatelessWidget {
  const DashedBorder({
    super.key,
    required this.color,
    required this.child,
    this.radius = 0,
    this.width = 1,
    this.dash = 3,
    this.gap = 2,
  });

  final Color color;
  final Widget child;
  final double radius;
  final double width;
  final double dash;
  final double gap;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _DashPainter(
      color: color,
      radius: radius,
      width: width,
      dash: dash,
      gap: gap,
    ),
    child: child,
  );
}

class _DashPainter extends CustomPainter {
  const _DashPainter({
    required this.color,
    required this.radius,
    required this.width,
    required this.dash,
    required this.gap,
  });

  final Color color;
  final double radius;
  final double width;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    if (dash <= 0 || gap < 0 || size.isEmpty) return;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(width / 2),
          Radius.circular(radius),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    for (final metric in outline.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += dash + gap) {
        canvas.drawPath(metric.extractPath(at, at + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.width != width ||
      old.dash != dash ||
      old.gap != gap;
}
