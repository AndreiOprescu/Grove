// Port of the `LeftDock` view of Sources/Grove/Layouts/LeftDock.swift.
import 'package:flutter/material.dart';

import 'shell_button.dart';
import 'shell_layout.dart';
import 'shell_model.dart';

/// The picture of a left panel on its dock button.
IconData paneIcon(LeftPane pane) => switch (pane) {
  LeftPane.notes => Icons.sticky_note_2_outlined,
  LeftPane.tasks => Icons.checklist,
  LeftPane.goals => Icons.track_changes,
};

/// Three small buttons at the top left, level with the screen switch. Each
/// opens its panel; a click on the open one closes it. Only the Today and
/// Planner screens have them.
class LeftDock extends StatelessWidget {
  const LeftDock({
    super.key,
    required this.model,
    this.layout = ShellLayout.desktop,
  });

  final ShellModel model;
  final ShellLayout layout;

  @override
  Widget build(BuildContext context) {
    if (!LeftPane.isAvailable(model.screen)) return const SizedBox.shrink();
    final size = ShellRules.dockButton(layout);
    return PillGroup(
      children: [
        for (final pane in LeftPane.values)
          ShellButton(
            key: ValueKey('dock-${pane.name}'),
            label: pane.title,
            selected: model.leftPane == pane,
            tooltip: pane.tooltip(isOpen: model.leftPane == pane),
            onTap: () => model.toggleLeftPane(pane),
            child: Pill(
              selected: model.leftPane == pane,
              child: (foreground) => SizedBox.fromSize(
                size: size,
                child: Icon(
                  paneIcon(pane),
                  size: layout == ShellLayout.phone ? 20 : 14,
                  color: foreground,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
