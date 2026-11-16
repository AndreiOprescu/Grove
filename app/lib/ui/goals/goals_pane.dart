// Port of Sources/Grove/Goals/GoalsPane.swift.
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../goal_map/project_form.dart';
import '../shell/shell_layout.dart';
import '../tasks/task_widgets.dart';
import '../theme/grove_theme.dart';
import '../theme/panel.dart';
import 'goal_row.dart';
import 'project_row.dart';

/// The Goals panel: projects in the top half, habits in the bottom half. Each
/// half has its own "+" and scrolls on its own. A habit is recurring work with a
/// weekly target of hours or sessions, and no date. Drag a habit into a day to
/// plan a block of it. Every block in the week is planned time; a block ticked
/// done in the planner is done time. A habit is never done: it stays every
/// week. A project lists its squares ([ProjectRow]). The
/// numbers are for the week that holds the selected day, the week the
/// Planner shows. A goal has subtasks under it; every block of the goal has
/// that one list. One goal at a time can be open: it shows all its
/// subtasks, and its editor when asked. The one open goal is kept here, for
/// both halves.
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

  /// The "+" of the Projects half: the form of a project, then its map.
  Future<void> _newProject() async {
    final phone =
        ShellRules.layoutFor(MediaQuery.sizeOf(context).width) ==
        ShellLayout.phone;
    final goal = await showNewGoalForm(
      context,
      _store,
      project: true,
      lockType: true,
    );
    if (goal == null) return;
    if (phone) _store.leftPane = null;
    _store.openGoalMap(goal.id);
  }

  /// The "+" of the Habits half: the form of a habit. The new habit is the
  /// open goal. It has no subtasks, so its add line takes the keys, and that
  /// brings it into view at the end of the list.
  Future<void> _newHabit() async {
    final goal = await showNewGoalForm(
      context,
      _store,
      project: false,
      lockType: true,
    );
    if (goal == null || !mounted) return;
    setState(() {
      _openGoal = goal.id;
      _editing = false;
    });
  }

  @override
  Widget build(BuildContext context) => StoreBuilder(
    store: _store,
    builder: (context) {
      final theme = GroveTheme.of(context);
      final day = _store.selectedDay;
      final sundayFirst = _store.weekStartsSunday;
      final week = GoalRules.week(day, sundayFirst: sundayFirst);
      final goals = _store.goals();
      final projects = [
        for (final g in goals)
          if (g.isProject) g,
      ];
      final habits = [
        for (final g in goals)
          if (!g.isProject) g,
      ];
      final subtasks = _store.goalSubtasksOf([for (final g in habits) g.id]);
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
              Expanded(
                child: _GoalSection(
                  key: const ValueKey('goal-section-projects'),
                  title: 'Projects',
                  count: projects.length,
                  addKey: const ValueKey('goal-new-project'),
                  addLabel: 'New project',
                  onAdd: _newProject,
                  emptyText: 'No projects yet',
                  children: [
                    for (final goal in projects)
                      ProjectRow(
                        key: ValueKey('goal-row-${goal.id}'),
                        store: _store,
                        goal: goal,
                      ),
                  ],
                ),
              ),
              Expanded(
                child: _GoalSection(
                  key: const ValueKey('goal-section-habits'),
                  title: 'Habits',
                  count: habits.length,
                  addKey: const ValueKey('goal-new-habit'),
                  addLabel: 'New habit',
                  onAdd: _newHabit,
                  emptyText: 'No habits yet',
                  children: [
                    for (final goal in habits)
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
            ],
          ),
        ),
      );
    },
  );
}

/// One half of the Goals panel: a header with the count and a "+", and its
/// own scroll of rows. With no rows it says so.
class _GoalSection extends StatelessWidget {
  const _GoalSection({
    super.key,
    required this.title,
    required this.count,
    required this.addKey,
    required this.addLabel,
    required this.onAdd,
    required this.emptyText,
    required this.children,
  });

  final String title;
  final int count;
  final Key addKey;
  final String addLabel;
  final VoidCallback onAdd;
  final String emptyText;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                spacing: 6,
                children: [
                  Flexible(
                    child: ThemedHeading(title, 12, weight: FontWeight.w700),
                  ),
                  if (count > 0)
                    Text(
                      '$count',
                      style: theme
                          .body(10, weight: FontWeight.w600)
                          .copyWith(color: theme.muted),
                    ),
                ],
              ),
            ),
            IconTap(
              key: addKey,
              icon: Icons.add,
              label: addLabel,
              color: theme.accent,
              size: 16,
              minSide: 28,
              onTap: onAdd,
            ),
          ],
        ),
        Expanded(
          child: children.isEmpty
              ? Align(
                  alignment: Alignment.topCenter,
                  child: DashedBorder(
                    color: theme.line,
                    radius: 10,
                    dash: 4,
                    gap: 3,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: 34,
                        minWidth: double.infinity,
                      ),
                      // On the left: a centred text can fall between two
                      // pixels and look blurred.
                      child: Align(
                        alignment: Alignment.centerLeft,
                        heightFactor: 1,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          child: Text(
                            emptyText,
                            style: theme.body(11).copyWith(color: theme.muted),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context)
                      .copyWith(scrollbars: false),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      spacing: 6,
                      children: children,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
