// Port of Sources/Grove/Planner/BlockSubtaskEditor.swift: the subtasks of
// one goal block. The Mac app shows them in a popover on the block. Here
// they are in a small window, so the same view fits a phone.
//
// Only this app: the window also has the subtasks of the goal that are
// planned in this block, and it can take more of them from the goal.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:grove/core/model/goal_subtask.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../theme/check_box.dart';
import '../theme/grove_theme.dart';
import '../theme/panel.dart';
import 'planner_dialogs.dart';

/// Shows the subtasks of the block `eventId`. The future ends when the
/// window is closed.
Future<void> showBlockSubtaskEditor(
  BuildContext context,
  AppStore store,
  String eventId,
) => showDialog<void>(
  context: context,
  builder: (context) => BlockSubtaskEditor(store: store, eventId: eventId),
);

/// The subtasks of one goal block: tick, rename, delete, add. First the
/// subtasks of the goal that are planned in this block, then the ones that
/// only this block has. Each change saves at once and is one undo step.
class BlockSubtaskEditor extends StatefulWidget {
  const BlockSubtaskEditor({
    super.key,
    required this.store,
    required this.eventId,
  });

  final AppStore store;
  final String eventId;

  @override
  State<BlockSubtaskEditor> createState() => _BlockSubtaskEditorState();
}

class _BlockSubtaskEditorState extends State<BlockSubtaskEditor> {
  final _newText = TextEditingController();
  final _addFocus = FocusNode(debugLabel: 'new block subtask');

  /// The field for a new subtask has the keys at the start when the list
  /// is empty.
  late final bool _startOnAdd =
      _store.blockSubtasks(widget.eventId).isEmpty &&
      _store.plannedGoalSubtasks(widget.eventId).isEmpty;
  bool _closed = false;

  AppStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    _store.addListener(_storeChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_storeChanged);
    _newText.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  void _storeChanged() {
    if (!mounted) return;
    // A change can come in the middle of a frame. The work waits for its end.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _storeChanged());
      return;
    }
    // The store closed the window, or the block is gone (Undo, a delete on
    // another device).
    if (_store.editingBlockSubtasks != widget.eventId ||
        _store.event(widget.eventId) == null) {
      _close();
      return;
    }
    setState(() {});
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    final route = ModalRoute.of(context);
    if (route == null) return;
    final navigator = Navigator.of(context);
    route.isCurrent ? navigator.pop() : navigator.removeRoute(route);
  }

  /// The name that the database has for a subtask of this block now, or
  /// null when the subtask is gone.
  String? _savedOwn(String id) => _store
      .blockSubtasks(widget.eventId)
      .where((s) => s.id == id)
      .firstOrNull
      ?.title;

  /// The same for a subtask of the goal that is planned in this block.
  String? _savedPlanned(String id) => _store
      .plannedGoalSubtasks(widget.eventId)
      .where((s) => s.id == id)
      .firstOrNull
      ?.title;

  void _add(String text) {
    if (_store.addBlockSubtask(to: widget.eventId, title: text) != null) {
      _newText.clear();
    }
    _addFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final subs = _store.blockSubtasks(widget.eventId);
    final planned = _store.plannedGoalSubtasks(widget.eventId);
    final free = _store.freeGoalSubtasks(widget.eventId);
    final count = subs.length + planned.length;
    final done =
        subs.where((s) => s.isDone).length +
        planned.where((s) => s.isDone).length;
    final small = theme.body(11).copyWith(color: theme.muted);
    final field = theme.body(13).copyWith(color: theme.ink);
    return PlannerSheet(
      width: 320,
      spacing: 8,
      children: [
        ThemedHeading(_store.event(widget.eventId)?.title ?? 'Goal block', 15),
        Text(
          count == 0 ? 'Subtasks' : 'Subtasks  $done/$count',
          style: small.copyWith(fontWeight: FontWeight.w600),
        ),
        Text(
          planned.isEmpty
              ? 'Only this block has these. Other blocks of the goal keep '
                    'their own.'
              : 'The ones with an arrow are from the goal. Only this block '
                    'has the others.',
          style: small,
        ),
        // The rows are as high as a finger needs, so they sit close.
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: 2,
          children: [
            for (final sub in planned)
              _SubtaskRow(
                key: ValueKey(sub.id),
                nameKey: ValueKey('block-goal-subtask-name-${sub.id}'),
                title: sub.title,
                isDone: sub.isDone,
                saved: () => _savedPlanned(sub.id),
                onToggle: () => _store.toggleGoalSubtask(sub.id),
                onRename: (name) => _store.renameGoalSubtask(sub.id, to: name),
                onDelete: () => _store.deleteGoalSubtask(sub.id),
                onBack: () => _store.unassignGoalSubtask(sub.id),
              ),
            for (final sub in subs)
              _SubtaskRow(
                key: ValueKey(sub.id),
                nameKey: ValueKey('block-subtask-name-${sub.id}'),
                title: sub.title,
                isDone: sub.isDone,
                saved: () => _savedOwn(sub.id),
                onToggle: () => _store.toggleBlockSubtask(sub.id),
                onRename: (name) => _store.renameBlockSubtask(sub.id, to: name),
                onDelete: () => _store.deleteBlockSubtask(sub.id),
              ),
            Row(
              spacing: 8,
              children: [
                SizedBox.square(
                  dimension: _SubtaskRow.target,
                  child: Icon(Icons.add, size: 16, color: theme.muted),
                ),
                Expanded(
                  child: TextField(
                    key: const ValueKey('block-subtask-add'),
                    controller: _newText,
                    focusNode: _addFocus,
                    autofocus: _startOnAdd,
                    maxLines: 1,
                    style: field,
                    cursorColor: theme.accent,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration.collapsed(
                      hintText: 'Add a subtask',
                      hintStyle: field.copyWith(color: theme.muted),
                    ),
                    // The field keeps the keys, so the next one goes in at
                    // once.
                    onEditingComplete: () {},
                    onSubmitted: _add,
                  ),
                ),
              ],
            ),
          ],
        ),
        if (free.isNotEmpty) ...[
          Text(
            'From the goal',
            style: small.copyWith(fontWeight: FontWeight.w600),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: 2,
            children: [
              for (final sub in free)
                _FreeRow(
                  key: ValueKey('block-goal-subtask-free-${sub.id}'),
                  sub: sub,
                  onTap: () =>
                      _store.assignGoalSubtask(sub.id, to: widget.eventId),
                ),
            ],
          ),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: DialogButton(label: 'Done', primary: true, onTap: _close),
        ),
      ],
    );
  }
}

