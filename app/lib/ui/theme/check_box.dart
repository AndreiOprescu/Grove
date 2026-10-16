// Port of Sources/Grove/Theme/CheckBox.swift: the box and its burst.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../state/rules/plant_math.dart' show BurstMath, BurstStyle;
import 'grove_theme.dart';
import 'symbols.dart';
import 'theme_math.dart';

/// The box in front of a task (PLAN §6.2): round in Grove and Minimal,
/// square in Futuristic and Vintage. It only draws. The button around it
/// does the work. When it turns on, it plays the burst of the theme.
class CheckBox extends StatefulWidget {
  const CheckBox({
    super.key,
    required this.isOn,
    this.size = 17,
    this.motion = false,
  });

  final bool isOn;
  final double size;

  /// The Motion setting. With it the box fills with a spring, and plays the
  /// burst when it turns on (PLAN §6.3). The device setting "reduce motion"
  /// also stops both.
  final bool motion;

  @override
  State<CheckBox> createState() => _CheckBoxState();
}

class _CheckBoxState extends State<CheckBox> with TickerProviderStateMixin {
  /// The spring of the Mac app: response 0.3, damping 0.6.
  static final _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: pow(2 * pi / 0.3, 2).toDouble(),
    ratio: 0.6,
  );

  /// The spring ends when the eye sees no more of it: half a percent of
  /// the box.
  static const _near = Tolerance(distance: 0.005, velocity: 0.05);

  /// How full the box is: 0 is empty, 1 is full. The spring goes a little
  /// over 1 on its way.
  late final AnimationController _fill = AnimationController.unbounded(
    vsync: this,
    value: widget.isOn ? 1 : 0,
  )..addListener(_tick);

  /// The time of the burst, from 0 to 1.
  late final AnimationController _burst =
      AnimationController(
        vsync: this,
        duration: Duration(milliseconds: (BurstMath.duration * 1000).round()),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _endBurst();
      });

  bool _bursting = false;
  bool _reduceMotion = false;

  bool get _motionOn =>
      MotionRules.isOn(setting: widget.motion, reduceMotion: _reduceMotion);

  void _tick() => setState(() {});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!_motionOn) _rest();
  }

  @override
  void didUpdateWidget(CheckBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_motionOn) {
      _rest();
      return;
    }
    if (oldWidget.isOn == widget.isOn) return;
    final end = widget.isOn ? 1.0 : 0.0;
    _fill
        .animateWith(
          SpringSimulation(_spring, _fill.value, end, 0, tolerance: _near),
        )
        .whenComplete(() {
          if (mounted) _fill.value = widget.isOn ? 1 : 0;
        });
    if (widget.isOn) {
      _bursting = true;
      _burst.forward(from: 0);
    } else {
      _burst.stop();
      _bursting = false;
    }
  }

  /// No motion: the box is at its end, and there is no burst.
  void _rest() {
    final end = widget.isOn ? 1.0 : 0.0;
    if (_fill.isAnimating || _fill.value != end) {
      _fill.stop();
      _fill.value = end;
    }
    _burst.stop();
    _bursting = false;
  }

  void _endBurst() {
    if (mounted) setState(() => _bursting = false);
  }

  @override
  void dispose() {
    _fill.dispose();
    _burst.dispose();
    super.dispose();
  }

  List<BoxShadow> _glow(GroveTheme theme) => [
    if (theme.glow && widget.isOn)
      BoxShadow(color: theme.accent.withValues(alpha: 0.55), blurRadius: 5),
  ];

  Widget _mark(GroveTheme theme) =>
      Icon(Icons.check, size: widget.size * 0.7, weight: 900, color: theme.bg);

  /// The box at rest.
  Widget _still(GroveTheme theme, double radius) {
    final isOn = widget.isOn;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isOn ? theme.accent : null,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: isOn ? theme.accent : theme.muted,
          width: 1.5,
        ),
        boxShadow: _glow(theme),
      ),
      child: isOn ? Center(child: _mark(theme)) : null,
    );
  }

  /// The box on its way: the ring, and over it the fill and the check mark,
  /// which grow from a fifth of their size and fade in.
  Widget _moving(GroveTheme theme, double radius) {
    final amount = _fill.value;
    final shape = BorderRadius.circular(radius);
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: shape,
            border: Border.all(
              color: widget.isOn ? theme.accent : theme.muted,
              width: 1.5,
            ),
          ),
        ),
        Opacity(
          opacity: amount.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: max(0.0, 0.2 + 0.8 * amount),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.accent,
                borderRadius: shape,
                boxShadow: _glow(theme),
              ),
              child: Center(child: _mark(theme)),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final size = widget.size;
    final radius = theme.squareChecks ? max(2.0, size * 0.16) : size / 2;
    final box = _fill.isAnimating
        ? _moving(theme, radius)
        : _still(theme, radius);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: !_bursting
            ? box
            : Stack(
                clipBehavior: Clip.none,
                fit: StackFit.expand,
                children: [
                  box,
                  CheckBurst(
                    style: BurstMath.style(theme.kind),
                    size: size,
                    time: _burst,
                  ),
                ],
              ),
      ),
    );
  }
}

