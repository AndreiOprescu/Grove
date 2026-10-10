// Port of `BlockView` in Sources/Grove/Planner/BlockView.swift: one block
// on the grid. Gestures report to the grid, which owns all live state.
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:grove/core/planner/planner_math.dart';
import 'package:grove/state/state.dart' show PlannerBlock;

import '../theme/check_box.dart';
import '../theme/grove_theme.dart';
import '../theme/named_colors.dart';
import '../theme/panel.dart';
import '../theme/symbols.dart';
import 'inline_title_field.dart';
import 'planner_geometry.dart';

enum DragMode { move, resizeTop, resizeBottom }

/// The pointers that drag at once: a mouse.
const mouseKinds = {PointerDeviceKind.mouse};

/// The pointers that must press and hold first, so a swipe can scroll.
const touchKinds = {
  PointerDeviceKind.touch,
  PointerDeviceKind.stylus,
  PointerDeviceKind.invertedStylus,
  PointerDeviceKind.unknown,
};

class BlockView extends StatelessWidget {
  const BlockView({
    super.key,
    required this.block,
    required this.start,
    required this.end,
    required this.size,
    this.subtasks = const [],
    required this.isOverlay,
    required this.isSelected,
    required this.isDragging,
    required this.isRenaming,
    required this.onTap,
    required this.onToggleDone,
    required this.onRename,
    required this.onCancelRename,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onMenu,
  });

  final PlannerBlock block;

  /// The minutes the block shows now. A drag changes them before a save.
  final int start;
  final int end;
  final Size size;
  final List<BlockSubtask> subtasks;

  /// True when the block lies on top of a longer block. It gets a solid
  /// base so the block below does not show through.
  final bool isOverlay;
  final bool isSelected;
  final bool isDragging;
  final bool isRenaming;
  final VoidCallback onTap;
  final VoidCallback onToggleDone;
  final ValueChanged<String> onRename;
  final VoidCallback onCancelRename;

  /// A drag starts at `global`, the place of the press.
  final void Function(DragMode mode, Offset global) onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  /// Open the menu at `global`: a right click, or a long press that did
  /// not move.
  final ValueChanged<Offset> onMenu;

  int get _length => end - start;
  bool get _compact => _length < 25 || size.height < 34;
  bool get _checks => block.isTaskBlock || block.isGoalBlock;
  int get _subtasksDone => subtasks.where((s) => s.isDone).length;

