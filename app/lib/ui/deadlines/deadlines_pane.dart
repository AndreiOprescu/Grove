import 'package:flutter/material.dart';
import 'package:grove/core/model/event.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../shell/shell_layout.dart';
import '../tasks/task_widgets.dart';
import '../theme/check_box.dart';
import '../theme/grove_theme.dart';
import '../theme/named_colors.dart';
import '../theme/panel.dart';

/// The Deadlines panel on the left of the Today and Planner screens: every
/// event marked as a deadline. Missed ones on top, then the ones still to
/// come, soonest first. The done ones are folded at the bottom, each with how
/// early or late it was ticked.
class DeadlinesPane extends StatefulWidget {
  const DeadlinesPane({super.key, required this.store});

  final AppStore store;

  @override
  State<DeadlinesPane> createState() => _DeadlinesPaneState();
}

class _DeadlinesPaneState extends State<DeadlinesPane> {
  bool _showDone = false;

  AppStore get _store => widget.store;

  /// Opens the card of the event. On a phone the panel covers the screen
  /// that shows the card, so the panel closes first.
  void _open(EventItem e) {
    final phone =
        ShellRules.layoutFor(MediaQuery.sizeOf(context).width) ==
        ShellLayout.phone;
    if (phone) _store.leftPane = null;
    _store.editEvent(e);
  }

  @override
  Widget build(BuildContext context) => StoreBuilder(
    store: _store,
    builder: (context) {
      final theme = GroveTheme.of(context);
      final s = _store.deadlineSections;
      final now = _store.clockNow();
      final open = s.missed.length + s.coming.length;
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
                  const Expanded(child: ThemedHeading('Deadlines', 20)),
                  Text(
                    open == 0 ? 'Nothing due' : '$open open',
                    style: theme.body(11).copyWith(color: theme.muted),
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  children: [
                    if (s.isEmpty)
                      Text(
                        'No deadlines. Open an event and turn on "Deadline".',
                        key: const ValueKey('deadlines-empty'),
                        style: theme.body(12).copyWith(color: theme.muted),
                      ),
                    if (s.missed.isNotEmpty)
                      ..._section(
                        theme,
                        'Missed',
                        s.missed,
                        now,
                        tint: theme.accent2,
                      ),
                    if (s.coming.isNotEmpty)
                      ..._section(theme, 'Coming', s.coming, now),
                    if (s.done.isNotEmpty) ..._doneSection(theme, s.done, now),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  List<Widget> _section(
    GroveTheme theme,
    String title,
    List<EventItem> rows,
    DateTime now, {
    Color? tint,
  }) => [
    Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: ThemedHeading(
        '$title · ${rows.length}',
        12,
        weight: FontWeight.w700,
        color: tint ?? theme.muted,
      ),
    ),
    for (final e in rows) _row(theme, e, now, tint: tint),
  ];

  List<Widget> _doneSection(
    GroveTheme theme,
    List<EventItem> rows,
    DateTime now,
  ) {
    final label = 'Done · ${rows.length}';
    void toggle() => setState(() => _showDone = !_showDone);
    return [
      Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
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
              key: const ValueKey('deadlines-done-toggle'),
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
        for (final e in rows) _row(theme, e, now),
    ];
  }

  Widget _row(GroveTheme theme, EventItem e, DateTime now, {Color? tint}) {
    final done = e.doneAt != null;
    final when = DeadlineRules.dueText(e, now: now);
    final margin = DeadlineRules.marginText(e);
    void tick() => _store.toggleDeadlineDone(e.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Semantics(
            container: true,
            button: true,
            checked: done,
            label: done
                ? 'Mark ${e.title} as not done'
                : 'Mark ${e.title} as done',
            onTap: tick,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                key: ValueKey('deadline-check-${e.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: tick,
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: CheckBox(isOn: done),
                ),
              ),
            ),
          ),
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                key: ValueKey('deadline-row-${e.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _open(e),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Row(
                      spacing: 6,
                      children: [
                        Icon(Icons.flag, size: 12, color: theme.color(e.color)),
                        Expanded(
                          child: Text(
                            e.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme
                                .body(13, weight: FontWeight.w600)
                                .copyWith(
                                  color: done ? theme.muted : theme.ink,
                                  decoration: done
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      margin == null ? when : '$when · $margin',
                      style: theme
                          .body(11)
                          .copyWith(color: tint ?? theme.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
