import 'package:flutter/material.dart';

import 'shell/root_view.dart';
import 'shell/shell_model.dart';
import 'theme/grove_theme.dart';

/// The app: the theme and the shell around every screen.
///
/// With no `model` the app makes one that lives in memory. The builders put
/// real screens and panels in place of the stand-ins of the shell.
class GroveApp extends StatefulWidget {
  const GroveApp({
    super.key,
    this.model,
    this.screenBuilder,
    this.paneBuilder,
    this.shortcuts,
    this.onSettings,
    this.topActions,
    this.homeBuilder,
  });

  final ShellModel? model;
  final ScreenBuilder? screenBuilder;
  final PaneBuilder? paneBuilder;

  /// More shortcuts for the whole window, for example Undo.
  final Map<ShortcutActivator, VoidCallback>? shortcuts;

  /// Opens the Settings window. See `RootView.onSettings`.
  final void Function(BuildContext context)? onSettings;

  /// See `RootView.topActions`.
  final TopActionBuilder? topActions;

  /// Puts a widget around the window, under the navigator. For a thing that
  /// opens a dialog by itself.
  final Widget Function(BuildContext context, Widget home)? homeBuilder;

  @override
  State<GroveApp> createState() => _GroveAppState();
}

class _GroveAppState extends State<GroveApp> {
  /// The model this state made because the widget gave none.
  LocalShellModel? _own;

  ShellModel get _model => widget.model ?? (_own ??= LocalShellModel());

  @override
  void didUpdateWidget(GroveApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.model != null) {
      _own?.dispose();
      _own = null;
    }
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = _model;
    final homeBuilder = widget.homeBuilder;
    final Widget root = RootView(
      model: model,
      screenBuilder: widget.screenBuilder,
      paneBuilder: widget.paneBuilder,
      shortcuts: widget.shortcuts,
      onSettings: widget.onSettings,
      topActions: widget.topActions,
    );
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => MaterialApp(
        title: 'Grove',
        debugShowCheckedModeBanner: false,
        theme: GroveTheme.make(model.themeId, Brightness.light).toMaterial(),
        darkTheme: GroveTheme.make(model.themeId, Brightness.dark).toMaterial(),
        themeMode: switch (model.appearance.brightness) {
          null => ThemeMode.system,
          Brightness.light => ThemeMode.light,
          Brightness.dark => ThemeMode.dark,
        },
        themeAnimationDuration: AnimatedGroveTheme.crossFade,
        themeAnimationCurve: Curves.easeInOut,
        // Above the navigator, so menus and dialogs get the theme too.
        builder: (context, child) => AnimatedGroveTheme(
          theme: GroveTheme.make(
            model.themeId,
            model.appearance.brightness ??
                MediaQuery.platformBrightnessOf(context),
          ),
          child: child!,
        ),
        home: homeBuilder == null
            ? root
            : Builder(builder: (context) => homeBuilder(context, root)),
      ),
    );
  }
}
