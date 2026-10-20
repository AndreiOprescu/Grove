// Port of Sources/Grove/Tasks/TaskRow.swift.
import 'package:flutter/material.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/task.dart';
import 'package:grove/core/planner/planner_math.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../planner/payload_drag.dart';
import '../theme/check_box.dart';
import '../theme/grove_theme.dart';
import '../theme/named_colors.dart';
import 'task_format.dart';
import 'task_widgets.dart';

/// One task in the list: check box, title, small labels, and its subtasks
/// when it is open. Drag it onto the planner to give it a time, or onto
/// another row to put it there.
class TaskRow extends StatefulWidget {
  const TaskRow({
    super.key,
    required this.store,
    required this.task,
    this.contextDay,
    this.showDate = false,
    required this.lists,
    required this.isExpanded,
    required this.toggleExpanded,
    this.onDrop,
  });

  final AppStore store;
  final TaskItem task;

  /// The day this list stands for. It picks which time block to show.
  final DayKey? contextDay;

  /// Show where the task is planned as a label: its day (warm when late),
  /// "Week of 5 Oct" or "Someday".
  final bool showDate;
  final Map<String, ListItem> lists;
  final bool isExpanded;
  final VoidCallback toggleExpanded;

  /// Called with the id of the task that was dropped on this row. null
  /// means the row takes no drops.
  final ValueChanged<String>? onDrop;

  @override
  State<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<TaskRow> with AutomaticKeepAliveClientMixin {
  final _rename = TextEditingController();
  final _renameFocus = FocusNode();
  final _subtask = TextEditingController();
  final _subtaskFocus = FocusNode();
  bool _renaming = false;
  bool _targeted = false;

  AppStore get _store => widget.store;
  TaskItem get _task => widget.task;

  /// The list builds only the rows near the view. A row with a text that
  /// is not saved yet stays when it goes out of view: a new name, or a
  /// half-typed subtask.
  @override
  bool get wantKeepAlive => _renaming || _subtask.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _renameFocus.addListener(_renameFocusChanged);
    _subtask.addListener(updateKeepAlive);
  }

  @override
  void dispose() {
    _renameFocus.removeListener(_renameFocusChanged);
    _subtask.removeListener(updateKeepAlive);
    _rename.dispose();
    _renameFocus.dispose();
    _subtask.dispose();
    _subtaskFocus.dispose();
    super.dispose();
  }

  bool get _motionOn =>
      _store.motionSetting && !MediaQuery.disableAnimationsOf(context);

  // MARK: Actions

