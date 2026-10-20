// The lines of the subtasks of one block. The subtask window of a plain
// block and the goal panel both use them.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:grove/core/model/goal_subtask.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../theme/check_box.dart';
import '../theme/grove_theme.dart';

/// One subtask in a list of a block: check box, name, delete. The name
/// saves on Return and when the field loses the keys. A subtask of the goal
/// also has an arrow that takes it out of the block.
class SubtaskLine extends StatefulWidget {
  const SubtaskLine({
    super.key,
    required this.nameKey,
    required this.title,
    required this.isDone,
    required this.saved,
    required this.onToggle,
    required this.onRename,
    this.onDelete,
    this.onBack,
    this.backLabel,
    this.backTip,
    this.checkKey,
    this.backKey,
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

  /// Deletes the subtask. Null: the row has no delete.
  final VoidCallback? onDelete;

  /// Takes a subtask of the goal out of this block. Null for a subtask
  /// that only this block has.
  final VoidCallback? onBack;

  /// What the back button says to a screen reader and in its tip.
  final String? backLabel;
  final String? backTip;

  /// Keys of the check box and of the back button, for tests.
  final Key? checkKey;
  final Key? backKey;

  @override
  State<SubtaskLine> createState() => _SubtaskLineState();
}

class _SubtaskLineState extends State<SubtaskLine> {
  late final _text = TextEditingController(text: widget.title);
  final _focus = FocusNode(debugLabel: 'block subtask name');

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(SubtaskLine oldWidget) {
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
    final onDelete = widget.onDelete;
    final style = theme
        .body(13)
        .copyWith(
          color: isDone ? theme.muted : theme.ink,
          decoration: isDone ? TextDecoration.lineThrough : null,
        );
    return Row(
      spacing: 8,
      children: [
        SubtaskLineButton(
          key: widget.checkKey,
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
          SubtaskLineButton(
            key: widget.backKey,
            label: widget.backLabel ?? 'Put $title back in the goal',
            tooltip: widget.backTip ?? 'Back to the goal, out of this block',
            onTap: onBack,
            child: Icon(Icons.reply, size: 16, color: theme.muted),
          ),
        if (onDelete != null)
          SubtaskLineButton(
            label: 'Delete subtask $title',
            tooltip: onBack == null
                ? 'Delete this subtask'
                : 'Delete this subtask from the goal too',
            onTap: onDelete,
            child: Icon(Icons.delete_outline, size: 16, color: theme.muted),
          ),
      ],
    );
  }
}

/// One open subtask of the goal that is in no block. A click or a tap puts
/// it in the block.
class FreeSubtaskLine extends StatelessWidget {
  const FreeSubtaskLine({
    super.key,
    required this.sub,
    required this.onTap,
    this.label,
  });

  final GoalSubtaskItem sub;
  final VoidCallback onTap;

  /// What the line says to a screen reader. "Put … in this block" when
  /// null.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: label ?? 'Put ${sub.title} in this block',
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            height: SubtaskLine.target,
            child: Row(
              spacing: 8,
              children: [
                SizedBox.square(
                  dimension: SubtaskLine.target,
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
class SubtaskLineButton extends StatelessWidget {
  const SubtaskLineButton({
    super.key,
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
          dimension: SubtaskLine.target,
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
