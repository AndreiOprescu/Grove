// Port of the views in Sources/Grove/Theme/AmbientBackground.swift and
// ThemeDecor.swift: what is drawn behind every screen.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'grove_theme.dart';
import 'theme_math.dart';

/// Everything behind a screen: the background colour, the drifting circles,
/// the grid of Futuristic and the paper of Vintage.
class ThemeBackdrop extends StatelessWidget {
  const ThemeBackdrop({super.key, required this.motion, this.intensity = 1});

  /// The Motion setting.
  final bool motion;

  /// The Accent intensity setting, 0 to 1.
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: theme.bg),
            AmbientBackground(motion: motion, intensity: intensity),
            if (theme.gridLines) const BackgroundGrid(),
            if (theme.paper) const PaperTexture(),
          ],
        ),
      ),
    );
  }
}

/// Three big soft circles in the colours of the theme, drifting slowly
/// behind everything (PLAN §6.3). With motion off it draws one still frame.
/// While the app is not in front it stops, and the circles stay where they
/// were.
class AmbientBackground extends StatefulWidget {
  const AmbientBackground({
    super.key,
    required this.motion,
    this.intensity = 1,
  });

  /// The Motion setting. The device setting "reduce motion" also stops the
  /// circles.
  final bool motion;

  /// The Accent intensity setting, 0 to 1.
  final double intensity;

  /// The circles are drawn again at most this often.
  static const framesPerSecond = 30;

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker = createTicker(_onTick);

  /// Seconds the circles have moved. The painter listens to it.
  final _time = ValueNotifier<double>(0);

  /// The value of [_time] when the ticker last started.
  double _startedAt = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(AmbientBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _sync();

  bool get _motionOn => MotionRules.isOn(
    setting: widget.motion,
    reduceMotion: MediaQuery.disableAnimationsOf(context),
  );

  /// Starts or stops the clock to match the settings and the app state.
  void _sync() {
    final state = WidgetsBinding.instance.lifecycleState;
    final runs = MotionRules.ambientRuns(
      motionOn: _motionOn,
      windowIsKey: state == null || state == AppLifecycleState.resumed,
    );
    if (runs && !_ticker.isActive) {
      _startedAt = _time.value;
      unawaited(_ticker.start());
    } else if (!runs && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    final now =
        _startedAt + elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    // A screen may draw 120 times a second. The circles are slow, so 30 is
    // enough.
    if (now - _time.value >= 1 / AmbientBackground.framesPerSecond - 0.001) {
      _time.value = now;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _BlobPainter(
          colors: theme.blobs,
          strength: AmbientMath.strength(
            base: theme.blobOpacity,
            intensity: widget.intensity,
          ),
          time: _time,
          still: !_motionOn,
        ),
      ),
    );
  }
}

class _BlobPainter extends CustomPainter {
  _BlobPainter({
    required this.colors,
    required this.strength,
    required this.time,
    required this.still,
  }) : super(repaint: time);

  final List<Color> colors;
  final double strength;
  final ValueListenable<double> time;

  /// Motion is off: draw the frame of time zero.
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    final t = still ? 0.0 : time.value;
    final radius =
        AmbientMath.diameter(width: size.width, height: size.height) / 2;
    if (radius <= 0) return;
    for (var i = 0; i < colors.length; i++) {
      final at = AmbientMath.centre(index: i, time: t);
      final centre = Offset(at.dx * size.width, at.dy * size.height);
      // A soft edge from a gradient. It looks like a blur and costs less.
      final fade = ui.Gradient.radial(
        centre,
        radius,
        [
          colors[i].withValues(alpha: strength),
          colors[i].withValues(alpha: strength * 0.55),
          colors[i].withValues(alpha: 0),
        ],
        const [0, 0.5, 1],
      );
      canvas.drawCircle(centre, radius, Paint()..shader = fade);
    }
  }

  @override
  bool shouldRepaint(_BlobPainter old) =>
      old.strength != strength ||
      old.still != still ||
      !listEquals(old.colors, colors);
}

/// Futuristic: the faint grid behind everything.
class BackgroundGrid extends StatelessWidget {
  const BackgroundGrid({super.key});

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size.infinite,
      painter: _GridPainter(GroveTheme.of(context).line),
    ),
  );
}

class _GridPainter extends CustomPainter {
  const _GridPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    for (final x in GridMath.lines(size.width)) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (final y in GridMath.lines(size.height)) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.color != color;
}

/// Vintage: fine paper noise, drawn once into a picture, and a brown
/// vignette that darkens the edges.
class PaperTexture extends StatelessWidget {
  const PaperTexture({super.key});

  @override
  Widget build(BuildContext context) => const RepaintBoundary(
    child: CustomPaint(size: Size.infinite, painter: _PaperPainter()),
  );
}

class _PaperPainter extends CustomPainter {
  const _PaperPainter();

  static const _tileSize = 200.0;
  static const _tileScale = 2.0;
  static const _vignette = Color(0x595A3C14); // rgb 90 60 20 at 35%

  /// Drawn once and kept.
  static final ui.Image _tile = _makeTile();

  static ui.Image _makeTile() {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(_tileScale);
    final dots = NoiseMath.dots(count: 3000, size: _tileSize, seed: 0x6E0517E);
    canvas.drawRawPoints(
      ui.PointMode.points,
      Float32List.fromList([
        for (final dot in dots) ...[dot.dx + 0.25, dot.dy + 0.25],
      ]),
      Paint()
        ..color =
            const Color(0x0A000000) // black at 4%
        ..strokeWidth = 0.5
        ..strokeCap = StrokeCap.square,
    );
    final side = (_tileSize * _tileScale).round();
    final picture = recorder.endRecording();
    final image = picture.toImageSync(side, side);
    picture.dispose();
    return image;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final area = Offset.zero & size;
    final shrink = Matrix4.diagonal3Values(1 / _tileScale, 1 / _tileScale, 1);
    canvas.drawRect(
      area,
      Paint()
        ..shader = ui.ImageShader(
          _tile,
          TileMode.repeated,
          TileMode.repeated,
          shrink.storage,
          filterQuality: FilterQuality.low,
        ),
    );
    final m = math.max(size.width, size.height);
    canvas.drawRect(
      area,
      Paint()
        ..blendMode = BlendMode.multiply
        ..shader = ui.Gradient.radial(
          area.center,
          m * 0.85,
          [_vignette.withValues(alpha: 0), _vignette],
          const [0.35 / 0.85, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(_PaperPainter old) => false;
}
