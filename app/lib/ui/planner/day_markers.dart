// The wake-up line and the sleep line of a day in the planner: two lines
// across a day column that the user drags up or down. They are marks only.
// The store keeps one time for each line of each day (`DayMarkerRules`).
//
// A drag changes only the state in this file. The database gets one write
// when the drag ends, as for a block (PLAN §5.1, §14).
import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/planner/planner_math.dart';
// The store has its own `MotionRules`, for the garden.
import 'package:grove/state/state.dart' hide MotionRules;

import '../theme/grove_theme.dart';
import '../theme/symbols.dart';
import 'block_view.dart';
import 'planner_geometry.dart';

/// One line of a menu of the lines. It looks like the lines of the menu of
/// a block.
PopupMenuItem<VoidCallback> _menuLine(
  GroveTheme theme,
  String label,
  VoidCallback action,
) => PopupMenuItem<VoidCallback>(
  value: action,
  height: 34,
  child: Text(label, style: theme.body(13).copyWith(color: theme.ink)),
);

Future<VoidCallback?> _showLines(
  BuildContext context,
  Offset global,
  List<PopupMenuEntry<VoidCallback>> items,
) {
  final theme = GroveTheme.of(context);
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  return showMenu<VoidCallback>(
    context: context,
    color: theme.solidSurface,
    position: RelativeRect.fromRect(
      global & Size.zero,
      Offset.zero & overlay.size,
    ),
    items: items,
  );
}

/// The menu of the "+" above the schedule, under the button of `context`.
/// It adds the wake-up line or the sleep line of [day]. A line that is
/// there can go away here.
///
/// [nameDay] puts the day in the first row: the week shows seven days, and
/// the lines are for one of them. [onAdded] gets the minute of a new line.
Future<void> showDayMarkerMenu(
  BuildContext context, {
  required AppStore store,
  required DayKey day,
  required bool nameDay,
  ValueChanged<int>? onAdded,
}) async {
  final theme = GroveTheme.of(context);
  final box = context.findRenderObject()! as RenderBox;
  final action = await _showLines(
    context,
    box.localToGlobal(Offset(0, box.size.height + 4)),
    [
      if (nameDay)
        PopupMenuItem<VoidCallback>(
          enabled: false,
          height: 26,
          child: Text(
            NotesRules.shortDay(day),
            style: theme
                .body(11, weight: FontWeight.w700)
                .copyWith(color: theme.muted),
          ),
        ),
      for (final kind in DayMarkerKind.values)
        if (store.dayMarker(kind, day) == null)
          _menuLine(theme, 'Add ${kind.lineName}', () {
            final minute = store.addDayMarker(kind, day);
            if (minute != null) onAdded?.call(minute);
          })
        else
          _menuLine(
            theme,
            'Remove ${kind.lineName}',
            () => store.removeDayMarker(kind, day),
          ),
    ],
  );
  action?.call();
}

/// A drag of a line that runs now. Nothing is saved until it ends.
class _LineDrag {
  _LineDrag({
    required this.kind,
    required this.day,
    required this.from,
    required this.down,
    required this.pointer,
    required this.startY,
  }) : minute = from;

  final DayMarkerKind kind;
  final DayKey day;

  /// The minute of the line when the drag began.
  final int from;

  /// Where the pointer went down, in the window.
  final Offset down;

  /// Where the pointer is, in the part of the grid on the screen.
  Offset pointer;

  /// Where the pointer went down, in the whole grid.
  final double startY;

  /// The minute of the line now.
  int minute;

  /// How far the pointer went from where it went down, at most.
  double slip = 0;
}

/// The lines of the days of the grid, over the blocks. Only a line and its
/// label take the pointer. The rest of the layer lets it through to the
/// grid.
class DayMarkerLayer extends StatefulWidget {
  const DayMarkerLayer({
    super.key,
    required this.store,
    required this.days,
    required this.geo,
    required this.dayLeft,
    required this.dayWidth,
    required this.scroll,
    required this.inViewport,
    required this.canStart,
    required this.onDragging,
  });

  final AppStore store;
  final List<DayKey> days;
  final PlannerGeometry geo;

