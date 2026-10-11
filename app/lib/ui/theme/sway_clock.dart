// A clock for a slow, small movement, like the sway of a plant.
import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Builds its child with the seconds since it started, 30 times a second at
/// most. While `on` is false the clock stands still at 0 and no frame is
/// asked for.
class SwayClock extends StatefulWidget {
  const SwayClock({super.key, required this.on, required this.builder});

  final bool on;
  final Widget Function(BuildContext context, double seconds) builder;

  /// A slow movement needs no more frames than this.
  static const framesPerSecond = 30;

  @override
  State<SwayClock> createState() => _SwayClockState();
}

class _SwayClockState extends State<SwayClock>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final _time = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(SwayClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.on && !_ticker.isActive) {
      unawaited(_ticker.start());
    } else if (!widget.on && _ticker.isActive) {
      _ticker.stop();
      _time.value = 0;
    }
  }

  void _onTick(Duration elapsed) {
    final now = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    if (now - _time.value >= 1 / SwayClock.framesPerSecond - 0.001) {
      _time.value = now;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: _time,
    builder: (context, seconds, _) =>
        widget.builder(context, widget.on ? seconds : 0),
  );
}
