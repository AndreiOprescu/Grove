// Port of Sources/Grove/Notes/DayPanel.swift: the card at the side of a
// daily note (its day) and of a weekly note (its week), the list of tasks
// finished on a day, and the mood of a day.
import 'package:flutter/material.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/link.dart';
import 'package:grove/core/model/note.dart';
import 'package:grove/core/model/task.dart';
import 'package:grove/core/planner/planner_math.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../calendar/month_view.dart' show moodTint;
import '../tasks/task_widgets.dart' show CardButton, ProgressBar, StoreBuilder;
import '../theme/grove_theme.dart';
import '../theme/panel.dart';
import '../theme/symbols.dart';

/// Something to click, with a name for a screen reader.
class NoteTap extends StatelessWidget {
  const NoteTap({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.tip,
    this.selected,
    this.onMenu,
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;

  /// The text of a tooltip. No tooltip when null.
  final String? tip;
  final bool? selected;

  /// A right click or a long press, with the place in the window.
  final ValueChanged<Offset>? onMenu;

  @override
  Widget build(BuildContext context) {
    final menu = onMenu;
    Widget out = Semantics(
      container: true,
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onSecondaryTapUp: menu == null ? null : (d) => menu(d.globalPosition),
          onLongPressStart: menu == null ? null : (d) => menu(d.globalPosition),
          child: child,
        ),
      ),
    );
    final tip = this.tip;
    if (tip != null) {
      out = Tooltip(message: tip, excludeFromSemantics: true, child: out);
    }
    return out;
  }
}

