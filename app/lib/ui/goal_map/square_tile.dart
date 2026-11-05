// One square of the goal map: a tinted icon tile on the left, a small state
// label over the title, and an edge in the colour of its state. It has the
// same size as `GoalMapLayout` says, so the map never measures it.
import 'package:flutter/material.dart';
import 'package:grove/core/goals/goal_graph.dart';
import 'package:grove/core/goals/goal_map_layout.dart';
import 'package:grove/core/model/goal_square.dart';

import '../theme/grove_theme.dart';
import '../theme/named_colors.dart';

/// The colours that say the state of a square. No see-through layers: a dim
/// square only has dim colours, so it costs nothing to draw.
class SquareLook {
  const SquareLook({
    required this.fill,
    required this.edge,
    required this.tile,
    required this.icon,
    required this.title,
    required this.label,
  });

  factory SquareLook.of(
    GroveTheme theme, {
    required Color goalColor,
    required SquareState state,
    required bool isRoot,
  }) {
    final solid = theme.solidSurface;
    final done = TaskPalette.color('green')!;
    final waiting = TaskPalette.color('orange')!;
    if (isRoot) {
      final strong = state == SquareState.done ? done : goalColor;
      final on = strong.computeLuminance() > 0.55
          ? const Color(0xFF1B1B1B)
          : Colors.white;
      return SquareLook(
        fill: strong,
        edge: strong,
        tile: on.withValues(alpha: 0.2),
        icon: on,
        title: on,
        label: on.withValues(alpha: 0.8),
      );
    }
    return switch (state) {
      SquareState.done => SquareLook(
        fill: solid,
        edge: done,
        tile: done.withValues(alpha: 0.18),
        icon: done,
        title: theme.ink,
        label: done,
      ),
      SquareState.waiting => SquareLook(
        fill: solid,
        edge: waiting,
        tile: waiting.withValues(alpha: 0.18),
        icon: waiting,
        title: theme.ink,
        label: waiting,
      ),
      SquareState.ready => SquareLook(
        fill: solid,
        edge: goalColor,
        tile: goalColor.withValues(alpha: 0.16),
        icon: goalColor,
        title: theme.ink,
        label: goalColor,
      ),
      SquareState.notReady => SquareLook(
        fill: Color.alphaBlend(theme.surface2, solid),
        edge: theme.line,
        tile: theme.muted.withValues(alpha: 0.12),
        icon: theme.muted,
        title: theme.muted,
        label: theme.muted,
      ),
    };
  }

  final Color fill;
  final Color edge;
  final Color tile;
  final Color icon;
  final Color title;
  final Color label;
}

IconData squareIcon(SquareState state, {required bool isRoot}) {
  if (isRoot) {
    return state == SquareState.done
        ? Icons.emoji_events_rounded
        : Icons.flag_rounded;
  }
  return switch (state) {
    SquareState.done => Icons.check_rounded,
    SquareState.waiting => Icons.hourglass_bottom_rounded,
    SquareState.ready => Icons.play_arrow_rounded,
    SquareState.notReady => Icons.more_horiz_rounded,
  };
}

/// The words for the state of a square. A wait says how long is left.
String squareLabel(GoalSquare square, SquareState state, DateTime now) {
  if (square.isRoot) return state == SquareState.done ? 'Finished' : 'Goal';
  return switch (state) {
    SquareState.done => 'Done',
    SquareState.waiting => 'Waiting, ${square.waitAt(now).label}',
    SquareState.ready => 'Ready',
    SquareState.notReady => 'Not ready',
  };
}

class SquareTile extends StatelessWidget {
  const SquareTile({
    super.key,
    required this.square,
    required this.state,
    required this.title,
    required this.goalColor,
    required this.now,
    required this.motion,
    this.selected = false,
    this.linkTarget = false,
    this.onTap,
    this.onTickTap,
  });

  final GoalSquare square;
  final SquareState state;

  /// The root shows the goal's name.
  final String title;
  final Color goalColor;
  final DateTime now;
  final bool motion;
  final bool selected;

  /// The user is linking, and this square can take the link.
  final bool linkTarget;
  final VoidCallback? onTap;

  /// A tap on the icon tile.
  final VoidCallback? onTickTap;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final look = SquareLook.of(
      theme,
      goalColor: goalColor,
      state: state,
      isRoot: square.isRoot,
    );
    final duration = motion ? const Duration(milliseconds: 280) : Duration.zero;
    final label = squareLabel(square, state, now);
    final radius = BorderRadius.circular(14);
    final focus = selected || linkTarget;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label: ${title.isEmpty ? 'Untitled' : title}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: duration,
          width: GoalMapLayout.squareWidth,
          height: GoalMapLayout.squareHeight,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: look.fill,
            borderRadius: radius,
            border: Border.all(
              color: focus ? theme.accent : look.edge,
              width: focus ? 3 : 2,
            ),
            boxShadow: theme.hairlines
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: Row(
            children: [
              ExcludeSemantics(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTickTap,
                  child: AnimatedContainer(
                    key: ValueKey('square-tick-${square.id}'),
                    duration: duration,
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: look.tile,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      squareIcon(state, isRoot: square.isRoot),
                      size: 24,
                      color: look.icon,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme
                          .body(11, weight: FontWeight.w600)
                          .copyWith(color: look.label),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title.isEmpty ? 'Untitled' : title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme
                          .body(14, weight: FontWeight.w600)
                          .copyWith(color: look.title),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