/// One subtask in the window: check box, name, delete. The name saves on
/// Return and when the field loses the keys. A subtask of the goal also has
/// an arrow that takes it out of the block.
class _SubtaskRow extends StatefulWidget {
  const _SubtaskRow({
    super.key,
    required this.nameKey,
    required this.title,
    required this.isDone,
    required this.saved,
    required this.onToggle,
    required this.onRename,
    required this.onDelete,
    this.onBack,
  });

  /// The side of a place to click or tap, in points.
  static const target = 28.0;

  final Key nameKey;
  final String title;
  final bool isDone;

  /// The name that the database has now, or null when the subtask is gone.
  final String? Function() saved;
  final VoidCallback onToggle;
  final ValueChanged<String> onRename;
  final VoidCallback onDelete;

  /// Takes a subtask of the goal out of this block. Null for a subtask
  /// that only this block has.
  final VoidCallback? onBack;

  @override
  State<_SubtaskRow> createState() => _SubtaskRowState();
}

class _SubtaskRowState extends State<_SubtaskRow> {
  late final _text = TextEditingController(text: widget.title);
  final _focus = FocusNode(debugLabel: 'block subtask name');

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(_SubtaskRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Undo, or a change from another device, while the field is not in use.
    if (oldWidget.title != widget.title && !_focus.hasFocus) {
      _show(widget.title);
    }
  }

  @override
  void dispose() {
    // The window can close with a new name still in the field. The store
    // tells its listeners, so the save waits for the end of this frame.
    final rename = widget.onRename;
    final text = _text.text;
    if (SubtaskRules.renamed(text, from: widget.title) != null) {
      scheduleMicrotask(() => rename(text));
    }
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (!_focus.hasFocus) _commit();
  }

  void _show(String title) {
    if (_text.text == title) return;
    _text.value = TextEditingValue(
      text: title,
      selection: TextSelection.collapsed(offset: title.length),
    );
  }

  void _commit() {
    final current = widget.saved();
    if (current == null) return;
    final name = SubtaskRules.renamed(_text.text, from: current);
    if (name != null) {
      _show(name);
      widget.onRename(name);
    } else {
      // Empty or not changed: show what is saved.
      _show(current);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final title = widget.title;
    final isDone = widget.isDone;
    final onBack = widget.onBack;
    final style = theme
        .body(13)
        .copyWith(
          color: isDone ? theme.muted : theme.ink,
          decoration: isDone ? TextDecoration.lineThrough : null,
        );
    return Row(
      spacing: 8,
      children: [
        _RowButton(
          label: isDone ? 'Mark $title as not done' : 'Mark $title as done',
          onTap: widget.onToggle,
          child: CheckBox(isOn: isDone, size: 14),
        ),
        Expanded(
          child: TextField(
            key: widget.nameKey,
            controller: _text,
            focusNode: _focus,
            maxLines: 1,
            style: style,
            cursorColor: theme.accent,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration.collapsed(
              hintText: 'Name',
              hintStyle: style.copyWith(color: theme.muted),
            ),
            onEditingComplete: () {},
            onSubmitted: (_) => _commit(),
          ),
        ),
        if (onBack != null)
          _RowButton(
            label: 'Put $title back in the goal',
            tooltip: 'Back to the goal, out of this block',
            onTap: onBack,
            child: Icon(Icons.reply, size: 16, color: theme.muted),
          ),
        _RowButton(
          label: 'Delete subtask $title',
          tooltip: onBack == null
              ? 'Delete this subtask'
              : 'Delete this subtask from the goal too',
          onTap: widget.onDelete,
          child: Icon(Icons.delete_outline, size: 16, color: theme.muted),
        ),
      ],
    );
  }
}

/// One open subtask of the goal that is in no block. A click or a tap puts
/// it in this block.
class _FreeRow extends StatelessWidget {
  const _FreeRow({super.key, required this.sub, required this.onTap});

  final GoalSubtaskItem sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: 'Put ${sub.title} in this block',
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            height: _SubtaskRow.target,
            child: Row(
              spacing: 8,
              children: [
                SizedBox.square(
                  dimension: _SubtaskRow.target,
                  child: Icon(Icons.add, size: 16, color: theme.muted),
                ),
                Expanded(
                  child: Text(
                    sub.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.body(13).copyWith(color: theme.ink),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small picture to click or tap, with room for a finger.
class _RowButton extends StatelessWidget {
  const _RowButton({
    required this.label,
    required this.onTap,
    required this.child,
    this.tooltip,
  });

  final String label;
  final String? tooltip;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Widget button = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: _SubtaskRow.target,
          child: Center(child: child),
        ),
      ),
    );
    final tip = tooltip;
    if (tip != null) {
      button = Tooltip(message: tip, excludeFromSemantics: true, child: button);
    }
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: label,
      onTap: onTap,
      child: button,
    );
  }
}
