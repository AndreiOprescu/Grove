// Port of Sources/Grove/Garden/GardenPainter.swift: the garden plant for
// one growth number (`Garden.growth`, 0 to 11). Nothing in the picture
// jumps: the stem, the forks, the leaves, the trunk, the canopy and the
// flowers each grow by a small step with every finished task.
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../../core/services/garden.dart';
import '../theme/grove_theme.dart';
import '../theme/theme_spec.dart';

class GardenPainter {
  const GardenPainter({
    required this.growth,
    required this.leaf,
    required this.bark,
    required this.petal,
    required this.heart,
    required this.soil,
  });

  final double growth;
  final Color leaf;
  final Color bark;
  final Color petal;
  final Color heart;
  final Color soil;

  /// Branch levels after the trunk. Each level forks in two at the tip of
  /// the one before.
  static const levels = 5;

  static double _clamp(double x) => max(0, min(1, x));

  static double _smooth(double x) {
    final c = _clamp(x);
    return c * c * (3 - 2 * c);
  }

  /// A steady "random" number from 0 to 1. The same input always gives the
  /// same output, so the tree never flickers.
  static double noise(int a, [int b = 0]) {
    final x = sin(a * 12.9898 + b * 78.233) * 43758.5453;
    return x - x.floorToDouble();
  }

  /// How grown level `k` is, from 0 to 1. The trunk is level 0.
  double levelGrowth(int k) {
    if (k == 0) return _smooth(growth / 3.0);
    return _smooth((growth - (1.5 + 1.8 * (k - 1))) / 1.8);
  }

  double get _t => growth / Garden.maxGrowth;

  static Color _faded(Color c, double by) => c.withValues(alpha: c.a * by);

  void paint(Canvas canvas, Size size) {
    // The tree is as wide as it is tall, so it is sized by the smaller side
    // and always fits its box.
    final h = min(size.height * 0.84, size.width / 1.275), w = h * 0.85;
    final base = Offset(size.width / 2, size.height * 0.88);
    _paintGround(canvas, base, w, h);
    if (growth < 0.35) _paintSeed(canvas, base, w);
    final trunk = h * (0.20 + 0.08 * _t);
    final width = max(1.6, w * (0.006 + 0.034 * _t));
    _paintBranch(
      canvas,
      from: base,
      angle: 0,
      level: 0,
      index: 0,
      length: trunk,
      width: width,
      w: w,
    );
    _paintGrassFront(canvas, base, w, h);
  }

  void _paintSeed(Canvas canvas, Offset base, double w) {
    final r = w * 0.022;
    final fade = 1 - _clamp(growth / 0.35);
    canvas.drawOval(
      Rect.fromLTWH(base.dx - r, base.dy - r * 1.3, r * 2, r * 1.5),
      Paint()..color = _faded(bark, fade),
    );
  }

  void _paintGround(Canvas canvas, Offset base, double w, double h) {
    final half = w * (0.17 + 0.17 * _t);
    canvas.drawOval(
      Rect.fromLTWH(base.dx - half, base.dy - h * 0.018, half * 2, h * 0.07),
      Paint()..color = soil,
    );
    canvas.drawOval(
      Rect.fromLTWH(base.dx - half, base.dy - h * 0.018, half * 2, h * 0.034),
      Paint()..color = _faded(leaf, 0.55),
    );
  }

