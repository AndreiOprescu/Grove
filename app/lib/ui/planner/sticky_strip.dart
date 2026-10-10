// Port of Sources/Grove/Planner/StickyStrip.swift: the strip under the day
// numbers. It shows each day's open tasks that have no time, as sticky
// notes. Drag a note onto the grid to give it a time. Drag a task block up
// here to take its time away.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/task.dart';
import 'package:grove/core/planner/planner_math.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../theme/grove_theme.dart';
import 'payload_drag.dart';
import 'planner_geometry.dart';
import 'sticky_rules.dart';

class StickyStrip extends StatefulWidget {
  const StickyStrip({
    super.key,
    required this.store,
    required this.days,
    required this.isDropTarget,
    required this.workStart,
    required this.workEnd,
  });

  final AppStore store;
  final List<DayKey> days;

  /// A task block is over the strip. A release takes it off the grid.
  final bool isDropTarget;
  final int workStart;
  final int workEnd;

  static const openKey = 'planner.stickyOpen';

  @override
  State<StickyStrip> createState() => _StickyStripState();
}

class _StickyStripState extends State<StickyStrip> {
  DayKey? _targeted;

  AppStore get _store => widget.store;
  bool get _open => _store.prefs.getBool(StickyStrip.openKey) ?? true;

  @override
  void initState() {
    super.initState();
    _store.addListener(_changed);
  }

  @override
  void didUpdateWidget(StickyStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_changed);
      widget.store.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _toggle() {
    _store.prefs.set(StickyStrip.openKey, !_open);
    setState(() {});
  }