  /// The tooltip: title and time, the short description of a task, or
  /// "Goal block" in front of a goal block's title.
  String get _helpText {
    final line =
        '${block.title} · ${PlannerMath.label(start: start, end: end)}';
    if (block.isGoalBlock) return 'Goal block · $line';
    return block.summary.isEmpty ? line : '$line\n${block.summary}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final tint = theme.color(block.color);
    final radius = min(8.0, theme.radius / 2);
    final shape = BorderRadius.circular(radius);
    final priority = block.isDone ? null : PriorityColors.color(block.priority);

    Widget face = DecoratedBox(
      decoration: BoxDecoration(
        color: tint.withValues(alpha: block.isTaskBlock ? 0.10 : 0.16),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 3,
            child: ColoredBox(color: tint),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(9, _compact ? 0 : 3, 5, 0),
            child: ClipRect(
              child: OverflowBox(
                minHeight: 0,
                maxHeight: double.infinity,
                alignment: _compact ? Alignment.centerLeft : Alignment.topLeft,
                child: _content(context, theme, tint),
              ),
            ),
          ),
        ],
      ),
    );
    face = ClipRRect(borderRadius: shape, child: face);
    if (priority != null) {
      face = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: shape,
          border: Border.all(
            color: priority,
            width: PriorityColors.borderWidth,
          ),
        ),
        child: face,
      );
    } else if (block.isTaskBlock) {
      face = DashedBorder(
        color: tint.withValues(alpha: 0.7),
        radius: radius,
        dash: 4,
        gap: 3,
        child: face,
      );
    }
    if (isSelected) {
      face = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: shape,
          border: Border.all(color: theme.accent, width: 2),
        ),
        child: face,
      );
    }
    face = Opacity(opacity: block.isDone ? 0.55 : 1, child: face);
    face = DecoratedBox(
      decoration: BoxDecoration(
        color: isOverlay ? theme.solidSurface : null,
        borderRadius: shape,
        boxShadow: [
          if (isDragging)
            const BoxShadow(
              color: Color(0x38000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            )
          else if (isOverlay)
            const BoxShadow(
              color: Color(0x2E000000),
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
        ],
      ),
      child: face,
    );

    final handle = min(6.0, max(2.0, size.height / 3));
    return Semantics(
      container: true,
      button: true,
      selected: isSelected,
      label: _helpText,
      onTap: onTap,
      child: SizedBox.fromSize(
        size: size,
        child: Stack(
          children: [
            Positioned.fill(
              child: Tooltip(
                message: _helpText,
                excludeFromSemantics: true,
                triggerMode: TooltipTriggerMode.manual,
                waitDuration: const Duration(milliseconds: 700),
                child: MouseRegion(
                  cursor: isDragging
                      ? SystemMouseCursors.grabbing
                      : SystemMouseCursors.grab,
                  child: _BodyGestures(
                    onTap: onTap,
                    onMenu: onMenu,
                    onDragStart: (at) => onDragStart(DragMode.move, at),
                    onDragUpdate: onDragUpdate,
                    onDragEnd: onDragEnd,
                    child: face,
                  ),
                ),
              ),
            ),
            if (!isRenaming) ...[
              _edge(DragMode.resizeTop, handle),
              _edge(DragMode.resizeBottom, handle),
            ],
          ],
        ),
      ),
    );
  }

  /// A thin strip on the top or bottom edge. It sits above the body, so it
  /// wins the press.
  Widget _edge(DragMode mode, double height) => Positioned(
    left: 0,
    right: 0,
    top: mode == DragMode.resizeTop ? 0 : null,
    bottom: mode == DragMode.resizeBottom ? 0 : null,
    height: height,
    child: EdgeHandle(
      key: ValueKey('${mode.name}-${block.id}'),
      onStart: (at) => onDragStart(mode, at),
      onUpdate: onDragUpdate,
      onEnd: onDragEnd,
    ),
  );

  Widget _content(BuildContext context, GroveTheme theme, Color tint) {
    final inner = size.width - 14;
    if (isRenaming) {
      return InlineTitleField(
        initial: block.title,
        placeholder: 'Title',
        onCommit: (text, _) => onRename(text),
        onCancel: onCancelRename,
      );
    }
    final titleStyle = theme
        .body(_compact ? 11 : 12, weight: FontWeight.w600)
        .copyWith(
          color: theme.ink,
          decoration: block.isDone ? TextDecoration.lineThrough : null,
        );
    if (_compact) {
      return Row(
        spacing: 5,
        children: [
          if (_checks && inner >= 46) _checkbox(12),
          if (block.isGoalBlock && inner >= 46)
            Icon(symbolIcon('target'), size: 10, color: tint),
          Expanded(
            child: Text(
              block.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: titleStyle,
            ),
          ),
          if (block.isGoalBlock && inner >= 110)
            Text(
              PlannerMath.duration(_length),
              maxLines: 1,
              style: theme
                  .number(10, weight: FontWeight.w700)
                  .copyWith(color: tint),
            ),
          if (inner >= 110) ?_badge(theme),
        ],
      );
    }
    final rows = PlannerLayoutRules.blockRows(
      height: size.height,
      hasSummary: block.summary.isNotEmpty,
      subtaskCount: subtasks.length,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 1,
      children: [
        // One row for time and length. A block laid on top of this one
        // then hides at most this row.
        _timeRow(context, theme, tint, inner),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 5,
          children: [
            if (_checks && inner >= 46) _checkbox(14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: 1,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 4,
                    children: [
                      Flexible(
                        child: Text(
                          block.title,
                          maxLines: rows.title,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                      ),
                      if (rows.badge && inner >= 90) ?_badge(theme),
                    ],
                  ),
                  if (rows.summary > 0)
                    Text(
                      block.summary,
                      maxLines: rows.summary,
                      overflow: TextOverflow.ellipsis,
                      style: theme
                          .body(11)
                          .copyWith(color: theme.ink.withValues(alpha: 0.7)),
                    ),
                  for (final sub in subtasks.take(rows.subtasks))
                    _subtaskRow(theme, sub),
                  if (rows.moreRow)
                    Text(
                      SubtaskLabels.more(
                        hidden: rows.hidden(subtasks.length),
                        shown: rows.subtasks,
                        done: _subtasksDone,
                        total: subtasks.length,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme
                          .body(10, weight: FontWeight.w600)
                          .copyWith(color: theme.muted),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The time row. It shows the longest text that fits. A goal block starts
  /// it with the target icon and keeps its length, the number the user
  /// plans it by.
  Widget _timeRow(
    BuildContext context,
    GroveTheme theme,
    Color tint,
    double width,
  ) {
    final style = theme
        .number(10, weight: FontWeight.w700)
        .copyWith(color: tint);
    final range = '${PlannerMath.clock(start)}–${PlannerMath.clock(end)}';
    final length = PlannerMath.duration(_length);
    final room = width - (block.isGoalBlock ? 13 : 0);
    final scaler = MediaQuery.textScalerOf(context);
    bool fits(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final ok = painter.width <= room;
      painter.dispose();
      return ok;
    }

    final text = fits('$range · $length')
        ? '$range · $length'
        : fits(range) || !block.isGoalBlock
        ? range
        : length;
    return Row(
      spacing: 3,
      children: [
        if (block.isGoalBlock && width >= 46)
          Icon(symbolIcon('target'), size: 10, color: tint),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: style,
          ),
        ),
      ],
    );
  }

  /// One subtask line: a small mark and the title. It only shows; the task
  /// panel changes subtasks.
  Widget _subtaskRow(GroveTheme theme, BlockSubtask sub) => Semantics(
    container: true,
    excludeSemantics: true,
    label: '${sub.isDone ? 'Done' : 'Subtask'}: ${sub.title}',
    child: Row(
      spacing: 4,
      children: [
        CheckBox(isOn: sub.isDone, size: 9),
        Expanded(
          child: Text(
            sub.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme
                .body(11)
                .copyWith(
                  color: sub.isDone
                      ? theme.muted
                      : theme.ink.withValues(alpha: 0.85),
                  decoration: sub.isDone ? TextDecoration.lineThrough : null,
                ),
          ),
        ),
      ],
    ),
  );

  /// "1/4" in the title row when the block has subtasks but no line to
  /// show them.
  Widget? _badge(GroveTheme theme) => subtasks.isEmpty
      ? null
      : Text(
          SubtaskLabels.badge(done: _subtasksDone, total: subtasks.length),
          maxLines: 1,
          semanticsLabel: '$_subtasksDone of ${subtasks.length} subtasks done',
          style: theme
              .number(10, weight: FontWeight.w700)
              .copyWith(color: theme.muted),
        );

  Widget _checkbox(double size) => Semantics(
    container: true,
    button: true,
    label: block.isDone ? 'Mark not done' : 'Mark done',
    onTap: onToggleDone,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: ValueKey('check-${block.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: onToggleDone,
        child: CheckBox(isOn: block.isDone, size: size),
      ),
    ),
  );
}

/// The gestures of a block body. A mouse drags at once. A finger presses
/// and holds first, so a swipe still scrolls the grid. A right click, or a
/// long press that does not move, opens the menu.
class _BodyGestures extends StatefulWidget {
  const _BodyGestures({
    required this.onTap,
    required this.onMenu,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.child,
  });

  final VoidCallback onTap;
  final ValueChanged<Offset> onMenu;
  final ValueChanged<Offset> onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  final Widget child;

  @override
  State<_BodyGestures> createState() => _BodyGesturesState();
}

class _BodyGesturesState extends State<_BodyGestures> {
  Offset? _pressAt;
  bool _moved = false;

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: HitTestBehavior.opaque,
    gestures: {
      TapGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            TapGestureRecognizer.new,
            (tap) {
              tap.onTap = widget.onTap;
              tap.onSecondaryTapUp = (d) => widget.onMenu(d.globalPosition);
            },
          ),
      PanGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
            () => PanGestureRecognizer(supportedDevices: mouseKinds),
            (pan) {
              pan.dragStartBehavior = DragStartBehavior.down;
              pan.onStart = (d) => widget.onDragStart(d.globalPosition);
              pan.onUpdate = (d) => widget.onDragUpdate(d.globalPosition);
              pan.onEnd = (_) => widget.onDragEnd();
              pan.onCancel = widget.onDragEnd;
            },
          ),
      LongPressGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(supportedDevices: touchKinds),
            (press) {
              press.onLongPressStart = (d) {
                _pressAt = d.globalPosition;
                _moved = false;
                widget.onDragStart(d.globalPosition);
              };
              press.onLongPressMoveUpdate = (d) {
                final from = _pressAt;
                if (from != null && (d.globalPosition - from).distance > 6) {
                  _moved = true;
                }
                widget.onDragUpdate(d.globalPosition);
              };
              press.onLongPressEnd = (d) {
                widget.onDragEnd();
                if (!_moved) widget.onMenu(d.globalPosition);
              };
              press.onLongPressCancel = widget.onDragEnd;
            },
          ),
    },
    child: widget.child,
  );
}

/// A place to drag an edge of a block up or down. It works with a mouse
/// and with a finger: it sits inside the scroll view, so it wins the drag.
class EdgeHandle extends StatelessWidget {
  const EdgeHandle({
    super.key,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    this.child,
  });

  final ValueChanged<Offset> onStart;
  final ValueChanged<Offset> onUpdate;
  final VoidCallback onEnd;
  final Widget? child;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.resizeUpDown,
    child: RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        VerticalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<VerticalDragGestureRecognizer>(
              VerticalDragGestureRecognizer.new,
              (drag) {
                drag.dragStartBehavior = DragStartBehavior.down;
                drag.onStart = (d) => onStart(d.globalPosition);
                drag.onUpdate = (d) => onUpdate(d.globalPosition);
                drag.onEnd = (_) => onEnd();
                drag.onCancel = onEnd;
              },
            ),
      },
      child: child,
    ),
  );
}
