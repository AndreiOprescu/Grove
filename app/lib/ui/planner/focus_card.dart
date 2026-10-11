// Port of Sources/Grove/Planner/FocusCard.swift: the small timer that
// floats at the bottom right while a focus session runs (PLAN §5.1.7).
// The Mac app hosts the card in its root view. Here `FocusLayer` hosts it
// over the planner, see `PlannerView`.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:grove/core/services/focus_rules.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../tasks/task_widgets.dart' show ProgressBar;
import '../theme/grove_theme.dart';
import '../theme/panel.dart';
import '../theme/theme_math.dart';

/// The focus timer of one session: the title, the time left to the end of
/// the block and a bar. At the end it asks "Mark done?".
class FocusCard extends StatefulWidget {
  const FocusCard({super.key, required this.store, required this.session});

  /// The width of the card, in points.
  static const width = 230.0;

  /// The side of a place to click or tap, in points.
  static const target = 28.0;

  /// The clock of the count down. A test sets its own.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  final AppStore store;
  final FocusSession session;

  @override
  State<FocusCard> createState() => _FocusCardState();
}

class _FocusCardState extends State<FocusCard> {
  /// Draws the count down again, once a second.
  Timer? _tick;

  /// Fires at the end of the block.
  Timer? _end;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(FocusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final was = oldWidget.session, now = widget.session;
    if (was.blockId != now.blockId ||
        was.end != now.end ||
        was.finished != now.finished) {
      _arm();
    }
  }

  @override
  void dispose() {
    _disarm();
    super.dispose();
  }

  void _disarm() {
    _tick?.cancel();
    _end?.cancel();
    _tick = _end = null;
  }

