// The small buttons of the app shell and the capsule that holds a row of
// them.
import 'package:flutter/material.dart';

import '../theme/grove_theme.dart';

/// A button of the shell. It tells a screen reader its name and if it is
/// the chosen one. `child` is what it looks like.
class ShellButton extends StatelessWidget {
  const ShellButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
    this.tooltip,
  });

  /// The name a screen reader says.
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  /// Shown when the pointer rests on the button. None when null.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    Widget button = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: child,
      ),
    );
    final tooltip = this.tooltip;
    if (tooltip != null) {
      button = Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: button,
      );
    }
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      selected: selected,
      label: label,
      tooltip: tooltip,
      onTap: onTap,
      child: button,
    );
  }
}

/// A capsule that holds a row of buttons: the screen switch and the left
/// dock.
class PillGroup extends StatelessWidget {
  const PillGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: theme.surface2,
        shape: StadiumBorder(side: BorderSide(color: theme.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 2,
          children: children,
        ),
      ),
    );
  }
}

/// One button of a [PillGroup]: accent colour when chosen.
class Pill extends StatelessWidget {
  const Pill({super.key, required this.selected, required this.child});

  final bool selected;

  /// Built with the colour of the text and the pictures inside.
  final Widget Function(Color foreground) child;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: selected ? theme.accent : null,
        shape: const StadiumBorder(),
      ),
      child: child(selected ? theme.surface : theme.muted),
    );
  }
}
