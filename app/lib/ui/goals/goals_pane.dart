// Port of Sources/Grove/Goals/GoalsPane.swift.
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:grove/core/model/goal.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../planner/inline_title_field.dart' show BlurAction, InlineTitleRules;
import '../tasks/task_widgets.dart';
import '../theme/grove_theme.dart';
import '../theme/panel.dart';
import 'goal_row.dart';

/// The Goals panel: recurring work with a weekly target of hours or
/// sessions, and no date. Drag a goal into a day to plan a block of it.
/// Every block in the week is planned time; a block ticked done in the
/// planner is done time. A goal is never done: it stays every week. The
/// numbers are for the week that holds the selected day, the week the
/// Planner shows. A goal has subtasks under it; every block of the goal has
/// that one list. One goal at a time can be open: it shows all its
/// subtasks, and its editor when asked.
class GoalsPane extends StatefulWidget {
  const GoalsPane({super.key, required this.store});

  final AppStore store;

  @override
  State<GoalsPane> createState() => _GoalsPaneState();
}

class _GoalsPaneState extends State<GoalsPane> {
  String? _openGoal;

  /// The open goal shows its editor too.
  bool _editing = false;

  AppStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    _store.addListener(_storeChanged);
    _takeGoalToEdit();
  }

  @override
  void dispose() {
    _store.removeListener(_storeChanged);
    super.dispose();
  }

  void _storeChanged() {
    if (!mounted || _store.goalToEdit == null) return;
    // A change can come in the middle of a frame. The work waits for its end.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _storeChanged());
      return;
    }
    setState(_takeGoalToEdit);
  }

  /// "Edit goal" in the goal panel: the goal opens with its editor. The
  /// store forgets the request after this frame.
  void _takeGoalToEdit() {
    final id = _store.goalToEdit;
    if (id == null) return;
    _openGoal = id;
    _editing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_store.goalToEdit == id) _store.goalToEdit = null;
    });
  }

  /// Opens the goal, or closes it when it is the open one. Opening one
  /// closes the other.
  void _toggle(String id) => setState(() {
    _openGoal = _openGoal == id ? null : id;
    _editing = false;
  });

  /// Shows the editor of the goal, and opens the goal for it when needed.
  /// Hides the editor when it shows: the goal stays open.
  void _edit(String id) => setState(() {
    _editing = !(_openGoal == id && _editing);
    _openGoal = id;
  });

  Widget _emptyState(GroveTheme theme) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        Icon(Icons.track_changes, size: 22, color: theme.accent),
        Text(
          'No goals yet. A goal is something you want to give hours or '
          'sessions to each week.',
          textAlign: TextAlign.center,
          style: theme.body(12).copyWith(color: theme.muted),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => StoreBuilder(
    store: _store,
    builder: (context) {
      final theme = GroveTheme.of(context);
      final day = _store.selectedDay;
      final sundayFirst = _store.weekStartsSunday;
      final week = GoalRules.week(day, sundayFirst: sundayFirst);
      final goals = _store.goals();
      final subtasks = _store.goalSubtasksOf([for (final g in goals) g.id]);
      final marks = _store.goalSubtaskMarks(subtasks.values.expand((s) => s));
      return Panel(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  const Expanded(child: ThemedHeading('Goals', 20)),
                  Text(
                    GoalRules.weekLabel(week, today: _store.clockToday),
                    style: theme.body(11).copyWith(color: theme.muted),
                  ),
                ],
              ),
              GoalAddRow(store: _store),
              Expanded(
                child: goals.isEmpty
                    ? _emptyState(theme)
                    : ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context)
                            .copyWith(scrollbars: false),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            spacing: 6,
                            children: [
                              for (final goal in goals)
                                GoalRow(
                                  key: ValueKey('goal-row-${goal.id}'),
                                  store: _store,
                                  goal: goal,
                                  progress: _store.goalProgress(
                                    goal.id,
                                    weekOf: day,
                                    sundayFirst: sundayFirst,
                                  ),
                                  subtasks: subtasks[goal.id] ?? const [],
                                  subtaskMarks: marks,
                                  isOpen: _openGoal == goal.id,
                                  isEditing: _openGoal == goal.id && _editing,
                                  onToggle: () => _toggle(goal.id),
                                  onEdit: () => _edit(goal.id),
                                ),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// One line to add a goal: a name, Hours or Sessions, and the target per
/// week. Return adds it. Leaving the field with a name in it adds it too.
class GoalAddRow extends StatefulWidget {
  const GoalAddRow({super.key, required this.store});

  final AppStore store;

  @override
  State<GoalAddRow> createState() => _GoalAddRowState();
}

class _GoalAddRowState extends State<GoalAddRow> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  GoalKind _kind = GoalKind.hours;
  int _target = GoalRules.defaultTarget;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (!_focus.hasFocus &&
        InlineTitleRules.onBlur(_text.text) == BlurAction.commit) {
      _save();
    }
  }

  /// Adds the goal and clears the field. The target goes back to the
  /// default of the kind for the next one. The kind stays, so several
  /// goals of one kind are quick to add.
  bool _save() {
    final goal = widget.store.addGoal(
      title: _text.text,
      kind: _kind,
      target: _target,
    );
    if (goal == null) return false;
    _text.clear();
    if (mounted) {
      setState(() => _target = GoalRules.defaultTargetFor(_kind));
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        GroveField(
          key: const ValueKey('goal-add'),
          controller: _text,
          focusNode: _focus,
          placeholder: 'Add a goal…',
          boxed: true,
          radius: 10,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          leading: Icon(Icons.add_circle, size: 16, color: theme.accent),
          keepFocus: true,
          onSubmitted: (_) => _save(),
          onEscape: () {
            _text.clear();
            _focus.unfocus();
          },
        ),
        GoalKindPicker(
          kind: _kind,
          onChange: (k) => setState(() {
            _kind = k;
            _target = GoalRules.defaultTargetFor(k);
          }),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: TargetStepper(
            kind: _kind,
            value: _target,
            onChange: (v) => setState(() => _target = v),
          ),
        ),
      ],
    );
  }
}
