// Only this app: the panel of one goal block, at the right of the planner
// and of Today (CONTEXT.md, "Goal panel"; ADR 0002).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:grove/core/model/event.dart';
import 'package:grove/core/model/goal.dart';
import 'package:grove/core/planner/planner_math.dart';
import 'package:grove/core/recurrence/recurrence_engine.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../persona/reward_editor.dart';
import '../planner/planner_dialogs.dart';
import '../planner/subtask_lines.dart';
import '../tasks/task_inspector.dart';
import '../tasks/task_widgets.dart';
import '../theme/grove_theme.dart';
import '../theme/named_colors.dart';
import '../theme/panel.dart';
import 'goal_row.dart';

/// The panel of a goal block: the goal, the time of the block, the week of
/// the goal, the subtasks planned in the block and the ones the block can
/// take, the linked note, and "Mark done" and "Delete". The goal itself is
/// read-only here: "Edit goal" opens its editor in the Goals panel. Each
/// change saves at once and is one undo step.
class GoalPanel extends StatefulWidget {
  const GoalPanel({super.key, required this.store, required this.blockId});

  final AppStore store;

  /// The goal block (an event id). A day of a repeating block has an
  /// occurrence id.
  final String blockId;

  /// As wide as the task panel.
  static const width = TaskInspector.width;

  @override
  State<GoalPanel> createState() => _GoalPanelState();
}

class _GoalPanelState extends State<GoalPanel> {
  final _newText = TextEditingController();

  AppStore get _store => widget.store;
  String get _id => widget.blockId;

  @override
  void dispose() {
    _newText.dispose();
    super.dispose();
  }

  void _close() => _store.closeGoalPanel();

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _add() {
    if (_store.addGoalSubtaskToBlock(_id, title: _newText.text) != null) {
      _newText.clear();
    }
  }

  /// The name that the database has for a planned subtask now, or null
  /// when the subtask is gone.
  String? _saved(String subId) => _store
      .goalSubtasks(_goalId)
      .where((s) => s.id == subId)
      .firstOrNull
      ?.title;

  String get _goalId => _store.event(_id)?.goalId ?? '';

  // MARK: Pieces

