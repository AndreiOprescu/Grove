// Port of Sources/Grove/Planner/BlockSubtaskEditor.swift: the subtasks of
// one goal block. The Mac app shows them in a popover on the block. Here
// they are in a small window, so the same view fits a phone.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:grove/core/model/block_subtask.dart';
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

/// The subtasks of one goal block: tick, rename, delete, add. Only this
/// block has them, not the other blocks of the goal. Each change saves at
/// once and is one undo step.
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
  late final bool _startOnAdd = _store.blockSubtasks(widget.eventId).isEmpty;
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
    final done = subs.where((s) => s.isDone).length;
    final small = theme.body(11).copyWith(color: theme.muted);
    final field = theme.body(13).copyWith(color: theme.ink);
    return PlannerSheet(
      width: 320,
      spacing: 8,
      children: [
        ThemedHeading(_store.event(widget.eventId)?.title ?? 'Goal block', 15),
        Text(
          subs.isEmpty ? 'Subtasks' : 'Subtasks  $done/${subs.length}',
          style: small.copyWith(fontWeight: FontWeight.w600),
        ),
        Text(
          'Only this block has these. Other blocks of the goal keep their '
          'own.',
          style: small,
        ),
        // The rows are as high as a finger needs, so they sit close.
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: 2,
          children: [
            for (final sub in subs)
              _SubtaskRow(key: ValueKey(sub.id), store: _store, sub: sub),
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
        Align(
          alignment: Alignment.centerRight,
          child: DialogButton(label: 'Done', primary: true, onTap: _close),
        ),
      ],
    );
  }
}

/// One subtask in the window: check box, name, delete. The name saves on
/// Return and when the field loses the keys.
class _SubtaskRow extends StatefulWidget {
  const _SubtaskRow({super.key, required this.store, required this.sub});

  /// The side of a place to click or tap, in points.
  static const target = 28.0;

  final AppStore store;
  final BlockSubtaskItem sub;

  @override
  State<_SubtaskRow> createState() => _SubtaskRowState();
}

class _SubtaskRowState extends State<_SubtaskRow> {
  late final _text = TextEditingController(text: widget.sub.title);
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
    if (oldWidget.sub.title != widget.sub.title && !_focus.hasFocus) {
      _show(widget.sub.title);
    }
  }

  @override
  void dispose() {
    // The window can close with a new name still in the field. The store
    // tells its listeners, so the save waits for the end of this frame.
    final store = widget.store;
    final id = widget.sub.id;
    final text = _text.text;
    if (SubtaskRules.renamed(text, from: widget.sub.title) != null) {
      scheduleMicrotask(() => store.renameBlockSubtask(id, to: text));
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
    final current = widget.store
        .blockSubtasks(widget.sub.eventId)
        .where((s) => s.id == widget.sub.id)
        .firstOrNull;
    if (current == null) return;
    final name = SubtaskRules.renamed(_text.text, from: current.title);
    if (name != null) {
      _show(name);
      widget.store.renameBlockSubtask(current.id, to: name);
    } else {
      // Empty or not changed: show what is saved.
      _show(current.title);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final sub = widget.sub;
    final style = theme
        .body(13)
        .copyWith(
          color: sub.isDone ? theme.muted : theme.ink,
          decoration: sub.isDone ? TextDecoration.lineThrough : null,
        );
    return Row(
      spacing: 8,
      children: [
        _RowButton(
          label: sub.isDone
              ? 'Mark ${sub.title} as not done'
              : 'Mark ${sub.title} as done',
          onTap: () => widget.store.toggleBlockSubtask(sub.id),
          child: CheckBox(isOn: sub.isDone, size: 14),
        ),
        Expanded(
          child: TextField(
            key: ValueKey('block-subtask-name-${sub.id}'),
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
        _RowButton(
          label: 'Delete subtask ${sub.title}',
          tooltip: 'Delete this subtask',
          onTap: () => widget.store.deleteBlockSubtask(sub.id),
          child: Icon(Icons.delete_outline, size: 16, color: theme.muted),
        ),
      ],
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
