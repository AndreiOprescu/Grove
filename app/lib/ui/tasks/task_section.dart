// Port of Sources/Grove/Tasks/TaskSection.swift.
import 'package:flutter/material.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/task.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../theme/grove_theme.dart';
import '../theme/panel.dart';
import 'sliver_column.dart';
import 'task_row.dart';

/// The rows of one list, each with 6 points over it. A sliver: only the
/// rows in or near the view are built, so a list of 1 000 tasks costs as
/// little as a list of 20.
class TaskRows extends StatelessWidget {
  const TaskRows({super.key, required this.tasks, required this.rowBuilder});

  final List<TaskItem> tasks;
  final Widget Function(TaskItem task) rowBuilder;

  static String _key(TaskItem task) => 'row-${task.id}';

  @override
  Widget build(BuildContext context) {
    final places = {for (final (i, task) in tasks.indexed) _key(task): i};
    return SliverList.builder(
      itemCount: tasks.length,
      // A row that moves in the list keeps its state: the text in its
      // fields, and the keyboard.
      findChildIndexCallback: (key) =>
          key is ValueKey<String> ? places[key.value] : null,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return Padding(
          key: ValueKey(_key(task)),
          padding: const EdgeInsets.only(top: 6),
          child: rowBuilder(task),
        );
      },
    );
  }
}

/// A titled group of task rows. Drop a task on the header, the empty area
/// or the end of the list to put it last.
///
/// A sliver, for a `CustomScrollView`: the rows are built only when they
/// are in or near the view ([TaskRows]).
class TaskSection extends StatefulWidget {
  const TaskSection({
    super.key,
    required this.store,
    required this.title,
    this.tint,
    required this.placement,
    required this.tasks,
    this.contextDay,
    this.showDate = false,
    this.emptyText = 'Nothing here.',
    required this.lists,
    required this.expanded,
    required this.onToggle,
  });

  final AppStore store;
  final String title;
  final Color? tint;

  /// Where dropped tasks go. null means this list takes no drops (for
  /// example, the late tasks).
  final TaskPlacement? placement;
  final List<TaskItem> tasks;

  /// The day this list stands for. null means each row uses its own day.
  final DayKey? contextDay;
  final bool showDate;
  final String emptyText;
  final Map<String, ListItem> lists;

  /// The ids of the rows that show their subtasks.
  final Set<String> expanded;
  final ValueChanged<String> onToggle;

  @override
  State<TaskSection> createState() => _TaskSectionState();
}

class _TaskSectionState extends State<TaskSection> {
  bool _targeted = false;

  /// Puts task `id` in this list, in front of `before` or last.
  void _drop(String id, {String? before}) {
    final placement = widget.placement;
    if (placement == null || id == before) return;
    widget.store.moveTask(id, to: placement, before: before);
  }

  /// An area that takes a dropped task and puts it last.
  Widget _zone(Widget child) => DragTarget<String>(
    onWillAcceptWithDetails: (details) {
      final ok =
          widget.placement != null &&
          details.data.startsWith(DragPayload.taskPrefix);
      if (ok) setState(() => _targeted = true);
      return ok;
    },
    onLeave: (_) => setState(() => _targeted = false),
    onAcceptWithDetails: (details) {
      setState(() => _targeted = false);
      _drop(details.data.substring(DragPayload.taskPrefix.length));
    },
    builder: (context, _, _) => child,
  );

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final tasks = widget.tasks;
    return SliverColumn(
      key: ValueKey('section-${widget.title}'),
      slivers: [
        SliverToBoxAdapter(
          child: _zone(
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 18),
              child: Row(
                spacing: 6,
                children: [
                  Flexible(
                    child: ThemedHeading(
                      widget.title,
                      12,
                      weight: FontWeight.w700,
                      color: widget.tint,
                    ),
                  ),
                  if (tasks.isNotEmpty)
                    Text(
                      '${tasks.length}',
                      style: theme
                          .body(10, weight: FontWeight.w600)
                          .copyWith(color: theme.muted),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (tasks.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.only(top: 6),
            sliver: SliverToBoxAdapter(
              child: _zone(
                DashedBorder(
                  color: _targeted ? theme.accent : theme.line,
                  radius: 10,
                  dash: 4,
                  gap: 3,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 34),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Text(
                          widget.emptyText,
                          textAlign: TextAlign.center,
                          style: theme.body(11).copyWith(color: theme.muted),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          )
        else ...[
          TaskRows(
            tasks: tasks,
            rowBuilder: (task) => TaskRow(
              store: widget.store,
              task: task,
              contextDay: widget.contextDay ?? task.planDate,
              showDate: widget.showDate,
              lists: widget.lists,
              isExpanded: widget.expanded.contains(task.id),
              toggleExpanded: () => widget.onToggle(task.id),
              onDrop: widget.placement == null
                  ? null
                  : (id) => _drop(id, before: task.id),
            ),
          ),
          // The end of the list: a thin strip that takes drops.
          SliverPadding(
            padding: const EdgeInsets.only(top: 6),
            sliver: SliverToBoxAdapter(
              child: _zone(
                SizedBox(
                  height: 10,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: _targeted
                        ? SizedBox(
                            height: 3,
                            child: DecoratedBox(
                              decoration: ShapeDecoration(
                                color: theme.accent,
                                shape: const StadiumBorder(),
                              ),
                              child: const SizedBox.expand(),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
