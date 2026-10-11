// Port of Sources/Grove/Layouts/RootView.swift: the window. The screen
// switch picks what fills it. A phone gets the same parts in another place.
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/ambient_background.dart';
import '../theme/grove_theme.dart';
import '../theme/panel.dart';
import 'appearance_button.dart';
import 'left_dock.dart';
import 'screen_switch.dart';
import 'shell_layout.dart';
import 'shell_model.dart';
import 'top_buttons.dart';

/// Builds a screen. null leaves the stand-in of the shell in place.
typedef ScreenBuilder = Widget? Function(BuildContext context, Screen screen);

/// Builds a left panel. null leaves the stand-in of the shell in place.
typedef PaneBuilder = Widget? Function(BuildContext context, LeftPane pane);

/// Builds what stands in front of the Appearance button.
typedef TopActionBuilder = Widget? Function(
  BuildContext context,
  ShellLayout layout,
);

class RootView extends StatelessWidget {
  const RootView({
    super.key,
    required this.model,
    this.screenBuilder,
    this.paneBuilder,
    this.onSearch,
    this.onSettings,
    this.topActions,
  });

  final ShellModel model;
  final ScreenBuilder? screenBuilder;
  final PaneBuilder? paneBuilder;

  /// Opens the command palette. With null there is no "Search" button.
  final VoidCallback? onSearch;

  /// Opens the Settings window. With null there is no "Settings…" in the
  /// menu and no gear.
  final void Function(BuildContext context)? onSettings;

  /// A small thing in front of the Appearance button, for example the sync
  /// mark. null shows nothing.
  final TopActionBuilder? topActions;

  /// From the left edge of a desktop window to the left dock. On a Mac
  /// the three window buttons take the first 84 points (Swift: the same).
  static double get dockLeft =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS ? 84 : 16;

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
      // The keys of the window are in `GroveApp`, over the navigator.
      return Focus(
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
      );
    },
  );

  /// Swift: the search pill and the gear. The sync mark and the Appearance
  /// button stand between them here.
  Widget _topRight(BuildContext context, ShellLayout layout) {
    final onSearch = this.onSearch;
    final onSettings = this.onSettings;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        if (onSearch != null) SearchButton(onTap: onSearch, layout: layout),
        ?topActions?.call(context, layout),
        AppearanceButton(
          model: model,
          layout: layout,
          onSettings: onSettings == null ? null : () => onSettings(context),
        ),
        // A phone has no room for the gear. "Settings…" is the last line of
        // the Appearance menu there.
        if (onSettings != null && layout == ShellLayout.desktop)
          SettingsButton(onTap: () => onSettings(context), layout: layout),
      ],
    );
  }

  Widget _desktop(BuildContext context, double width, LeftPane? pane) =>
      SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: ShellRules.desktopTopStrip,
              child: CustomMultiChildLayout(
                delegate: _TopStrip(dockLeft: dockLeft),
                children: [
                  LayoutId(
                    id: _StripPart.dock,
                    child: LeftDock(model: model),
                  ),
                  LayoutId(
                    id: _StripPart.screens,
                    child: ScreenSwitch(
                      model: model,
                      showLabels: ShellRules.switchShowsLabels(width),
                    ),
                  ),
                  LayoutId(
                    id: _StripPart.buttons,
                    child: _topRight(context, ShellLayout.desktop),
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
                _topRight(context, ShellLayout.phone),
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

enum _StripPart { dock, screens, buttons }

/// Places the three parts of the strip at the top of a desktop window. The
/// screen switch is in the middle of the window (Swift: the same). When
/// the buttons at a side reach into the middle, the switch moves away from
/// them: no part covers another.
class _TopStrip extends MultiChildLayoutDelegate {
  _TopStrip({required this.dockLeft});

  final double dockLeft;

  /// Swift: 5 points from the top, 16 from the right edge.
  static const top = 5.0;
  static const right = 16.0;

  /// The least room between the switch and the buttons next to it.
  static const gap = 8.0;

  @override
  void performLayout(Size size) {
    final loose = BoxConstraints.loose(size);
    final dock = layoutChild(_StripPart.dock, loose);
    positionChild(_StripPart.dock, Offset(dockLeft, top));
    final buttons = layoutChild(_StripPart.buttons, loose);
    final buttonsLeft = size.width - right - buttons.width;
    positionChild(_StripPart.buttons, Offset(buttonsLeft, top));
    final screens = layoutChild(_StripPart.screens, loose);
    // On a whole point, also in a window of an odd width.
    var left = ((size.width - screens.width) / 2).floorToDouble();
    left = math.min(left, buttonsLeft - gap - screens.width);
    left = math.max(left, dockLeft + dock.width + gap);
    positionChild(_StripPart.screens, Offset(left, top));
  }

  @override
  bool shouldRelayout(_TopStrip old) => old.dockLeft != dockLeft;
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
