// Port of Sources/Grove/Planner/PlannerView.swift: the time grid with its
// header. `PlannerKind.week` is the Planner screen. `PlannerKind.today` is
// the timeline of one day: a small header and no day names.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/event.dart';
import 'package:grove/core/planner/planner_math.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../shell/shell_layout.dart';
import '../theme/grove_theme.dart';
import '../theme/named_colors.dart';
import '../theme/panel.dart';
import '../theme/symbols.dart';
import 'planner_clock.dart';
import 'planner_dialogs.dart';
import 'planner_geometry.dart';
import 'planner_grid.dart';
import 'planner_kind.dart';
import 'sticky_strip.dart';
import 'workload.dart';

class PlannerView extends StatefulWidget {
  const PlannerView({super.key, required this.store, required this.kind})
    : assert(kind != PlannerKind.month, 'The month has its own screen.');

  final AppStore store;
  final PlannerKind kind;

  @override
  State<PlannerView> createState() => _PlannerViewState();
}

class _PlannerViewState extends State<PlannerView> {
  bool _dropToStrip = false;
  int _scrollRequest = 0;
  int _todaySeen = 0;

  /// One window at a time: the plan, the warning or the question.
  bool _windowOpen = false;

  AppStore get _store => widget.store;
  PlannerKind get _kind => widget.kind;

  int get _workStart => _store.prefs.getInt('planner.workStart') ?? 9 * 60;
  int get _workEnd => _store.prefs.getInt('planner.workEnd') ?? 18 * 60;

  @override
  void initState() {
    super.initState();
    _todaySeen = _store.todayRequest;
    _store.addListener(_storeChanged);
    // The palette may ask for "Plan my day" while this screen is not shown.
    // The request waits for it here.
    WidgetsBinding.instance.addPostFrameCallback((_) => _openWindows());
  }

