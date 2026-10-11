// The app on a real store: the shell, the screens that are built, and the
// shortcuts that need the store. `main.dart` and the integration test both
// start here. It places the Settings window, the sync mark and the question
// of the first login too.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:grove/core/parsing/palette_rules.dart' show PaletteCommandId;
import 'package:grove/state/state.dart' hide MotionRules;

import 'app.dart';
import 'auth/first_sync_dialog.dart';
import 'calendar/event_editor.dart';
import 'editor/editor_tools.dart';
import 'garden/garden_view.dart';
import 'notes/notes_pane.dart';
import 'notes/notes_view.dart';
import 'planner/planner_kind.dart';
import 'planner/planner_view.dart';
import 'settings/settings_view.dart';
import 'settings/sync_mark.dart';
import 'shell/app_menus.dart';
import 'shell/command_palette.dart';
import 'shell/error_alert.dart';
import 'shell/store_shell_model.dart';
import 'spread/day_spread_view.dart';
import 'tasks/store_panes.dart';

class StoreApp extends StatefulWidget {
  const StoreApp({
    super.key,
    required this.store,
    this.files,
    this.pickImages,
    this.openLink,
  });

  /// The one who made the store closes it.
  final AppStore store;

  /// The file windows for "Export" and "Import" in Settings. With null the
  /// two buttons are hidden. `main.dart` gives the real ones; a test gives
  /// a fake or none, so no test opens a real window.
  final SettingsFiles? files;

  /// The window to pick pictures, for "Add an image" in a note and in the
  /// notes of an event. With null the button is hidden.
  final ImagePicker? pickImages;

  /// Opens a web link of a note in the browser. With null a click on a web
  /// link does nothing.
  final LinkOpener? openLink;

  @override
  State<StoreApp> createState() => _StoreAppState();
}

class _StoreAppState extends State<StoreApp> {
  late StoreShellModel _model = StoreShellModel(widget.store);

  /// Settings is open. A second key press does not open a second window.
  bool _settingsOpen = false;

  void _openSettings(
    BuildContext context, {
    SettingsTab tab = SettingsTab.appearance,
  }) {
    if (_settingsOpen) return;
    _settingsOpen = true;
    unawaited(
      showSettings(
        context,
        widget.store,
        tab: tab,
        files: widget.files,
      ).whenComplete(() => _settingsOpen = false),
    );
  }

  @override
  void didUpdateWidget(StoreApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _model = StoreShellModel(widget.store);
    }
  }

  /// What the menus of the Mac app do with the store. The shell gives
  /// each line its key (Command on Apple devices, Ctrl on the others). A
  /// text field keeps its own undo.
  ShellCommands _commands() {
    final store = widget.store;
    return ShellCommands(
      newTask: () => store.run(PaletteCommandId.newTask),
      newNote: store.newNote,
      newEvent: store.newEventNow,
      palette: store.togglePalette,
      undo: store.undoName == null ? null : store.undo,
      redo: store.redoName == null ? null : store.redo,
      undoName: store.undoName,
      redoName: store.redoName,
      zoomIn: () => store.zoomPlanner(zoomStep),
      zoomOut: () => store.zoomPlanner(1 / zoomStep),
    );
  }

  /// The keys that are in no menu.
  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    final store = widget.store;
    final apple =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    return {
      // Redo the Windows way.
      if (!apple)
        const SingleActivator(LogicalKeyboardKey.keyY, control: true):
            store.redo,
      // Escape closes the command palette, and then the panel of the chosen
      // task, from any place. A field or a screen that uses Escape itself
      // takes the key first.
      const SingleActivator(LogicalKeyboardKey.escape): () {
        if (store.paletteOpen) {
          store.paletteOpen = false;
        } else if (store.selectedTaskId != null) {
          store.selectedTaskId = null;
        }
      },
    };
  }

  Widget? _screen(BuildContext context, Screen screen) {
    final store = widget.store;
    final view = _view(screen);
    // The card of an event opens over each screen.
    // The Notes screen has no planner, so the card asks the question of a
    // series there by itself.
    return view == null
        ? null
        : EventEditorHost(
            store: store,
            asksScope: screen == Screen.notes,
            child: view,
          );
  }

  Widget? _view(Screen screen) {
    final store = widget.store;
    return switch (screen) {
      // The panel of the chosen task is at the side of each screen (F8).
      Screen.planner => InspectorHost(
        store: store,
        child: PlannerView(store: store, kind: PlannerKind.week),
      ),
      // The Day Spread has its own place for the panel of the chosen task.
      Screen.today => DaySpreadView(store: store),
      Screen.calendar => InspectorHost(
        store: store,
        child: PlannerView(store: store, kind: PlannerKind.month),
      ),
      Screen.notes => InspectorHost(
        store: store,
        child: NotesView(store: store),
      ),
      Screen.garden => GardenView(store: store),
    };
  }

  /// The notes in the left panel are a part of the screens (Track B). The
  /// other panels come from `storePane`.
  Widget? _pane(BuildContext context, LeftPane pane) => pane == LeftPane.notes
      ? NotesPane(store: widget.store)
      : storePane(context, widget.store, pane);

  @override
  Widget build(BuildContext context) => EditorTools(
    pickImages: widget.pickImages,
    openLink: widget.openLink,
    child: _app(context),
  );

  Widget _app(BuildContext context) => GroveApp(
    model: _model,
    screenBuilder: _screen,
    paneBuilder: _pane,
    shortcuts: _shortcuts,
    commands: _commands,
    onSettings: _openSettings,
    // The mark shows nothing in a copy of Grove with no sync.
    topActions: (context, layout) => SyncMark(
      store: widget.store,
      layout: layout,
      onTap: () => _openSettings(context, tab: SettingsTab.sync),
    ),
    // The question of the first login and an error message open over each
    // screen. So does the command palette.
    homeBuilder: (context, home) => FirstSyncGate(
      store: widget.store,
      child: ErrorGate(
        store: widget.store,
        child: PaletteHost(store: widget.store, child: home),
      ),
    ),
  );
}
