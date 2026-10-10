import 'package:flutter/material.dart';

import 'shell/root_view.dart';
import 'shell/shell_model.dart';
import 'theme/grove_theme.dart';

/// The app: the theme and the shell around every screen.
///
/// With no `model` the app makes one that lives in memory. The builders put
/// real screens and panels in place of the stand-ins of the shell.
class GroveApp extends StatefulWidget {
  const GroveApp({super.key, this.model, this.screenBuilder, this.paneBuilder});

  final ShellModel? model;
  final ScreenBuilder? screenBuilder;
  final PaneBuilder? paneBuilder;

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
        home: RootView(
          model: model,
          screenBuilder: widget.screenBuilder,
          paneBuilder: widget.paneBuilder,
        ),
      ),
    );
  }
}
