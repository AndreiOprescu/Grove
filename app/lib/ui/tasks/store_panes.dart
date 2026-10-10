// What the shell shows for the store: the left panels of Tasks and Goals,
// and the panel of the chosen task. `StoreApp` plugs these in.
import 'package:flutter/material.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../goals/goals_pane.dart';
import '../shell/shell_layout.dart';
import 'task_inspector.dart';
import 'task_widgets.dart';
import 'tasks_pane.dart';

/// The left panel for `pane`. null for a panel that is not built yet.
Widget? storePane(BuildContext context, AppStore store, LeftPane pane) =>
    switch (pane) {
      LeftPane.tasks => _PaneOrInspector(
        store: store,
        child: TasksPane(store: store, mode: TasksPaneMode.unscheduled),
      ),
      LeftPane.goals => _PaneOrInspector(
        store: store,
        child: GoalsPane(store: store),
      ),
      LeftPane.notes => null,
    };

bool _isPhone(BuildContext context) =>
    ShellRules.layoutFor(MediaQuery.sizeOf(context).width) == ShellLayout.phone;

/// On a phone an open panel fills the screen. So the panel of the chosen
/// task takes its place there.
class _PaneOrInspector extends StatelessWidget {
  const _PaneOrInspector({required this.store, required this.child});

  final AppStore store;
  final Widget child;

  @override
  Widget build(BuildContext context) => StoreBuilder(
    store: store,
    builder: (context) {
      final id = _isPhone(context) ? store.selectedTaskId : null;
      return _Covered(
        cover: id == null ? null : TaskInspector(store: store, taskId: id),
        child: child,
      );
    },
  );
}

/// Shows `cover` in the place of `child`. The child stays in the tree, so
/// it keeps its scroll position and its open rows.
class _Covered extends StatelessWidget {
  const _Covered({required this.cover, required this.child});

  final Widget child;
  final Widget? cover;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Offstage(
        offstage: cover != null,
        child: TickerMode(enabled: cover == null, child: child),
      ),
      ?cover,
    ],
  );
}

/// Shows a screen with the panel of the chosen task. In a desktop window
/// the panel is at the right of the screen. On a phone it takes the place
/// of the screen. The screen stays in the tree in each case, so it keeps
/// its state and the keyboard focus.
class InspectorHost extends StatefulWidget {
  const InspectorHost({super.key, required this.store, required this.child});

  final AppStore store;
  final Widget child;

  @override
  State<InspectorHost> createState() => _InspectorHostState();
}

class _InspectorHostState extends State<InspectorHost> {
  /// Keeps the state of the screen when the window changes between the
  /// desktop and the phone layout.
  final _screen = GlobalKey();

  @override
  Widget build(BuildContext context) => StoreBuilder(
    store: widget.store,
    builder: (context) {
      final id = widget.store.selectedTaskId;
      final screen = KeyedSubtree(key: _screen, child: widget.child);
      final inspector = id == null
          ? null
          : TaskInspector(store: widget.store, taskId: id);
      if (_isPhone(context)) {
        return _Covered(
          cover: inspector == null
              ? null
              : Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: inspector,
                ),
          child: screen,
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: screen),
          if (inspector != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 16, 16),
              child: SizedBox(width: TaskInspector.width, child: inspector),
            ),
        ],
      );
    },
  );
}
