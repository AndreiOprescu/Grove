// Port of Sources/Grove/Tasks/TasksPane.swift.
import 'package:flutter/material.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/task.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../theme/grove_theme.dart';
import '../theme/panel.dart';
import 'notice_cards.dart';
import 'quick_add_field.dart';
import 'sliver_column.dart';
import 'task_format.dart';
import 'task_row.dart';
import 'task_section.dart';
import 'task_widgets.dart';

/// `today` is the list of today. `unscheduled` is the list that feeds the
/// planner: the tasks that are late and the ones with no day.
enum TasksPaneMode { today, unscheduled }

/// A task list for the left side of the Today and Planner screens.
class TasksPane extends StatefulWidget {
  const TasksPane({
    super.key,
    required this.store,
    required this.mode,
    this.day,
  });

  final AppStore store;
  final TasksPaneMode mode;

  /// The day of the list in the `today` mode. Null is today. The Today
  /// screen gives tomorrow when it shows tomorrow.
  final DayKey? day;

  @override
  State<TasksPane> createState() => _TasksPaneState();
}

class _TasksPaneState extends State<TasksPane> {
  final _expanded = <String>{};
  bool _showDone = false;

  AppStore get _store => widget.store;

  void _toggle(String id) => setState(() {
    if (!_expanded.remove(id)) _expanded.add(id);
  });

