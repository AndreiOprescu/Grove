// A clock for a slow movement that never ends: the circles of the
// background, the sway of a plant.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Seconds that go up a few times a second, from a timer.
///
/// Why not a `Ticker`: a running ticker asks the engine for a new frame at
/// every refresh of the screen, 120 times a second on a new Mac. The engine
/// then draws the whole window again each time, also when nothing changed.
/// Measured on the profile build: 14 to 45 % of one core for a window that
/// nobody touches (docs/acceptance/F12-shell-gaps.md). This clock asks for
/// a frame only when its value changes.
///
/// All the running clocks step at the same moment, as often as the fastest
/// of them needs. So two slow movements on one screen cost one frame, not
/// two.
///
/// The seconds are counted, not read from a watch: a late timer makes the
/// movement a little slower and never makes it jump.
class SlowClock {
  SlowClock({required int framesPerSecond})
    : assert(framesPerSecond > 0),
      _framesPerSecond = framesPerSecond;

  /// The clocks that run now.
  static final _running = <SlowClock>{};
  static Timer? _beat;
  static int _beatRate = 0;

  /// Makes the beat as fast as the fastest running clock needs.
  static void _syncBeat() {
    final rate = _running.fold(0, (r, c) => math.max(r, c._framesPerSecond));
    if (rate == _beatRate) return;
    _beat?.cancel();
    _beatRate = rate;
    _beat = rate == 0
        ? null
        : Timer.periodic(
            Duration(microseconds: Duration.microsecondsPerSecond ~/ rate),
            (_) {
              final step = 1 / rate;
              for (final clock in _running.toList()) {
                if (clock.isRunning) clock._seconds.value += step;
              }
            },
          );
  }

  /// How often the value must change while the clock runs. It changes more
  /// often while another clock that needs more runs too.
  int get framesPerSecond => _framesPerSecond;
  int _framesPerSecond;
  set framesPerSecond(int value) {
    assert(value > 0);
    if (value == _framesPerSecond) return;
    _framesPerSecond = value;
    if (isRunning) _syncBeat();
  }

  final _seconds = ValueNotifier<double>(0);

  /// The seconds this clock has run. A painter can listen to it.
  ValueListenable<double> get seconds => _seconds;

  bool get isRunning => _running.contains(this);

  /// Starts or stops the clock. A stopped clock keeps its value.
  set isRunning(bool runs) {
    if (runs == isRunning) return;
    if (runs) {
      _running.add(this);
    } else {
      _running.remove(this);
    }
    _syncBeat();
  }

  /// Back to zero.
  void reset() => _seconds.value = 0;

  void dispose() {
    isRunning = false;
    _seconds.dispose();
  }
}
