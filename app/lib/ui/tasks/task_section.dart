// Port of Sources/Grove/Tasks/TaskSection.swift.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
///
/// With motion, a row that comes into the list slides in from under the row
/// over it and fades in. A row that goes out of the list does the reverse
/// (PLAN §6.3).
class TaskRows extends StatefulWidget {
  const TaskRows({
    super.key,
    required this.tasks,
    required this.rowBuilder,
    this.motion = false,
  });

  final List<TaskItem> tasks;
  final Widget Function(TaskItem task) rowBuilder;

  /// The Motion setting. The device setting "reduce motion" also stops the
  /// slide.
  final bool motion;

  /// How long a row slides.
  static const moveTime = Duration(milliseconds: 250);

  /// When more rows than this come and go in one step, they do it at once.
  /// A row that slides in starts with no height, so the list would build
  /// all of them.
  static const mostMoving = 12;

  @override
  State<TaskRows> createState() => _TaskRowsState();
}

class _TaskRowsState extends State<TaskRows>
    with SingleTickerProviderStateMixin {
  late final AnimationController _move =
      AnimationController(vsync: this, duration: TaskRows.moveTime)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) _settle();
        });
  late final Animation<double> _in = CurvedAnimation(
    parent: _move,
    curve: Curves.fastOutSlowIn,
  );
  late final Animation<double> _out = ReverseAnimation(_in);

  /// The ids of the rows on their way in.
  Set<String> _coming = const {};

  /// The rows on their way out. The key is the id of the row they stand in
  /// front of; null is the end of the list.
  Map<String?, List<TaskItem>> _going = const {};

  bool _reduceMotion = false;

  bool get _motionOn => widget.motion && !_reduceMotion;

  static String _key(TaskItem task) => 'row-${task.id}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!_motionOn) _stop();
  }

  @override
  void didUpdateWidget(TaskRows oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_motionOn) {
      _stop();
      return;
    }
    final was = {for (final task in oldWidget.tasks) task.id};
    final now = {for (final task in widget.tasks) task.id};
    // The same rows: a new text, or a row that moved in the list.
    if (was.length == now.length && was.containsAll(now)) return;
    // A new step ends the one before it.
    _stop();
    final coming = now.difference(was);
    final gone = was.difference(now);
    if (coming.length + gone.length > TaskRows.mostMoving) return;
    final going = <String?, List<TaskItem>>{};
    var waiting = <TaskItem>[];
    for (final task in oldWidget.tasks) {
      if (gone.contains(task.id)) {
        waiting.add(task);
      } else if (waiting.isNotEmpty) {
        going[task.id] = waiting;
        waiting = [];
      }
    }
    if (waiting.isNotEmpty) going[null] = waiting;
    _coming = coming;
    _going = going;
    _move.forward(from: 0);
  }

  /// All rows are at rest.
  void _stop() {
    _move.stop();
    _coming = const {};
    _going = const {};
  }

  /// The slide is over: the rows that went out are taken away.
  void _settle() {
    if (mounted) setState(_stop);
  }

  @override
  void dispose() {
    _move.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final going = _going;
    final leaving = <String>{};
    var rows = widget.tasks;
    if (going.isNotEmpty) {
      rows = [
        for (final task in widget.tasks) ...[...?going[task.id], task],
        ...?going[null],
      ];
      for (final group in going.values) {
        for (final task in group) {
          leaving.add(task.id);
        }
      }
    }
    final places = {for (final (i, task) in rows.indexed) _key(task): i};
    return SliverList.builder(
      itemCount: rows.length,
      // A row that moves in the list keeps its state: the text in its
      // fields, and the keyboard.
      findChildIndexCallback: (key) =>
          key is ValueKey<String> ? places[key.value] : null,
      itemBuilder: (context, index) {
        final task = rows[index];
        final amount = leaving.contains(task.id)
            ? _out
            : _coming.contains(task.id)
            ? _in
            : kAlwaysCompleteAnimation;
        return RowSlide(
          key: ValueKey(_key(task)),
          amount: amount,
          child: FadeTransition(
            opacity: amount,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: widget.rowBuilder(task),
            ),
          ),
        );
      },
    );
  }
}

/// Shows `amount` of the height of its child, from the lower edge up: the
/// child slides in from under what is over it. At 1 it is the child as it
/// is, with no clip. Under 1 the child takes no click.
class RowSlide extends SingleChildRenderObjectWidget {
  const RowSlide({super.key, required this.amount, required super.child});

  /// From 0, no height, to 1, the whole child.
  final Animation<double> amount;

  @override
  RenderRowSlide createRenderObject(BuildContext context) =>
      RenderRowSlide(amount);

  @override
  void updateRenderObject(BuildContext context, RenderRowSlide renderObject) {
    renderObject.amount = amount;
  }
}

class RenderRowSlide extends RenderShiftedBox {
  RenderRowSlide(this._amount) : super(null);

  Animation<double> _amount;
  Animation<double> get amount => _amount;
  set amount(Animation<double> value) {
    if (identical(value, _amount)) return;
    if (attached) _amount.removeListener(markNeedsLayout);
    _amount = value;
    if (attached) _amount.addListener(markNeedsLayout);
    markNeedsLayout();
  }

  double get _part => _amount.value.clamp(0.0, 1.0);

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _amount.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _amount.removeListener(markNeedsLayout);
    super.detach();
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      super.computeMinIntrinsicHeight(width) * _part;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      super.computeMaxIntrinsicHeight(width) * _part;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final inner = child?.getDryLayout(constraints) ?? Size.zero;
    return constraints.constrain(Size(inner.width, inner.height * _part));
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints, parentUsesSize: true);
    size = constraints.constrain(
      Size(child.size.width, child.size.height * _part),
    );
    (child.parentData! as BoxParentData).offset = Offset(
      0,
      size.height - child.size.height,
    );
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      _part >= 1 && super.hitTest(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || _part >= 1) {
      layer = null;
      super.paint(context, offset);
    } else if (size.isEmpty) {
      layer = null;
    } else {
      layer = context.pushClipRect(
        needsCompositing,
        offset,
        Offset.zero & size,
        super.paint,
        oldLayer: layer as ClipRectLayer?,
      );
    }
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
        // Always there, also with no rows: the last row of the list slides
        // out of it, and the first one slides into it.
        TaskRows(
          tasks: tasks,
          motion: widget.store.motionSetting,
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
        else
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
    );
  }
}
