// Port of Sources/Grove/Calendar/MonthView.swift: six weeks, Monday first
// (Sunday first in Settings). Each day shows its events, a dot for each open
// task (up to three) and a leaf when it has a daily note. A click opens the
// Planner on that week. A double click makes an all-day event.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/event.dart';
import 'package:grove/core/planner/planner_math.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../tasks/task_widgets.dart' show WholeCenter, wholeShares;
import '../theme/grove_theme.dart';
import '../theme/named_colors.dart';
import '../theme/symbols.dart';

/// The colour of a mood. The same in each theme, as in the Mac app.
Color moodTint(Mood mood) => switch (mood) {
  Mood.rain => const Color.fromRGBO(107, 140, 191, 1),
  Mood.cloud => const Color.fromRGBO(199, 173, 110, 1),
  Mood.sun => const Color.fromRGBO(227, 179, 64, 1),
};

class MonthView extends StatefulWidget {
  const MonthView({
    super.key,
    required this.store,
    required this.openDay,
    this.moodTint = false,
  });

  final AppStore store;

  /// Called after a click on a day, so the Calendar can open the Planner on
  /// that week.
  final ValueChanged<DayKey> openDay;

  /// Colours each day by the mood of its daily note.
  final bool moodTint;

  /// How long a click waits for a second click.
  static const doubleClick = Duration(milliseconds: 300);

  @override
  State<MonthView> createState() => _MonthViewState();
}

class _MonthViewState extends State<MonthView> {
  Timer? _click;
  DayKey? _clicked;

  AppStore get _store => widget.store;

  @override
  void dispose() {
    _click?.cancel();
    super.dispose();
  }