  void _arm() {
    _disarm();
    final session = widget.session;
    if (session.finished) return;
    final left = session.end.difference(FocusCard.clock());
    // The time can be up at the start: the session ended while another
    // screen was open. The store hears it after this frame.
    _end = Timer(left.isNegative ? Duration.zero : left, _timeUp);
    if (left > Duration.zero) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => _second());
    }
  }

  void _second() {
    if (!mounted) return;
    final left = FocusRules.remaining(
      until: widget.session.end,
      now: FocusCard.clock(),
    );
    // A sleeping computer can make the timer of the end late.
    left == 0 ? _timeUp() : setState(() {});
  }

  void _timeUp() {
    _disarm();
    if (!mounted) return;
    // The clock of the system was set back: the end is later than planned.
    if (widget.session.end.isAfter(FocusCard.clock())) {
      _arm();
      return;
    }
    setState(() {});
    widget.store.focusTimeUp();
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final session = widget.session;
    final now = FocusCard.clock();
    final left = FocusRules.remaining(until: session.end, now: now);
    final corners = BorderRadius.circular(theme.radius);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Focus timer',
      child: SizedBox(
        width: FocusCard.width,
        child: DecoratedBox(
          // A SwiftUI shadow of radius r looks like a blur radius of 2 r.
          decoration: BoxDecoration(
            borderRadius: corners,
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 20,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Panel(
            child: Padding(
              // The cross has room for a finger, so the top and the right
              // have less padding. Its picture is 13 from both edges.
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                spacing: 2,
                children: [
                  _header(theme, session),
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: session.finished || left == 0
                        ? _finished(theme, session)
                        : _running(theme, session, left, now),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(GroveTheme theme, FocusSession session) => Row(
    children: [
      Icon(Icons.timer_outlined, size: 14, color: theme.accent),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          session.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme
              .body(12, weight: FontWeight.w600)
              .copyWith(color: theme.ink),
        ),
      ),
      const SizedBox(width: 2),
      Semantics(
        container: true,
        excludeSemantics: true,
        button: true,
        label: 'Stop focus',
        onTap: widget.store.stopFocus,
        child: Tooltip(
          message: 'Stop focus',
          excludeFromSemantics: true,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.store.stopFocus,
              child: SizedBox.square(
                dimension: FocusCard.target,
                child: Icon(Icons.close, size: 14, color: theme.muted),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _running(
    GroveTheme theme,
    FocusSession session,
    int left,
    DateTime now,
  ) {
    final clock = FocusRules.clock(left);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        Semantics(
          container: true,
          excludeSemantics: true,
          label: 'Time left',
          value: clock,
          // Many hours in a wide font get smaller, not cut.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              clock,
              maxLines: 1,
              style: theme
                  .number(30, weight: FontWeight.w600)
                  .copyWith(color: theme.ink),
            ),
          ),
        ),
        ProgressBar(
          fraction: FocusRules.progress(
            start: session.start,
            end: session.end,
            now: now,
          ),
        ),
      ],
    );
  }

  Widget _finished(GroveTheme theme, FocusSession session) {
    final store = widget.store;
    final hasTask = session.taskId != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        Text(
          hasTask ? 'Time is up. Mark done?' : 'Time is up.',
          style: theme
              .body(13, weight: FontWeight.w600)
              .copyWith(color: theme.ink),
        ),
        // The buttons go on two lines when the text is large.
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: hasTask
              ? [
                  _Button(
                    label: 'Mark done',
                    primary: true,
                    onTap: store.markFocusDone,
                  ),
                  _Button(label: 'Not yet', onTap: store.stopFocus),
                ]
              : [_Button(label: 'OK', primary: true, onTap: store.stopFocus)],
        ),
      ],
    );
  }
}

/// A small button of the card, with room for a finger.
class _Button extends StatelessWidget {
  const _Button({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: label,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: primary ? theme.accent : theme.surface2,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: primary ? theme.accent : theme.line),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: FocusCard.target,
                minHeight: FocusCard.target,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: theme
                        .body(12, weight: FontWeight.w600)
                        .copyWith(color: primary ? theme.bg : theme.ink),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Puts the focus card over `child`, 16 points from the bottom right
/// corner, while the store has a focus session. The card comes in from the
/// right and goes out the same way.
class FocusLayer extends StatefulWidget {
  const FocusLayer({super.key, required this.store, required this.child});

  /// The space between the card and the corner, in points.
  static const margin = 16.0;

  final AppStore store;
  final Widget child;

  @override
  State<FocusLayer> createState() => _FocusLayerState();
}

class _FocusLayerState extends State<FocusLayer>
    with SingleTickerProviderStateMixin {
  late final _show = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  /// The session on the card. It stays while the card goes out.
  FocusSession? _session;

  @override
  void initState() {
    super.initState();
    _session = widget.store.focus;
    if (_session != null) _show.value = 1;
    _show.addStatusListener(_statusChanged);
    widget.store.addListener(_storeChanged);
  }

  @override
  void didUpdateWidget(FocusLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_storeChanged);
      widget.store.addListener(_storeChanged);
      _session = widget.store.focus;
      _show.value = _session == null ? 0 : 1;
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_storeChanged);
    _show.dispose();
    super.dispose();
  }

  void _statusChanged(AnimationStatus status) {
    // The card is out: take it away.
    if (status == AnimationStatus.dismissed && _session != null && mounted) {
      setState(() => _session = null);
    }
  }

  void _storeChanged() {
    if (!mounted) return;
    final focus = widget.store.focus;
    if (focus == _session && (focus == null || _show.value == 1)) return;
    // A change can come in the middle of a frame. The work waits for its end.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _storeChanged());
      return;
    }
    final moves = MotionRules.isOn(
      setting: widget.store.motionSetting,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
    );
    if (focus != null) {
      setState(() => _session = focus);
      moves ? _show.forward() : _show.value = 1;
    } else {
      moves ? _show.reverse() : _show.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        if (session != null)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _show,
              builder: (context, card) {
                final shown = Curves.easeInOut.transform(_show.value);
                return CustomSingleChildLayout(
                  delegate: _Corner(out: 1 - shown),
                  child: Opacity(opacity: shown, child: card),
                );
              },
              child: FocusCard(store: widget.store, session: session),
            ),
          ),
      ],
    );
  }
}

/// The place of the card: the bottom right corner, on whole points, so the
/// text is sharp. `out` moves the card out at the right: 0 is at rest, 1 is
/// out of view.
class _Corner extends SingleChildLayoutDelegate {
  const _Corner({required this.out});

  final double out;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(
          (constraints.maxWidth - 2 * FocusLayer.margin).clamp(
            0.0,
            double.infinity,
          ),
          (constraints.maxHeight - 2 * FocusLayer.margin).clamp(
            0.0,
            double.infinity,
          ),
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final reach = childSize.width + FocusLayer.margin;
    return Offset(
      (size.width - reach + out * reach).floorToDouble(),
      (size.height - FocusLayer.margin - childSize.height).floorToDouble(),
    );
  }

  @override
  bool shouldRelayout(_Corner oldDelegate) => oldDelegate.out != out;
}