/// The card on the right of a daily or weekly note.
class SideCard extends StatelessWidget {
  const SideCard({
    super.key,
    required this.title,
    this.subtitle = '',
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  static const width = 236.0;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final radius = BorderRadius.circular((theme.radius * 0.8).roundToDouble());
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surface2.withValues(alpha: 0.7),
        borderRadius: radius,
        border: Border.all(color: theme.line.withValues(alpha: 0.8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  title.toUpperCase(),
                  maxLines: 1,
                  style: theme
                      .body(10, weight: FontWeight.w700)
                      .copyWith(color: theme.muted),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: theme.body(12).copyWith(color: theme.ink),
                  ),
              ],
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// The day of a daily note: events, task blocks and tasks, live
/// (PLAN §5.5 item 4).
class DayPanel extends StatelessWidget {
  const DayPanel({super.key, required this.store, required this.day});

  final AppStore store;
  final DayKey day;

  static String summary({
    required int events,
    required int tasks,
    required int finished,
  }) => [
    if (events > 0) '$events event${events == 1 ? '' : 's'}',
    if (tasks > 0) '$finished/$tasks task${tasks == 1 ? '' : 's'} done',
  ].join(' · ');

  static String _icon(AgendaRow r) => switch (r.kind) {
    AgendaKind.event => 'calendar',
    AgendaKind.block => r.done ? 'checkmark.circle.fill' : 'clock',
    AgendaKind.task => r.done ? 'checkmark.circle.fill' : 'circle',
  };

  @override
  Widget build(BuildContext context) => StoreBuilder(
    store: store,
    builder: (context) {
      final theme = GroveTheme.of(context);
      final rows = store.agenda(day);
      final events = rows.where((r) => r.kind == AgendaKind.event).length;
      final tasks = rows.length - events;
      final finished = rows
          .where((r) => r.kind != AgendaKind.event && r.done)
          .length;
      return SideCard(
        title: day == store.clockToday ? 'Today' : 'This day',
        subtitle: summary(events: events, tasks: tasks, finished: finished),
        children: [
          if (rows.isEmpty)
            Text(
              'Nothing planned for this day.',
              style: theme.body(12).copyWith(color: theme.muted),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 7,
              children: [
                for (final (i, r) in rows.indexed) ...[
                  if (r.kind == AgendaKind.task &&
                      i > 0 &&
                      rows[i - 1].kind != AgendaKind.task)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Not scheduled',
                        style: theme
                            .body(10, weight: FontWeight.w600)
                            .copyWith(color: theme.muted),
                      ),
                    ),
                  _row(theme, r),
                ],
              ],
            ),
          NoteTap(
            key: const ValueKey('day-open-planner'),
            label: 'Open in planner',
            onTap: () => store
              ..selectedDay = day
              ..screen = Screen.planner,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                Icon(
                  symbolIcon('arrow.up.right'),
                  size: 12,
                  color: theme.accent,
                ),
                Text(
                  'Open in planner',
                  style: theme
                      .body(12, weight: FontWeight.w500)
                      .copyWith(color: theme.accent),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );

  Widget _row(GroveTheme theme, AgendaRow r) {
    final time = DayRules.timeLabel(r);
    final title = r.title.isEmpty ? 'Untitled' : r.title;
    return NoteTap(
      key: ValueKey('day-row-${r.id}'),
      label: time.isEmpty ? title : '$title, $time',
      tip: r.kind == AgendaKind.event
          ? 'Show this event in the planner'
          : 'Show this task in the planner',
      onTap: () => store.open(r.ref),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 7,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              symbolIcon(_icon(r)),
              size: 12,
              color: r.done
                  ? theme.muted
                  : (r.kind == AgendaKind.event ? theme.accent2 : theme.accent),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 1,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme
                      .body(12)
                      .copyWith(
                        color: r.done ? theme.muted : theme.ink,
                        decoration: r.done ? TextDecoration.lineThrough : null,
                      ),
                ),
                if (time.isNotEmpty)
                  Text(
                    time,
                    maxLines: 1,
                    style: theme.number(10).copyWith(color: theme.muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The tasks finished on a day, with the time. It is built from the tasks.
/// It is not saved in the note (PLAN §5.5 item 5).
class DoneLog extends StatelessWidget {
  const DoneLog({super.key, required this.store, required this.day});

  final AppStore store;
  final DayKey day;

  @override
  Widget build(BuildContext context) => StoreBuilder(
    store: store,
    builder: (context) {
      final theme = GroveTheme.of(context);
      final tasks = store.completedTasks(day);
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            ThemedHeading(
              day == store.clockToday ? 'Done today' : 'Done this day',
              12,
              weight: FontWeight.w700,
            ),
            if (tasks.isEmpty)
              Text(
                'Nothing finished yet.',
                style: theme.body(12).copyWith(color: theme.muted),
              ),
            for (final t in tasks) _row(theme, t),
          ],
        ),
      );
    },
  );

  Widget _row(GroveTheme theme, TaskItem t) => NoteTap(
    key: ValueKey('done-${t.id}'),
    label: '${t.title}, finished at ${DayRules.finishedClock(t)}',
    onTap: () => store.open(ItemRef(ItemType.task, t.id)),
    child: Row(
      spacing: 8,
      children: [
        Icon(
          symbolIcon('checkmark.circle.fill'),
          size: 13,
          color: theme.accent,
        ),
        Text(
          DayRules.finishedClock(t),
          maxLines: 1,
          style: theme.number(12).copyWith(color: theme.muted),
        ),
        Expanded(
          child: Text(
            t.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.body(12).copyWith(color: theme.ink),
          ),
        ),
      ],
    ),
  );
}

/// Three icons: rough, okay, good. A second click on the same icon clears
/// it (PLAN §5.5 item 12).
class MoodPicker extends StatelessWidget {
  const MoodPicker({super.key, required this.store, required this.note});

  final AppStore store;
  final Note note;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: theme.surface2,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 2,
          children: [for (final m in Mood.values) _button(theme, m)],
        ),
      ),
    );
  }

  Widget _button(GroveTheme theme, Mood m) {
    final on = note.mood == m.value;
    final tint = moodTint(m);
    return NoteTap(
      key: ValueKey('mood-${m.name}'),
      label: m.label,
      selected: on,
      tip: on ? '${m.label}. Click again to clear it.' : m.label,
      onTap: () => store.setMood(note.id, m),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: on ? tint.withValues(alpha: 0.16) : null,
          shape: const StadiumBorder(),
        ),
        child: SizedBox(
          width: 26,
          height: 24,
          child: Icon(
            symbolIcon(m.symbol),
            size: 15,
            color: on ? tint : theme.muted,
          ),
        ),
      ),
    );
  }
}

/// The week of a weekly note: what was done, what is open, hours and the
/// busiest day (PLAN §5.5 item 10).
class WeekReviewPanel extends StatelessWidget {
  const WeekReviewPanel({
    super.key,
    required this.store,
    required this.monday,
    required this.hasSummary,
    required this.onInsert,
  });