  void _startRename() {
    _rename.text = _task.title;
    _rename.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _task.title.length,
    );
    setState(() => _renaming = true);
    updateKeepAlive();
    _renameFocus.requestFocus();
  }

  void _renameFocusChanged() {
    if (!_renameFocus.hasFocus) _commitRename();
  }

  void _commitRename() {
    if (!_renaming) return;
    if (mounted) {
      setState(() => _renaming = false);
      updateKeepAlive();
    } else {
      _renaming = false;
    }
    final name = _rename.text.trim();
    if (name.isNotEmpty && name != _task.title) {
      _store.editTask(
        _task.id,
        (t) => t.copyWith(title: name),
        name: 'Rename Task',
      );
    }
  }

  void _addSubtask() {
    _store.addSubtask(to: _task.id, title: _subtask.text);
    _subtask.clear();
  }

  void _openSubtaskField() {
    if (!widget.isExpanded) widget.toggleExpanded();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _subtaskFocus.requestFocus();
    });
  }

  void _menu(Offset global) {
    final id = _task.id;
    final today = _store.clockToday;
    void move(TaskPlacement to) => _store.moveTask(id, to: to);
    showGroveMenu(context, global, [
      MenuLine(
        _task.isDone ? 'Mark Not Done' : 'Mark Done',
        () => _store.toggleDone(taskId: id),
      ),
      const MenuLine.divider(),
      const MenuLine.title('Move To'),
      MenuLine('Today', () => move(TaskPlacement.day(today))),
      MenuLine(
        'Tomorrow',
        () => move(TaskPlacement.day(today.adding(days: 1))),
      ),
      MenuLine('This Week', () => move(TaskPlacement.week(today))),
      MenuLine(
        'Next Week',
        () => move(TaskPlacement.week(today.weekStart().adding(days: 7))),
      ),
      MenuLine('Inbox', () => move(TaskPlacement.inbox)),
      MenuLine('Someday', () => move(TaskPlacement.someday)),
      const MenuLine.divider(),
      const MenuLine.title('Priority'),
      for (final (value, name) in const [
        (0, 'None'),
        (1, 'Low'),
        (2, 'Medium'),
        (3, 'High'),
      ])
        MenuLine(
          name,
          () => _store.editTask(
            id,
            (t) => t.copyWith(priority: value),
            name: 'Set Priority',
          ),
          checked: _task.priority == value,
        ),
      const MenuLine.divider(),
      MenuLine('Add Subtask', _openSubtaskField),
      MenuLine('Rename', _startRename),
      const MenuLine.divider(),
      MenuLine('Delete', () => _store.deleteTask(id)),
    ]);
  }

  // MARK: Pieces

  Widget _checkbox(TaskItem t, {double size = 17, bool linger = false}) {
    final label = t.isDone
        ? 'Mark ${t.title} as not done'
        : 'Mark ${t.title} as done';
    void toggle() => _store.toggleDone(taskId: t.id, linger: linger);
    return Semantics(
      container: true,
      button: true,
      checked: t.isDone,
      label: label,
      onTap: toggle,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: ValueKey('check-${t.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: toggle,
          child: CheckBox(isOn: t.isDone, size: size),
        ),
      ),
    );
  }

  Widget _title(GroveTheme theme) {
    final style = theme.body(13, weight: FontWeight.w600);
    if (_renaming) {
      return GroveField(
        key: ValueKey('rename-${_task.id}'),
        controller: _rename,
        focusNode: _renameFocus,
        placeholder: 'Title',
        style: style.copyWith(color: theme.ink),
        onSubmitted: (_) => _commitRename(),
        onEscape: () {
          setState(() => _renaming = false);
          updateKeepAlive();
        },
      );
    }
    return Text(
      _task.title,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: style.copyWith(
        color: _task.isDone ? theme.muted : theme.ink,
        decoration: _task.isDone ? TextDecoration.lineThrough : null,
        decorationColor: theme.muted,
      ),
    );
  }

  Widget _labels(GroveTheme theme) {
    final today = _store.clockToday;
    final tags = _store.tagNames(_task.id);
    final blocks = [..._store.blocksOfTask(_task.id)]
      ..sort((a, b) => a.start.compareTo(b.start));
    final shown =
        blocks.where((b) => b.start.day == widget.contextDay).firstOrNull ??
        blocks.firstOrNull;
    final place = widget.showDate
        ? TaskFormat.planLabel(_task, today: today)
        : null;
    final planDate = _task.planDate;
    final late =
        _task.bucket == TaskBucket.day && planDate != null && planDate < today;
    final due = _task.due;
    final list = widget.lists[_task.listId];
    final chips = [
      if (place != null)
        TaskChip(
          place,
          icon: _task.bucket == TaskBucket.someday
              ? Icons.bedtime_outlined
              : Icons.calendar_today_outlined,
          tint: late ? theme.accent2 : null,
        ),
      if (shown != null)
        TaskChip(
          '${PlannerMath.clock(shown.start.minute)}–'
          '${PlannerMath.clock(shown.end.minute)}'
          '${blocks.length > 1 ? ' +${blocks.length - 1}' : ''}',
          icon: Icons.schedule,
          tint: theme.accent,
        )
      else if (_task.estimateMin != 30)
        TaskChip(
          PlannerMath.duration(_task.estimateMin),
          icon: Icons.hourglass_empty,
        ),
      if (due != null)
        () {
          final d = TaskFormat.due(
            due,
            today: today,
            nowMinute: _store.nowMinute(),
          );
          return TaskChip(
            d.text,
            icon: Icons.flag_outlined,
            tint: d.late ? theme.accent2 : null,
          );
        }(),
      if (_task.recurrence != null)
        const TaskChip('Repeats', icon: Icons.repeat),
      if (list != null) TaskChip(list.name, icon: Icons.folder_outlined),
      if (_task.notes.isNotEmpty) const TaskChip('Notes', icon: Icons.notes),
      for (final tag in tags) TaskChip('#$tag'),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 4, runSpacing: 4, children: chips);
  }

  Widget _subtaskToggle(GroveTheme theme, List<TaskItem> subtasks) {
    final tip = widget.isExpanded ? 'Hide subtasks' : 'Show subtasks';
    return Tooltip(
      message: tip,
      excludeFromSemantics: true,
      child: Semantics(
        container: true,
        button: true,
        label: tip,
        onTap: widget.toggleExpanded,
        excludeSemantics: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            key: ValueKey('subtasks-${_task.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: widget.toggleExpanded,
            child: Padding(
              padding: const EdgeInsets.only(top: 3, left: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 3,
                children: [
                  if (subtasks.isNotEmpty)
                    Text(
                      '${subtasks.where((s) => s.isDone).length}/'
                      '${subtasks.length}',
                      style: theme
                          .body(10, weight: FontWeight.w600)
                          .copyWith(color: theme.muted),
                    ),
                  Icon(
                    widget.isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 13,
                    color: theme.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _subtaskList(GroveTheme theme, List<TaskItem> subtasks) => Padding(
    padding: const EdgeInsets.only(left: 25),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        for (final sub in subtasks)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapUp: (d) => showGroveMenu(context, d.globalPosition, [
              MenuLine('Delete Subtask', () => _store.deleteTask(sub.id)),
            ]),
            child: Row(
              spacing: 6,
              children: [
                _checkbox(sub, size: 14),
                Expanded(
                  child: Text(
                    sub.title,
                    style: theme
                        .body(12)
                        .copyWith(
                          color: sub.isDone ? theme.muted : theme.ink,
                          decoration: sub.isDone
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: theme.muted,
                        ),
                  ),
                ),
              ],
            ),
          ),
        Row(
          spacing: 6,
          children: [
            SizedBox(
              width: 14,
              child: Icon(Icons.add, size: 12, color: theme.muted),
            ),
            Expanded(
              child: GroveField(
                key: ValueKey('add-subtask-${_task.id}'),
                controller: _subtask,
                focusNode: _subtaskFocus,
                placeholder: 'Add a subtask',
                style: theme.body(12).copyWith(color: theme.ink),
                keepFocus: true,
                onSubmitted: (_) => _addSubtask(),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = GroveTheme.of(context);
    final subtasks = _store.subtasks(_task.id);
    final selected = _store.selectedTaskId == _task.id;
    final tint = TaskPalette.color(_task.color);
    final priority = _task.isDone ? null : PriorityColors.color(_task.priority);
    final corners = BorderRadius.circular(10);

    // The part that drags: the check box, the title and the labels.
    final top = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        _checkbox(_task, linger: _motionOn),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [_title(theme), if (!_task.isDone) _labels(theme)],
          ),
        ),
        if (subtasks.isNotEmpty || widget.isExpanded)
          _subtaskToggle(theme, subtasks),
      ],
    );

    final fill = tint == null
        ? theme.surface2
        : Color.alphaBlend(
            tint.withValues(alpha: _task.isDone ? 0.10 : 0.22),
            theme.surface2,
          );
    final box = CustomPaint(
      // A chosen row with a priority outline glows.
      painter: priority != null && selected
          ? _GlowPainter(theme.accent.withValues(alpha: 0.7))
          : null,
      child: DecoratedBox(
        decoration: BoxDecoration(color: fill, borderRadius: corners),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: corners,
            border: priority != null
                ? Border.all(color: priority, width: PriorityColors.borderWidth)
                : selected
                ? Border.all(color: theme.accent, width: 1.5)
                : null,
          ),
          child: Stack(
            children: [
              if (tint != null)
                Positioned(
                  left: 5,
                  top: 8,
                  bottom: 8,
                  width: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: tint,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    _renaming
                        ? top
                        : PayloadDrag(
                            payload: DragPayload.task(_task.id),
                            label: _task.title,
                            child: top,
                          ),
                    if (widget.isExpanded) _subtaskList(theme, subtasks),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final onDrop = widget.onDrop;
    return Semantics(
      container: true,
      selected: selected,
      child: DragTarget<String>(
        onWillAcceptWithDetails: (details) {
          final ok =
              onDrop != null && details.data.startsWith(DragPayload.taskPrefix);
          if (ok) setState(() => _targeted = true);
          return ok;
        },
        onLeave: (_) => setState(() => _targeted = false),
        onAcceptWithDetails: (details) {
          setState(() => _targeted = false);
          onDrop?.call(details.data.substring(DragPayload.taskPrefix.length));
        },
        builder: (context, _, _) => GestureDetector(
          key: ValueKey('task-${_task.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _store.selectedTaskId = selected ? null : _task.id,
          onSecondaryTapUp: (d) => _menu(d.globalPosition),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              box,
              if (_targeted)
                Positioned(
                  left: 0,
                  right: 0,
                  top: -4.5,
                  height: 3,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: theme.accent,
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A soft glow around a row with round corners. It paints only outside
/// the row, so a see-through row does not get darker.
class _GlowPainter extends CustomPainter {
  const _GlowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final row = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(10),
    );
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect((Offset.zero & size).inflate(30)),
      Path()..addRRect(row),
    );
    canvas
      ..save()
      ..clipPath(outside)
      ..drawRRect(
        row,
        Paint()
          ..color = color
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.color != color;
}
