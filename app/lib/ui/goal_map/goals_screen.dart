// The Goals screen: the map of one goal fills the screen, and the list of
// goals is at the bottom. It is the same on a Mac and on a phone.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:grove/core/goals/goal_graph.dart';
import 'package:grove/core/model/goal.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../planner/planner_dialogs.dart';
import '../shell/shell_layout.dart';
import '../tasks/task_format.dart';
import '../tasks/task_widgets.dart';
import '../theme/grove_theme.dart';
import '../theme/named_colors.dart';
import '../theme/panel.dart';
import 'block_tick_question.dart';
import 'goal_map_view.dart';
import 'project_form.dart';
import 'square_sheet.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key, required this.store});

  final AppStore store;

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  static const _listHeight = 60.0;
  static const _sheetWidth = 280.0;
  static const _gap = 12.0;
  static const _phoneSheetShare = 0.45;

  final _controller = GoalMapController();
  final _keys = FocusNode(debugLabel: 'goal map');

  String? _selected;

  /// A square that was just made: the sheet asks for its name.
  String? _naming;

  /// The Link button is on: a tap on a lit square makes the link.
  bool _linking = false;

  AppStore get _store => widget.store;

  @override
  void dispose() {
    _keys.dispose();
    super.dispose();
  }

  void _select(String? id) => setState(() {
    _selected = id;
    _linking = false;
    _naming = null;
    _keys.requestFocus();
  });

  void _tapSquare(GoalGraph graph, String id) {
    final from = _selected;
    if (_linking && from != null) {
      if (graph.canLink(child: from, parent: id)) {
        _store.linkSquares(child: from, parent: id);
        setState(() => _linking = false);
      }
      return;
    }
    _select(id);
  }

  void _addChild(String parentId) {
    final square = _store.addSquare(parentId: parentId);
    if (square == null) return;
    setState(() {
      _selected = square.id;
      _naming = square.id;
      _linking = false;
    });
  }

  /// A new square with the same parent, for Enter.
  void _addBeside(GoalGraph graph, String id) {
    final parents = graph.parentsOf(id);
    _addChild(parents.isEmpty ? id : parents.first);
  }

  void _delete(String id) {
    final graph = _graphOfSelected();
    final next = graph?.parentsOf(id).firstOrNull;
    if (_store.deleteSquare(id)) _select(next);
  }

  GoalGraph? _graphOfSelected() {
    final goal = _store.shownMapGoal;
    return goal == null ? null : _store.goalGraph(goal.id);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    // Keys in a text field belong to the field.
    if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_linking) {
        setState(() => _linking = false);
        return KeyEventResult.handled;
      }
      if (_selected != null) {
        _select(null);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final id = _selected;
    final graph = _graphOfSelected();
    if (id == null || graph == null || !graph.contains(id)) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.tab) {
      _addChild(id);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _addBeside(graph, id);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _delete(id);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _newGoal() async {
    final goal = await showNewGoalForm(context, _store);
    if (goal != null) _store.showMapGoal(goal.id);
  }

  Widget _toolBar(GroveTheme theme, GoalGraph graph) {
    final selected = _selected;
    final canLink =
        selected != null &&
        graph.contains(selected) &&
        selected != graph.rootId;
    Widget tool(
      String key,
      IconData icon,
      String label,
      VoidCallback? onTap, {
      bool on = false,
    }) => IconTap(
      key: ValueKey(key),
      icon: icon,
      label: label,
      tip: label,
      size: 20,
      minSide: 44,
      color: onTap == null
          ? theme.bg.withValues(alpha: 0.4)
          : (on ? theme.accent : theme.bg),
      onTap: onTap ?? () {},
    );
    return DecoratedBox(
      key: const ValueKey('map-tools'),
      decoration: BoxDecoration(
        color: theme.ink,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          tool(
            'map-tool-add',
            Icons.add,
            'Add a step that must come first',
            () => _addChild(selected ?? graph.rootId),
          ),
          tool(
            'map-tool-link',
            Icons.link,
            'Link this step to another step',
            canLink ? () => setState(() => _linking = !_linking) : null,
            on: _linking,
          ),
          tool(
            'map-tool-fit',
            Icons.fit_screen,
            'Show the whole map',
            _controller.fit,
          ),
        ],
      ),
    );
  }

  Widget _header(GroveTheme theme, GoalItem goal, double maxWidth) {
    final progress = _store.projectProgress(goal);
    final due = goal.dueDay;
    final facts = [
      if (due != null) 'By ${TaskFormat.dateLabel(due)}',
      GoalRules.projectStepsText(progress),
      if (GoalRules.projectHoursText(progress).isNotEmpty)
        GoalRules.projectHoursText(progress),
    ].join(' · ');
    return ConstrainedBox(
      key: const ValueKey('map-header'),
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Panel(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  spacing: 2,
                  children: [
                    Text(
                      GoalRules.titleOf(goal),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme
                          .heading(15, weight: FontWeight.w600)
                          .copyWith(color: theme.ink),
                    ),
                    Text(
                      facts,
                      key: const ValueKey('map-facts'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.body(11).copyWith(color: theme.muted),
                    ),
                    if (goal.notes.isNotEmpty)
                      Text(
                        goal.notes,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.body(11).copyWith(color: theme.muted),
                      ),
                  ],
                ),
              ),
              IconTap(
                key: const ValueKey('map-edit'),
                icon: Icons.edit_outlined,
                label: 'Edit the project',
                tip: 'Edit the project',
                color: theme.muted,
                minSide: 28,
                onTap: () => unawaited(showProjectForm(context, _store, goal)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _linkBanner(GroveTheme theme) => Panel(
    key: const ValueKey('map-link-banner'),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          Flexible(
            child: Text(
              'Tap the step that needs this one first.',
              style: theme.body(12).copyWith(color: theme.ink),
            ),
          ),
          DialogButton(
            label: 'Cancel',
            onTap: () => setState(() => _linking = false),
          ),
        ],
      ),
    ),
  );

  Widget _habit(GroveTheme theme, GoalItem goal) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Panel(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                ThemedHeading(GoalRules.titleOf(goal), 18),
                Text(
                  'This goal is a habit. It comes back each week, so it has '
                  'no map. Make it a project if it can finish. Its subtasks '
                  'become steps. Its blocks and points stay. You cannot make '
                  'it a habit again.',
                  style: theme.body(13).copyWith(color: theme.muted),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: DialogButton(
                    key: const ValueKey('make-project'),
                    label: 'Make it a Project',
                    primary: true,
                    onTap: () => _store.makeProject(goal.id),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _empty(GroveTheme theme) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 10,
      children: [
        Icon(Icons.account_tree_outlined, size: 24, color: theme.accent),
        Text(
          'No goals yet. Make one, and map what it needs.',
          textAlign: TextAlign.center,
          style: theme.body(13).copyWith(color: theme.muted),
        ),
      ],
    ),
  );

  Widget _chip(GroveTheme theme, GoalItem goal, GoalItem? shown) {
    final selected = goal.id == shown?.id;
    final tint = theme.color(GoalRules.blockColor(goal));
    final title = GoalRules.titleOf(goal);
    final small = goal.isProject
        ? GoalRules.projectStepsText(_store.projectProgress(goal))
        : 'Habit';
    void pick() {
      setState(() {
        _selected = null;
        _linking = false;
        _naming = null;
      });
      _store.showMapGoal(goal.id);
    }

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: '$title, $small',
      onTap: pick,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: ValueKey('map-goal-${goal.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: pick,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 200, minWidth: 96),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? tint.withValues(alpha: 0.16) : theme.surface2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? tint : const Color(0x00000000),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                Icon(
                  goal.isProject ? Icons.account_tree_outlined : Icons.repeat,
                  size: 14,
                  color: tint,
                ),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme
                            .body(12, weight: FontWeight.w600)
                            .copyWith(color: theme.ink, height: 1.2),
                      ),
                      Text(
                        small,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme
                            .body(10)
                            .copyWith(color: theme.muted, height: 1.2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _list(GroveTheme theme, List<GoalItem> goals, GoalItem? shown) =>
      Panel(
        key: const ValueKey('map-goal-list'),
        child: SizedBox(
          height: _listHeight,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconTap(
                  key: const ValueKey('map-new-goal'),
                  icon: Icons.add,
                  label: 'New goal',
                  tip: 'New goal',
                  size: 20,
                  minSide: 44,
                  color: theme.accent,
                  onTap: () => unawaited(_newGoal()),
                ),
              ),
              for (final goal in goals)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _chip(theme, goal, shown),
                ),
            ],
          ),
        ),
      );

  Widget _map(
    BuildContext context,
    GroveTheme theme,
    GoalItem goal,
    GoalGraph graph,
    EdgeInsets safe, {
    required bool phone,
  }) {
    final selected = _selected;
    final targets = _linking && selected != null
        ? {
            for (final id in graph.ids)
              if (graph.canLink(child: selected, parent: id)) id,
          }
        : const <String>{};
    return GoalMapView(
      goalId: goal.id,
      title: GoalRules.titleOf(goal),
      graph: graph,
      goalColor: theme.color(GoalRules.blockColor(goal)),
      motion: _store.motionSetting,
      controller: _controller,
      selectedId: selected,
      linkTargets: targets,
      safeArea: safe,
      clock: _store.clockNow,
      onTapSquare: (id) => _tapSquare(graph, id),
      onTickSquare: (id) => unawaited(tickSquare(context, _store, id)),
      onTapEmpty: () => _select(null),
      onLink: phone
          ? null
          : (child, parent) => _store.linkSquares(child: child, parent: parent),
      tools: (context) => IconTap(
        key: const ValueKey('square-add-child'),
        icon: Icons.add_circle,
        label: 'Add a step that must come first',
        tip: 'Add a step that must come first  (Tab)',
        size: 26,
        minSide: 44,
        color: theme.accent,
        onTap: () {
          if (selected != null) _addChild(selected);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => StoreBuilder(
    store: _store,
    builder: (context) {
      final theme = GroveTheme.of(context);
      final goals = _store.goals();
      final goal = _store.shownMapGoal;
      final graph = goal != null && goal.isProject
          ? _store.goalGraph(goal.id)
          : null;
      final phone =
          ShellRules.layoutFor(MediaQuery.sizeOf(context).width) ==
          ShellLayout.phone;
      // A square that is gone by an undo or a sync is no longer selected.
      final selected =
          _selected != null && (graph?.contains(_selected!) ?? false)
          ? _selected
          : null;
      if (selected == null && _selected != null) {
        _selected = null;
        _linking = false;
      }
      final listSpace = _listHeight + _gap * 2;
      final sheetOpen = selected != null;
      return Focus(
        focusNode: _keys,
        autofocus: true,
        onKeyEvent: _key,
        child: LayoutBuilder(
          builder: (context, box) {
            // While the user types on a phone, the keyboard takes half the
            // screen. The sheet and the square are all that stay. The Scaffold
            // takes the keyboard out of MediaQuery, so ask the window. The box
            // gets shorter with the keyboard, so this runs again when it moves.
            final typing =
                phone && sheetOpen && View.of(context).viewInsets.bottom > 0;
            final sheetBottom = typing ? _gap : listSpace;
            final safe = EdgeInsets.fromLTRB(
              72,
              typing ? _gap : (phone ? 96 : 72),
              (!phone && sheetOpen) ? _sheetWidth + _gap * 2 : _gap,
              sheetBottom +
                  (phone && sheetOpen ? box.maxHeight * _phoneSheetShare : 16),
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                if (goal == null)
                  _empty(theme)
                else if (graph == null)
                  _habit(theme, goal)
                else
                  _map(context, theme, goal, graph, safe, phone: phone),
                if (goal != null && graph != null) ...[
                  if (!typing)
                    Positioned(
                      left: _gap,
                      top: _gap,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        spacing: _gap,
                        children: [
                          _header(
                            theme,
                            goal,
                            box.maxWidth -
                                _gap * 2 -
                                ((!phone && selected != null)
                                    ? _sheetWidth + _gap
                                    : 0),
                          ),
                          _toolBar(theme, graph),
                        ],
                      ),
                    ),
                  if (_linking)
                    Positioned(
                      left: 72,
                      right: _gap,
                      bottom: _listHeight + _gap * 2,
                      child: Center(child: _linkBanner(theme)),
                    ),
                  if (selected != null)
                    Positioned(
                      key: const ValueKey('square-sheet-place'),
                      right: _gap,
                      left: phone ? _gap : null,
                      top: phone ? null : _gap,
                      bottom: sheetBottom,
                      width: phone ? null : _sheetWidth,
                      child: Align(
                        alignment: phone
                            ? Alignment.bottomCenter
                            : Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: phone
                                ? box.maxHeight * _phoneSheetShare
                                : double.infinity,
                          ),
                          child: SquareSheet(
                            key: ValueKey('square-sheet-$selected'),
                            store: _store,
                            goal: goal,
                            graph: graph,
                            squareId: selected,
                            focusName: _naming == selected,
                            onClose: () => _select(null),
                            onDelete: () => _delete(selected),
                            onSelect: _select,
                            onNameDone: _keys.requestFocus,
                          ),
                        ),
                      ),
                    ),
                ],
                if (!typing)
                  Positioned(
                    left: _gap,
                    right: _gap,
                    bottom: _gap,
                    child: _list(theme, goals, goal),
                  ),
              ],
            );
          },
        ),
      );
    },
  );
}
