// Port of Sources/Grove/Layouts/ScreenSwitch.swift, and the same choice as
// a bar at the bottom of a phone.
import 'dart:math' as math;

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
  Screen.goals => Icons.account_tree_outlined,
  Screen.notes => Icons.sticky_note_2_outlined,
  Screen.garden => Icons.eco_outlined,
  Screen.persona => Icons.person_outline,
  Screen.agents => Icons.auto_awesome_outlined,
};

/// The screens of the window, in the strip at the top of a desktop window.
/// A narrow window shows the pictures only.
class ScreenSwitch extends StatelessWidget {
  const ScreenSwitch({super.key, required this.model, this.showLabels = true});

  final ShellModel model;
  final bool showLabels;

  /// The width of the switch with a word beside each picture. The words
  /// are measured in the bold style, the widest one.
  static double labelledWidth(
    GroveTheme theme,
    TextScaler scaler, [
    List<Screen> screens = Screen.always,
  ]) {
    var width = 2.0 * 2 + 2 * 1 + 2.0 * (screens.length - 1);
    for (final screen in screens) {
      final text = TextPainter(
        text: TextSpan(
          text: screen.title,
          style: theme.body(12, weight: FontWeight.w600).copyWith(height: 1.2),
        ),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      width += 12 + 14 + 6 + text.width.ceilToDouble() + 12;
      text.dispose();
    }
    return width;
  }

  @override
  Widget build(BuildContext context) {
    if (!showLabels) return _switch(context, labels: false);
    return LayoutBuilder(
      builder: (context, box) {
        final need = labelledWidth(
          GroveTheme.of(context),
          MediaQuery.textScalerOf(context),
          model.screens,
        );
        return _switch(context, labels: need <= box.maxWidth);
      },
    );
  }

  Widget _switch(BuildContext context, {required bool labels}) {
    final theme = GroveTheme.of(context);
    final showLabels = labels;
    return PillGroup(
      children: [
        for (final screen in model.screens)
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

  /// True when the widest word of the bar fits in a tab. If it does not,
  /// only the selected tab shows its word, and it may be clipped there.
  static bool wordsFit(
    GroveTheme theme,
    TextScaler scaler,
    List<Screen> screens,
    double width,
  ) {
    if (screens.isEmpty) return true;
    var widest = 0.0;
    for (final screen in screens) {
      final text = TextPainter(
        text: TextSpan(
          text: screen.title,
          style: theme.body(10, weight: FontWeight.w600).copyWith(height: 1.2),
        ),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      widest = math.max(widest, text.width);
      text.dispose();
    }
    return widest <= width / screens.length - 2;
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return SizedBox(
      height: ShellRules.phoneNavBar,
      child: LayoutBuilder(
        builder: (context, box) {
          final fit = wordsFit(
            theme,
            MediaQuery.textScalerOf(context),
            model.screens,
            box.maxWidth,
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final screen in model.screens)
                Expanded(
                  child: ShellButton(
                    key: ValueKey('screen-${screen.name}'),
                    label: screen.title,
                    selected: model.screen == screen,
                    onTap: () => model.screen = screen,
                    child: _NavItem(
                      screen: screen,
                      color: model.screen == screen
                          ? theme.accent
                          : theme.muted,
                      selected: model.screen == screen,
                      showWord: fit || model.screen == screen,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.screen,
    required this.color,
    required this.selected,
    required this.showWord,
  });

  final Screen screen;
  final Color color;
  final bool selected;
  final bool showWord;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 3,
      children: [
        Icon(screenIcon(screen), size: 22, color: color),
        if (showWord)
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
