// The small windows of the planner: "Busy day", the question about a
// repeating event, and the "Plan my day" list.
import 'package:flutter/material.dart';
import 'package:grove/core/planner/planner_math.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../theme/grove_theme.dart';
import '../theme/panel.dart';

/// A button of a planner window. `primary` is the one Enter picks.
class DialogButton extends StatelessWidget {
  const DialogButton({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: label,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: primary ? theme.accent : theme.surface2,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: primary ? theme.accent : theme.line),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                label,
                maxLines: 1,
                style: theme
                    .body(13, weight: FontWeight.w600)
                    .copyWith(color: primary ? theme.bg : theme.ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The frame of a planner window.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.children, this.width = 420});

  final List<Widget> children;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return Dialog(
      backgroundColor: theme.solidSurface,
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.radius),
        side: BorderSide(color: theme.line),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: DefaultTextStyle(
            style: theme.body(13).copyWith(color: theme.ink),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

Widget _buttons(List<Widget> buttons) => Wrap(
  alignment: WrapAlignment.end,
  spacing: 8,
  runSpacing: 8,
  children: buttons,
);

/// "Busy day": the day is over the daily limit.
Future<void> showBusyDay(BuildContext context, String message) =>
    showDialog<void>(
      context: context,
      builder: (context) {
        final theme = GroveTheme.of(context);
        return _Sheet(
          width: 340,
          children: [
            const ThemedHeading('Busy day', 18),
            Text(message, style: theme.body(13).copyWith(color: theme.ink)),
            _buttons([
              DialogButton(
                label: 'OK',
                primary: true,
                onTap: () => Navigator.of(context).pop(),
              ),
            ]),
          ],
        );
      },
    );

/// "This event only" or "All events". null when the user closed the window.
Future<RecurringScope?> showRecurringQuestion(
  BuildContext context,
  String verb,
) => showDialog<RecurringScope>(
  context: context,
  builder: (context) {
    final theme = GroveTheme.of(context);
    return _Sheet(
      width: 360,
      children: [
        ThemedHeading('$verb a repeating event', 18),
        Text(
          'Change this day only, or every day of the event?',
          style: theme.body(13).copyWith(color: theme.muted),
        ),
        _buttons([
          DialogButton(
            label: 'Cancel',
            onTap: () => Navigator.of(context).pop(),
          ),
          DialogButton(
            label: 'All events',
            onTap: () => Navigator.of(context).pop(RecurringScope.all),
          ),
          DialogButton(
            label: 'This event only',
            primary: true,
            onTap: () => Navigator.of(context).pop(RecurringScope.only),
          ),
        ]),
      ],
    );
  },
);

/// The list of "Plan my day". true when the user picked Apply.
Future<bool> showPlanSheet(BuildContext context, List<PlanStep> plan) async {
  final apply = await showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = GroveTheme.of(context);
      return _Sheet(
        children: [
          const ThemedHeading('Plan my day', 22),
          Text(
            'Grove will place these tasks in free working hours, highest '
            'priority first.',
            style: theme.body(12).copyWith(color: theme.muted),
          ),
          for (final step in plan)
            Row(
              spacing: 8,
              children: [
                Text(
                  '${PlannerMath.clock(step.start)}–'
                  '${PlannerMath.clock(step.start + PlannerMath.blockLength(step.task.estimateMin))}',
                  style: theme.number(13).copyWith(color: theme.accent),
                ),
                Expanded(
                  child: Text(
                    step.task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.body(13).copyWith(color: theme.ink),
                  ),
                ),
              ],
            ),
          _buttons([
            DialogButton(
              label: 'Cancel',
              onTap: () => Navigator.of(context).pop(false),
            ),
            DialogButton(
              key: const ValueKey('plan-apply'),
              label: 'Apply',
              primary: true,
              onTap: () => Navigator.of(context).pop(true),
            ),
          ]),
        ],
      );
    },
  );
  return apply ?? false;
}