  /// Grass blades and small flowers on the ground, in front of the trunk.
  /// More of them as the plant grows.
  void _paintGrassFront(Canvas canvas, Offset base, double w, double h) {
    final half = w * (0.17 + 0.17 * _t);
    final blades = 4 + (14 * _t).truncate();
    final paint = Paint()
      ..color = leaf
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1, w * 0.004)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < blades; i++) {
      final x = base.dx + (noise(i, 3) * 2 - 1) * half * 0.92;
      final y = base.dy + h * 0.006 + noise(i, 4) * h * 0.016;
      final tall =
          h * (0.016 + 0.020 * noise(i, 5)) * (0.5 + 0.5 * _smooth(growth / 2));
      canvas.drawPath(
        Path()
          ..moveTo(x, y)
          ..quadraticBezierTo(
            x,
            y - tall * 0.6,
            x + (noise(i, 6) - 0.5) * tall,
            y - tall,
          ),
        paint,
      );
    }
    final flowers = (_smooth((growth - 6) / 5) * 7).floor();
    for (var i = 0; i < flowers; i++) {
      final x = base.dx + (noise(i, 9) * 2 - 1) * half * 0.85;
      final y = base.dy + h * 0.012 + noise(i, 10) * h * 0.012;
      _paintFlower(canvas, Offset(x, y), w * 0.010, i);
    }
  }

  /// A young branch is green. It turns to wood as the plant grows, the
  /// trunk first.
  Color _mixed(int k) {
    final wood = _smooth((growth - 3.5) / 4) * max(0, 1 - 0.28 * k);
    return Color.lerp(leaf, bark, wood)!;
  }

  /// One branch. Its two children grow from its tip.
  void _paintBranch(
    Canvas canvas, {
    required Offset from,
    required double angle,
    required int level,
    required int index,
    required double length,
    required double width,
    required double w,
  }) {
    final p = from, k = level;
    final grown = levelGrowth(k);
    if (grown <= 0.002) return;
    final len = length * grown * (0.9 + 0.2 * noise(k, index));
    final tip = Offset(p.dx + sin(angle) * len, p.dy - cos(angle) * len);
    final bend = (noise(index, k + 20) - 0.5) * len * 0.22;
    final control = Offset(
      (p.dx + tip.dx) / 2 + cos(angle) * bend,
      (p.dy + tip.dy) / 2 + sin(angle) * bend,
    );
    Offset point(double s) {
      final u = 1 - s;
      return Offset(
        u * u * p.dx + 2 * u * s * control.dx + s * s * tip.dx,
        u * u * p.dy + 2 * u * s * control.dy + s * s * tip.dy,
      );
    }

    canvas.drawPath(
      Path()
        ..moveTo(p.dx, p.dy)
        ..quadraticBezierTo(control.dx, control.dy, tip.dx, tip.dy),
      Paint()
        ..color = _mixed(k)
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.1, width)
        ..strokeCap = StrokeCap.round,
    );

    // Leaves along the branch, one side then the other. Deeper levels carry
    // more.
    final leafGrowth = _clamp((grown - 0.25) / 0.6);
    if (leafGrowth > 0) {
      final size = w * (0.078 - 0.038 * _t) * leafGrowth;
      final stops = k >= 2 ? const [0.45, 0.72, 1.0] : const [0.4, 0.65, 0.9];
      for (final (j, s) in stops.indexed) {
        final side = (j + index).isEven ? 1.0 : -1.0;
        _paintLeaf(
          canvas,
          point(s),
          angle + side * (0.85 + 0.25 * noise(j, index + k)),
          size * (s >= 1.0 ? 1.15 : 0.9),
        );
      }
    }

    if (k < levels) {
      // The canopy: a tuft of leaves at the tips, once the tree is tall
      // enough.
      final canopy = _smooth((growth - 6.5) / 4);
      if (k >= 3 && canopy > 0) {
        final size = w * 0.045 * canopy * grown;
        for (var j = 0; j < 6; j++) {
          final a = j * pi / 3 + noise(index, k + j);
          _paintLeaf(canvas, tip, a, size * (0.9 + 0.4 * noise(j, index)));
        }
      }
      final spread = 0.36 + 0.12 * noise(index, k + 40);
      final next = length * 0.76;
      final thin = width * 0.66;
      _paintBranch(
        canvas,
        from: tip,
        angle: angle - spread,
        level: k + 1,
        index: index * 2,
        length: next,
        width: thin,
        w: w,
      );
      _paintBranch(
        canvas,
        from: tip,
        angle: angle + spread * (0.8 + 0.4 * noise(index, k + 50)),
        level: k + 1,
        index: index * 2 + 1,
        length: next,
        width: thin,
        w: w,
      );
    } else {
      // The last level: flowers at some of the tips.
      final bloom = _smooth((growth - 6) / 3);
      if (bloom > 0 && index.isEven) {
        _paintFlower(canvas, tip, w * 0.016 * bloom * grown, index);
      }
    }
  }

  void _paintLeaf(Canvas canvas, Offset p, double angle, double length) {
    if (length <= 0.4) return;
    final tip = Offset(p.dx + sin(angle) * length, p.dy - cos(angle) * length);
    final mid = Offset((p.dx + tip.dx) / 2, (p.dy + tip.dy) / 2);
    final nx = cos(angle) * length * 0.38, ny = sin(angle) * length * 0.38;
    canvas.drawPath(
      Path()
        ..moveTo(p.dx, p.dy)
        ..quadraticBezierTo(mid.dx + nx, mid.dy + ny, tip.dx, tip.dy)
        ..quadraticBezierTo(mid.dx - nx, mid.dy - ny, p.dx, p.dy),
      Paint()..color = _faded(leaf, 0.88),
    );
  }

  void _paintFlower(Canvas canvas, Offset c, double r, int tone) {
    if (r <= 0.4) return;
    final second = tone % 3 == 1;
    final rim = Paint()..color = second ? heart : petal;
    for (var k = 0; k < 5; k++) {
      final a = k * 2 * pi / 5;
      canvas.drawCircle(
        Offset(c.dx + cos(a) * r, c.dy + sin(a) * r),
        r * 0.7,
        rim,
      );
    }
    canvas.drawCircle(c, r * 0.55, Paint()..color = second ? petal : heart);
  }

  @override
  bool operator ==(Object other) =>
      other is GardenPainter &&
      other.growth == growth &&
      other.leaf == leaf &&
      other.bark == bark &&
      other.petal == petal &&
      other.heart == heart &&
      other.soil == soil;

  @override
  int get hashCode => Object.hash(growth, leaf, bark, petal, heart, soil);
}

/// The picture as a widget. `growth` can be between two numbers, so the
/// plant can grow smoothly.
class GardenDrawing extends StatelessWidget {
  const GardenDrawing({super.key, required this.growth});

  final double growth;

  static const bark = Color(0xFF6E4D33);
  static const soil = Color(0xFF5C402B);

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    // Vintage swaps the colours, like the small plant: green leaves from
    // accent2, a red flower.
    final vintage = theme.kind == ThemeId.vintage;
    return CustomPaint(
      size: Size.infinite,
      painter: _GardenCanvas(
        GardenPainter(
          growth: growth,
          leaf: vintage ? theme.accent2 : theme.accent,
          bark: bark,
          petal: vintage ? theme.accent : theme.accent2,
          heart: theme.accent3,
          soil: soil,
        ),
      ),
    );
  }
}

class _GardenCanvas extends CustomPainter {
  const _GardenCanvas(this.painter);

  final GardenPainter painter;

  @override
  void paint(Canvas canvas, Size size) => painter.paint(canvas, size);

  @override
  bool shouldRepaint(_GardenCanvas old) => old.painter != painter;
}