  @override
  void didUpdateWidget(PlannerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_storeChanged);
      widget.store.addListener(_storeChanged);
      _todaySeen = widget.store.todayRequest;
    }
  }

  @override
  void dispose() {
    _store.removeListener(_storeChanged);
    super.dispose();
  }

  void _storeChanged() {
    if (!mounted) return;
    if (_store.todayRequest != _todaySeen) {
      _todaySeen = _store.todayRequest;
      _scrollRequest += 1;
    }
    // A change can come in the middle of a frame. The work waits for its end.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _storeChanged());
      return;
    }
    setState(() {});
    _openWindows();
  }

  /// Shows what the store asks for: the plan, the warning or the question.
  void _openWindows() {
    if (!mounted || _windowOpen) return;
    final prompt = _store.recurringPrompt;
    final warning = _store.overloadWarning;
    if (prompt != null) {
      unawaited(_askScope(prompt));
    } else if (warning != null) {
      unawaited(_warn(warning));
    } else if (_store.planMyDayHandled != _store.planMyDayRequest) {
      _store.planMyDayHandled = _store.planMyDayRequest;
      unawaited(_showPlan());
    }
  }

  Future<void> _askScope(RecurringPrompt prompt) async {
    _windowOpen = true;
    final scope = await showRecurringQuestion(context, prompt.verb);
    _windowOpen = false;
    if (scope != null) {
      _store.answerRecurring(scope, prompt: prompt);
    } else if (_store.recurringPrompt?.id == prompt.id) {
      _store.cancelRecurring();
    }
    _openWindows();
  }

  Future<void> _warn(String message) async {
    _windowOpen = true;
    await showBusyDay(context, message);
    _windowOpen = false;
    _store.overloadWarning = null;
    _openWindows();
  }

  Future<void> _showPlan() async {
    final day = _store.selectedDay;
    final plan = _store.planMyDayPreview(
      day: day,
      workStart: _workStart,
      workEnd: _workEnd,
      step: PlannerMath.step,
    );
    if (plan.isEmpty) {
      _store.showToast(
        'Nothing to plan. No unscheduled task fits in working hours.',
      );
      return;
    }
    _windowOpen = true;
    final apply = await showPlanSheet(context, plan);
    _windowOpen = false;
    if (apply) _store.applyPlan(plan, day: day);
    _openWindows();
  }

  // Days

  /// A narrow screen shows one day column in place of the week.
  bool _oneDay(BuildContext context) =>
      _kind == PlannerKind.week &&
      ShellRules.layoutFor(MediaQuery.sizeOf(context).width) ==
          ShellLayout.phone;

  List<DayKey> _days(BuildContext context) => _oneDay(context)
      ? [_store.selectedDay]
      : _kind.days(
          selected: _store.selectedDay,
          today: _store.plannerToday,
          sundayFirst: _store.weekStartsSunday,
        );

  void _move(BuildContext context, int direction) {
    _store.selectedDay = _oneDay(context)
        ? _store.selectedDay.adding(days: direction)
        : _kind.moved(_store.selectedDay, by: direction);
  }

  void _goToday() {
    _store.selectedDay = _store.plannerToday;
    setState(() => _scrollRequest += 1);
  }

  String _title(BuildContext context, List<DayKey> days) {
    if (_kind == PlannerKind.today) return 'Timeline';
    if (days.length == 1) return NotesRules.longDay(days.first);
    return '${NotesRules.shortDate(days.first)} – '
        '${NotesRules.shortDate(days.last)} ${days.last.year}';
  }

  // Build

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final days = _days(context);
    final phone =
        ShellRules.layoutFor(MediaQuery.sizeOf(context).width) ==
        ShellLayout.phone;
    final pad = phone ? 12.0 : 16.0;
    final events = _store.allDayEvents(DayRange(days.first, days.last));
    final corners = BorderRadius.circular(theme.radius);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        if (_kind == PlannerKind.today)
          _columnHeader(context, theme)
        else
          _header(context, theme, days),
        if (events.isNotEmpty) _allDayStrip(theme, events),
        Expanded(
          child: Panel(
            child: ClipRRect(
              borderRadius: corners,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_kind == PlannerKind.week) _dayHeaders(theme, days),
                  StickyStrip(
                    store: _store,
                    days: days,
                    isDropTarget: _dropToStrip,
                    workStart: _workStart,
                    workEnd: _workEnd,
                  ),
                  Expanded(
                    child: PlannerGrid(
                      store: _store,
                      days: days,
                      hourHeight: _store.plannerHourHeight,
                      workStart: _workStart,
                      workEnd: _workEnd,
                      scrollRequest: _scrollRequest,
                      onStripTarget: (value) {
                        if (value != _dropToStrip) {
                          setState(() => _dropToStrip = value);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
    if (_kind == PlannerKind.today) return content;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 6, pad, pad),
      child: content,
    );
  }

  // Header

  ({int planned, int free, int done, int total}) get _totals {
    final day = _store.selectedDay;
    return _store.dayTotals(
      day,
      blocks: _store.blocks(DayRange.single(day)),
      workStart: _workStart,
      workEnd: _workEnd,
    );
  }

  Widget _stats() {
    final t = _totals;
    return WorkloadBar(
      planned: t.planned,
      limit: _store.dailyLimitMinutes,
      detail:
          '${PlannerMath.duration(t.planned)} planned · '
          '${PlannerMath.duration(t.free)} free in working hours · '
          '${t.done}/${t.total} done',
    );
  }

  /// One row when there is room. Two or three rows when there is not.
  Widget _header(BuildContext context, GroveTheme theme, List<DayKey> days) {
    final day = _store.selectedDay;
    final nav = <Widget>[
      _HeaderButton(
        label: 'Previous',
        tooltip: 'Previous',
        icon: Icons.chevron_left,
        onTap: () => _move(context, -1),
      ),
      _HeaderButton(
        key: const ValueKey('planner-today'),
        label: 'Today',
        text: 'Today',
        onTap: _goToday,
      ),
      _HeaderButton(
        label: 'Next',
        tooltip: 'Next',
        icon: Icons.chevron_right,
        onTap: () => _move(context, 1),
      ),
      _HeaderButton(
        label: 'Note for the day',
        tooltip: day == _store.plannerToday
            ? "Today's note"
            : 'Note for ${NotesRules.weekdayName(day)} '
                  '${NotesRules.shortDate(day)}',
        icon: symbolIcon('note.text'),
        onTap: () => _store.openDailyNote(day),
      ),
    ];
    final title = ThemedHeading(_title(context, days), 22);
    return LayoutBuilder(
      builder: (context, box) {
        final stats = SizedBox(width: 220, child: _stats());
        if (box.maxWidth >= 640) {
          return Row(
            spacing: 10,
            children: [
              ...nav,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [title, stats],
                ),
              ),
              _planButton(compact: false),
              ..._zoomButtons(),
            ],
          );
        }
        final first = Row(
          spacing: 10,
          children: [
            ...nav,
            Expanded(child: title),
          ],
        );
        if (box.maxWidth >= 430) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              first,
              Row(
                spacing: 10,
                children: [
                  stats,
                  const Spacer(),
                  _planButton(compact: false),
                  ..._zoomButtons(),
                ],
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            first,
            Row(
              spacing: 10,
              children: [
                Expanded(child: _stats()),
                _planButton(compact: true),
                ..._zoomButtons(),
              ],
            ),
          ],
        );
      },
    );
  }

  /// The small header of the one-day timeline: a title, the day's numbers,
  /// "Plan my day" and the zoom.
  Widget _columnHeader(BuildContext context, GroveTheme theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    spacing: 4,
    children: [
      Row(
        spacing: 8,
        children: [
          const Expanded(child: ThemedHeading('Timeline', 20)),
          _planButton(compact: true, small: true),
          ..._zoomButtons(small: true),
        ],
      ),
      _stats(),
    ],
  );

  Widget _planButton({required bool compact, bool small = false}) => compact
      ? _HeaderButton(
          key: const ValueKey('plan-my-day'),
          label: 'Plan my day',
          tooltip:
              "Plan my day: fit today's unscheduled tasks into free "
              'working hours',
          icon: symbolIcon('wand.and.stars'),
          small: small,
          onTap: _showPlan,
        )
      : _HeaderButton(
          key: const ValueKey('plan-my-day'),
          label: 'Plan my day',
          tooltip: "Fit today's unscheduled tasks into free working hours",
          text: 'Plan my day',
          onTap: _showPlan,
        );

  List<Widget> _zoomButtons({bool small = false}) => [
    _HeaderButton(
      label: 'Zoom out',
      tooltip: 'Zoom out',
      icon: Icons.zoom_out,
      small: small,
      onTap: () => _store.zoomPlanner(1 / 1.2),
    ),
    _HeaderButton(
      label: 'Zoom in',
      tooltip: 'Zoom in',
      icon: Icons.zoom_in,
      small: small,
      onTap: () => _store.zoomPlanner(1.2),
    ),
  ];

  Widget _dayHeaders(GroveTheme theme, List<DayKey> days) {
    final today = _store.plannerToday;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.line)),
      ),
      child: Row(
        children: [
          const SizedBox(width: PlannerGeometry.gutterWidth),
          for (final day in days)
            Expanded(
              child: Semantics(
                container: true,
                excludeSemantics: true,
                button: true,
                label: NotesRules.longDay(day),
                onTap: () => _store.selectedDay = day,
                child: GestureDetector(
                  key: ValueKey('day-header-${day.string}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _store.selectedDay = day,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          NotesRules.weekdayName(day).substring(0, 3),
                          maxLines: 1,
                          style: theme
                              .body(11)
                              .copyWith(
                                color: day == today ? theme.accent : theme.ink,
                              ),
                        ),
                        Text(
                          '${day.day}',
                          maxLines: 1,
                          style: theme
                              .body(15, weight: FontWeight.w700)
                              .copyWith(
                                color: day == today ? theme.accent : theme.ink,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _allDayStrip(GroveTheme theme, List<EventItem> events) =>
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          spacing: 6,
          children: [
            Text('All day', style: theme.body(11).copyWith(color: theme.muted)),
            for (final e in events)
              GestureDetector(
                key: ValueKey('all-day-${e.id}'),
                onTap: () => _store.editEvent(e),
                child: ThemedChip(
                  tint: theme.color(e.color),
                  fill: 0.2,
                  child: Text(
                    e.title,
                    maxLines: 1,
                    style: theme
                        .body(11, weight: FontWeight.w600)
                        .copyWith(color: theme.ink),
                  ),
                ),
              ),
          ],
        ),
      );
}

/// A bordered button of the planner header: a picture or a word.
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    super.key,
    required this.label,
    required this.onTap,
    this.tooltip,
    this.icon,
    this.text,
    this.small = false,
  }) : assert(icon != null || text != null, 'A picture or a word.');

  /// The name a screen reader says.
  final String label;
  final VoidCallback onTap;
  final String? tooltip;
  final IconData? icon;
  final String? text;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final icon = this.icon;
    final height = small ? 24.0 : 28.0;
    Widget button = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.surface2,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: theme.line),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: height, minHeight: height),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: icon == null ? 10 : 5),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: icon != null
                    ? Icon(icon, size: small ? 14 : 16, color: theme.ink)
                    : Text(
                        text!,
                        maxLines: 1,
                        style: theme.body(13).copyWith(color: theme.ink),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
    final tooltip = this.tooltip;
    if (tooltip != null) {
      button = Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: button,
      );
    }
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: label,
      tooltip: tooltip,
      onTap: onTap,
      child: button,
    );
  }
}
