// A clock for a slow, small movement, like the sway of a plant.
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'slow_clock.dart';
import 'theme_math.dart';

/// Builds its child with the seconds since it started, [framesPerSecond]
/// times a second or more. While `on` is false the clock stands still at 0
/// and no frame is asked for. It also stands still, where it is, while the
/// app is not in front and under a `TickerMode` that is off.
class SwayClock extends StatefulWidget {
  const SwayClock({
    super.key,
    required this.on,
    required this.builder,
    this.framesPerSecond = mostFrames,
  });

  final bool on;
  final Widget Function(BuildContext context, double seconds) builder;

  /// How often the child is built again. See [framesFor].
  final int framesPerSecond;

  /// A slow movement needs no more frames than this, and gets no fewer than
  /// [fewestFrames].
  static const mostFrames = 30;
  static const fewestFrames = 5;

  /// A step of a sharp shape that is no longer than this looks the same as
  /// any shorter step: a quarter of a point is half a pixel of a 2x screen.
  static const longestStep = 0.25;

  /// How often a thing that turns around its foot must be drawn again so
  /// that its tip, `reach` points from the foot, never moves more than
  /// [longestStep] in one step. `degreesPerSecond` is its fastest turn.
  static int framesFor({
    required double reach,
    required double degreesPerSecond,
  }) {
    final pointsPerSecond = reach * degreesPerSecond * math.pi / 180;
    return math.min(
      mostFrames,
      math.max(fewestFrames, (pointsPerSecond / longestStep).ceil()),
    );
  }

  @override
  State<SwayClock> createState() => _SwayClockState();
}

class _SwayClockState extends State<SwayClock> with WidgetsBindingObserver {
  /// A timer and not a ticker: see [SlowClock].
  final _clock = SlowClock(framesPerSecond: SwayClock.mostFrames);

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
  void didUpdateWidget(SwayClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _sync();

  void _sync() {
    _clock.framesPerSecond = widget.framesPerSecond;
    _clock.isRunning = MotionRules.ambientRuns(
      motionOn: widget.on && TickerMode.valuesOf(context).enabled,
      windowIsKey: MotionRules.windowIsKey(
        WidgetsBinding.instance.lifecycleState,
      ),
    );
    if (!widget.on) _clock.reset();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: _clock.seconds,
    builder: (context, seconds, _) =>
        widget.builder(context, widget.on ? seconds : 0),
  );
}
