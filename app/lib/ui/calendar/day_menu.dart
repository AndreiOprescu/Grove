// The day menu: a right-click (a long press on a phone) on a day name at the
// top of the Planner week, or on a day of the Calendar month. It lists what
// can be done with that day.
import 'package:flutter/material.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../planner/planner_dialogs.dart';
import '../tasks/task_widgets.dart';
import '../theme/grove_theme.dart';
import '../theme/panel.dart';

/// The day as the menu and its toasts say it: "Wed 21 Oct".
String dayMenuDate(DayKey day) =>
    '${NotesRules.weekdayName(day).substring(0, 3)} ${NotesRules.shortDate(day)}';

/// Opens the day menu for [day] at [global]. [showInPlanner] adds "Show in
/// Planner" (the Calendar). [planDay] adds "Plan my day" for today and later
/// days (the Planner).
Future<void> showDayMenu(
  BuildContext context,
  Offset global, {
  required AppStore store,
  required DayKey day,
  VoidCallback? showInPlanner,
  VoidCallback? planDay,
}) {
  final hasOpen = store.openTasks(TaskPlacement.day(day)).isNotEmpty;
  return showGroveMenu(context, global, [
    MenuLine.title(NotesRules.longDay(day)),
    MenuLine('New event', () => store.newEvent(on: day)),
    MenuLine('New deadline', () => store.newEvent(on: day, deadline: true)),
    MenuLine('New task…', () {
      if (context.mounted) showNewTaskDialog(context, store: store, day: day);
    }),
    const MenuLine.divider(),
    MenuLine('Open daily note', () => store.openDailyNote(day)),
    MenuLine('Open weekly note', () => store.openWeeklyNote(day)),
    if (showInPlanner != null) MenuLine('Show in Planner', showInPlanner),
    if (planDay != null && day >= store.clockToday)
      MenuLine('Plan my day', planDay),
    if (hasOpen) ...[
      const MenuLine.divider(),
      MenuLine('Move open tasks to…', () {
        if (context.mounted) _moveOpenTasks(context, store: store, day: day);
      }),
    ],
  ]);
}

/// Asks for the new day, then moves the open tasks of [day] there.
Future<void> _moveOpenTasks(
  BuildContext context, {
  required AppStore store,
  required DayKey day,
}) async {
  final picked = await showDatePicker(
    context: context,
    helpText: 'Move open tasks to',
    initialDate: day.adding(days: 1).date,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100, 12, 31),
  );
  if (picked == null) return;
  final to = DayKey.fromDate(picked);
  final moved = store.moveOpenTasks(from: day, to: to);
  if (moved == 0) return;
  store.showToast(
    'Moved $moved task${moved == 1 ? '' : 's'} to ${dayMenuDate(to)}',
  );
}

/// The window of "New task…": one line, read like the quick add field
/// ("Call mum 6pm for 20m #home"). The task is planned for [day].
Future<void> showNewTaskDialog(
  BuildContext context, {
  required AppStore store,
  required DayKey day,
}) => showDialog<void>(
  context: context,
  builder: (_) => _NewTaskDialog(store: store, day: day),
);

class _NewTaskDialog extends StatefulWidget {
  const _NewTaskDialog({required this.store, required this.day});

  final AppStore store;
  final DayKey day;

  @override
  State<_NewTaskDialog> createState() => _NewTaskDialogState();
}

class _NewTaskDialogState extends State<_NewTaskDialog> {
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _ready => _text.text.trim().isNotEmpty;

  void _add() {
    if (!_ready) return;
    widget.store.quickAdd(_text.text, placement: TaskPlacement.day(widget.day));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final style = theme.body(13).copyWith(color: theme.ink);
    return PlannerSheet(
      key: const ValueKey('day-new-task'),
      width: 380,
      children: [
        ThemedHeading('New task for ${dayMenuDate(widget.day)}', 18),
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.surface2,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: theme.line),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: TextField(
              key: const ValueKey('day-new-task-field'),
              controller: _text,
              autofocus: true,
              maxLines: 1,
              style: style,
              cursorColor: theme.accent,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration.collapsed(
                hintText: 'Call mum 6pm for 20m #home',
                hintStyle: style.copyWith(color: theme.muted),
              ),
              onSubmitted: (_) => _add(),
            ),
          ),
        ),
        dialogButtons([
          DialogButton(
            label: 'Cancel',
            onTap: () => Navigator.of(context).pop(),
          ),
          DialogButton(
            label: 'Add',
            primary: true,
            onTap: _ready ? _add : null,
          ),
        ]),
      ],
    );
  }
}
