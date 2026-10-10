// Port of Sources/Grove/Layouts/RootView.swift: the window. The screen
// switch picks what fills it. A phone gets the same parts in another place.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/ambient_background.dart';
import '../theme/grove_theme.dart';
import '../theme/panel.dart';
import 'appearance_button.dart';
import 'left_dock.dart';
import 'screen_switch.dart';
import 'shell_layout.dart';
import 'shell_model.dart';

/// Builds a screen. null leaves the stand-in of the shell in place.
typedef ScreenBuilder = Widget? Function(BuildContext context, Screen screen);

/// Builds a left panel. null leaves the stand-in of the shell in place.
typedef PaneBuilder = Widget? Function(BuildContext context, LeftPane pane);

class RootView extends StatelessWidget {
  const RootView({
    super.key,
    required this.model,
    this.screenBuilder,
    this.paneBuilder,
    this.shortcuts,
  });

  final ShellModel model;
  final ScreenBuilder? screenBuilder;
  final PaneBuilder? paneBuilder;

  /// More shortcuts for the whole window, for example Undo.
  final Map<ShortcutActivator, VoidCallback>? shortcuts;

  /// The shortcuts of the View menu of the Mac app. Command on Apple
  /// devices, Ctrl on the others.
  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    final apple =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    SingleActivator key(LogicalKeyboardKey key) =>
        SingleActivator(key, meta: apple, control: !apple);
    return {
      key(LogicalKeyboardKey.keyT): model.showToday,
      key(LogicalKeyboardKey.digit1): () => model.screen = Screen.planner,
      key(LogicalKeyboardKey.digit2): model.showTasks,
      key(LogicalKeyboardKey.digit3): () => model.screen = Screen.calendar,
      key(LogicalKeyboardKey.digit4): () => model.screen = Screen.notes,
      key(LogicalKeyboardKey.digit5): () => model.screen = Screen.garden,
      ...?shortcuts,
    };
  }

  Widget _screen(BuildContext context) => SizedBox.expand(
    key: ValueKey('content-${model.screen.name}'),
    child:
        screenBuilder?.call(context, model.screen) ??
        _ScreenStandIn(model.screen),
  );

  Widget _pane(BuildContext context, LeftPane pane) =>
      paneBuilder?.call(context, pane) ?? _PaneStandIn(pane);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) {
      final theme = GroveTheme.of(context);
      final width = MediaQuery.sizeOf(context).width;
      final layout = ShellRules.layoutFor(width);
      final pane = LeftPane.isAvailable(model.screen) ? model.leftPane : null;
      return CallbackShortcuts(
        bindings: _shortcuts,
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: theme.bg,
            body: DefaultTextStyle(
              style: theme.body(13).copyWith(color: theme.ink),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ThemeBackdrop(
                    motion: model.motionSetting,
                    intensity: model.intensity,
                  ),
                  switch (layout) {
                    ShellLayout.desktop => _desktop(context, width, pane),
                    ShellLayout.phone => _phone(context, pane),
                  },
                  _ToastLayer(text: model.toast, layout: layout),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _desktop(BuildContext context, double width, LeftPane? pane) =>
      SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: ShellRules.desktopTopStrip,
              child: Stack(
                children: [
                  Positioned(left: 16, top: 5, child: LeftDock(model: model)),
                  Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: ScreenSwitch(
                        model: model,
                        showLabels: ShellRules.switchShowsLabels(width),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 16,
                    top: 5,
                    child: AppearanceButton(model: model),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (pane != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 16),
                      child: SizedBox(
                        key: ValueKey('pane-${pane.name}'),
                        width: LeftPane.plannerWidth,
                        child: _pane(context, pane),
                      ),
                    ),
                  Expanded(child: _screen(context)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _phone(BuildContext context, LeftPane? pane) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SafeArea(
        bottom: false,
        child: SizedBox(
          height: ShellRules.phoneTopStrip,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                LeftDock(model: model, layout: ShellLayout.phone),
                const Spacer(),
                AppearanceButton(model: model, layout: ShellLayout.phone),
              ],
            ),
          ),
        ),
      ),
      Expanded(
        child: SafeArea(
          top: false,
          bottom: false,
          child: pane == null
              ? _screen(context)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: SizedBox.expand(
                    key: ValueKey('pane-${pane.name}'),
                    child: _pane(context, pane),
                  ),
                ),
        ),
      ),
      _PhoneBar(child: PhoneNavBar(model: model)),
    ],
  );
}

/// The background of the bar at the bottom of a phone. It runs down to the
/// edge of the screen; the buttons stay above the home bar.
class _PhoneBar extends StatelessWidget {
  const _PhoneBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.glass ? theme.surface : theme.solidSurface,
        border: Border(top: BorderSide(color: theme.line)),
      ),
      child: SafeArea(top: false, child: child),
    );
  }
}

/// A short message at the bottom of the window. Swift: `ToastView`.
class _ToastLayer extends StatelessWidget {
  const _ToastLayer({required this.text, required this.layout});

  final String? text;
  final ShellLayout layout;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final text = this.text;
    final lift = layout == ShellLayout.phone ? ShellRules.phoneNavBar : 0.0;
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(bottom: 20 + lift),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.6),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: text == null
                  ? const SizedBox.shrink()
                  : Semantics(
                      key: ValueKey(text),
                      liveRegion: true,
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          color: theme.ink,
                          shape: const StadiumBorder(),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          child: Text(
                            text,
                            style: theme
                                .body(12, weight: FontWeight.w600)
                                .copyWith(color: theme.bg),
                          ),
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

/// What a screen shows until its milestone builds it.
class _ScreenStandIn extends StatelessWidget {
  const _ScreenStandIn(this.screen);

  final Screen screen;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Panel(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 10,
              children: [
                Icon(screenIcon(screen), size: 28, color: theme.accent),
                ThemedHeading(screen.title, 28),
                Text(
                  'This screen is not built yet.',
                  textAlign: TextAlign.center,
                  style: theme.body(13).copyWith(color: theme.muted),
                ),
                ThemedChip(
                  tint: theme.accent2,
                  child: Text(
                    'Coming soon',
                    style: theme.body(11).copyWith(color: theme.accent2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What a left panel shows until its milestone builds it.
class _PaneStandIn extends StatelessWidget {
  const _PaneStandIn(this.pane);

  final LeftPane pane;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return Panel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            ThemedHeading(pane.title, 16),
            Text(
              'This panel is not built yet.',
              style: theme.body(13).copyWith(color: theme.muted),
            ),
          ],
        ),
      ),
    );
  }
}
