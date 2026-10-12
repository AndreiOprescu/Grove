// Port of Sources/Grove/Layouts/DaySpreadView.swift: the home screen
// (PLAN §8, layout B). A header with the date, then three columns: the
// tasks, the timeline of the day, the note of the day. The panel of the
// chosen task takes the place of the note. The timeline is the main column:
// it takes the width the other two leave. A switch in the header shows
// tomorrow in place of today, to plan the next day.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../notes/note_editor_pane.dart';
import '../planner/planner_kind.dart';
import '../planner/planner_view.dart';
import '../shell/shell_layout.dart';
import '../tasks/store_panes.dart';
import '../tasks/task_inspector.dart';
import '../tasks/task_widgets.dart';
import '../tasks/tasks_pane.dart';
import '../theme/grove_theme.dart';
import '../theme/growing_plant.dart';
import '../theme/panel.dart';
import '../theme/symbols.dart';
import 'spread_rules.dart';

class DaySpreadView extends StatefulWidget {
  const DaySpreadView({super.key, required this.store});

  final AppStore store;

  @override
  State<DaySpreadView> createState() => _DaySpreadViewState();
}

class _DaySpreadViewState extends State<DaySpreadView> {
  /// The width while the edge is dragged. Saved when the drag ends.
  double? _live;

  /// Where the pointer asks the edge to be, before the limits.
  double? _dragStart;

  /// Keeps the timeline, with its scroll place, when the columns change.
  final _timeline = GlobalKey();

  /// Looks at the clock: at midnight the day of the screen is a new one.
  Timer? _clock;
  late DayKey _clockDay;

  AppStore get _store => widget.store;

  double get _saved =>
      _store.prefs.getDouble(SpreadRules.tasksWidthKey) ??
      SpreadRules.tasksDefault;

  double get _tasksWidth => SpreadRules.clampTasks(_live ?? _saved);

  @override
  void initState() {
    super.initState();
    _clockDay = _store.clockToday;
    _keepDay();
    // No store change tells that midnight passed. The screen is drawn again
    // only when the day is a new one, so this asks for no frame on any
    // other beat.
    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted || _clockDay == _store.clockToday) return;
      setState(() => _clockDay = _store.clockToday);
      _keepDay();
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  /// This screen has its own day: today, or tomorrow after the switch of
  /// the header (`AppStore.todayScreenDay`). The day another screen chose
  /// does not come here.
  void _keepDay() {
    final store = _store;
    if (store.selectedDay == store.todayScreenDay) return;
    writeLater(store, () {
      if (store.screen == Screen.today &&
          store.selectedDay != store.todayScreenDay) {
        store.selectedDay = store.todayScreenDay;
      }
    });
  }

