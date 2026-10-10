// The button at the top right: a menu with the four themes, light or dark,
// and the motion switch. The same choices as the Appearance settings of the
// Mac app (PLAN §5.8).
import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/grove_theme.dart';
import '../theme/theme_spec.dart';
import 'shell_button.dart';
import 'shell_layout.dart';
import 'shell_model.dart';

class AppearanceButton extends StatelessWidget {
  const AppearanceButton({
    super.key,
    required this.model,
    this.layout = ShellLayout.desktop,
  });

  final ShellModel model;
  final ShellLayout layout;

  static const tooltip = 'Theme and appearance';

  void _open(BuildContext context) {
    final theme = GroveTheme.of(context);
    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final below = Rect.fromPoints(
      button.localToGlobal(button.size.bottomLeft(Offset.zero)),
      button.localToGlobal(button.size.bottomRight(const Offset(0, 6))),
    );

    PopupMenuItem<void> item(
      String text, {
      required bool checked,
      required VoidCallback onTap,
    }) => PopupMenuItem<void>(
      height: 40,
      onTap: onTap,
      child: Row(
        spacing: 10,
        children: [
          SizedBox(
            width: 16,
            child: checked
                ? Icon(Icons.check, size: 16, color: theme.accent)
                : null,
          ),
          Text(text),
        ],
      ),
    );

    unawaited(
      showMenu<void>(
        context: context,
        position: RelativeRect.fromRect(below, Offset.zero & overlay.size),
        items: [
          for (final spec in ThemeSpec.all)
            item(
              spec.name,
              checked: model.themeId == spec.id,
              onTap: () => model.setTheme(spec.id),
            ),
          const PopupMenuDivider(),
          for (final mode in AppearanceMode.values)
            item(
              mode.label,
              checked: model.appearance == mode,
              onTap: () => model.setAppearance(mode),
            ),
          const PopupMenuDivider(),
          item(
            'Motion',
            checked: model.motionSetting,
            onTap: () => model.setMotion(!model.motionSetting),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = ShellRules.dockButton(layout);
    return ShellButton(
      label: 'Appearance',
      selected: false,
      tooltip: tooltip,
      onTap: () => _open(context),
      child: PillGroup(
        children: [
          Pill(
            selected: false,
            child: (foreground) => SizedBox.fromSize(
              size: size,
              child: Icon(
                Icons.palette_outlined,
                size: layout == ShellLayout.phone ? 20 : 14,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
