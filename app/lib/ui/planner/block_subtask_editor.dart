// Port of Sources/Grove/Planner/BlockSubtaskEditor.swift: the subtasks of
// one goal block. The Mac app shows them in a popover on the block. Here
// they are in a small window, so the same view fits a phone.
//
// Only this app: the window also has the subtasks of the goal that are
// planned in this block, and it can take more of them from the goal.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../theme/grove_theme.dart';
import '../theme/panel.dart';
import 'planner_dialogs.dart';
import 'subtask_lines.dart';

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
              SubtaskLine(
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
              SubtaskLine(
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
                  dimension: SubtaskLine.target,
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
                FreeSubtaskLine(
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
