// A project in the Goals panel. A project row cannot be dragged: its squares
// can. Each one makes a block that holds that square.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:grove/core/goals/goal_graph.dart';
import 'package:grove/core/model/goal.dart';
import 'package:grove/core/model/goal_square.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../goal_map/block_tick_question.dart';
import '../goal_map/project_form.dart';
import '../goal_map/square_tile.dart';
import '../tasks/task_widgets.dart';
import '../planner/payload_drag.dart';
import '../shell/shell_layout.dart';
import '../theme/check_box.dart';
import '../theme/grove_theme.dart';
import '../theme/named_colors.dart';
import 'goal_row.dart';
import 'goal_subtasks.dart';

class ProjectRow extends StatefulWidget {
  const ProjectRow({super.key, required this.store, required this.goal});

  final AppStore store;
  final GoalItem goal;

  @override
  State<ProjectRow> createState() => _ProjectRowState();
}

class _ProjectRowState extends State<ProjectRow> {
  bool _showLater = false;

  AppStore get _store => widget.store;
  GoalItem get _goal => widget.goal;

  void _openMap() {
    final phone =
        ShellRules.layoutFor(MediaQuery.sizeOf(context).width) ==
        ShellLayout.phone;
    if (phone) _store.leftPane = null;
    _store.openGoalMap(_goal.id);
  }

  void _menu(Offset global) {
    showGroveMenu(context, global, [
      MenuLine('Open Map', _openMap),
      MenuLine('Edit…', () => showProjectForm(context, _store, _goal)),
      const MenuLine.divider(),
      MenuLine('Delete Goal…', () => confirmDeleteGoal(context, _store, _goal)),
    ]);
  }

  Widget _header(GroveTheme theme, ProjectProgress progress, Color tint) {
    final title = GoalRules.titleOf(_goal);
    final hours = GoalRules.projectHoursText(progress);
    final steps = GoalRules.projectStepsText(progress);
    return Semantics(
      container: true,
      button: true,
      label: '$title, project, $steps',
      hint: 'Opens the map',
      onTap: _openMap,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: ValueKey('goal-${_goal.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: _openMap,
          onSecondaryTapUp: (d) => _menu(d.globalPosition),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.account_tree_outlined, size: 13, color: tint),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  spacing: 5,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      spacing: 6,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme
                                .body(13, weight: FontWeight.w600)
                                .copyWith(color: theme.ink),
                          ),
                        ),
                        Text(
                          steps,
                          maxLines: 1,
                          style: theme
                              .number(11, weight: FontWeight.w600)
                              .copyWith(color: theme.muted),
                        ),
                      ],
                    ),
                    GoalBar(
                      parts: (
                        done: GoalRules.projectBar(progress),
                        planned: GoalRules.projectBar(progress),
                      ),
                      tint: tint,
                    ),
                    if (hours.isNotEmpty)
                      Text(
                        hours,
                        style: theme.body(10).copyWith(color: theme.muted),
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

  Widget _line(GroveTheme theme, GoalGraph graph, String id) {
    final square = graph.square(id);
    final state = graph.stateOf(id);
    final title = squareNameOf(square, _goal);
    final dim = state != SquareState.ready;
    void tick() => unawaited(tickSquare(context, _store, id));
    return Opacity(
      opacity: dim ? 0.6 : 1,
      child: PayloadDrag(
        key: ValueKey('project-square-$id'),
        payload: DragPayload.square(id),
        label: title,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Semantics(
              container: true,
              button: true,
              checked: false,
              label: 'Mark $title as done',
              onTap: tick,
              excludeSemantics: true,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  key: ValueKey('project-square-check-$id'),
                  behavior: HitTestBehavior.opaque,
                  onTap: tick,
                  child: const SizedBox.square(
                    dimension: goalSubtaskTarget,
                    child: Center(child: CheckBox(isOn: false, size: 15)),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.body(12).copyWith(color: theme.ink),
              ),
            ),
            if (state == SquareState.waiting)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  squareLabel(square, state, _store.clockNow()),
                  maxLines: 1,
                  style: theme.body(10).copyWith(color: theme.muted),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _laterToggle(GroveTheme theme, int count) {
    final label = 'Later steps · $count';
    void toggle() => setState(() => _showLater = !_showLater);
    return Semantics(
      container: true,
      button: true,
      expanded: _showLater,
      label: label,
      onTap: toggle,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: ValueKey('project-later-${_goal.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: toggle,
          child: SizedBox(
            height: goalSubtaskTarget,
            child: Row(
              spacing: 4,
              children: [
                SizedBox(
                  width: goalSubtaskTarget,
                  child: Icon(
                    _showLater
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 14,
                    color: theme.muted,
                  ),
                ),
                Expanded(
                  child: Text(
                    label,
                    style: theme.body(11).copyWith(color: theme.muted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final tint = theme.color(GoalRules.blockColor(_goal));
    final progress = _store.projectProgress(_goal);
    final graph = _store.goalGraph(_goal.id);
    final open = graph != null && !progress.isFinished;
    final later = open ? graph.laterIds : const <String>[];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surface2,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: _header(theme, progress, tint),
            ),
            if (open) ...[
              for (final id in graph.readyIds) _line(theme, graph, id),
              for (final id in graph.waitingIds) _line(theme, graph, id),
              if (later.isNotEmpty) _laterToggle(theme, later.length),
              if (_showLater)
                for (final id in later) _line(theme, graph, id),
            ],
          ],
        ),
      ),
    );
  }
}

/// The word that a screen reader and a list say for a square.
String squareNameOf(GoalSquare square, GoalItem goal) => square.isRoot
    ? GoalRules.titleOf(goal)
    : (square.title.isEmpty ? 'Untitled' : square.title);