  /// The left edge and the width of a day column of the grid.
  final double Function(int index) dayLeft;
  final double Function(int index) dayWidth;

  /// The scroll of the grid.
  final ScrollController scroll;

  /// A point of the window, in the part of the grid on the screen.
  final Offset Function(Offset global) inViewport;

  /// False while the grid has a drag or two fingers of its own.
  final bool Function() canStart;

  /// True while a line is dragged: the grid must not scroll under it.
  final ValueChanged<bool> onDragging;

  /// The thickness of a line.
  static const lineHeight = 2.0;

  /// The height of the part of a line that takes the pointer.
  static const gripHeight = 8.0;

  /// The height of a label, and of the part of it that takes the pointer.
  static const chipHeight = 20.0;
  static const chipGrip = 32.0;

  /// A column that is at least this wide has the name of the line in the
  /// label, and not only its picture.
  static const wordFrom = 200.0;

  /// A column that is narrower has no picture in the label, only the time.
  static const iconFrom = 76.0;

  /// A click that slips less than this far is still a click.
  static const clickSlip = 6.0;

  @override
  State<DayMarkerLayer> createState() => _DayMarkerLayerState();
}

class _DayMarkerLayerState extends State<DayMarkerLayer> {
  List<DayMarker> _markers = const [];
  List<DayKey> _loadedDays = const [];
  int _revision = -1;
  _LineDrag? _drag;
  Timer? _autoScroll;

  AppStore get _store => widget.store;
  double get _scrollY => widget.scroll.hasClients ? widget.scroll.offset : 0;

  @override
  void dispose() {
    _autoScroll?.cancel();
    super.dispose();
  }

  // Data

  /// Reads the lines again when the store or the days are new ones.
  void _load() {
    final days = widget.days;
    final sameDays =
        days.length == _loadedDays.length &&
        (days.isEmpty ||
            (days.first == _loadedDays.first && days.last == _loadedDays.last));
    if (sameDays && _store.revision == _revision) return;
    _revision = _store.revision;
    _loadedDays = days;
    _markers = days.isEmpty
        ? const []
        : _store.dayMarkers(DayRange(days.first, days.last));
    // The dragged line went away: its day left the screen, or another
    // device took the line off. Its drag gets no end of its own, so it
    // ends here.
    final drag = _drag;
    if (drag != null &&
        !_markers.any((m) => m.kind == drag.kind && m.day == drag.day)) {
      _stopDrag();
      scheduleMicrotask(() {
        if (mounted) widget.onDragging(false);
      });
    }
  }

  // A drag of a line

  void _start(DayMarker marker, Offset global) {
    if (_drag != null || !widget.canStart()) return;
    final at = widget.inViewport(global);
    setState(() {
      _drag = _LineDrag(
        kind: marker.kind,
        day: marker.day,
        from: marker.minute,
        down: global,
        pointer: at,
        startY: at.dy + _scrollY,
      );
    });
    widget.onDragging(true);
    _startAutoScroll();
  }

  void _update(Offset global) {
    final drag = _drag;
    if (drag == null) return;
    drag
      ..pointer = widget.inViewport(global)
      ..slip = max(drag.slip, (global - drag.down).distance);
    _refresh();
  }

