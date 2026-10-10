// The app on a real store: the shell, the screens that are built, and the
// shortcuts that need the store. `main.dart` and the integration test both
// start here.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import 'app.dart';
import 'planner/planner_kind.dart';
import 'planner/planner_view.dart';
import 'shell/store_shell_model.dart';

class StoreApp extends StatefulWidget {
  const StoreApp({super.key, required this.store});

  /// The one who made the store closes it.
  final AppStore store;

  @override
  State<StoreApp> createState() => _StoreAppState();
}

class _StoreAppState extends State<StoreApp> {
  late StoreShellModel _model = StoreShellModel(widget.store);

  @override
  void didUpdateWidget(StoreApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _model = StoreShellModel(widget.store);
    }
  }

  /// Undo and Redo, as in the Edit menu of the Mac app. Command on Apple
  /// devices, Ctrl on the others. A text field keeps its own undo.
  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    final store = widget.store;
    final apple =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    const z = LogicalKeyboardKey.keyZ;
    return {
      SingleActivator(z, meta: apple, control: !apple): store.undo,
      SingleActivator(z, meta: apple, control: !apple, shift: true): store.redo,
      if (!apple)
        const SingleActivator(LogicalKeyboardKey.keyY, control: true):
            store.redo,
    };
  }

  Widget? _screen(BuildContext context, Screen screen) {
    final store = widget.store;
    return switch (screen) {
      Screen.planner => PlannerView(store: store, kind: PlannerKind.week),
      // The timeline of today. The other parts of the Day Spread come with
      // milestone F9.
      Screen.today => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: PlannerView(store: store, kind: PlannerKind.today),
          ),
        ),
      ),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) =>
      GroveApp(model: _model, screenBuilder: _screen, shortcuts: _shortcuts);
}
