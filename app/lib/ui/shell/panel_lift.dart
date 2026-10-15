// On a phone an open left panel takes the place of the screen. A drag that
// starts in the panel takes the panel away, so the drop can land on the
// grid of the screen under it.
import 'package:flutter/widgets.dart';

/// Says if a drag from the left panel is on. The phone shell owns it and
/// gives it to the panel with [PanelLiftScope].
class PanelLift extends ChangeNotifier {
  PanelLift({required this.onDropped});

  /// A drop that a place on the screen took. The panel then stays closed.
  final VoidCallback onDropped;

  int _drags = 0;
  bool _disposed = false;

  /// True while a drag from the panel is on: the screen shows.
  bool get lifted => _drags > 0;

  void start() {
    _drags++;
    if (_drags == 1) notifyListeners();
  }

  /// `accepted` is false for a drop on no place: the panel comes back.
  void end({required bool accepted}) {
    if (_disposed || _drags == 0) return;
    _drags--;
    if (accepted) onDropped();
    if (_drags == 0) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Puts a [PanelLift] over a left panel. A drag in the panel finds it.
class PanelLiftScope extends InheritedWidget {
  const PanelLiftScope({super.key, required this.lift, required super.child});

  final PanelLift lift;

  /// null outside a phone panel: the drag takes nothing away.
  static PanelLift? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PanelLiftScope>()?.lift;

  @override
  bool updateShouldNotify(PanelLiftScope oldWidget) => lift != oldWidget.lift;
}

/// The content of a phone under the top strip: the screen, and the open
/// left panel in its place. Both stay in the tree, so each keeps its
/// state. During a drag from the panel the screen shows.
class PhonePaneHost extends StatefulWidget {
  const PhonePaneHost({
    super.key,
    required this.screen,
    required this.pane,
    required this.onDropped,
  });

  final Widget screen;

  /// The open left panel. null is none.
  final Widget? pane;

  /// A drag from the panel landed on the screen.
  final VoidCallback onDropped;

  @override
  State<PhonePaneHost> createState() => _PhonePaneHostState();
}

class _PhonePaneHostState extends State<PhonePaneHost> {
  late final _lift = PanelLift(onDropped: () => widget.onDropped());

  @override
  void dispose() {
    _lift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _lift,
    builder: (context, _) {
      final pane = widget.pane;
      final covered = pane != null && !_lift.lifted;
      return Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage: covered,
            child: TickerMode(enabled: !covered, child: widget.screen),
          ),
          if (pane != null)
            Offstage(
              offstage: _lift.lifted,
              child: TickerMode(
                enabled: !_lift.lifted,
                child: PanelLiftScope(lift: _lift, child: pane),
              ),
            ),
        ],
      );
    },
  );
}