  Widget _header(GroveTheme theme, String side) => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      const Expanded(child: ThemedHeading('Tasks', 20)),
      Text(side, style: theme.body(11).copyWith(color: theme.muted)),
    ],
  );

  /// "Tasks", how many of the day are done, and a bar for it.
  Widget _todayHeader(GroveTheme theme, PlantProgress progress) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    spacing: 6,
    children: [
      _header(
        theme,
        progress.total == 0
            ? 'Nothing planned'
            : '${progress.done} of ${progress.total} done',
      ),
      ProgressBar(fraction: progress.fraction),
    ],
  );

  /// The open tasks of the day, then the ones checked off that day. The
  /// late ones are in the list of the Planner screen. Each part is a sliver,
  /// with a key: a part keeps its rows when a card over it goes away.
  List<Widget> _todayContent(
    Map<String, ListItem> lists,
    DayKey day,
    DayKey today,
  ) {
    final done = [
      for (final t in _store.repos.tasks.forDay(day))
        if (t.isDone && !_store.lingering.contains(t.id)) t,
    ];
    return [
      TaskSection(
        key: const ValueKey('part-day'),
        store: _store,
        title: TaskFormat.dayLabel(day, today: today),
        placement: TaskPlacement.day(day),
        tasks: _store.openTasks(TaskPlacement.day(day)),
        contextDay: day,
        emptyText: 'Nothing planned. Add a task above, or drop one here.',
        lists: lists,
        expanded: _expanded,
        onToggle: _toggle,
      ),
      if (done.isNotEmpty) _doneSection(done, 'Done', day, lists),
    ];
  }

  /// The late tasks, then the tasks with no day. The order comes from the
  /// plan, so these lists take no drops. Rows can still be dragged to the
  /// planner. Below them: the tasks checked off today, so a slip can be
  /// undone.
  List<Widget> _unscheduledContent(
    GroveTheme theme,
    Map<String, ListItem> lists,
    ({List<TaskItem> overdue, List<TaskItem> unscheduled}) waiting,
    DayKey today,
  ) {
    final done = [
      for (final t in _store.repos.tasks.completedOn(today))
        if (t.parentId == null && !_store.lingering.contains(t.id)) t,
    ];
    return [
      if (waiting.overdue.isNotEmpty)
        TaskSection(
          key: const ValueKey('part-overdue'),
          store: _store,
          title: 'Overdue',
          tint: theme.accent2,
          placement: null,
          tasks: waiting.overdue,
          showDate: true,
          lists: lists,
          expanded: _expanded,
          onToggle: _toggle,
        ),
      TaskSection(
        key: const ValueKey('part-unscheduled'),
        store: _store,
        title: 'Unscheduled',
        placement: null,
        tasks: waiting.unscheduled,
        showDate: true,
        emptyText: 'Nothing waiting. Every task has a day.',
        lists: lists,
        expanded: _expanded,
        onToggle: _toggle,
      ),
      if (done.isNotEmpty) _doneSection(done, 'Done today', today, lists),
    ];
  }

  Widget _doneSection(
    List<TaskItem> done,
    String title,
    DayKey day,
    Map<String, ListItem> lists,
  ) {
    final theme = GroveTheme.of(context);
    final label = '$title · ${done.length}';
    void toggle() => setState(() => _showDone = !_showDone);
    return SliverColumn(
      key: const ValueKey('part-done'),
      slivers: [
        SliverToBoxAdapter(
          child: Semantics(
            container: true,
            button: true,
            expanded: _showDone,
            label: label,
            onTap: toggle,
            excludeSemantics: true,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                key: const ValueKey('done-toggle'),
                behavior: HitTestBehavior.opaque,
                onTap: toggle,
                child: Row(
                  spacing: 4,
                  children: [
                    Icon(
                      _showDone
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      size: 13,
                      color: theme.muted,
                    ),
                    Expanded(
                      child: ThemedHeading(
                        label,
                        12,
                        weight: FontWeight.w700,
                        color: theme.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_showDone)
          TaskRows(
            tasks: done,
            rowBuilder: (task) => TaskRow(
              store: _store,
              task: task,
              contextDay: day,
              lists: lists,
              isExpanded: _expanded.contains(task.id),
              toggleExpanded: () => _toggle(task.id),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => StoreBuilder(
    store: _store,
    builder: (context) {
      final theme = GroveTheme.of(context);
      final today = _store.clockToday;
      final lists = {
        for (final l in _store.repos.lists.all(includeArchived: true)) l.id: l,
      };
      final List<Widget> top;
      final List<Widget> content;
      switch (widget.mode) {
        case TasksPaneMode.today:
          final day = widget.day ?? today;
          // The two cards are about the real today: the first steps of a
          // new user, and what was left open yesterday.
          final isToday = day == today;
          final yesterday = isToday ? _store.rollOverItems() : null;
          top = [
            _todayHeader(theme, _store.plantProgress(day)),
            QuickAddField(
              store: _store,
              placement: TaskPlacement.day(day),
              placementLabel: TaskFormat.dayLabel(day, today: today),
            ),
          ];
          content = [
            if (isToday && _store.welcomeVisible)
              SliverToBoxAdapter(
                key: const ValueKey('card-welcome'),
                child: WelcomeCard(store: _store),
              ),
            if (yesterday != null && yesterday.isNotEmpty)
              SliverToBoxAdapter(
                key: const ValueKey('card-yesterday'),
                child: RollOverCard(store: _store, items: yesterday),
              ),
            ..._todayContent(lists, day, today),
          ];
        case TasksPaneMode.unscheduled:
          final waiting = _store.unscheduledTasks(today: today);
          final count = waiting.overdue.length + waiting.unscheduled.length;
          top = [
            _header(theme, count == 0 ? 'Nothing waiting' : '$count waiting'),
            QuickAddField(
              store: _store,
              placement: TaskPlacement.inbox,
              placementLabel: 'Unscheduled',
            ),
          ];
          content = _unscheduledContent(theme, lists, waiting, today);
      }
      return Panel(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              ...top,
              Expanded(
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context)
                      .copyWith(scrollbars: false),
                  // Slivers: a long list builds only the rows in or near
                  // the view (see `TaskRows`).
                  child: CustomScrollView(
                    slivers: [
                      // One group that paints its parts from the first to
                      // the last, as the `Column` before it did.
                      SliverColumn(
                        slivers: [
                          for (final (i, part) in content.indexed)
                            SliverPadding(
                              key: part.key,
                              padding: EdgeInsets.only(top: i == 0 ? 0 : 14),
                              sliver: part,
                            ),
                          const SliverPadding(
                            padding: EdgeInsets.only(bottom: 8),
                          ),
                        ],
                      ),
                    ],
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
