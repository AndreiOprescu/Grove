// Port of Sources/Grove/Planner/Workload.swift: how full a day is.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:grove/core/planner/planner_math.dart';

import '../theme/grove_theme.dart';

abstract final class Workload {
  /// How much of the bar is filled, 0 to 1. With no limit the bar is full.
  static double fraction({required int planned, required int limit}) =>
      limit <= 0 ? 1 : min(1, max(0, planned / limit));

  static bool isOver({required int planned, required int limit}) =>
      planned > limit;

  /// "6h 30m/9h"
  static String label({required int planned, required int limit}) =>
      '${PlannerMath.duration(planned)}/${PlannerMath.duration(limit)}';
}

/// A thin bar for the planned time of a day against the daily limit. It
/// turns bright red when the day is over the limit.
class WorkloadBar extends StatelessWidget {
  const WorkloadBar({
    super.key,
    required this.planned,
    required this.limit,
    required this.detail,
  });

  final int planned;
  final int limit;

  /// The longer text, for the tooltip.
  final String detail;

  static const overColor = Color.from(
    alpha: 1,
    red: 1,
    green: 0.10,
    blue: 0.10,
  );

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final over = Workload.isOver(planned: planned, limit: limit);
    final label = Workload.label(planned: planned, limit: limit);
    final tint = over ? overColor : theme.accent;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: over ? 'Planned $label. Over the daily limit.' : 'Planned $label',
      tooltip: detail,
      child: Tooltip(
        message: detail,
        excludeFromSemantics: true,
        child: Row(
          spacing: 8,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 8,
                  child: ColoredBox(
                    color: theme.line,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: Workload.fraction(
                        planned: planned,
                        limit: limit,
                      ),
                      child: ColoredBox(color: tint),
                    ),
                  ),
                ),
              ),
            ),
            Text(
              label,
              maxLines: 1,
              style: theme
                  .number(11, weight: over ? FontWeight.w700 : FontWeight.w500)
                  .copyWith(color: over ? overColor : theme.muted),
            ),
          ],
        ),
      ),
    );
  }
}