  /// Finds the minute of the dragged line again: the pointer moved, or the
  /// grid scrolled under a still pointer.
  void _refresh() {
    final drag = _drag;
    if (drag == null) return;
    final moved =
        ((drag.pointer.dy + _scrollY - drag.startY) /
                widget.geo.hourHeight *
                60)
            .round();
    final minute = DayMarkerRules.snapped(drag.from + moved);
    if (minute == drag.minute) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() => drag.minute = minute);
  }

  void _stopDrag() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _drag = null;
  }

  void _end() {
    final drag = _drag;
    if (drag == null) return;
    setState(_stopDrag);
    widget.onDragging(false);
    if (drag.minute != drag.from) {
      _store.moveDayMarker(drag.kind, drag.day, drag.minute);
    } else if (drag.slip < DayMarkerLayer.clickSlip) {
      // A click with a hand that is not still: it moved the line nowhere.
      unawaited(_openMenu(drag.kind, drag.day, drag.down));
    }
  }

  /// Scrolls the grid while the pointer is near its top or bottom edge, at
  /// the speed of a block drag.
  void _startAutoScroll() {
    _autoScroll?.cancel();
    _autoScroll = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final drag = _drag;
      final scroll = widget.scroll;
      if (drag == null || !scroll.hasClients) return;
      const edge = 40.0;
      const top = 24.0;
      final y = drag.pointer.dy;
      final height = scroll.position.viewportDimension;
      var speed = 0.0;
      if (y < edge) {
        speed = -min(top, (edge - y) / edge * top);
      } else if (y > height - edge) {
        speed = min(top, (y - (height - edge)) / edge * top);
      }
      if (speed == 0) return;
      final next = (scroll.offset + speed).clamp(
        0.0,
        scroll.position.maxScrollExtent,
      );
      if (next == scroll.offset) return;
      scroll.jumpTo(next);
      _refresh();
    });
  }

  // The menu of a line

  Future<void> _openMenu(DayMarkerKind kind, DayKey day, Offset global) async {
    if (_drag != null || !widget.canStart()) return;
    final theme = GroveTheme.of(context);
    final action = await _showLines(context, global, [
      _menuLine(
        theme,
        'Remove ${kind.lineName}',
        () => _store.removeDayMarker(kind, day),
      ),
    ]);
    if (mounted) action?.call();
  }

  void _step(DayMarker marker, int by) => _store.moveDayMarker(
    marker.kind,
    marker.day,
    marker.minute + by * PlannerMath.step,
  );

  // The layers

  double _textWidth(String text, TextStyle style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    // On a whole point, so the next text of the label starts on one.
    final width = painter.width.ceilToDouble();
    painter.dispose();
    return width;
  }

  Widget _grip(DayMarker marker, {required Widget child}) => MouseRegion(
    cursor: SystemMouseCursors.resizeUpDown,
    child: RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        _LineDragRecognizer:
            GestureRecognizerFactoryWithHandlers<_LineDragRecognizer>(
              _LineDragRecognizer.new,
              (drag) {
                drag.dragStartBehavior = DragStartBehavior.down;
                drag.onStart = (d) => _start(marker, d.globalPosition);
                drag.onUpdate = (d) => _update(d.globalPosition);
                drag.onEnd = (_) => _end();
                drag.onCancel = _end;
              },
            ),
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              TapGestureRecognizer.new,
              (tap) {
                tap.onTapUp = (d) => unawaited(
                  _openMenu(marker.kind, marker.day, d.globalPosition),
                );
                tap.onSecondaryTapUp = (d) => unawaited(
                  _openMenu(marker.kind, marker.day, d.globalPosition),
                );
              },
            ),
      },
      child: child,
    ),
  );

  @override
  Widget build(BuildContext context) {
    _load();
    final theme = GroveTheme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final geo = widget.geo;
    final drag = _drag;
    final color = theme.accent3;
    final timeStyle = theme
        .number(10, weight: FontWeight.w700)
        .copyWith(height: 1.4);
    final wordStyle = theme
        .body(10, weight: FontWeight.w700)
        .copyWith(height: 1.4);

    final lines = <Widget>[];
    final chips = <Widget>[];
    for (final stored in _markers) {
      final index = widget.days.indexOf(stored.day);
      if (index < 0) continue;
      final live =
          drag != null && drag.kind == stored.kind && drag.day == stored.day;
      final marker = live
          ? DayMarker(kind: stored.kind, day: stored.day, minute: drag.minute)
          : stored;
      final kind = marker.kind;
      final id = '${kind.name}-${marker.day.string}';
      final left = widget.dayLeft(index);
      final width = widget.dayWidth(index);
      final y = geo.y(marker.minute).roundToDouble();

      // The line, on whole points. At 00:00 it lies just under the top.
      final lineTop = max(0.0, y - DayMarkerLayer.lineHeight / 2);
      const gripPad =
          (DayMarkerLayer.gripHeight - DayMarkerLayer.lineHeight) / 2;
      lines.add(
        Positioned(
          key: ValueKey('day-marker-line-$id'),
          left: left,
          top: lineTop - gripPad,
          width: width,
          height: DayMarkerLayer.gripHeight,
          child: ExcludeSemantics(
            child: _grip(
              stored,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: gripPad),
                child: CustomPaint(painter: _DashPainter(color)),
              ),
            ),
          ),
        ),
      );

      // The label: a picture, the name when there is room, and the time.
      final time = PlannerMath.clock(marker.minute);
      final hasWord = width >= DayMarkerLayer.wordFrom;
      final hasIcon = width >= DayMarkerLayer.iconFrom;
      final timeWidth = _textWidth(time, timeStyle, scaler);
      final wordWidth = hasWord
          ? _textWidth(kind.label, wordStyle, scaler)
          : 0.0;
      final chipWidth =
          6 +
          (hasIcon ? 12 + 3 : 0) +
          (hasWord ? wordWidth + 5 : 0) +
          timeWidth +
          7;
      const chipHeight = DayMarkerLayer.chipHeight;
      const pad = (DayMarkerLayer.chipGrip - chipHeight) / 2;
      final chipTop = min(
        max(2.0, y - chipHeight / 2),
        geo.totalHeight - chipHeight - 2,
      );
      final chipLeft = max(left + 1, left + width - 4 - chipWidth);
      final ink = live ? theme.bg : theme.ink;
      chips.add(
        Positioned(
          key: ValueKey('day-marker-grip-$id'),
          left: chipLeft - 4,
          top: chipTop - pad,
          width: chipWidth + 8,
          height: DayMarkerLayer.chipGrip,
          child: Builder(
            builder: (context) => Semantics(
              container: true,
              excludeSemantics: true,
              button: true,
              label: '${kind.label} line',
              value: time,
              increasedValue: PlannerMath.clock(
                DayMarkerRules.snapped(marker.minute + PlannerMath.step),
              ),
              decreasedValue: PlannerMath.clock(
                DayMarkerRules.snapped(marker.minute - PlannerMath.step),
              ),
              hint: 'Drag up or down to change the time',
              onTap: () {
                final box = context.findRenderObject()! as RenderBox;
                unawaited(
                  _openMenu(
                    kind,
                    marker.day,
                    box.localToGlobal(box.size.center(Offset.zero)),
                  ),
                );
              },
              onIncrease: () => _step(stored, 1),
              onDecrease: () => _step(stored, -1),
              child: _grip(
                stored,
                child: Center(
                  child: SizedBox(
                    key: ValueKey('day-marker-$id'),
                    width: chipWidth,
                    height: chipHeight,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: live ? theme.ink : theme.solidSurface,
                        shape: StadiumBorder(
                          side: BorderSide(color: live ? theme.ink : color),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6, right: 7),
                        child: Row(
                          children: [
                            if (hasIcon) ...[
                              Icon(
                                symbolIcon(kind.symbol),
                                size: 12,
                                color: live ? theme.bg : color,
                              ),
                              const SizedBox(width: 3),
                            ],
                            if (hasWord) ...[
                              SizedBox(
                                width: wordWidth,
                                child: Text(
                                  kind.label,
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.clip,
                                  style: wordStyle.copyWith(color: ink),
                                ),
                              ),
                              const SizedBox(width: 5),
                            ],
                            SizedBox(
                              width: timeWidth,
                              child: Text(
                                time,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.clip,
                                style: timeStyle.copyWith(color: ink),
                              ),
                            ),
                          ],
                        ),
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
    // A label lies over each line, so a line never cuts a label.
    return Stack(children: [...lines, ...chips]);
  }
}

/// Takes a drag up or down at the first move, with a mouse and with a
/// finger: before the scroll view of the grid can. Two fingers on a
/// trackpad are not for it. They scroll the grid.
class _LineDragRecognizer extends VerticalDragGestureRecognizer {
  _LineDragRecognizer()
    : super(supportedDevices: const {...mouseKinds, ...touchKinds});

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) => globalDistanceMoved != 0;
}

/// A line of short strokes, drawn as boxes on whole points.
class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);

  final Color color;

  static const _dash = 6.0;
  static const _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var x = 0.0; x < size.width; x += _dash + _gap) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, min(_dash, size.width - x), size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}
