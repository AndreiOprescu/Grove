// Colours that the data names with a word. Ports of `Theme.color(named:)`
// and `Theme.blockColorNames` (Theme.swift), `TaskPalette` and
// `TaskFormat.priorityColor` (TaskRow.swift).
import 'package:flutter/painting.dart';

import 'grove_theme.dart';

/// The eight colours a task can have. The names are stored
/// (`TaskColor.names`), so the colours stay the same in every theme.
abstract final class TaskPalette {
  static const _colors = {
    'red': Color.from(alpha: 1, red: 0.90, green: 0.30, blue: 0.30),
    'orange': Color.from(alpha: 1, red: 0.96, green: 0.58, blue: 0.20),
    'yellow': Color.from(alpha: 1, red: 0.93, green: 0.76, blue: 0.20),
    'green': Color.from(alpha: 1, red: 0.34, green: 0.70, blue: 0.40),
    'teal': Color.from(alpha: 1, red: 0.18, green: 0.66, blue: 0.66),
    'blue': Color.from(alpha: 1, red: 0.30, green: 0.54, blue: 0.90),
    'purple': Color.from(alpha: 1, red: 0.62, green: 0.44, blue: 0.85),
    'pink': Color.from(alpha: 1, red: 0.92, green: 0.44, blue: 0.70),
  };

  /// The colour for a stored name, or null for "" and unknown names.
  static Color? color(String name) => _colors[name];
}

/// The colour of a priority: green, yellow, red. The same in every theme.
abstract final class PriorityColors {
  static const low = Color.from(alpha: 1, red: 0.20, green: 0.72, blue: 0.35);
  static const medium = Color.from(
    alpha: 1,
    red: 0.98,
    green: 0.80,
    blue: 0.10,
  );
  static const high = Color.from(alpha: 1, red: 0.92, green: 0.18, blue: 0.18);

  /// The border around a task or a block that has a priority.
  static const borderWidth = 3.5;

  /// null when the priority is not 1, 2 or 3.
  static Color? color(int priority) => switch (priority) {
    1 => low,
    2 => medium,
    3 => high,
    _ => null,
  };
}

extension NamedColors on GroveTheme {
  /// The names in the "Colour" entry of a block's menu.
  static const blockColorNames = ['accent', 'accent2', 'accent3', 'muted'];

  /// The colour of an event or a block. A theme word gives a theme colour.
  /// A task colour word gives that colour. Anything else gives `accent2`.
  Color color(String named) => switch (named) {
    'accent' => accent,
    'accent3' => accent3,
    'muted' => muted,
    _ => TaskPalette.color(named) ?? accent2,
  };
}
