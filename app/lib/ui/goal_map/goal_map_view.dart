// The goal map: squares in a `Flow`, lines in a painter, both in a pan and
// zoom view. Grove places every square (`GoalMapLayout`). When the map changes
// one controller moves all squares from where they are to their new places.
//
// It costs nothing at rest: no controller runs, and a one-minute timer only
// runs while a square is waiting. In a move each square is a stored layer that
// is only moved, so the frame draws just the lines.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:grove/core/goals/goal_graph.dart';
import 'package:grove/core/goals/goal_map_layout.dart';
import 'package:grove/core/model/goal_square.dart';

import '../theme/grove_theme.dart';
import '../theme/named_colors.dart';
import 'map_motion.dart';
import 'map_painters.dart';
import 'square_tile.dart';

/// Lets the tool bar move the camera.
class GoalMapController {
  VoidCallback? _fit;

  /// Shows the whole map.
  void fit() => _fit?.call();
}

class GoalMapView extends StatefulWidget {
  const GoalMapView({
    super.key,
    required this.goalId,
    required this.title,
    required this.graph,
    required this.goalColor,
    required this.motion,
    this.controller,
    this.selectedId,
    this.linkTargets = const {},
    this.safeArea = EdgeInsets.zero,
    this.clock = DateTime.now,
    this.onTapSquare,
    this.onTickSquare,
    this.onTapEmpty,
    this.tools,
    this.onLink,
  });

  final String goalId;

  /// The name of the goal: the root shows it.
  final String title;
  final GoalGraph graph;
  final Color goalColor;

  /// False: nothing moves, and the map only changes.
  final bool motion;
  final GoalMapController? controller;
  final String? selectedId;

  /// The squares that can take a link now.
  final Set<String> linkTargets;

  /// The parts of the view that other things cover. The camera fits the map
  /// in the rest.
  final EdgeInsets safeArea;
  final DateTime Function() clock;
  final ValueChanged<String>? onTapSquare;
  final ValueChanged<String>? onTickSquare;
  final VoidCallback? onTapEmpty;

  /// Buttons at the left of the selected square.
  final WidgetBuilder? tools;

  /// With a mouse: a handle at the right of the selected square. Dragging it
  /// onto a square makes the selected square a child of that one. Null: no
  /// handle, as on a phone, where the Link button does this.
  final void Function(String child, String parent)? onLink;

  @override
  State<GoalMapView> createState() => GoalMapViewState();
}

