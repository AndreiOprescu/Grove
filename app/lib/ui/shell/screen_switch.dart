// Port of Sources/Grove/Layouts/ScreenSwitch.swift, and the same choice as
// a bar at the bottom of a phone.
import 'package:flutter/material.dart';

import '../theme/grove_theme.dart';
import 'shell_button.dart';
import 'shell_layout.dart';
import 'shell_model.dart';

/// The picture of a screen in the switch.
IconData screenIcon(Screen screen) => switch (screen) {
  Screen.today => Icons.wb_sunny_outlined,
  Screen.planner => Icons.view_timeline_outlined,
  Screen.calendar => Icons.calendar_month_outlined,
  Screen.notes => Icons.sticky_note_2_outlined,
  Screen.garden => Icons.eco_outlined,
};

/// The screens of the window, in the strip at the top of a desktop window.
/// A narrow window shows the pictures only.
class ScreenSwitch extends StatelessWidget {
  const ScreenSwitch({super.key, required this.model, this.showLabels = true});

  final ShellModel model;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return PillGroup(
      children: [
        for (final screen in Screen.values)
          ShellButton(
            key: ValueKey('screen-${screen.name}'),
            label: screen.title,
            selected: model.screen == screen,
            tooltip: showLabels ? null : screen.title,
            onTap: () => model.screen = screen,
            child: Pill(
              selected: model.screen == screen,
              child: (foreground) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    Icon(screenIcon(screen), size: 14, color: foreground),
                    if (showLabels)
                      Text(
                        screen.title,
                        style: theme
                            .body(
                              12,
                              weight: model.screen == screen
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            )
                            .copyWith(color: foreground, height: 1.2),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The screens as a row of buttons at the bottom of a phone. Each button is
/// big enough for a finger.
class PhoneNavBar extends StatelessWidget {
  const PhoneNavBar({super.key, required this.model});

  final ShellModel model;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return SizedBox(
      height: ShellRules.phoneNavBar,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final screen in Screen.values)
            Expanded(
              child: ShellButton(
                key: ValueKey('screen-${screen.name}'),
                label: screen.title,
                selected: model.screen == screen,
                onTap: () => model.screen = screen,
                child: _NavItem(
                  screen: screen,
                  color: model.screen == screen ? theme.accent : theme.muted,
                  selected: model.screen == screen,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.screen,
    required this.color,
    required this.selected,
  });

  final Screen screen;
  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 3,
      children: [
        Icon(screenIcon(screen), size: 22, color: color),
        Text(
          screen.title,
          maxLines: 1,
          overflow: TextOverflow.clip,
          softWrap: false,
          style: theme
              .body(10, weight: selected ? FontWeight.w600 : FontWeight.w400)
              .copyWith(color: color, height: 1.2),
        ),
      ],
    );
  }
}
