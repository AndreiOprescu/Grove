// Port of `PaletteButton` and `SettingsButton` of Sources/Grove/Shared/
// CommandPalette.swift: the "Search" pill and the gear at the top right.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/grove_theme.dart';
import '../theme/symbols.dart';
import 'shell_button.dart';
import 'shell_layout.dart';

/// How a shortcut of the Mac app is written on this system.
abstract final class KeyNames {
  /// True on a Mac, an iPhone and an iPad: the Command key. On the other
  /// systems Ctrl does the same.
  static bool get apple =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// `mac` is the Mac way, like `⌘N`, `⌥⌘N` or `⇧⌘N`. On the other systems
  /// it is `Ctrl+N`, `Ctrl+Alt+N` or `Ctrl+Shift+N`.
  static String of(String mac, {bool? apple}) {
    if (apple ?? KeyNames.apple) return mac;
    const marks = {'⌘': 'Ctrl', '⌥': 'Alt', '⇧': 'Shift', '⌃': 'Ctrl'};
    final key = mac.split('').where((c) => !marks.containsKey(c)).join();
    return [
      // The order a Windows menu uses.
      for (final mark in const ['⌘', '⌥', '⇧'])
        if (mac.contains(mark)) marks[mark]!,
      key,
    ].join('+');
  }
}

/// The small "Search ⌘K" pill in the strip at the top of the window. A
/// phone gets the picture only.
class SearchButton extends StatelessWidget {
  const SearchButton({
    super.key,
    required this.onTap,
    this.layout = ShellLayout.desktop,
  });

  final VoidCallback onTap;
  final ShellLayout layout;

  /// The shortcut, the Mac way.
  static const shortcut = '⌘K';

  static String get tooltip => 'Search and commands (${KeyNames.of(shortcut)})';

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final phone = layout == ShellLayout.phone;
    final size = ShellRules.dockButton(layout);
    return ShellButton(
      key: const ValueKey('search-button'),
      label: 'Search',
      selected: false,
      tooltip: tooltip,
      onTap: onTap,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: theme.surface2,
          shape: StadiumBorder(side: BorderSide(color: theme.line)),
        ),
        child: phone
            ? SizedBox(
                width: size.width + 4,
                height: size.height + 4,
                child: Icon(
                  symbolIcon('magnifyingglass'),
                  size: 20,
                  color: theme.muted,
                ),
              )
            : SizedBox(
                // As high as the screen switch.
                height: size.height + 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 6,
                    children: [
                      Icon(
                        symbolIcon('magnifyingglass'),
                        size: 14,
                        color: theme.muted,
                      ),
                      Text(
                        'Search',
                        style: theme.body(12).copyWith(color: theme.muted),
                      ),
                      Text(
                        KeyNames.of(shortcut),
                        style: theme
                            .body(10, weight: FontWeight.w600)
                            .copyWith(color: theme.muted),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// The gear next to the search pill. It opens the Settings window, the
/// same as ⌘ and comma.
class SettingsButton extends StatelessWidget {
  const SettingsButton({
    super.key,
    required this.onTap,
    this.layout = ShellLayout.desktop,
  });

  final VoidCallback onTap;
  final ShellLayout layout;

  /// The shortcut, the Mac way.
  static const shortcut = '⌘,';

  static String get tooltip => 'Settings (${KeyNames.of(shortcut)})';

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final phone = layout == ShellLayout.phone;
    // A circle as high as the other buttons of the strip.
    final side = ShellRules.dockButton(layout).height + 4;
    return ShellButton(
      key: const ValueKey('settings-button'),
      label: 'Settings',
      selected: false,
      tooltip: tooltip,
      onTap: onTap,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: theme.surface2,
          shape: CircleBorder(side: BorderSide(color: theme.line)),
        ),
        child: SizedBox.square(
          dimension: side,
          child: Icon(
            symbolIcon('gearshape'),
            size: phone ? 20 : 14,
            color: theme.muted,
          ),
        ),
      ),
    );
  }
}