class GoalMapViewState extends State<GoalMapView>
    with TickerProviderStateMixin {
  /// Room around the map in the scene, so a square can move outside the
  /// layout without leaving the scene.
  static const _margin = 800.0;
  static const _scenePad = Offset(_margin, _margin);
  static const _moveTime = Duration(milliseconds: 420);
  static const _growTime = Duration(milliseconds: 680);
  static const _fadeTime = Duration(milliseconds: 150);
  static const _tickTime = Duration(milliseconds: 950);
  static const _waveTime = Duration(milliseconds: 1500);
  static const _toolsSize = 44.0;
  static const _handleSize = 28.0;

  /// The moment of a tick effect when light reaches the parent.
  static const _wakeAt = 0.66;

  final _camera = TransformationController();
  final _moving = MapMotion();

  late final AnimationController _move =
      AnimationController(vsync: this, duration: _moveTime)
        ..addListener(_onMove)
        ..addStatusListener(_onMoveStatus);
  late final AnimationController _cam = AnimationController(
    vsync: this,
    duration: _moveTime,
  )..addListener(_onCam);
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: _fadeTime,
    value: 1,
  );
  late final AnimationController _fx = AnimationController(
    vsync: this,
    duration: _tickTime,
  )..addListener(_onFx);

  Matrix4Tween? _camTween;
  Timer? _clockTimer;
  late DateTime _now;
  bool _pendingFit = true;
  Size _viewport = Size.zero;

  late GoalGraph _graph;
  late String _goalId;
  late GoalMapLayout _layout;
  late String _signature;

  /// Squares that are gone from the graph, while they shrink away.
  final Map<String, (GoalSquare, SquareState)> _gone = {};

  /// A parent keeps its old state until the light reaches it.
  final Map<String, SquareState> _held = {};
  List<RingEffect> _rings = const [];
  List<LightEffect> _lights = const [];

  /// A new goal waits here while the old map fades.
  bool _swapping = false;

  /// The square that a drag of the handle started from.
  String? _linkFrom;

  /// Where the drag of the handle is now, in the place of the layout.
  final _linkEnd = ValueNotifier<Offset?>(null);

  bool get _animate =>
      widget.motion && !MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    _now = widget.clock();
    _graph = widget.graph;
    _goalId = widget.goalId;
    _signature = _signatureOf(_graph);
    _layout = GoalMapLayout.of(_graph);
    _moving.jump(_layout);
    widget.controller?._fit = fit;
    _syncClock();
  }

  @override
  void didUpdateWidget(GoalMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._fit = null;
      widget.controller?._fit = fit;
    }
    if (widget.goalId != _goalId) {
      _changeGoal();
      return;
    }
    if (_swapping) return;
    final before = _layout;
    _applyGraph(widget.graph);
    if (oldWidget.selectedId != widget.selectedId ||
        oldWidget.safeArea != widget.safeArea ||
        !identical(before, _layout)) {
      _revealSelected();
    }
  }

  void _changeGoal() {
    _goalId = widget.goalId;
    if (!_animate) {
      _showGraph(widget.graph);
      _moving.jump(_layout);
      _move.value = 1;
      _clearEffects();
      _openCamera(animated: false);
      return;
    }
    _swapping = true;
    _fade.reverse().whenComplete(() {
      if (!mounted) return;
      _swapping = false;
      _showGraph(widget.graph);
      _clearEffects();
      _fade.value = 1;
      _moving.growInto(_layout, _graph);
      _move
        ..duration = _growTime
        ..forward(from: 0);
      _openCamera(animated: true);
      setState(() {});
    });
  }

  void _showGraph(GoalGraph graph) {
    _graph = graph;
    _signature = _signatureOf(graph);
    _layout = GoalMapLayout.of(graph);
    _gone.clear();
    _syncClock();
  }

  void _clearEffects() {
    _fx.stop();
    _held.clear();
    _rings = const [];
    _lights = const [];
  }

  void _applyGraph(GoalGraph next) {
    final before = _graph;
    final animate = _animate;
    if (animate) _startEffects(before, next);
    _graph = next;
    _syncClock();
    final signature = _signatureOf(next);
    if (signature == _signature) return;
    _signature = signature;
    final oldLayout = _layout;
    _layout = GoalMapLayout.of(next);
    if (!animate) {
      _moving.jump(_layout);
      _gone.clear();
      _move.value = 1;
      return;
    }
    for (final id in before.ids) {
      if (!next.contains(id)) {
        _gone[id] = (before.square(id), before.stateOf(id));
      }
    }
    _keepCameraSteady(oldLayout, _layout, next);
    _moving.moveTo(_layout, before);
    _move
      ..duration = _moveTime
      ..forward(from: 0);
  }

  /// What decides the places. A new title or a tick moves nothing.
  static String _signatureOf(GoalGraph g) {
    final ids = g.ids.toList()..sort();
    return [
      for (final id in ids)
        '$id@${g.square(id).sort}<${g.childrenOf(id).join(',')}',
    ].join('|');
  }

  /// A tick: a ring on the square, light on its lines, then each parent wakes.
  /// A tick of the root: a wave across the map.
  void _startEffects(GoalGraph before, GoalGraph next) {
    final done = TaskPalette.color('green')!;
    final ticked = [
      for (final id in next.ids)
        if (before.contains(id) &&
            !before.square(id).isDone &&
            next.square(id).isDone)
          id,
    ];
    if (ticked.isEmpty) return;
    final rings = <RingEffect>[];
    final lights = <LightEffect>[];
    if (ticked.contains(next.rootId)) {
      final maxRank = next.ranks.values.fold<int>(0, math.max);
      for (final id in next.ids) {
        final at = maxRank == 0 ? 0.0 : next.ranks[id]! / maxRank * 0.6;
        rings.add(RingEffect(id, at, at + 0.4, done));
      }
      _fx.duration = _waveTime;
    } else {
      final wake = <String>{};
      for (final id in ticked) {
        rings.add(RingEffect(id, 0, 0.4, done));
        for (final edge in _layout.edges) {
          if (edge.childId != id) continue;
          lights.add(LightEffect(edge, 0.12, _wakeAt, done));
          wake.add(edge.parentId);
        }
      }
      for (final id in wake) {
        if (!next.contains(id) || !before.contains(id)) continue;
        final was = before.stateOf(id);
        if (was == next.stateOf(id)) continue;
        _held[id] = was;
        rings.add(RingEffect(id, _wakeAt, 1, widget.goalColor));
      }
      _fx.duration = _tickTime;
    }
    _rings = rings;
    _lights = lights;
    _fx.forward(from: 0);
  }

  void _onFx() {
    if (_fx.isCompleted) {
      setState(() {
        _held.clear();
        _rings = const [];
        _lights = const [];
      });
    } else if (_held.isNotEmpty && _fx.value >= _wakeAt) {
      setState(_held.clear);
    }
  }

  void _onMove() => _moving.t = _move.value;

  void _onMoveStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final hadGone = _moving.leaving.isNotEmpty;
    _moving.settle();
    _gone.clear();
    if (hadGone && mounted) setState(() {});
  }

  void _onCam() {
    final tween = _camTween;
    if (tween == null) return;
    _camera.value = tween.transform(
      Curves.easeInOutCubic.transform(_cam.value),
    );
  }

  /// A countdown only needs a new word now and then.
  void _syncClock() {
    final waiting = _graph.waitingIds.isNotEmpty;
    if (!waiting) {
      _clockTimer?.cancel();
      _clockTimer = null;
    } else {
      _clockTimer ??= Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() => _now = widget.clock());
      });
      _now = widget.clock();
    }
  }

  // The camera

  /// Shows the whole map.
  void fit() => _fitCamera(animated: _animate);

  Matrix4 _fitMatrix() {
    final safe = widget.safeArea;
    final w = math.max(1.0, _viewport.width - safe.horizontal);
    final h = math.max(1.0, _viewport.height - safe.vertical);
    const pad = 32.0;
    final scale = math
        .min(
          (w - pad * 2) / math.max(1.0, _layout.width),
          (h - pad * 2) / math.max(1.0, _layout.height),
        )
        .clamp(_minScale, 1.0);
    final x = safe.left + (w - _layout.width * scale) / 2 - _margin * scale;
    final y = safe.top + (h - _layout.height * scale) / 2 - _margin * scale;
    return Matrix4.identity()
      ..translateByDouble(x, y, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  /// The first look at a map. A map that fits with words that can be read
  /// shows whole. A bigger one, as on a phone, starts at the next thing to do.
  Matrix4 _openMatrix() {
    final whole = _fitMatrix();
    if (whole.getMaxScaleOnAxis() >= _readableScale) return whole;
    final ready = _graph.readyIds;
    final at = _layout.at(ready.isEmpty ? _graph.rootId : ready.first);
    final safe = widget.safeArea;
    final h = math.max(1.0, _viewport.height - safe.vertical);
    const scale = _readableScale;
    final x = safe.left + 8 - (at.x + _margin) * scale;
    final y =
        safe.top +
        (h - GoalMapLayout.squareHeight * scale) / 2 -
        (at.y + _margin) * scale;
    return Matrix4.identity()
      ..translateByDouble(x, y, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  /// Where the camera will be: a move that runs now counts as done.
  Matrix4 get _cameraGoal =>
      _cam.isAnimating ? (_camTween?.end ?? _camera.value) : _camera.value;

  /// A selected square comes out from under the panels, by the shortest way.
  void _revealSelected() {
    final id = widget.selectedId;
    if (id == null || !_layout.ids.contains(id) || _viewport == Size.zero) {
      return;
    }
    final at = _layout.at(id);
    final camera = _cameraGoal;
    final box = MatrixUtils.transformRect(
      camera,
      Rect.fromLTWH(
        at.x + _margin,
        at.y + _margin,
        GoalMapLayout.squareWidth,
        GoalMapLayout.squareHeight,
      ),
    );
    final free = widget.safeArea.deflateRect(Offset.zero & _viewport);
    if (free.width < box.width || free.height < box.height) return;
    var dx = 0.0, dy = 0.0;
    if (box.left < free.left) dx = free.left - box.left;
    if (box.right > free.right) dx = free.right - box.right;
    if (box.top < free.top) dy = free.top - box.top;
    if (box.bottom > free.bottom) dy = free.bottom - box.bottom;
    if (dx == 0 && dy == 0) return;
    final to = camera.clone()..storage[12] += dx;
    to.storage[13] += dy;
    _goCamera(to, animated: _animate);
  }

  static const _readableScale = 0.6;
  static const _minScale = 0.15;
  static const _maxScale = 1.6;

  void _fitCamera({required bool animated}) {
    if (_viewport == Size.zero) {
      _pendingFit = true;
      return;
    }
    _goCamera(_fitMatrix(), animated: animated);
  }

  void _openCamera({required bool animated}) {
    if (_viewport == Size.zero) {
      _pendingFit = true;
      return;
    }
    _goCamera(_openMatrix(), animated: animated);
  }

  void _goCamera(Matrix4 to, {required bool animated}) {
    if (!animated) {
      _cam.stop();
      _camera.value = to;
      return;
    }
    _camTween = Matrix4Tween(begin: _camera.value.clone(), end: to);
    _cam.forward(from: 0);
  }

  /// Layers can start further left, which moves every square in the scene. The
  /// camera moves with them, so a square the user looks at stays where it is.
  /// A selected square that would end off the screen comes into view.
  void _keepCameraSteady(
    GoalMapLayout before,
    GoalMapLayout after,
    GoalGraph graph,
  ) {
    final selected = widget.selectedId;
    final anchor =
        selected != null &&
            before.ids.contains(selected) &&
            after.ids.contains(selected)
        ? selected
        : graph.rootId;
    if (!before.ids.contains(anchor) || !after.ids.contains(anchor)) return;
    final a = before.at(anchor), b = after.at(anchor);
    final scale = _cameraGoal.getMaxScaleOnAxis();
    final m = _cameraGoal.clone();
    var dx = (a.x - b.x) * scale + m.storage[12];
    var dy = (a.y - b.y) * scale + m.storage[13];
    // New squares can end outside the screen: bring the map's near edge in.
    final safe = widget.safeArea;
    final left = dx + _margin * scale;
    final top = dy + _margin * scale;
    final right = left + after.width * scale;
    final bottom = top + after.height * scale;
    final roomW = _viewport.width - safe.horizontal;
    final roomH = _viewport.height - safe.vertical;
    if (after.width * scale <= roomW) {
      if (left < safe.left) dx += safe.left - left;
      if (right > safe.left + roomW) dx -= right - safe.left - roomW;
    }
    if (after.height * scale <= roomH) {
      if (top < safe.top) dy += safe.top - top;
      if (bottom > safe.top + roomH) dy -= bottom - safe.top - roomH;
    }
    m.storage[12] = dx;
    m.storage[13] = dy;
    _goCamera(m, animated: true);
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    widget.controller?._fit = null;
    _move.dispose();
    _cam.dispose();
    _fade.dispose();
    _fx.dispose();
    _camera.dispose();
    super.dispose();
  }

  // Build

  Offset _layoutPoint(Offset global) {
    final box = context.findRenderObject()! as RenderBox;
    return _camera.toScene(box.globalToLocal(global)) - _scenePad;
  }

  void _startLink(PointerDownEvent e, String from) {
    if (e.kind != PointerDeviceKind.mouse) return;
    _linkEnd.value = _layoutPoint(e.position);
    setState(() => _linkFrom = from);
  }

  void _endLink(Offset? global) {
    final from = _linkFrom;
    if (from == null) return;
    if (global != null) {
      final at = _layoutPoint(global);
      for (final id in _moving.ids) {
        final box = _moving.place(id) & _squareSize;
        if (box.contains(at) && _graph.canLink(child: from, parent: id)) {
          widget.onLink?.call(from, id);
          break;
        }
      }
    }
    _linkEnd.value = null;
    setState(() => _linkFrom = null);
  }

  static const _squareSize = Size(
    GoalMapLayout.squareWidth,
    GoalMapLayout.squareHeight,
  );

  Widget _handle(GroveTheme theme, String from) => Listener(
    key: const ValueKey('square-link-handle'),
    onPointerDown: (e) => _startLink(e, from),
    onPointerMove: (e) {
      if (_linkFrom != null) _linkEnd.value = _layoutPoint(e.position);
    },
    onPointerUp: (e) => _endLink(e.position),
    onPointerCancel: (_) => _endLink(null),
    child: MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Tooltip(
        message: 'Drag onto the step that needs this one first',
        child: SizedBox.square(
          dimension: _handleSize,
          child: Center(
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: theme.solidSurface,
                shape: BoxShape.circle,
                border: Border.all(color: theme.ink, width: 2),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _tile(String id, GoalSquare square, SquareState state) =>
      RepaintBoundary(
        key: ValueKey('square-$id'),
        child: SquareTile(
          square: square,
          state: state,
          title: square.isRoot ? widget.title : square.title,
          goalColor: widget.goalColor,
          now: _now,
          motion: _animate,
          selected: id == widget.selectedId,
          linkTarget:
              widget.linkTargets.contains(id) ||
              (_linkFrom != null &&
                  _graph.contains(id) &&
                  _graph.canLink(child: _linkFrom!, parent: id)),
          onTap: widget.onTapSquare == null
              ? null
              : () => widget.onTapSquare!(id),
          onTickTap: widget.onTickSquare == null
              ? null
              : () => widget.onTickSquare!(id),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final graph = _graph;
    final dark = theme.brightness == Brightness.dark;
    final lineColor = theme.ink.withValues(alpha: dark ? 0.55 : 0.78);
    final dotColor = theme.muted.withValues(alpha: 0.28);
    final done = TaskPalette.color('green')!;
    final ids = _moving.ids.where(graph.contains).toList();
    final leaving = _moving.leaving.toList();
    final selected = widget.selectedId;
    final hasTools =
        widget.tools != null && selected != null && graph.contains(selected);
    final hasHandle =
        widget.onLink != null &&
        selected != null &&
        graph.contains(selected) &&
        selected != graph.rootId;
    final sceneSize = Size(
      _layout.width + _margin * 2,
      _layout.height + _margin * 2,
    );
    return LayoutBuilder(
      builder: (context, box) {
        _viewport = box.biggest;
        if (_pendingFit && _viewport != Size.zero) {
          _pendingFit = false;
          _camera.value = _openMatrix();
        }
        return ClipRect(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onTapEmpty,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: CustomPaint(painter: DotsPainter(_camera, dotColor)),
                ),
                FadeTransition(
                  opacity: _fade,
                  child: InteractiveViewer(
                    transformationController: _camera,
                    constrained: false,
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    minScale: _minScale,
                    maxScale: _maxScale,
                    panEnabled: _linkFrom == null,
                    scaleEnabled: _linkFrom == null,
                    onInteractionStart: (_) => _cam.stop(),
                    child: SizedBox(
                      width: sceneSize.width,
                      height: sceneSize.height,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          RepaintBoundary(
                            child: CustomPaint(
                              painter: LinesPainter(
                                motion: _moving,
                                isDone: (e) =>
                                    graph.contains(e.childId) &&
                                    graph.square(e.childId).isDone,
                                lineColor: lineColor,
                                doneColor: done,
                                origin: _scenePad,
                                repaint: _move,
                              ),
                            ),
                          ),
                          Flow(
                            delegate: _SceneDelegate(
                              motion: _moving,
                              ids: ids,
                              leaving: leaving,
                              selected: hasTools ? selected : null,
                              handle: hasHandle ? selected : null,
                              repaint: _move,
                            ),
                            clipBehavior: Clip.none,
                            children: [
                              for (final id in ids)
                                _tile(
                                  id,
                                  graph.square(id),
                                  _held[id] ?? graph.stateOf(id),
                                ),
                              for (final l in leaving)
                                if (_gone[l.id] case final g?)
                                  _tile(l.id, g.$1, g.$2)
                                else
                                  const SizedBox.shrink(),
                              if (hasTools)
                                Builder(
                                  key: const ValueKey('square-tools'),
                                  builder: widget.tools!,
                                ),
                              if (hasHandle) _handle(theme, selected),
                            ],
                          ),
                          if (_linkFrom case final from?)
                            IgnorePointer(
                              child: CustomPaint(
                                painter: LinkDragPainter(
                                  from:
                                      _moving.place(from) +
                                      _scenePad +
                                      Offset(
                                        _squareSize.width,
                                        _squareSize.height / 2,
                                      ),
                                  end: _linkEnd,
                                  origin: _scenePad,
                                  color: theme.accent,
                                ),
                              ),
                            ),
                          IgnorePointer(
                            child: RepaintBoundary(
                              child: CustomPaint(
                                painter: EffectsPainter(
                                  motion: _moving,
                                  time: _fx,
                                  rings: _rings,
                                  lights: _lights,
                                  origin: _scenePad,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Places the children: the squares of the map, the squares that leave, and
/// the buttons of the selected square. A frame of a move only runs this: no
/// child is built or laid out again.
class _SceneDelegate extends FlowDelegate {
  _SceneDelegate({
    required this.motion,
    required this.ids,
    required this.leaving,
    required this.selected,
    required this.handle,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final MapMotion motion;
  final List<String> ids;
  final List<LeavingSquare> leaving;
  final String? selected;
  final String? handle;

  static const _pad = GoalMapViewState._scenePad;
  static const _center = Offset(
    GoalMapLayout.squareWidth / 2,
    GoalMapLayout.squareHeight / 2,
  );

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      i < ids.length + leaving.length
      ? const BoxConstraints.tightFor(
          width: GoalMapLayout.squareWidth,
          height: GoalMapLayout.squareHeight,
        )
      : const BoxConstraints();

  void _paint(
    FlowPaintingContext context,
    int i,
    Offset place,
    double scale,
    double alpha,
  ) {
    if (alpha <= 0) return;
    final at = place + _pad;
    final m = Matrix4.translationValues(at.dx, at.dy, 0);
    if (scale != 1) {
      m
        ..translateByDouble(_center.dx, _center.dy, 0, 1)
        ..scaleByDouble(scale, scale, scale, 1)
        ..translateByDouble(-_center.dx, -_center.dy, 0, 1);
    }
    context.paintChild(i, transform: m, opacity: alpha);
  }

  @override
  void paintChildren(FlowPaintingContext context) {
    var i = 0;
    for (final id in ids) {
      _paint(
        context,
        i++,
        motion.place(id),
        motion.scaleOf(id),
        motion.alphaOf(id),
      );
    }
    for (final l in leaving) {
      _paint(
        context,
        i++,
        motion.leavingPlace(l),
        motion.leavingScale(),
        motion.leavingAlpha(),
      );
    }
    final tools = selected;
    if (tools != null && motion.alphaOf(tools) >= 1) {
      final place = motion.place(tools);
      _paint(
        context,
        i++,
        place +
            const Offset(
              -GoalMapViewState._toolsSize - 8,
              (GoalMapLayout.squareHeight - GoalMapViewState._toolsSize) / 2,
            ),
        1,
        1,
      );
    }
    final handle = this.handle;
    if (handle != null && motion.alphaOf(handle) >= 1) {
      _paint(
        context,
        i,
        motion.place(handle) +
            const Offset(
              GoalMapLayout.squareWidth + 2,
              (GoalMapLayout.squareHeight - GoalMapViewState._handleSize) / 2,
            ),
        1,
        1,
      );
    }
  }

  @override
  bool shouldRepaint(_SceneDelegate old) =>
      old.ids != ids ||
      old.leaving != leaving ||
      old.selected != selected ||
      old.handle != handle;

  @override
  bool shouldRelayout(_SceneDelegate old) =>
      old.ids.length != ids.length ||
      old.leaving.length != leaving.length ||
      old.selected != selected ||
      old.handle != handle;
}
