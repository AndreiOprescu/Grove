// The details of the selected square: its name, its tick, its wait and its
// links. It stands beside the map on a wide window, and over it on a phone.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:grove/core/goals/goal_graph.dart';
import 'package:grove/core/model/goal.dart';
import 'package:grove/core/model/goal_square.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../goals/project_row.dart' show squareNameOf;
import '../goals/step_length.dart';
import '../planner/planner_dialogs.dart';
import '../tasks/task_widgets.dart';
import '../theme/grove_theme.dart';
import '../theme/panel.dart';
import 'block_tick_question.dart';
import 'square_tile.dart';

class SquareSheet extends StatefulWidget {
  const SquareSheet({
    super.key,
    required this.store,
    required this.goal,
    required this.graph,
    required this.squareId,
    required this.focusName,
    required this.onClose,
    required this.onDelete,
    required this.onSelect,
    required this.onNameDone,
  });

  final AppStore store;
  final GoalItem goal;
  final GoalGraph graph;
  final String squareId;

  /// True for a new square: the user names it first.
  final bool focusName;
  final VoidCallback onClose;
  final VoidCallback onDelete;
  final ValueChanged<String> onSelect;

  /// Enter in the name: the keys go back to the map.
  final VoidCallback onNameDone;

  @override
  State<SquareSheet> createState() => _SquareSheetState();
}

class _SquareSheetState extends State<SquareSheet> {
  late final _name = TextEditingController(text: _savedName);
  final _nameFocus = FocusNode();
  late int _days = WaitDays.of(_square);

  AppStore get _store => widget.store;
  GoalSquare get _square => widget.graph.square(widget.squareId);

  String get _savedName => _square.isRoot ? widget.goal.title : _square.title;

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(SquareSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // An undo or a sync can change the name. What is being typed stays.
    if (!_nameFocus.hasFocus && _name.text != _savedName) {
      _name.text = _savedName;
    }
  }

  @override
  void dispose() {
    final store = _store;
    final id = widget.squareId;
    final name = _name.text;
    final saved = _savedName;
    if (name.trim() != saved) {
      writeLater(store, () => store.renameSquare(id, name));
    }
    _nameFocus.removeListener(_focusChanged);
    _nameFocus.dispose();
    _name.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (!_nameFocus.hasFocus) _saveName();
  }

  void _saveName() {
    if (_name.text.trim() != _savedName) {
      _store.renameSquare(widget.squareId, _name.text);
    }
  }

  Widget _heading(GroveTheme theme, String text) => Text(
    text,
    style: theme.body(11, weight: FontWeight.w600).copyWith(color: theme.muted),
  );

  /// One link: its square, and a button that takes the link away. A square
  /// with only the root as parent has no such button: it must hold on to the
  /// map.
  Widget _linkLine(
    GroveTheme theme, {
    required String id,
    required SquareLink link,
  }) {
    final graph = widget.graph;
    final name = squareNameOf(graph.square(id), widget.goal);
    final edit = graph.unlinkEdit(child: link.childId, parent: link.parentId);
    return Row(
      children: [
        Expanded(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onSelect(id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.body(12).copyWith(color: theme.ink),
                ),
              ),
            ),
          ),
        ),
        if (edit != null && !edit.isEmpty)
          IconTap(
            key: ValueKey('square-unlink-${link.childId}-${link.parentId}'),
            icon: Icons.link_off,
            label: 'Remove the link to $name',
            tip: 'Remove this link',
            color: theme.muted,
            minSide: 28,
            onTap: () => _store.unlinkSquares(
              child: link.childId,
              parent: link.parentId,
            ),
          ),
      ],
    );
  }

  Widget _wait(GroveTheme theme, GoalSquare square, DateTime now) {
    if (square.isWaiting) {
      return Row(
        spacing: 8,
        children: [
          Expanded(
            child: Text(
              squareLabel(square, SquareState.waiting, now),
              key: const ValueKey('square-wait-label'),
              style: theme.body(12).copyWith(color: theme.ink),
            ),
          ),
          DialogButton(
            key: const ValueKey('square-stop-wait'),
            label: 'Stop waiting',
            onTap: () => _store.stopWaiting(square.id),
          ),
        ],
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        WaitDays(days: _days, onChange: (d) => setState(() => _days = d)),
        DialogButton(
          key: const ValueKey('square-start-wait'),
          label: 'Start waiting',
          onTap: () => _store.startWaiting(
            square.id,
            minutes: _days * WaitDays.minutesPerDay,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final graph = widget.graph;
    final square = _square;
    final state = graph.stateOf(square.id);
    final now = _store.clockNow();
    final parents = graph.parentsOf(square.id);
    final children = graph.childrenOf(square.id);
    final blocks = _store.blockCountOfSquare(square.id);
    return Panel(
      key: const ValueKey('square-sheet'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: 10,
          children: [
            Row(
              spacing: 6,
              children: [
                Expanded(
                  child: Text(
                    squareLabel(square, state, now),
                    style: theme
                        .body(11, weight: FontWeight.w600)
                        .copyWith(color: theme.muted),
                  ),
                ),
                IconTap(
                  key: const ValueKey('square-sheet-close'),
                  icon: Icons.close,
                  label: 'Close',
                  color: theme.muted,
                  onTap: widget.onClose,
                ),
              ],
            ),
            GroveField(
              key: const ValueKey('square-name'),
              controller: _name,
              focusNode: _nameFocus,
              placeholder: 'Name this step',
              label: 'Name of the step',
              boxed: true,
              autofocus: widget.focusName,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              onSubmitted: (_) {
                _saveName();
                widget.onNameDone();
              },
              onEscape: () {
                _name.text = _savedName;
                widget.onNameDone();
              },
            ),
            DialogButton(
              key: const ValueKey('square-tick'),
              label: square.isDone
                  ? (square.isRoot ? 'Open the project again' : 'Mark not done')
                  : (square.isRoot ? 'Finish the project' : 'Mark done'),
              primary: !square.isDone,
              onTap: () => unawaited(tickSquare(context, _store, square.id)),
            ),
            if (!square.isRoot) ...[
              _heading(theme, 'How long it takes'),
              StepLengthPick(
                key: const ValueKey('square-length'),
                minutes: square.lengthMinutes,
                onPick: (m) => _store.setSquareLength(square.id, m),
              ),
            ],
            if (!square.isRoot && !square.isDone) ...[
              _heading(theme, 'Wait for a reply'),
              _wait(theme, square, now),
            ],
            if (children.isNotEmpty) ...[
              _heading(theme, 'Needs first'),
              for (final id in children)
                _linkLine(
                  theme,
                  id: id,
                  link: SquareLink(childId: id, parentId: square.id),
                ),
            ],
            if (parents.isNotEmpty) ...[
              _heading(theme, 'Needed by'),
              for (final id in parents)
                _linkLine(
                  theme,
                  id: id,
                  link: SquareLink(childId: square.id, parentId: id),
                ),
            ],
            if (blocks > 0)
              Text(
                blocks == 1 ? 'In 1 block' : 'In $blocks blocks',
                style: theme.body(11).copyWith(color: theme.muted),
              ),
            if (!square.isRoot)
              Align(
                alignment: Alignment.centerRight,
                child: DialogButton(
                  key: const ValueKey('square-delete'),
                  label: 'Delete step',
                  onTap: widget.onDelete,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
