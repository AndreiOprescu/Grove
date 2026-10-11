// Port of Sources/Grove/Theme/GrowingPlant.swift: a small plant that grows
// with the day (PLAN §6.3). Up to six leaves, and a flower when all is done.
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../../state/rules/plant_math.dart' show PlantMath, PlantProgress;
import 'grove_theme.dart';
import 'sway_clock.dart';
import 'theme_math.dart';
import 'theme_spec.dart';

/// The stem and the leaves grow with a small bounce. The plant sways 3
/// degrees over 5 seconds when motion is on.
class GrowingPlant extends StatelessWidget {
  const GrowingPlant({
    super.key,
    required this.progress,
    required this.motion,
    this.height = 40,
  });

  final PlantProgress progress;

  /// The Motion setting. The device setting "reduce motion" also stops the
  /// plant.
  final bool motion;
  final double height;

  /// How long a new leaf takes to grow.
  static const growTime = Duration(milliseconds: 500);

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final motionOn = MotionRules.isOn(
      setting: motion,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
    );
    final leaves = PlantMath.leaves(done: progress.done, total: progress.total);
    final flower = PlantMath.hasFlower(
      done: progress.done,
      total: progress.total,
    );
    // Vintage swaps the colours: green leaves, an ochre pot, a red flower.
    final vintage = theme.kind == ThemeId.vintage;
    return Semantics(
      container: true,
      label: 'Plant',
      value: progress.total == 0
          ? 'Nothing planned today'
          : '${progress.percent} percent of today grown',
      child: SizedBox(
        width: height * 0.8,
        height: height,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: leaves.toDouble()),
          duration: motionOn ? growTime : Duration.zero,
          curve: Curves.easeOutBack,
          builder: (context, amount, _) => SwayClock(
            on: motionOn,
            builder: (context, seconds) => Transform.rotate(
              angle: motionOn
                  ? PlantMath.swayDegrees(at: seconds) * pi / 180
                  : 0,
              alignment: Alignment.bottomCenter,
              child: CustomPaint(
                size: Size.infinite,
                painter: PlantPainter(
                  amount: amount,
                  flower: flower,
                  green: vintage ? theme.accent2 : theme.accent,
                  pot: vintage ? theme.accent3 : theme.accent2,
                  petal: vintage ? theme.accent : theme.accent2,
                  heart: theme.accent3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The picture. `amount` is the number of leaves as a number that can be in
/// between, so a leaf can grow.
class PlantPainter extends CustomPainter {
  const PlantPainter({
    required this.amount,
    required this.flower,
    required this.green,
    required this.pot,
    required this.petal,
    required this.heart,
  });

  final double amount;
  final bool flower;
  final Color green;
  final Color pot;
  final Color petal;
  final Color heart;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final potTop = h * 0.84;
    final growth = PlantMath.stemGrowth(amount);
    final base = Offset(w / 2, potTop);
    final top = Offset(w / 2 + w * 0.04, potTop - (potTop - h * 0.22) * growth);

    canvas.drawPath(
      Path()
        ..moveTo(w * 0.22, potTop)
        ..lineTo(w * 0.78, potTop)
        ..lineTo(w * 0.68, h)
        ..lineTo(w * 0.32, h)
        ..close(),
      Paint()..color = pot,
    );

    final control = Offset(w * 0.36, (base.dy + top.dy) / 2);
    Offset point(double t) {
      final u = 1 - t;
      return Offset(
        u * u * base.dx + 2 * u * t * control.dx + t * t * top.dx,
        u * u * base.dy + 2 * u * t * control.dy + t * t * top.dy,
      );
    }

    canvas.drawPath(
      Path()
        ..moveTo(base.dx, base.dy)
        ..quadraticBezierTo(control.dx, control.dy, top.dx, top.dy),
      Paint()
        ..color = green
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.5, w * 0.06)
        ..strokeCap = StrokeCap.round,
    );

    // The leaves, bottom to top, one on each side.
    final leafPaint = Paint()..color = green.withValues(alpha: 0.85 * green.a);
    for (var i = 0; i < PlantMath.maxLeaves; i++) {
      final grown = max(0.0, min(1.0, amount - i));
      if (grown <= 0) continue;
      final t = 0.3 + 0.12 * i;
      final p = point(min(t, 0.95));
      final side = i.isEven ? 1.0 : -1.0;
      final len = w * 0.34 * grown;
      final angle = side * -0.7 - pi / 2 + (side > 0 ? 0.2 : -0.2);
      final tip = Offset(
        p.dx + cos(angle) * len * 1.2,
        p.dy + sin(angle) * len * 1.2,
      );
      final mid = Offset((p.dx + tip.dx) / 2, (p.dy + tip.dy) / 2);
      final nx = -sin(angle) * len * 0.45, ny = cos(angle) * len * 0.45;
      canvas.drawPath(
        Path()
          ..moveTo(p.dx, p.dy)
          ..quadraticBezierTo(mid.dx + nx, mid.dy + ny, tip.dx, tip.dy)
          ..quadraticBezierTo(mid.dx - nx, mid.dy - ny, p.dx, p.dy),
        leafPaint,
      );
    }

    if (flower) {
      final r = w * 0.12;
      final petalPaint = Paint()..color = petal;
      for (var k = 0; k < 5; k++) {
        final a = k * 2 * pi / 5;
        canvas.drawCircle(
          Offset(top.dx + cos(a) * r, top.dy + sin(a) * r),
          r * 0.7,
          petalPaint,
        );
      }
      canvas.drawCircle(top, r * 0.6, Paint()..color = heart);
    }
  }

  @override
  bool shouldRepaint(PlantPainter old) =>
      old.amount != amount ||
      old.flower != flower ||
      old.green != green ||
      old.pot != pot ||
      old.petal != petal ||
      old.heart != heart;
}
