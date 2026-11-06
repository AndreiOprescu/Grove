// What the goal map paints: the dots behind it, the lines and the short
// effects of a tick. Nothing here makes a layer or a blur, so a frame costs
// only the paths it draws.
import 'dart:ui' show PathMetric, PointMode;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:grove/core/goals/goal_map_layout.dart';

import 'map_motion.dart';

/// The small dots of the background. They move with the map, and they get
/// fewer when the map is small.
class DotsPainter extends CustomPainter {
  DotsPainter(this.camera, this.color) : super(repaint: camera);

  final TransformationController camera;
  final Color color;

  static const _gap = 26.0;

  @override
  void paint(Canvas canvas, Size size) {
    final m = camera.value;
    final scale = m.getMaxScaleOnAxis();
    var gap = _gap * scale;
    while (gap < 16) {
      gap *= 2;
    }
    final origin = Offset(m.storage[12] % gap, m.storage[13] % gap);
    final points = <Offset>[
      for (var x = origin.dx; x < size.width; x += gap)
        for (var y = origin.dy; y < size.height; y += gap) Offset(x, y),
    ];
    canvas.drawPoints(
      PointMode.points,
      points,
      Paint()
        ..color = color
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(DotsPainter old) =>
      old.color != color || old.camera != camera;
}

/// The path of one line: a curve across each gap between layers, straight
/// past the layers that it skips.
Path linePath(List<Offset> points) {
  final path = Path();
  if (points.length < 2) return path;
  path.moveTo(points.first.dx, points.first.dy);
  for (var i = 0; i + 1 < points.length; i++) {
    final a = points[i], b = points[i + 1];
    if (i.isEven) {
      final mid = (b.dx - a.dx) / 2;
      path.cubicTo(a.dx + mid, a.dy, b.dx - mid, b.dy, b.dx, b.dy);
    } else {
      path.lineTo(b.dx, b.dy);
    }
  }
  return path;
}

/// All the lines of the map, with a small round joint at each end. Lines of
/// the same kind go in one path, so a big map is a few draw calls.
class LinesPainter extends CustomPainter {
  LinesPainter({
    required this.motion,
    required this.isDone,
    required this.lineColor,
    required this.doneColor,
    required this.origin,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final MapMotion motion;

  /// True for a line whose child is done.
  final bool Function(MapEdge edge) isDone;
  final Color lineColor;
  final Color doneColor;
  final Offset origin;

  static const _width = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(origin.dx, origin.dy);
    final open = Path(), done = Path();
    final openJoints = <Offset>[], doneJoints = <Offset>[];
    for (final edge in motion.edges) {
      final points = motion.pointsOf(edge);
      if (points.length < 2) continue;
      final alpha = motion.edgeAlpha(edge);
      final finished = isDone(edge);
      if (alpha < 1) {
        // Only while a map grows. It draws the line on its own.
        if (alpha <= 0) continue;
        final color = (finished ? doneColor : lineColor);
        canvas.drawPath(
          linePath(points),
          _stroke(color.withValues(alpha: color.a * alpha)),
        );
        continue;
      }
      (finished ? done : open).addPath(linePath(points), Offset.zero);
      (finished ? doneJoints : openJoints)
        ..add(points.first)
        ..add(points.last);
    }
    canvas
      ..drawPath(open, _stroke(lineColor))
      ..drawPath(done, _stroke(doneColor));
    _joints(canvas, openJoints, lineColor);
    _joints(canvas, doneJoints, doneColor);
  }

  void _joints(Canvas canvas, List<Offset> points, Color color) {
    if (points.isEmpty) return;
    canvas.drawPoints(
      PointMode.points,
      points,
      Paint()
        ..color = color
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round,
    );
  }

  static Paint _stroke(Color color) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = _width
    ..strokeCap = StrokeCap.round;

  @override
  bool shouldRepaint(LinesPainter old) => true;
}

/// A ring around a square, for part of the time of an effect.
class RingEffect {
  const RingEffect(this.id, this.start, this.end, this.color);

  final String id;
  final double start;
  final double end;
  final Color color;
}

/// Light that runs along a line, for part of the time of an effect.
class LightEffect {
  const LightEffect(this.edge, this.start, this.end, this.color);

  final MapEdge edge;
  final double start;
  final double end;
  final Color color;
}

/// The effects of a tick: a ring on the square, light on the line, a ring on
/// the parent. Two strokes make the glow; there is no blur.
class EffectsPainter extends CustomPainter {
  EffectsPainter({
    required this.motion,
    required this.time,
    required this.rings,
    required this.lights,
    required this.origin,
  }) : super(repaint: time);

  final MapMotion motion;
  final Animation<double> time;
  final List<RingEffect> rings;
  final List<LightEffect> lights;
  final Offset origin;

  static const _runLength = 70.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (rings.isEmpty && lights.isEmpty) return;
    final now = time.value;
    canvas.translate(origin.dx, origin.dy);
    for (final l in lights) {
      if (now < l.start || now > l.end) continue;
      final at = (now - l.start) / (l.end - l.start);
      _light(canvas, l, at);
    }
    for (final r in rings) {
      if (now < r.start || now > r.end) continue;
      final at = (now - r.start) / (r.end - r.start);
      final place = motion.place(r.id);
      final grow = 3 + 14 * Curves.easeOutCubic.transform(at);
      final rect = RRect.fromRectAndRadius(
        (place &
                const Size(
                  GoalMapLayout.squareWidth,
                  GoalMapLayout.squareHeight,
                ))
            .inflate(grow),
        Radius.circular(14 + grow),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = r.color.withValues(alpha: (1 - at) * 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  void _light(Canvas canvas, LightEffect l, double at) {
    final points = motion.pointsOf(l.edge);
    if (points.length < 2) return;
    final PathMetric metric;
    final metrics = linePath(points).computeMetrics().iterator;
    if (!metrics.moveNext()) return;
    metric = metrics.current;
    final head = metric.length * Curves.easeInOut.transform(at);
    final tail = (head - _runLength).clamp(0.0, metric.length);
    final piece = metric.extractPath(tail, head);
    canvas
      ..drawPath(
        piece,
        Paint()
          ..color = l.color.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 9,
      )
      ..drawPath(
        piece,
        Paint()
          ..color = l.color
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 4,
      );
  }

  @override
  bool shouldRepaint(EffectsPainter old) => true;
}

/// The line that follows the pointer while the link handle is dragged.
class LinkDragPainter extends CustomPainter {
  LinkDragPainter({
    required this.from,
    required this.end,
    required this.origin,
    required this.color,
  }) : super(repaint: end);

  final Offset from;
  final ValueListenable<Offset?> end;
  final Offset origin;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final to = end.value;
    if (to == null) return;
    canvas.drawLine(
      from,
      to + origin,
      Paint()
        ..color = color
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(LinkDragPainter old) =>
      old.from != from || old.end != end || old.color != color;
}