  @override
  Widget build(BuildContext context) => StoreBuilder(
    store: _store,
    onChange: _keepDay,
    builder: (context) {
      final day = _store.todayScreenDay;
      final phone =
          ShellRules.layoutFor(MediaQuery.sizeOf(context).width) ==
          ShellLayout.phone;
      final timeline = KeyedSubtree(
        key: _timeline,
        child: PlannerView(store: _store, kind: PlannerKind.today, day: day),
      );
      if (phone) {
        // A phone shows one day column. The tasks are in the left panel,
        // the note is on the Notes screen.
        return InspectorHost(
          store: _store,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              // 4 and not 10: the touch area of the switch has empty space
              // under the control
              spacing: 4,
              children: [
                SpreadHeader(store: _store, compact: true),
                Expanded(child: timeline),
              ],
            ),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          SpreadRules.side,
          6,
          SpreadRules.side,
          16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            SpreadHeader(store: _store),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => _columns(
                  box.maxWidth + 2 * SpreadRules.side,
                  timeline,
                  day,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _columns(double width, Widget timeline, DayKey day) {
    final taskId = _store.selectedTaskId;
    final inspector = taskId == null
        ? null
        : TaskInspector(store: _store, taskId: taskId);
    // An open left panel stands in the place of the task list.
    final paneOpen = _store.leftPane != null;
    final double tasks;
    final double note;
    if (paneOpen) {
      tasks = 0;
      note = SpreadRules.columnsBesidePane(width: width).note;
    } else {
      final c = SpreadRules.columns(width: width, tasks: _tasksWidth);
      tasks = c.tasks;
      note = c.note;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!paneOpen) ...[
          SizedBox(
            key: const ValueKey('spread-tasks'),
            width: tasks,
            child: TasksPane(
              store: _store,
              mode: TasksPaneMode.today,
              day: day,
            ),
          ),
          _handle(),
        ],
        Expanded(
          key: const ValueKey('spread-timeline'),
          // With no room for a third column, the panel of the chosen task
          // covers the timeline. The timeline stays in the tree.
          child: note > 0
              ? timeline
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Offstage(
                      offstage: inspector != null,
                      child: TickerMode(
                        enabled: inspector == null,
                        child: timeline,
                      ),
                    ),
                    ?inspector,
                  ],
                ),
        ),
        if (note > 0) ...[
          const SizedBox(width: SpreadRules.gap),
          SizedBox(
            key: const ValueKey('spread-note'),
            width: note,
            child:
                inspector ??
                DayNoteColumn(
                  // A new column when "tomorrow" turns into "today" at
                  // midnight: the note of today is made then.
                  key: ValueKey(
                    day == _store.clockToday ? 'note-today' : 'note-next',
                  ),
                  store: _store,
                  day: day,
                ),
          ),
        ],
      ],
    );
  }

  /// A thin strip between the tasks and the timeline. Drag it right to make
  /// the task list wider.
  Widget _handle() => Tooltip(
    message: 'Drag to change the width of the task list',
    excludeFromSemantics: true,
    child: Semantics(
      label: 'Task list width',
      value: '${_tasksWidth.round()}',
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          key: const ValueKey('spread-handle'),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => _dragStart = _tasksWidth,
          onHorizontalDragUpdate: (d) => setState(() {
            // The whole way of the pointer counts, so small steps add up.
            _dragStart = (_dragStart ?? _tasksWidth) + d.delta.dx;
            _live = SpreadRules.clampTasks(_dragStart!).roundToDouble();
          }),
          onHorizontalDragEnd: (_) => _endDrag(),
          onHorizontalDragCancel: _endDrag,
          child: const SizedBox(width: SpreadRules.gap),
        ),
      ),
    ),
  );

  void _endDrag() {
    final live = _live;
    if (live != null) _store.prefs.set(SpreadRules.tasksWidthKey, live);
    setState(() {
      _live = null;
      _dragStart = null;
    });
  }
}

/// The big date, the greeting, the growth of the day, the plant, and the
/// switch between today and tomorrow. The tomorrow view has no greeting, no
/// growth and no plant: those are about the real today.
class SpreadHeader extends StatelessWidget {
  const SpreadHeader({super.key, required this.store, this.compact = false});

  final AppStore store;

  /// A phone: smaller letters, and the switch on its own row.
  final bool compact;