  void _fit(TaskItem task, DayKey day) => _store.fit(
    taskId: task.id,
    day: day,
    workStart: widget.workStart,
    workEnd: widget.workEnd,
    step: PlannerMath.step,
  );

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final notes = _store.timeless(widget.days);
    final total = notes.values.fold(0, (sum, list) => sum + list.length);
    final expanded = _open && total > 0;
    return LayoutBuilder(
      builder: (context, box) {
        const gutter = PlannerGeometry.gutterWidth;
        final cellWidth = max(
          60.0,
          (box.maxWidth - gutter) / max(widget.days.length, 1),
        );
        final cells = IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, day) in widget.days.indexed)
                Expanded(
                  child: _cell(
                    theme,
                    index,
                    day,
                    notes[day] ?? const [],
                    expanded: expanded,
                    cellWidth: cellWidth,
                  ),
                ),
            ],
          ),
        );
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.line)),
          ),
          child: ColoredBox(
            color: theme.accent.withValues(
              alpha: widget.isDropTarget ? 0.10 : 0,
            ),
            child: Stack(
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: StickyRules.foldedHeight,
                    maxHeight: expanded
                        ? StickyRules.maxHeight
                        : StickyRules.foldedHeight,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _foldButton(theme, total),
                      Expanded(
                        child: expanded
                            ? SingleChildScrollView(child: cells)
                            : cells,
                      ),
                    ],
                  ),
                ),
                if (total == 0)
                  Positioned.fill(
                    left: gutter,
                    child: IgnorePointer(
                      child: Center(
                        child: Text(
                          'Tasks with no time land here',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.body(11).copyWith(color: theme.muted),
                        ),
                      ),
                    ),
                  ),
                if (widget.isDropTarget)
                  Positioned.fill(
                    child: IgnorePointer(child: _releaseHint(theme)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _releaseHint(GroveTheme theme) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: theme.accent, width: 2),
    ),
    child: Center(
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: theme.accent,
          shape: const StadiumBorder(),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 5,
            children: [
              Icon(Icons.move_to_inbox_outlined, size: 13, color: theme.bg),
              Text(
                'Release to unschedule',
                style: theme
                    .body(12, weight: FontWeight.w600)
                    .copyWith(color: theme.bg),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _foldButton(GroveTheme theme, int total) {
    final open = _open;
    final color = total > 0 ? theme.ink : theme.muted;
    return Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      label:
          '$total task${total == 1 ? '' : 's'} with no time. '
          '${open ? 'Hide' : 'Show'}',
      onTap: _toggle,
      child: Tooltip(
        message: open
            ? 'Hide the tasks with no time'
            : 'Show the tasks with no time',
        excludeFromSemantics: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            key: const ValueKey('sticky-fold'),
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            child: SizedBox(
              width: PlannerGeometry.gutterWidth,
              height: StickyRules.foldedHeight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 1,
                children: [
                  Icon(
                    open ? Icons.keyboard_arrow_down : Icons.chevron_right,
                    size: 14,
                    color: color,
                  ),
                  Text(
                    '$total',
                    style: theme
                        .number(11, weight: FontWeight.w700)
                        .copyWith(color: color),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cell(
    GroveTheme theme,
    int index,
    DayKey day,
    List<TaskItem> tasks, {
    required bool expanded,
    required double cellWidth,
  }) {
    final Widget content;
    if (expanded) {
      final columns = StickyRules.columns(cellWidth);
      content = Padding(
        padding: const EdgeInsets.all(StickyRules.spacing),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            for (var i = 0; i < tasks.length; i += columns)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: StickyRules.spacing,
                children: [
                  for (var c = 0; c < columns; c++)
                    Expanded(
                      child: i + c < tasks.length
                          ? _StickyNote(
                              key: ValueKey('sticky-${tasks[i + c].id}'),
                              store: _store,
                              task: tasks[i + c],
                              onFit: () => _fit(tasks[i + c], day),
                            )
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
          ],
        ),
      );
    } else if (tasks.isNotEmpty) {
      content = SizedBox(
        height: StickyRules.foldedHeight,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '${tasks.length} with no time',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.body(11).copyWith(color: theme.muted),
            ),
          ),
        ),
      );
    } else {
      content = const SizedBox(height: StickyRules.foldedHeight);
    }
    return DragTarget<String>(
      key: ValueKey('sticky-cell-${day.string}'),
      onWillAcceptWithDetails: (details) {
        if (!details.data.startsWith(DragPayload.taskPrefix)) return false;
        setState(() => _targeted = day);
        return true;
      },
      onLeave: (_) {
        if (_targeted == day) setState(() => _targeted = null);
      },
      onAcceptWithDetails: (details) {
        setState(() => _targeted = null);
        _store.dropTask(
          details.data.substring(DragPayload.taskPrefix.length),
          on: day,
        );
      },
      builder: (context, _, _) => DecoratedBox(
        decoration: BoxDecoration(
          color: theme.accent.withValues(alpha: _targeted == day ? 0.10 : 0),
          // The same column lines as the grid.
          border: index > 0
              ? Border(left: BorderSide(color: theme.line))
              : null,
        ),
        child: Align(alignment: Alignment.topLeft, child: content),
      ),
    );
  }
}

/// One task with no time, as a sticky note. A click opens the task. A drag
/// onto the grid gives it a time.
class _StickyNote extends StatelessWidget {
  const _StickyNote({
    super.key,
    required this.store,
    required this.task,
    required this.onFit,
  });

  final AppStore store;
  final TaskItem task;
  final VoidCallback onFit;

  Future<void> _menu(BuildContext context, Offset global) async {
    final theme = GroveTheme.of(context);
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    PopupMenuItem<VoidCallback> item(String label, VoidCallback action) =>
        PopupMenuItem<VoidCallback>(
          value: action,
          height: 34,
          child: Text(label, style: theme.body(13).copyWith(color: theme.ink)),
        );
    final action = await showMenu<VoidCallback>(
      context: context,
      color: theme.solidSurface,
      position: RelativeRect.fromRect(
        global & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        item(
          task.isDone ? 'Mark Not Done' : 'Mark Done',
          () => store.toggleDone(taskId: task.id),
        ),
        item('Fit in Next Gap', onFit),
        const PopupMenuDivider(),
        item('Delete Task', () => store.deleteTask(task.id)),
      ],
    );
    action?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final tint = [
      theme.accent,
      theme.accent2,
      theme.accent3,
    ][StickyRules.colorIndex(task.id)];
    final length = PlannerMath.duration(
      PlannerMath.blockLength(task.estimateMin),
    );
    final selected = store.selectedTaskId == task.id;

    // Square paper in the colour of the note, a darker band of glue on
    // top, and a soft shadow.
    final paper = DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          tint.withValues(alpha: 0.22),
          theme.solidSurface,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 3,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: selected ? Border.all(color: theme.accent, width: 1.5) : null,
        ),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 7,
              child: ColoredBox(color: tint.withValues(alpha: 0.32)),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 11, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  spacing: 4,
                  children: [
                    Text(
                      task.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme
                          .body(12, weight: FontWeight.w600)
                          .copyWith(color: theme.ink),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            length,
                            maxLines: 1,
                            style: theme.body(10).copyWith(color: theme.muted),
                          ),
                        ),
                        Semantics(
                          container: true,
                          button: true,
                          label: 'Fit ${task.title} in the next free gap',
                          onTap: onFit,
                          child: Tooltip(
                            message: 'Put this task in the next free gap',
                            excludeFromSemantics: true,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                key: ValueKey('fit-${task.id}'),
                                behavior: HitTestBehavior.opaque,
                                onTap: onFit,
                                child: Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: Icon(
                                    Icons.vertical_align_bottom,
                                    size: 13,
                                    color: tint,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Semantics(
      container: true,
      label: '${task.title}, $length, no time yet. Drag onto the timeline.',
      child: PayloadDrag(
        payload: DragPayload.task(task.id),
        label: task.title,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => store.selectedTaskId = selected ? null : task.id,
          onSecondaryTapUp: (d) => _menu(context, d.globalPosition),
          child: Transform.rotate(
            angle: StickyRules.tilt(task.id) * pi / 180,
            child: paper,
          ),
        ),
      ),
    );
  }
}
