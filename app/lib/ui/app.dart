import 'package:flutter/material.dart';

import 'shell/app_menus.dart';
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
    this.commands,
    this.onSettings,
    this.topActions,
    this.homeBuilder,
  });

  final ShellModel? model;
  final ScreenBuilder? screenBuilder;
  final PaneBuilder? paneBuilder;

  /// More shortcuts for the whole window, for example Escape. The keys of
  /// the menus come first.
  final Map<ShortcutActivator, VoidCallback>? shortcuts;

  /// What the menus do with the store: New Task, Undo, the command palette.
  /// It is read when a menu is built and when a key comes. With null those
  /// lines are grey and there is no "Search" button.
  final ShellCommands Function()? commands;

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

  final _navigator = GlobalKey<NavigatorState>();

  /// A place inside the first page, to open a dialog from a key or a menu.
  final _home = GlobalKey();

  ShellModel get _model => widget.model ?? (_own ??= LocalShellModel());

  /// False while a dialog or a menu is open over the window.
  bool _isFree() => !(_navigator.currentState?.canPop() ?? false);

  void _openSettings() {
    final context = _home.currentContext;
    if (context != null) widget.onSettings?.call(context);
  }

  /// The commands of the store, with Settings from the shell.
  ShellCommands _commands() {
    final given = widget.commands?.call() ?? const ShellCommands();
    return ShellCommands(
      newTask: given.newTask,
      newNote: given.newNote,
      newEvent: given.newEvent,
      palette: given.palette,
      undo: given.undo,
      redo: given.redo,
      undoName: given.undoName,
      redoName: given.redoName,
      zoomIn: given.zoomIn,
      zoomOut: given.zoomOut,
      settings:
          given.settings ?? (widget.onSettings == null ? null : _openSettings),
    );
  }

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
      onSearch: widget.commands == null
          ? null
          : () => widget.commands?.call().palette?.call(),
      onSettings: widget.onSettings,
      topActions: widget.topActions,
    );
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final commands = _commands();
        return ShellMenuBar(
          menus: shellMenus(model, commands),
          commands: commands,
          isFree: _isFree,
          child: MaterialApp(
            title: 'Grove',
            navigatorKey: _navigator,
            debugShowCheckedModeBanner: false,
            theme: GroveTheme.make(
              model.themeId,
              Brightness.light,
            ).toMaterial(),
            darkTheme: GroveTheme.make(
              model.themeId,
              Brightness.dark,
            ).toMaterial(),
            themeMode: switch (model.appearance.brightness) {
              null => ThemeMode.system,
              Brightness.light => ThemeMode.light,
              Brightness.dark => ThemeMode.dark,
            },
            themeAnimationDuration: AnimatedGroveTheme.crossFade,
            themeAnimationCurve: Curves.easeInOut,
            // Above the navigator, so menus and dialogs get the theme too,
            // and the keys of the menus work wherever the focus is.
            builder: (context, child) => AnimatedGroveTheme(
              theme: GroveTheme.make(
                model.themeId,
                model.appearance.brightness ??
                    MediaQuery.platformBrightnessOf(context),
              ),
              child: ShellKeys(
                entries: () => shellKeys(model, _commands()),
                isFree: _isFree,
                more: widget.shortcuts,
                child: child!,
              ),
            ),
            home: KeyedSubtree(
              key: _home,
              child: homeBuilder == null
                  ? root
                  : Builder(builder: (context) => homeBuilder(context, root)),
            ),
          ),
        );
      },
    );
  }
}