  /// One click opens the day. A second click in time makes an event.
  void _tap(DayKey day) {
    if (_click != null && _clicked == day) {
      _click?.cancel();
      _click = null;
      _store.newEvent(on: day);
      return;
    }
    _click?.cancel();
    _clicked = day;
    _click = Timer(MonthView.doubleClick, () {
      _click = null;
      if (!mounted) return;
      _store.selectedDay = day;
      widget.openDay(day);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final grid = CalendarRules.monthGrid(
      _store.selectedDay,
      sundayFirst: _store.weekStartsSunday,
    );
    final info = _store.dayInfo(DayRange(grid[0], grid[41]));
    final month = _store.selectedDay.month;
    return LayoutBuilder(
      builder: (context, box) {
        final widths = wholeShares(box.maxWidth, 7);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _weekdays(theme, grid, widths),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final heights = wholeShares(box.maxHeight, 6);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var row = 0; row < 6; row++)
                        SizedBox(
                          height: heights[row],
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var col = 0; col < 7; col++)
                                SizedBox(
                                  width: widths[col],
                                  child: _cell(
                                    theme,
                                    grid[row * 7 + col],
                                    info[grid[row * 7 + col]] ??
                                        const DayInfo(),
                                    inMonth: grid[row * 7 + col].month == month,
                                    height: heights[row],
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _weekdays(GroveTheme theme, List<DayKey> grid, List<double> widths) =>
      DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.line)),
        ),
        child: ExcludeSemantics(
          child: Row(
            children: [
              for (var i = 0; i < 7; i++)
                SizedBox(
                  width: widths[i],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: WholeCenter(
                      child: Text(
                        NotesRules.weekdayName(grid[i]).substring(0, 3),
                        maxLines: 1,
                        style: theme
                            .body(11, weight: FontWeight.w600)
                            .copyWith(color: theme.muted),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );

  // Cell

  Widget _cell(
    GroveTheme theme,
    DayKey day,
    DayInfo info, {
    required bool inMonth,
    required double height,
  }) {
    final slots = CalendarRules.pillSlots(cellHeight: height);
    final pills = CalendarRules.pills(info.events, slots: slots);
    final selected = day == _store.selectedDay;
    final mood = widget.moodTint && info.mood != null
        ? Mood.fromValue(info.mood!)
        : null;
    final dots = CalendarRules.dots(info.openTasks);
    final tasks =
        '${info.openTasks} open task${info.openTasks == 1 ? '' : 's'}';
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 2,
      children: [
        Row(
          spacing: 4,
          children: [
            _dayNumber(theme, day),
            const Spacer(),
            if (info.hasNote)
              Tooltip(
                message: 'This day has a note',
                child: Icon(
                  symbolIcon('leaf.fill'),
                  key: ValueKey('month-leaf-${day.string}'),
                  size: 10,
                  color: theme.accent,
                ),
              ),
            if (dots > 0)
              Tooltip(
                message: tasks,
                child: Row(
                  key: ValueKey('month-dots-${day.string}'),
                  mainAxisSize: MainAxisSize.min,
                  spacing: 2,
                  children: [
                    for (var i = 0; i < dots; i++)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.accent2,
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox(width: 4, height: 4),
                      ),
                  ],
                ),
              ),
          ],
        ),
        for (final e in pills.shown) _pill(theme, e, day),
        if (pills.hidden > 0)
          Text(
            '+${pills.hidden} more',
            maxLines: 1,
            style: theme.body(10).copyWith(color: theme.muted),
          ),
      ],
    );
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data.startsWith(DragPayload.taskPrefix),
      onAcceptWithDetails: (d) => _store.dropTask(
        d.data.substring(DragPayload.taskPrefix.length),
        on: day,
      ),
      builder: (context, candidates, _) {
        final target = candidates.isNotEmpty;
        return Semantics(
          container: true,
          button: true,
          selected: selected,
          label: NotesRules.longDay(day),
          value: [
            if (info.events.isNotEmpty)
              '${info.events.length} event${info.events.length == 1 ? '' : 's'}',
            if (info.openTasks > 0) tasks,
            if (info.hasNote) 'has a note',
          ].join(', '),
          onTap: () {
            _store.selectedDay = day;
            widget.openDay(day);
          },
          child: GestureDetector(
            key: ValueKey('month-day-${day.string}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _tap(day),
            child: Opacity(
              opacity: inMonth ? 1 : 0.5,
              child: DecoratedBox(
                key: mood == null ? null : ValueKey('month-mood-${day.string}'),
                decoration: BoxDecoration(
                  color: mood == null
                      ? null
                      : moodTint(mood).withValues(alpha: 0.2),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: target
                        ? theme.accent.withValues(alpha: 0.12)
                        : selected
                        ? theme.accent.withValues(alpha: 0.07)
                        : null,
                    border: target
                        ? Border.all(color: theme.accent, width: 1.5)
                        : Border.all(
                            color: theme.line.withValues(alpha: 0.7),
                            width: 0.5,
                          ),
                  ),
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minHeight: 0,
                      maxHeight: double.infinity,
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: content,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _dayNumber(GroveTheme theme, DayKey day) {
    final today = day == _store.clockToday;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: today ? theme.accent : null,
        shape: BoxShape.circle,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: ExcludeSemantics(
            child: Text(
              '${day.day}',
              maxLines: 1,
              style: theme
                  .body(12, weight: today ? FontWeight.w700 : FontWeight.w600)
                  .copyWith(color: today ? theme.surface : theme.ink),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(GroveTheme theme, EventItem e, DayKey day) {
    final anchor = '${e.id}#${day.string}';
    final time = !e.allDay && e.start.day == day
        ? '${PlannerMath.clock(e.start.minute)} '
        : '';
    final title = e.title.isEmpty ? 'New Event' : e.title;
    void open() => _store.editEvent(e, anchor: anchor);
    return Semantics(
      container: true,
      button: true,
      label: '$time$title',
      onTap: open,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('month-pill-$anchor'),
        behavior: HitTestBehavior.opaque,
        onTap: open,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.color(e.color).withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            child: Text.rich(
              TextSpan(
                children: [
                  if (time.isNotEmpty)
                    TextSpan(
                      text: time,
                      style: TextStyle(color: theme.muted),
                    ),
                  TextSpan(text: title),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme
                  .body(10, weight: FontWeight.w600)
                  .copyWith(color: theme.ink),
            ),
          ),
        ),
      ),
    );
  }
}