/// The little show when a task is checked off (PLAN §6.2): leaves in Grove,
/// a fade in Minimal, a ring and sparks in Futuristic, an ink stamp in
/// Vintage. It is drawn over the box and around it. It takes no room and no
/// click.
class CheckBurst extends StatelessWidget {
  const CheckBurst({
    super.key,
    required this.style,
    required this.size,
    required this.time,
  });

  final BurstStyle style;

  /// The side of the box.
  final double size;

  /// From 0 to 1 in `BurstMath.duration` seconds.
  final Animation<double> time;

  /// A part that flies out on its line and fades.
  Widget _fly(double angle, double progress, Widget child) {
    final far = BurstMath.distance(BurstMath.reach, progress: progress);
    final a = angle * pi / 180;
    return Transform.translate(
      offset: Offset(cos(a) * far, sin(a) * far),
      child: Opacity(
        opacity: BurstMath.opacity(progress: progress),
        child: child,
      ),
    );
  }

  List<Widget> _parts(GroveTheme theme, double t) {
    final progress = Curves.easeOut.transform(t);
    final fade = BurstMath.opacity(progress: progress);
    switch (style) {
      case BurstStyle.leaves:
        return [
          for (final p in BurstMath.particles(style))
            _fly(
              p.angle,
              progress,
              Transform.rotate(
                angle: (p.angle + 90) * pi / 180,
                child: Icon(
                  symbolIcon('leaf.fill'),
                  size: 7,
                  color: theme.accent,
                ),
              ),
            ),
        ];
      case BurstStyle.fade:
        return [
          Opacity(
            opacity: fade,
            child: Transform.scale(
              scale: 1 + 0.7 * progress,
              child: SizedBox.square(
                dimension: size,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.accent.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(size / 2),
                  ),
                ),
              ),
            ),
          ),
        ];
      case BurstStyle.ringAndSparks:
        return [
          Opacity(
            opacity: fade,
            child: Transform.scale(
              scale: 0.8 + 1.4 * progress,
              child: SizedBox.square(
                dimension: size,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(size * 0.16),
                    border: Border.all(color: theme.accent, width: 1.5),
                  ),
                ),
              ),
            ),
          ),
          for (final p in BurstMath.particles(style))
            _fly(
              p.angle,
              progress,
              SizedBox.square(
                dimension: 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.accent3,
                    boxShadow: [
                      BoxShadow(
                        color: theme.accent3.withValues(alpha: 0.8),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ];
      case BurstStyle.stamp:
        // The stamp turns in during the first half, and fades in the last
        // two fifths.
        final turn = Curves.easeOutBack.transform(min(1.0, t * 2));
        final out = Curves.easeIn.transform(max(0.0, (t - 0.6) / 0.4));
        return [
          Transform.translate(
            offset: Offset(size / 2 + 8, 0),
            child: Opacity(
              opacity: (min(1.0, t * 4) * (1 - out)).clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 1.8 - 0.8 * turn,
                child: Transform.rotate(
                  angle: (-40 + 32 * turn) * pi / 180,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.accent, width: 1.2),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 1,
                      ),
                      child: Text(
                        'DONE',
                        maxLines: 1,
                        softWrap: false,
                        style: theme
                            .number(9, weight: FontWeight.w900)
                            .copyWith(color: theme.accent, letterSpacing: 1),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return IgnorePointer(
      child: ExcludeSemantics(
        // The parts are as big as they like, with their middle on the
        // middle of the box.
        child: OverflowBox(
          minWidth: 0,
          minHeight: 0,
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: AnimatedBuilder(
            animation: time,
            builder: (context, _) => Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: _parts(theme, time.value.clamp(0.0, 1.0)),
            ),
          ),
        ),
      ),
    );
  }
}
