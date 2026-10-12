// The subtasks of a goal, under the goal in the Goals panel. Only this app
// has them (the Mac app has no such list).
import 'package:flutter/material.dart';
import 'package:grove/core/model/goal.dart';
import 'package:grove/core/model/goal_subtask.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../planner/inline_title_field.dart' show BlurAction, InlineTitleRules;
import '../tasks/task_widgets.dart';
import '../theme/check_box.dart';
import '../theme/grove_theme.dart';

/// The side of a place to click or tap, and the height of a line, in
/// points. The same as in the subtask window of a block.
const double goalSubtaskTarget = 28;

/// What a closed goal shows of its subtasks: the first three that are not
/// done, and a line that says what is not shown ("+2 more"). A click on a
/// box ticks that subtask. A click on any other place opens the goal.
/// Nothing at all for a goal with no subtasks.
class GoalSubtasksClosed extends StatelessWidget {
  const GoalSubtasksClosed({
    super.key,
    required this.store,
    required this.goal,
    required this.subtasks,
    required this.onOpen,
  });

  final AppStore store;
  final GoalItem goal;

  /// All subtasks of the goal, in list order.
  final List<GoalSubtaskItem> subtasks;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final shown = GoalSubtaskRules.closed(subtasks);
    final more = GoalSubtaskRules.moreLine(subtasks);
    if (shown.isEmpty && more == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4, right: 10),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // The goal row above says "click to show the subtasks" to a
          // screen reader, and the line under the rows is a button.
          excludeFromSemantics: true,
          onTap: onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final sub in shown)
                SizedBox(
                  key: ValueKey('goal-subtask-${sub.id}'),
                  height: goalSubtaskTarget,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _CheckButton(store: store, sub: sub),
                      Expanded(
                        child: _Line(
                          child: Text(
                            sub.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.body(12).copyWith(color: theme.ink),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (more != null)
                Semantics(
                  container: true,
                  button: true,
                  label: more,
                  hint: 'Shows all subtasks',
                  onTap: onOpen,
                  excludeSemantics: true,
                  child: SizedBox(
                    key: ValueKey('goal-subtasks-more-${goal.id}'),
                    height: goalSubtaskTarget,
                    child: Padding(
                      padding: const EdgeInsets.only(left: goalSubtaskTarget),
                      child: _Line(
                        child: Text(
                          more,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.body(11).copyWith(color: theme.muted),
                        ),
                      ),
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

/// What an open goal shows of its subtasks: all of them, done ones too, and
/// a line to add one. Each subtask can be ticked, renamed and deleted. Each
/// change saves at once and is one undo step.
class GoalSubtasksOpen extends StatefulWidget {
  const GoalSubtasksOpen({
    super.key,
    required this.store,
    required this.goal,
    required this.subtasks,
  });

  final AppStore store;
  final GoalItem goal;

  /// All subtasks of the goal, in list order.
  final List<GoalSubtaskItem> subtasks;

  @override
  State<GoalSubtasksOpen> createState() => _GoalSubtasksOpenState();
}

class _GoalSubtasksOpenState extends State<GoalSubtasksOpen> {
  final _newText = TextEditingController();
  final _addFocus = FocusNode(debugLabel: 'new goal subtask');

  /// The line for a new subtask has the keys at the start when the list is
  /// empty: the goal was opened to add the first one.
  late final bool _startOnAdd = widget.subtasks.isEmpty;

  @override
  void initState() {
    super.initState();
    _addFocus.addListener(_focusChanged);
  }

  @override
  void dispose() {
    // The goal can close with a line still typed. It is added, as when the
    // line loses the keys.
    final store = widget.store;
    final goalId = widget.goal.id;
    final text = _newText.text;
    if (InlineTitleRules.onBlur(text) == BlurAction.commit) {
      writeLater(store, () => store.addGoalSubtask(to: goalId, title: text));
    }
    _addFocus.removeListener(_focusChanged);
    _addFocus.dispose();
    _newText.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (!_addFocus.hasFocus &&
        InlineTitleRules.onBlur(_newText.text) == BlurAction.commit) {
      _add();
    }
  }

  void _add() {
    final id = widget.store.addGoalSubtask(
      to: widget.goal.id,
      title: _newText.text,
    );
    if (id != null) _newText.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final store = widget.store;
    return Padding(
      padding: const EdgeInsets.only(top: 4, right: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final sub in widget.subtasks)
            _OpenRow(
              key: ValueKey('goal-subtask-${sub.id}'),
              store: store,
              sub: sub,
            ),
          SizedBox(
            key: ValueKey('goal-subtask-add-${widget.goal.id}'),
            height: goalSubtaskTarget,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: goalSubtaskTarget,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Icon(Icons.add, size: 14, color: theme.muted),
                    ),
                  ),
                ),
                Expanded(
                  child: _Line(
                    child: GroveField(
                      controller: _newText,
                      focusNode: _addFocus,
                      placeholder: 'Add a subtask',
                      style: theme.body(12).copyWith(color: theme.ink),
                      autofocus: _startOnAdd,
                      // The line keeps the keys, so the next one goes in at
                      // once.
                      keepFocus: true,
                      onSubmitted: (_) => _add(),
                      onEscape: () {
                        _newText.clear();
                        _addFocus.unfocus();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One subtask in an open goal: check box, name, delete. The name saves on
/// Return, when the field loses the keys and when the goal closes.
class _OpenRow extends StatefulWidget {
  const _OpenRow({super.key, required this.store, required this.sub});

  final AppStore store;
  final GoalSubtaskItem sub;

  @override
  State<_OpenRow> createState() => _OpenRowState();
}

class _OpenRowState extends State<_OpenRow> {
  late final _text = TextEditingController(text: widget.sub.title);
  final _focus = FocusNode(debugLabel: 'goal subtask name');

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(_OpenRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Undo, or a change from another device, while the field is not in use.
    if (oldWidget.sub.title != widget.sub.title && !_focus.hasFocus) {
      _show(widget.sub.title);
    }
  }

  @override
  void dispose() {
    // The goal can close with a new name still in the field.
    final store = widget.store;
    final id = widget.sub.id;
    final text = _text.text;
    if (SubtaskRules.renamed(text, from: widget.sub.title) != null) {
      writeLater(store, () => store.renameGoalSubtask(id, to: text));
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

  /// What the database has for this subtask now, or null when it is gone.
  GoalSubtaskItem? get _saved => widget.store
      .goalSubtasks(widget.sub.goalId)
      .where((s) => s.id == widget.sub.id)
      .firstOrNull;

  void _commit() {
    final current = _saved;
    if (current == null) return;
    final name = SubtaskRules.renamed(_text.text, from: current.title);
    if (name != null) {
      _show(name);
      widget.store.renameGoalSubtask(current.id, to: name);
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
        .body(12)
        .copyWith(
          color: sub.isDone ? theme.muted : theme.ink,
          decoration: sub.isDone ? TextDecoration.lineThrough : null,
          decorationColor: theme.muted,
        );
    return SizedBox(
      height: goalSubtaskTarget,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CheckButton(store: widget.store, sub: sub),
          Expanded(
            child: _Line(
              child: GroveField(
                key: ValueKey('goal-subtask-name-${sub.id}'),
                controller: _text,
                focusNode: _focus,
                placeholder: 'Name',
                label: 'Subtask name',
                style: style,
                keepFocus: true,
                onSubmitted: (_) => _commit(),
                onEscape: () {
                  _show(_saved?.title ?? sub.title);
                  _focus.unfocus();
                },
              ),
            ),
          ),
          _TapBox(
            key: ValueKey('goal-subtask-delete-${sub.id}'),
            label: 'Delete subtask ${sub.title}',
            tooltip: 'Delete this subtask',
            onTap: () => widget.store.deleteGoalSubtask(sub.id),
            child: Icon(Icons.delete_outline, size: 16, color: theme.muted),
          ),
        ],
      ),
    );
  }
}

/// The check box of a subtask. Its middle is under the colour dot of the
/// goal, and the name after it starts under the name of the goal.
class _CheckButton extends StatelessWidget {
  const _CheckButton({required this.store, required this.sub});

  final AppStore store;
  final GoalSubtaskItem sub;

  @override
  Widget build(BuildContext context) => _TapBox(
    key: ValueKey('goal-subtask-check-${sub.id}'),
    label: sub.isDone
        ? 'Mark ${sub.title} as not done'
        : 'Mark ${sub.title} as done',
    onTap: () => store.toggleGoalSubtask(sub.id),
    child: Padding(
      padding: const EdgeInsets.only(left: 2),
      child: CheckBox(isOn: sub.isDone, size: 14),
    ),
  );
}

/// A small picture to click or tap, with room for a finger.
class _TapBox extends StatelessWidget {
  const _TapBox({
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
          dimension: goalSubtaskTarget,
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

/// One line of text at the left of its place, in the middle of the height
/// on a whole point (`Center` puts it on half a point when the free space
/// is an odd number).
class _Line extends StatelessWidget {
  const _Line({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => WholeCenter(
    child: SizedBox(width: double.infinity, child: child),
  );
}