  final AppStore store;
  final DayKey monday;
  final bool hasSummary;
  final VoidCallback onInsert;

  @override
  Widget build(BuildContext context) => StoreBuilder(
    store: store,
    builder: (context) {
      final theme = GroveTheme.of(context);
      final r = store.weekReview(monday);
      final busiest = r.busiest;
      return SideCard(
        title: 'Week review',
        subtitle:
            '${NotesRules.shortDate(monday)} – '
            '${NotesRules.shortDate(monday.adding(days: 6))}',
        children: [
          Row(
            spacing: 10,
            children: [
              Expanded(child: _number(theme, r.done.length, 'done')),
              Expanded(child: _number(theme, r.open.length, 'still open')),
            ],
          ),
          if (r.plannedMinutes == 0)
            Text(
              'No task blocks planned.',
              style: theme.body(12).copyWith(color: theme.muted),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 4,
              children: [
                Text(
                  '${PlannerMath.duration(r.doneMinutes)} finished of '
                  '${PlannerMath.duration(r.plannedMinutes)} planned',
                  style: theme.body(12).copyWith(color: theme.ink),
                ),
                ProgressBar(fraction: r.doneMinutes / r.plannedMinutes),
              ],
            ),
          if (busiest != null)
            Row(
              spacing: 5,
              children: [
                Icon(symbolIcon('flame'), size: 13, color: theme.ink),
                Expanded(
                  child: Text(
                    'Busiest: ${NotesRules.weekdayName(busiest.day)}, '
                    '${PlannerMath.duration(busiest.minutes)}',
                    style: theme.body(12).copyWith(color: theme.ink),
                  ),
                ),
              ],
            ),
          ..._list(theme, 'Finished', r.done, 'checkmark.circle.fill'),
          ..._list(theme, 'Left open', r.open, 'circle'),
          Tooltip(
            message: 'Write this review under ## Review in the note',
            excludeFromSemantics: true,
            child: CardButton(
              key: const ValueKey('week-summary'),
              label: hasSummary ? 'Update summary' : 'Insert summary',
              onTap: onInsert,
            ),
          ),
        ],
      );
    },
  );

  Widget _number(GroveTheme theme, int n, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ThemedHeading('$n', 24),
      Text(label, style: theme.body(11).copyWith(color: theme.muted)),
    ],
  );

  List<Widget> _list(
    GroveTheme theme,
    String title,
    List<TaskItem> tasks,
    String icon,
  ) {
    if (tasks.isEmpty) return const [];
    return [
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 5,
        children: [
          Text(
            title,
            style: theme
                .body(10, weight: FontWeight.w600)
                .copyWith(color: theme.muted),
          ),
          for (final t in tasks.take(5))
            NoteTap(
              key: ValueKey('week-task-${t.id}'),
              label: t.title,
              onTap: () => store.open(ItemRef(ItemType.task, t.id)),
              child: Row(
                spacing: 6,
                children: [
                  Icon(symbolIcon(icon), size: 11, color: theme.accent),
                  Expanded(
                    child: Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.body(12).copyWith(color: theme.ink),
                    ),
                  ),
                ],
              ),
            ),
          if (tasks.length > 5)
            Text(
              'and ${tasks.length - 5} more',
              style: theme.body(11).copyWith(color: theme.muted),
            ),
        ],
      ),
    ];
  }
}
