// How long a step takes: a square of a project or a subtask of a habit.
// The step and its block have the same length, both ways.
import 'package:flutter/material.dart';
import 'package:grove/core/planner/planner_math.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../tasks/task_widgets.dart';
import '../theme/grove_theme.dart';

/// The lengths a step can take: none, the lengths of a block, and the one
/// it has now (a resize can give any length).
List<int?> stepLengthChoices(int? now) => [
  null,
  ...{...PlannerLimits.durationChoices, ?now}.toList()..sort(),
];

String stepLengthText(int? minutes) =>
    minutes == null ? 'No length' : PlannerMath.duration(minutes);

/// The length of a step, with a menu of lengths.
class StepLengthPick extends StatelessWidget {
  const StepLengthPick({
    super.key,
    required this.minutes,
    required this.onPick,
  });

  final int? minutes;
  final ValueChanged<int?> onPick;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: MenuPick<int?>(
      value: minutes,
      values: stepLengthChoices(minutes),
      name: stepLengthText,
      onPick: onPick,
      label: 'How long it takes',
    ),
  );
}

/// A small length in a row: "45m", or a clock when the step has none. A
/// tap opens the menu of lengths.
class StepLengthChip extends StatelessWidget {
  const StepLengthChip({
    super.key,
    required this.minutes,
    required this.name,
    required this.onPick,
    this.side = 28,
  });

  final int? minutes;

  /// The name of the step, for a screen reader.
  final String name;
  final ValueChanged<int?> onPick;

  /// The smallest width and the height.
  final double side;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final m = minutes;
    void open() {
      final box = context.findRenderObject()! as RenderBox;
      showGroveMenu(context, box.localToGlobal(Offset(0, box.size.height)), [
        for (final v in stepLengthChoices(m))
          MenuLine(stepLengthText(v), () => onPick(v), checked: v == m),
      ]);
    }

    return Semantics(
      container: true,
      button: true,
      label: 'How long $name takes',
      value: stepLengthText(m),
      onTap: open,
      excludeSemantics: true,
      child: Tooltip(
        message: 'How long it takes',
        excludeFromSemantics: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: open,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: side, minHeight: side),
              child: Center(
                child: m == null
                    ? Icon(Icons.schedule, size: 14, color: theme.muted)
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          PlannerMath.duration(m),
                          style: theme.number(11).copyWith(color: theme.muted),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