  Widget _header(GroveTheme theme, GoalItem goal) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 8,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Container(
          key: const ValueKey('goal-panel-colour'),
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: theme.color(GoalRules.blockColor(goal)),
            shape: BoxShape.circle,
          ),
        ),
      ),
      Expanded(
        child: Text(
          goal.title,
          key: const ValueKey('goal-panel-title'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: theme
              .heading(16, weight: FontWeight.w600)
              .copyWith(color: theme.ink),
        ),
      ),
      IconTap(
        key: const ValueKey('goal-panel-edit'),
        icon: Icons.edit_outlined,
        label: 'Edit goal',
        tip: 'Edit the goal in the Goals panel',
        color: theme.muted,
        onTap: () => _store.editGoalFromPanel(goal.id),
      ),
      IconTap(
        key: const ValueKey('goal-panel-close'),
        icon: Icons.close,
        label: 'Close',
        tip: 'Close  (Esc)',
        color: theme.muted,
        onTap: _close,
      ),
    ],
  );

  Widget _time(GroveTheme theme, EventItem block) {
    final start = block.start.minute;
    final end = block.end.day == block.start.day
        ? block.end.minute
        : PlannerMath.dayEnd;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        Text(
          NotesRules.longDay(block.start.day),
          key: const ValueKey('goal-panel-day'),
          style: theme.body(12).copyWith(color: theme.ink),
        ),
        Text(
          '${PlannerMath.label(start: start, end: end)} · '
          '${PlannerMath.duration(end - start)}',
          key: const ValueKey('goal-panel-time'),
          style: theme.number(12).copyWith(color: theme.muted),
        ),
      ],
    );
  }

  Widget _week(GroveTheme theme, GoalItem goal, EventItem block) {
    final progress = _store.goalProgress(goal.id, weekOf: block.start.day);
    return _section(theme, 'This week', [
      Row(
        children: [
          Expanded(
            child: Text(
              GoalRules.plannedText(progress),
              style: theme.body(11).copyWith(color: theme.muted),
            ),
          ),
          Text(
            GoalRules.progressText(progress),
            key: const ValueKey('goal-panel-progress'),
            style: theme
                .number(11, weight: FontWeight.w600)
                .copyWith(color: theme.muted),
          ),
        ],
      ),
      GoalBar(
        parts: GoalRules.bar(progress),
        tint: theme.color(GoalRules.blockColor(goal)),
      ),
    ]);
  }

  Widget _planned(GroveTheme theme, String blockId) {
    final planned = _store.plannedGoalSubtasks(blockId);
    final small = theme.body(12).copyWith(color: theme.muted);
    final field = theme.body(13).copyWith(color: theme.ink);
    return _section(theme, 'In this block', [
      if (planned.isEmpty)
        Text(
          'Nothing planned here yet. Add a subtask, or take one from the '
          'goal below.',
          style: small,
        ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: 2,
        children: [
          for (final sub in planned)
            SubtaskLine(
              key: ValueKey('goal-panel-sub-${sub.id}'),
              nameKey: ValueKey('goal-panel-sub-name-${sub.id}'),
              checkKey: ValueKey('goal-panel-sub-check-${sub.id}'),
              backKey: ValueKey('goal-panel-sub-unplan-${sub.id}'),
              title: sub.title,
              isDone: sub.isDone,
              saved: () => _saved(sub.id),
              onToggle: () => _store.toggleGoalSubtask(sub.id),
              onRename: (name) => _store.renameGoalSubtask(sub.id, to: name),
              onBack: () => _store.unassignGoalSubtask(sub.id),
              backLabel: 'Remove ${sub.title} from the planner',
              backTip: 'Remove from the planner. It stays in the goal.',
            ),
          Row(
            spacing: 8,
            children: [
              SizedBox.square(
                dimension: SubtaskLine.target,
                child: Icon(Icons.add, size: 16, color: theme.muted),
              ),
              Expanded(
                child: GroveField(
                  key: const ValueKey('goal-panel-add'),
                  controller: _newText,
                  placeholder: 'Add a subtask',
                  label: 'Add a subtask to the goal and to this block',
                  style: field,
                  keepFocus: true,
                  onSubmitted: (_) => _add(),
                ),
              ),
            ],
          ),
        ],
      ),
    ]);
  }

  Widget? _free(GroveTheme theme, String blockId) {
    final free = _store.freeGoalSubtasks(blockId);
    if (free.isEmpty) return null;
    return _section(theme, 'Add from goal', [
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: 2,
        children: [
          for (final sub in free)
            FreeSubtaskLine(
              key: ValueKey('goal-panel-free-${sub.id}'),
              sub: sub,
              label: 'Add ${sub.title} to this block',
              onTap: () => _store.assignGoalSubtask(sub.id, to: blockId),
            ),
        ],
      ),
    ]);
  }

  Widget _note(GroveTheme theme, EventItem block) {
    final has = _store.withMeetingNote([block]).isNotEmpty;
    final text = has ? 'Open linked note' : 'Create linked note';
    void open() => _store.createMeetingNote(block);
    return _section(theme, 'Linked note', [
      Semantics(
        container: true,
        button: true,
        label: text,
        onTap: open,
        excludeSemantics: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            key: const ValueKey('goal-panel-note'),
            behavior: HitTestBehavior.opaque,
            onTap: open,
            child: Row(
              spacing: 8,
              children: [
                Icon(
                  has ? Icons.sticky_note_2_outlined : Icons.note_add_outlined,
                  size: 13,
                  color: theme.accent,
                ),
                Expanded(
                  child: Text(
                    text,
                    style: theme.body(12).copyWith(color: theme.ink),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _actions(EventItem block) {
    // A day of a repeating block cannot be ticked yet (as on the grid).
    final repeats = OccurrenceId.parse(_id) != null;
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [
        DialogButton(
          key: const ValueKey('goal-panel-delete'),
          label: 'Delete goal block',
          onTap: () {
            _store.deleteBlocks([_id], name: 'Delete Goal Block');
            if (_store.event(_id) == null) _close();
          },
        ),
        if (!repeats)
          DialogButton(
            key: const ValueKey('goal-panel-done'),
            label: block.doneAt == null ? 'Mark done' : 'Mark not done',
            primary: block.doneAt == null,
            onTap: () => _store.toggleGoalBlockDone(eventId: _id),
          ),
      ],
    );
  }

  Widget _section(GroveTheme theme, String name, List<Widget> children) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          ThemedHeading(name, 12, weight: FontWeight.w700, color: theme.ink),
          ...children,
        ],
      );

  Widget _content(GroveTheme theme, GoalItem goal, EventItem block) =>
      ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: 16,
            children: [
              _header(theme, goal),
              _time(theme, block),
              _week(theme, goal, block),
              RewardEditor.goal(
                store: _store,
                ownerId: goal.id,
                blockMinutes: block.durationMinutes,
              ),
              _planned(theme, _id),
              ?_free(theme, _id),
              _note(theme, block),
              _actions(block),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => StoreBuilder(
    store: _store,
    builder: (context) {
      final theme = GroveTheme.of(context);
      final block = _store.event(_id);
      final goalId = block?.goalId;
      final goal = goalId == null ? null : _store.goal(goalId);
      return Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _key,
        child: Panel(
          key: const ValueKey('goal-panel'),
          child: block == null || goal == null
              ? Center(
                  child: Text(
                    'This goal block is gone.',
                    style: theme.body(13).copyWith(color: theme.muted),
                  ),
                )
              : _content(theme, goal, block),
        ),
      );
    },
  );
}
