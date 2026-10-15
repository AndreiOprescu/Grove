// The persona: one person drawn by hand on the canvas, in the style of the
// garden plant. The drawing is the same at every level (owner, 2026-10-15).
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../theme/grove_theme.dart';
import '../theme/theme_spec.dart';

class PersonaPainter {
  const PersonaPainter({
    required this.shirt,
    required this.trousers,
    required this.skin,
    required this.hair,
    required this.soil,
    required this.grass,
  });

  final Color shirt;
  final Color trousers;
  final Color skin;
  final Color hair;
  final Color soil;
  final Color grass;

  static Color _faded(Color c, double by) => c.withValues(alpha: c.a * by);

  void paint(Canvas canvas, Size size) {
    // The person is about half as wide as tall, so it is sized by the
    // smaller side and always fits its box.
    final h = min(size.height * 0.84, size.width / 0.75);
    final base = Offset(size.width / 2, size.height * 0.88);
    _paintGround(canvas, base, h);
    _paintLegs(canvas, base, h);
    _paintBody(canvas, base, h);
    _paintHead(canvas, base, h);
  }

  void _paintGround(Canvas canvas, Offset base, double h) {
    final half = h * 0.26;
    canvas.drawOval(
      Rect.fromLTWH(base.dx - half, base.dy - h * 0.018, half * 2, h * 0.07),
      Paint()..color = soil,
    );
    canvas.drawOval(
      Rect.fromLTWH(base.dx - half, base.dy - h * 0.018, half * 2, h * 0.034),
      Paint()..color = _faded(grass, 0.55),
    );
  }

  Paint _stroke(Color c, double width) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round;

  void _paintLegs(Canvas canvas, Offset base, double h) {
    final hip = base.dy - h * 0.40;
    final leg = _stroke(trousers, h * 0.07);
    for (final side in const [-1.0, 1.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(base.dx + side * h * 0.045, hip)
          ..quadraticBezierTo(
            base.dx + side * h * 0.06,
            base.dy - h * 0.20,
            base.dx + side * h * 0.07,
            base.dy - h * 0.03,
          ),
        leg,
      );
      // The shoe.
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(base.dx + side * h * 0.085, base.dy - h * 0.015),
          width: h * 0.10,
          height: h * 0.045,
        ),
        Paint()..color = soil,
      );
    }
  }

  void _paintBody(Canvas canvas, Offset base, double h) {
    final top = base.dy - h * 0.74;
    final hip = base.dy - h * 0.38;
    final arm = _stroke(shirt, h * 0.06);
    // Arms first, so the body covers the shoulders.
    for (final side in const [-1.0, 1.0]) {
      final shoulder = Offset(base.dx + side * h * 0.11, top + h * 0.05);
      final hand = Offset(base.dx + side * h * 0.19, hip - h * 0.02);
      canvas.drawPath(
        Path()
          ..moveTo(shoulder.dx, shoulder.dy)
          ..quadraticBezierTo(
            base.dx + side * h * 0.19,
            top + h * 0.16,
            hand.dx,
            hand.dy,
          ),
        arm,
      );
      canvas.drawCircle(hand, h * 0.03, Paint()..color = skin);
    }
    final body = Path()
      ..moveTo(base.dx - h * 0.12, top + h * 0.04)
      ..quadraticBezierTo(
        base.dx,
        top - h * 0.02,
        base.dx + h * 0.12,
        top + h * 0.04,
      )
      ..lineTo(base.dx + h * 0.10, hip)
      ..quadraticBezierTo(base.dx, hip + h * 0.03, base.dx - h * 0.10, hip)
      ..close();
    canvas.drawPath(body, Paint()..color = shirt);
    // The collar.
    canvas.drawPath(
      Path()
        ..moveTo(base.dx - h * 0.04, top + h * 0.005)
        ..quadraticBezierTo(
          base.dx,
          top + h * 0.05,
          base.dx + h * 0.04,
          top + h * 0.005,
        ),
      _stroke(_faded(skin, 0.9), h * 0.012),
    );
  }

  void _paintHead(Canvas canvas, Offset base, double h) {
    final centre = Offset(base.dx, base.dy - h * 0.85);
    final r = h * 0.105;
    canvas.drawCircle(centre, r, Paint()..color = skin);
    // The hair: a cap over the top of the head.
    canvas.drawArc(
      Rect.fromCircle(center: centre.translate(0, -r * 0.08), radius: r * 1.04),
      pi * 1.02,
      pi * 0.96,
      true,
      Paint()..color = hair,
    );
    final eye = Paint()..color = hair;
    for (final side in const [-1.0, 1.0]) {
      canvas.drawCircle(
        centre.translate(side * r * 0.38, r * 0.12),
        r * 0.09,
        eye,
      );
    }
    canvas.drawArc(
      Rect.fromCenter(
        center: centre.translate(0, r * 0.32),
        width: r * 0.6,
        height: r * 0.36,
      ),
      pi * 0.15,
      pi * 0.7,
      false,
      _stroke(hair, max(1, r * 0.09)),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PersonaPainter &&
      other.shirt == shirt &&
      other.trousers == trousers &&
      other.skin == skin &&
      other.hair == hair &&
      other.soil == soil &&
      other.grass == grass;

  @override
  int get hashCode => Object.hash(shirt, trousers, skin, hair, soil, grass);
}

/// The picture as a widget, in the colours of the theme.
class PersonaDrawing extends StatelessWidget {
  const PersonaDrawing({super.key});

  static const skin = Color(0xFFE8B98F);
  static const hair = Color(0xFF4A3426);
  static const soil = Color(0xFF5C402B);

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final vintage = theme.kind == ThemeId.vintage;
    return CustomPaint(
      size: Size.infinite,
      painter: _PersonaCanvas(
        PersonaPainter(
          shirt: vintage ? theme.accent2 : theme.accent,
          trousers: theme.accent3,
          skin: skin,
          hair: hair,
          soil: soil,
          grass: vintage ? theme.accent2 : theme.accent,
        ),
      ),
    );
  }
}

class _PersonaCanvas extends CustomPainter {
  const _PersonaCanvas(this.painter);

  final PersonaPainter painter;

  @override
  void paint(Canvas canvas, Size size) => painter.paint(canvas, size);

  @override
  bool shouldRepaint(_PersonaCanvas old) => old.painter != painter;
}
