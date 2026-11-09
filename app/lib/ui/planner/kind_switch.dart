// Task or activity: the two chips under a new block of the planner, in the
// task panel and in the editor of an activity. A block on the grid turns
// from one into the other in place (`AppStore.toggleKind`).
import 'package:flutter/material.dart';
import 'package:grove/core/model/event.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../theme/grove_theme.dart';
import '../theme/panel.dart';
import '../theme/symbols.dart';
import 'planner_dialogs.dart';

/// The chips "Task" and "Activity". [activity] says which one is on: null
/// for neither (a draft that is a plain event). Their keys are
/// `<keyPrefix>-task` and `<keyPrefix>-activity`.
class KindChips extends StatelessWidget {
  const KindChips({
    super.key,
    required this.keyPrefix,
    required this.activity,
    required this.onPick,
  });

  final String keyPrefix;
  final bool? activity;

  /// Gets true for "Activity", false for "Task".
  final ValueChanged<bool> onPick;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 4,
    children: [
      _KindChip(
        key: ValueKey('$keyPrefix-task'),
        icon: symbolIcon('square'),
        label: 'Task',
        on: activity == false,
        onTap: () => onPick(false),
      ),
      _KindChip(
        key: ValueKey('$keyPrefix-activity'),
        icon: symbolIcon('cup.and.saucer'),
        label: 'Activity',
        on: activity == true,
        onTap: () => onPick(true),
      ),
    ],
  );
}

/// One chip: an icon and a word.
class _KindChip extends StatelessWidget {
  const _KindChip({
    super.key,
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final color = on ? theme.accent : theme.muted;
    return Semantics(
      button: true,
      selected: on,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: on
                ? theme.accent.withValues(alpha: 0.14)
                : theme.solidSurface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: on ? theme.accent : theme.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              Icon(icon, size: 12, color: color),
              Text(
                label,
                style: theme
                    .body(10, weight: FontWeight.w700)
                    .copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Turns the block [eventId] into the other kind. A task that would go away
/// with its subtasks or points asks first. True when the block changed.
Future<bool> turnBlockKind(
  BuildContext context,
  AppStore store,
  String eventId,
) async {
  final to = store.kindSwitch(eventId);
  if (to == null) return false;
  final loss = store.kindSwitchLoss(eventId);
  if (loss != null) {
    final title = store.task(store.event(eventId)?.taskId ?? '')?.title ?? '';
    final yes = await _askLoss(context, title, loss);
    if (!yes || store.kindSwitch(eventId) != to) return false;
  }
  store.toggleKind(eventId);
  return store.event(eventId)?.kind == to;
}

/// "Turn into an activity?": the task goes away with what it has.
Future<bool> _askLoss(
  BuildContext context,
  String title,
  ({int subtasks, int rewards}) loss,
) async {
  String count(int n, String word) => '$n $word${n == 1 ? '' : 's'}';
  final lost = [
    if (loss.subtasks > 0) count(loss.subtasks, 'subtask'),
    if (loss.rewards > 0) 'its points',
  ].join(' and ');
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = GroveTheme.of(context);
      return PlannerSheet(
        width: 360,
        children: [
          const ThemedHeading('Turn into an activity?', 18),
          Text(
            'The task “$title” goes away with $lost. The time stays on the '
            'planner as an activity. Undo brings the task back.',
            style: theme.body(13).copyWith(color: theme.muted),
          ),
          dialogButtons([
            DialogButton(
              key: const ValueKey('kind-cancel'),
              label: 'Cancel',
              onTap: () => Navigator.of(context).pop(false),
            ),
            DialogButton(
              key: const ValueKey('kind-confirm'),
              label: 'Turn into Activity',
              primary: true,
              onTap: () => Navigator.of(context).pop(true),
            ),
          ]),
        ],
      );
    },
  );
  return answer ?? false;
}

/// The name of the menu line that switches the block, or null.
String? kindSwitchLine(AppStore store, String eventId) =>
    switch (store.kindSwitch(eventId)) {
      EventKind.activity => 'Turn into Activity',
      EventKind.block => 'Turn into Task',
      _ => null,
    };