  /// The gap between the parts of the row.
  static const _gap = 16.0;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final day = store.todayScreenDay;
    final isToday = !store.showsTomorrow;
    final progress = store.plantProgress(day);
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        ThemedHeading(
          NotesRules.longDay(day),
          compact ? 22 : 28,
          key: const ValueKey('spread-date'),
        ),
        Text(
          isToday
              ? SpreadRules.subtitle(
                  isToday: true,
                  greeting: Greeting.text(hour: store.nowMinute() ~/ 60),
                  progress: progress,
                )
              : SpreadRules.tomorrowSubtitle(progress),
          key: const ValueKey('spread-subtitle'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.body(12).copyWith(color: theme.muted),
        ),
      ],
    );
    // The plant grows with the tasks done today. Tomorrow has an empty
    // place of the same size, so the switch does not move.
    final plant = SizedBox(
      width: SpreadRules.plantSlot,
      height: 44,
      child: isToday
          ? Align(
              alignment: Alignment.centerRight,
              child: GrowingPlant(
                progress: progress,
                motion: store.motionSetting,
                height: 44,
              ),
            )
          : null,
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: 2,
        children: [
          Row(
            spacing: _gap,
            children: [
              Expanded(child: words),
              plant,
            ],
          ),
          SizedBox(
            height: SpreadRules.daySwitchTouch,
            child: _DaySwitch(store: store),
          ),
        ],
      );
    }
    // The switch is over its place in the row and as high as the row: it
    // then sits on a whole point, whatever the height of the letters is.
    return Stack(
      children: [
        Row(
          spacing: _gap,
          children: [
            Expanded(child: words),
            const SizedBox(
              width: SpreadRules.daySwitchWidth,
              height: SpreadRules.daySwitchTouch,
            ),
            plant,
          ],
        ),
        Positioned(
          top: 0,
          bottom: 0,
          right: SpreadRules.plantSlot + _gap,
          width: SpreadRules.daySwitchWidth,
          child: _DaySwitch(store: store),
        ),
      ],
    );
  }
}

/// "Today / Tomorrow": which day the screen shows. The control is small. The
/// box around it takes a touch too, so a finger has the room of a dock
/// button: a tap over or under a word picks that word.
class _DaySwitch extends StatelessWidget {
  const _DaySwitch({required this.store});

  final AppStore store;

  void _pick(bool tomorrow) {
    if (tomorrow != store.showsTomorrow) store.showsTomorrow = tomorrow;
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: const ValueKey('spread-day-touch'),
    behavior: HitTestBehavior.opaque,
    // The two buttons inside are what a screen reader gets.
    excludeFromSemantics: true,
    onTapUp: (tap) => _pick(tap.localPosition.dx >= context.size!.width / 2),
    child: WholeCenter(
      child: Segments<bool>(
        key: const ValueKey('spread-day-switch'),
        value: store.showsTomorrow,
        values: const [false, true],
        name: (tomorrow) => tomorrow ? 'Tomorrow' : 'Today',
        tip: (tomorrow) => tomorrow ? 'Plan tomorrow' : 'Back to today',
        label: 'Day shown',
        onPick: _pick,
      ),
    ),
  );
}

/// The note of a day, in the third column. A day with no note yet shows a
/// button to start one. The note of today is made when the column opens,
/// because the page is about today.
class DayNoteColumn extends StatefulWidget {
  const DayNoteColumn({super.key, required this.store, required this.day});

  final AppStore store;
  final DayKey day;

  @override
  State<DayNoteColumn> createState() => _DayNoteColumnState();
}

class _DayNoteColumnState extends State<DayNoteColumn> {
  @override
  void initState() {
    super.initState();
    _makeToday();
  }

  @override
  void didUpdateWidget(DayNoteColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.day != widget.day) _makeToday();
  }

  void _makeToday() {
    final store = widget.store;
    final day = widget.day;
    if (day != store.clockToday || store.existingDailyNote(day) != null) {
      return;
    }
    writeLater(store, () => store.dailyNote(day));
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final theme = GroveTheme.of(context);
    final note = store.existingDailyNote(widget.day);
    if (note != null) {
      return NoteEditorPane(
        key: ValueKey('spread-note-${note.id}'),
        store: store,
        noteId: note.id,
        compact: true,
      );
    }
    return Panel(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 10,
        children: [
          WholeCenter(
            child: Icon(symbolIcon('leaf'), size: 22, color: theme.accent),
          ),
          WholeCenter(
            child: Text(
              'No note for this day yet.',
              style: theme.body(13).copyWith(color: theme.muted),
            ),
          ),
          WholeCenter(
            child: CardButton(
              key: const ValueKey('spread-start-note'),
              label: 'Start a note',
              onTap: () => store.dailyNote(widget.day),
            ),
          ),
        ],
      ),
    );
  }
}
