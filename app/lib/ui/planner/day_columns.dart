// The day columns of the header and of the strip of notes. They start on the
// same whole points as the day columns of the grid.
import 'dart:math';

import 'package:flutter/widgets.dart';

import 'planner_geometry.dart';

/// [children] as the day columns of a row that is [width] wide. The last
/// column takes the space that is left, so the row is always full.
List<Widget> dayColumns(double width, List<Widget> children) {
  final dayWidth = width / max(children.length, 1);
  return [
    for (final (index, child) in children.indexed)
      if (index == children.length - 1)
        Expanded(child: child)
      else
        SizedBox(
          width: PlannerGeometry.dayWidthAt(dayWidth, index),
          child: child,
        ),
  ];
}
