// Port of Sources/Grove/Planner/PlannerGrid.swift: the time grid with its
// blocks. A drag changes only the state in this file. The database gets one
// write when the drag ends (PLAN §5.1, §14).
import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/event.dart';
import 'package:grove/core/model/task.dart';
import 'package:grove/core/planner/planner_math.dart';
// The store has its own `MotionRules`, for the garden.
import 'package:grove/state/state.dart' hide MotionRules;

import '../theme/grove_theme.dart';
import '../theme/named_colors.dart';
import '../theme/theme_math.dart';
import 'block_view.dart';
import 'inline_title_field.dart';
import 'planner_clock.dart';
import 'planner_geometry.dart';

/// A move or a resize that runs now. Nothing is saved until it ends.
class LiveEdit {
  LiveEdit({
    required this.mode,
    required this.ids,
    required this.primaryId,
    required this.originals,
  });

  final DragMode mode;
  final List<String> ids;
  final String primaryId;
  final Map<String, BlockEdit> originals;
  int deltaMinutes = 0;
  int deltaDays = 0;
}

/// A drag on empty time that makes a new block.
class CreateDrag {
  CreateDrag({required this.dayIndex, required this.anchor}) : current = anchor;

  final int dayIndex;
  final int anchor;
  int current;
}

/// A new block that waits for its title.
class Draft {
  Draft({
    required this.serial,
    required this.day,
    required this.start,
    required this.end,
    this.asEvent = false,
  });

  /// Each draft has its own number, so a late answer from an old title field
  /// cannot save a new draft.
  final int serial;
  final DayKey day;
  final int start;
  final int end;
  final bool asEvent;
  String text = '';
}

/// Where the pointer is during a drag.
class _Pointer {
  _Pointer({required this.start, required this.last});

  /// The press, in grid space (it scrolls with the grid).
  final Offset start;

  /// The last place, in the space of the visible part of the grid.
  Offset last;
}

class PlannerGrid extends StatefulWidget {
  const PlannerGrid({
    super.key,
    required this.store,
    required this.days,
    required this.hourHeight,
    required this.workStart,
    required this.workEnd,
    this.scrollRequest = 0,
    this.onStripTarget,
  });

  final AppStore store;
  final List<DayKey> days;
  final double hourHeight;
  final int workStart;
  final int workEnd;

  /// Add 1 to scroll to "now".
  final int scrollRequest;

  /// True while a task block is dragged up over the sticky strip. A release
  /// there takes the block off the grid.
  final ValueChanged<bool>? onStripTarget;

  @override
  State<PlannerGrid> createState() => PlannerGridState();
}

class PlannerGridState extends State<PlannerGrid> {
  final _viewportKey = GlobalKey();
  final _focus = FocusNode(debugLabel: 'planner grid');
  late final ScrollController _scroll;

  List<PlannerBlock> _blocks = const [];
  Map<String, Layer> _layers = const {};
  Map<String, List<BlockSubtask>> _subtasks = const {};
  LiveEdit? _live;
  CreateDrag? _create;
  Draft? _draft;
  String? _renamingId;
  _Pointer? _pointer;
  DayKey? _targetedDay;
  Timer? _autoScroll;
  Timer? _clock;
  Timer? _tapTimer;
  String? _tapId;
  bool _overStrip = false;
  bool _motionOn = false;
  int _revision = -1;
  int _draftSerial = 0;
  double _gridWidth = 800;

  AppStore get _store => widget.store;
  List<DayKey> get _days => widget.days;
  PlannerGeometry get _geo => PlannerGeometry(hourHeight: widget.hourHeight);
  double get _dayWidth => max(
    60,
    (_gridWidth - PlannerGeometry.gutterWidth) / max(_days.length, 1),
  );

  /// The left edge and the width of a day column, on whole points.
  double _dayLeft(int index) =>
      PlannerGeometry.gutterWidth + PlannerGeometry.dayOffset(_dayWidth, index);
  double _dayWidthAt(int index) => PlannerGeometry.dayWidthAt(_dayWidth, index);

  bool get _isDragging => _live != null || _create != null;
  double get _scrollY => _scroll.hasClients ? _scroll.offset : 0;

  /// The new block that waits for its title, for tests.
  @visibleForTesting
  Draft? get draft => _draft;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController(initialScrollOffset: _nowTarget);
    _store.addListener(_storeChanged);
    // The now line and the faded past follow the clock.
    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
    _reload();
  }

  @override
  void didUpdateWidget(PlannerGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_storeChanged);
      widget.store.addListener(_storeChanged);
    }
    if (!_sameDays(oldWidget.days, widget.days) ||
        oldWidget.store != widget.store) {
      _reload();
      // The store must not change during a build, so the save of the draft
      // waits for the end of this frame.
      final draft = _draft;
      _draft = null;
      _renamingId = null;
      if (draft != null &&
          InlineTitleRules.onBlur(draft.text) == BlurAction.commit) {
        scheduleMicrotask(() {
          if (!mounted) return;
          _store.createFromDraft(
            title: draft.text,
            day: draft.day,
            start: draft.start,
            end: draft.end,
            asEvent: draft.asEvent,
          );
        });
      }
    } else if (oldWidget.hourHeight != widget.hourHeight) {
      _relayout();
    }
    if (oldWidget.scrollRequest != widget.scrollRequest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) scrollToNow(animated: true);
      });
    }
  }

  @override
  void dispose() {
    _store.removeListener(_storeChanged);
    _autoScroll?.cancel();
    _clock?.cancel();
    _tapTimer?.cancel();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  static bool _sameDays(List<DayKey> a, List<DayKey> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // Data

  void _storeChanged() {
    if (!mounted) return;
    if (_store.revision != _revision) _reload();
    setState(() {});
  }

  void _reload() {
    _revision = _store.revision;
    if (_days.isEmpty) return;
    _blocks = _store.blocks(DayRange(_days.first, _days.last));
    // Dart `PlannerBlock` has no subtasks yet (a request to Track A), so
    // the grid reads them here.
    final subtasks = <String, List<BlockSubtask>>{};
    for (final b in _blocks) {
      final taskId = b.taskId;
      if (taskId == null || subtasks.containsKey(taskId)) continue;
      subtasks[taskId] = [
        for (final t in _store.subtasks(taskId))
          if (t.status != TaskStatus.cancelled)
            BlockSubtask(id: t.id, title: t.title, isDone: t.isDone),
      ];
    }
    _subtasks = subtasks;
    _relayout();
    final ids = {for (final b in _blocks) b.id};
    final selection = _store.selection;
    if (!ids.containsAll(selection)) {
      // The store tells its listeners, and this runs again. Wait for the
      // end of this call.
      scheduleMicrotask(() {
        if (mounted) _store.selection = selection.intersection(ids);
      });
    }
  }

  /// Finds which block lies on which, for each day. It runs again when the
  /// zoom changes: a short block is drawn taller than its length, so it
  /// covers more minutes.
  void _relayout() {
    final geo = _geo;
    final result = <String, Layer>{};
    for (final day in _days) {
      final dayBlocks = _blocks.where((b) => b.day == day).toList();
      final tightById = <String, int>{
        for (final b in dayBlocks)
          if (b.summary.isNotEmpty)
            b.id: PlannerLayoutRules.tightMinutes(
              hourHeight: geo.hourHeight,
              blockHeight: max(PlannerGeometry.minBlockHeight, geo.y(b.length)),
              hasSummary: true,
            ),
      };
      final layers = PlannerMath.layoutLayers(
        [for (final b in dayBlocks) b.span],
        minLength: geo.minDrawnMinutes,
        tightWithin: geo.tightMinutes,
        tightWithinById: tightById,
      );
      for (final entry in layers.entries) {
        result.putIfAbsent(entry.key, () => entry.value);
      }
    }
    _layers = result;
  }

  /// Where a block is drawn. A live drag changes it before a save.
  ({DayKey day, int start, int end}) _displayed(PlannerBlock b) {
    final live = _live;
    final o = live?.originals[b.id];
    if (live == null || o == null) {
      return (day: b.day, start: b.startMinute, end: b.endMinute);
    }
    switch (live.mode) {
      case DragMode.move:
        final s = o.start + live.deltaMinutes;
        return (
          day: o.day.adding(days: live.deltaDays),
          start: s,
          end: s + (o.end - o.start),
        );
      case DragMode.resizeTop:
        return (day: o.day, start: o.start + live.deltaMinutes, end: o.end);
      case DragMode.resizeBottom:
        return (day: o.day, start: o.start, end: o.end + live.deltaMinutes);
    }
  }

  /// On a whole point, so the blocks and their text are drawn sharp.
  double get _nowTarget =>
      max(0, _geo.y(max(0, _store.plannerNow - 60))).roundToDouble();

  /// Puts "now" one hour below the top of the grid.
  void scrollToNow({required bool animated}) {
    if (!_scroll.hasClients) return;
    final target = min(_nowTarget, _scroll.position.maxScrollExtent);
    if (animated && _motionOn) {
      unawaited(
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        ),
      );
    } else {
      _scroll.jumpTo(target);
    }
  }

  /// The check box and the space bar. A task block ticks its task. A goal
  /// block adds to the done count of its goal.
  void _toggleDone(PlannerBlock block) {
    final taskId = block.taskId;
    if (taskId != null) {
      _store.toggleDone(taskId: taskId);
    } else if (block.isGoalBlock) {
      _store.toggleGoalBlockDone(eventId: block.id);
    }
  }

  void _selectBlock(PlannerBlock block) {
    _closeDraft();
    _store.selectBlock(block, extend: commandHeld());
    _focus.requestFocus();
  }

  /// True for the second tap of a double tap on the same thing.
  bool _secondTap(String id) {
    final again = _tapId == id && (_tapTimer?.isActive ?? false);
    _tapTimer?.cancel();
    _tapId = again ? null : id;
    if (!again) {
      _tapTimer = Timer(const Duration(milliseconds: 350), () => _tapId = null);
    }
    return again;
  }

  void _blockTapped(PlannerBlock block) {
    final again = _secondTap('block-${block.id}');
    _selectBlock(block);
    // A plain event opens its editor. All other blocks get a title field.
    if (again && (block.kind != EventKind.event || block.isTaskBlock)) {
      setState(() => _renamingId = block.id);
    }
  }

  // The pointer

  Offset _inViewport(Offset global) {
    final box = _viewportKey.currentContext?.findRenderObject();
    return box is RenderBox ? box.globalToLocal(global) : global;
  }

  /// The pointer's y in grid space. It moves when the grid scrolls under a
  /// still pointer.
  double get _pointerY => (_pointer?.last.dy ?? 0) + _scrollY;

  void _setOverStrip(bool value) {
    if (_overStrip == value) return;
    _overStrip = value;
    widget.onStripTarget?.call(value);
  }

  // A drag of a block

  void _blockDragStart(PlannerBlock block, DragMode mode, Offset global) {
    if (_isDragging) return;
    final selection = _store.selection;
    final List<String> ids;
    if (mode == DragMode.move && selection.contains(block.id)) {
      ids = [
        for (final b in _blocks)
          if (selection.contains(b.id)) b.id,
      ];
    } else {
      ids = [block.id];
      _store.selection = {block.id};
    }
    final at = _inViewport(global);
    setState(() {
      _live = LiveEdit(
        mode: mode,
        ids: ids,
        primaryId: block.id,
        originals: {
          for (final b in _blocks)
            if (ids.contains(b.id))
              b.id: BlockEdit(
                id: b.id,
                day: b.day,
                start: b.startMinute,
                end: b.endMinute,
              ),
        },
      );
      _pointer = _Pointer(start: at + Offset(0, _scrollY), last: at);
      _draft = null;
    });
    _focus.requestFocus();
    _startAutoScroll();
  }

  void _dragUpdate(Offset global) {
    final p = _pointer;
    if (p == null) return;
    p.last = _inViewport(global);
    if (_live != null) _refreshLive();
    if (_create != null) _refreshCreate();
  }

  void _refreshLive() {
    final live = _live;
    final p = _pointer;
    final primary = live?.originals[live.primaryId];
    if (live == null || p == null || primary == null) return;
    const step = PlannerMath.step;
    final raw = ((_pointerY - p.start.dy) / widget.hourHeight * 60).round();
    final before = live.deltaMinutes;
    final beforeDays = live.deltaDays;
    switch (live.mode) {
      case DragMode.move:
        final target = PlannerMath.snap(primary.start + raw, step: step);
        final starts = live.originals.values.map((o) => o.start);
        final ends = live.originals.values.map((o) => o.end);
        live.deltaMinutes = max(
          -starts.reduce(min),
          min(target - primary.start, PlannerMath.dayEnd - ends.reduce(max)),
        );
        if (_days.length > 1) {
          final indexes = [
            for (final o in live.originals.values)
              if (_days.contains(o.day)) _days.indexOf(o.day),
          ];
          final rawDays = ((p.last.dx - p.start.dx) / _dayWidth).round();
          final lo = -(indexes.isEmpty ? 0 : indexes.reduce(min));
          final hi =
              _days.length - 1 - (indexes.isEmpty ? 0 : indexes.reduce(max));
          live.deltaDays = max(lo, min(rawDays, hi));
        }
        // Above the top of the visible grid is the sticky strip.
        final primaryBlock = _block(live.primaryId);
        _setOverStrip(p.last.dy < 0 && (primaryBlock?.isTaskBlock ?? false));
      case DragMode.resizeTop:
        final r = PlannerMath.resizeTop(
          start: primary.start,
          end: primary.end,
          newStart: primary.start + raw,
          step: step,
          minLen: PlannerMath.minLength,
        );
        live.deltaMinutes = r.$1 - primary.start;
      case DragMode.resizeBottom:
        final r = PlannerMath.resizeBottom(
          start: primary.start,
          end: primary.end,
          newEnd: primary.end + raw,
          step: step,
          minLen: PlannerMath.minLength,
        );
        live.deltaMinutes = r.$2 - primary.end;
    }
    if (live.deltaMinutes != before) unawaited(HapticFeedback.selectionClick());
    if (live.deltaMinutes != before || live.deltaDays != beforeDays) {
      setState(() {});
    }
  }

  void _blockDragEnd() {
    final live = _live;
    if (live == null) return;
    _refreshLive();
    final toStrip = _overStrip && live.mode == DragMode.move;
    final edits = <BlockEdit>[
      for (final id in [
        live.primaryId,
        ...live.ids.where((id) => id != live.primaryId),
      ])
        if (_block(id) case final b?)
          () {
            final s = _displayed(b);
            return BlockEdit(id: id, day: s.day, start: s.start, end: s.end);
          }(),
    ];
    final moved = live.deltaMinutes != 0 || live.deltaDays != 0;
    _autoScroll?.cancel();
    _setOverStrip(false);
    setState(() {
      _live = null;
      _pointer = null;
    });
    if (toStrip) {
      _store.deleteBlocks(live.ids, name: 'Unschedule');
    } else if (moved && edits.isNotEmpty) {
      _store.applyEdits(
        edits,
        ripple: HardwareKeyboard.instance.isShiftPressed,
        name: live.mode == DragMode.move ? 'Move Block' : 'Resize Block',
      );
    }
  }

  PlannerBlock? _block(String id) {
    for (final b in _blocks) {
      if (b.id == id) return b;
    }
    return null;
  }

  // A drag on empty time

  void _createStart(int index, Offset global) {
    if (_isDragging) return;
    final at = _inViewport(global);
    final start = at + Offset(0, _scrollY);
    final anchor = PlannerMath.snap(
      _geo.minute(start.dy),
      step: PlannerMath.step,
    ).clamp(0, PlannerMath.dayEnd);
    _closeDraft();
    setState(() {
      _create = CreateDrag(dayIndex: index, anchor: anchor);
      _pointer = _Pointer(start: start, last: at);
      _renamingId = null;
    });
    _store.selection = {};
    _focus.requestFocus();
    _startAutoScroll();
  }

  void _refreshCreate() {
    final create = _create;
    if (create == null) return;
    final minute = PlannerMath.snap(
      _geo.minute(_pointerY),
      step: PlannerMath.step,
    ).clamp(0, PlannerMath.dayEnd);
    if (minute == create.current) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() => create.current = minute);
  }

  void _createEnd() {
    final create = _create;
    if (create == null) return;
    _refreshCreate();
    var s = min(create.anchor, create.current);
    var e = max(create.anchor, create.current);
    if (e - s < PlannerMath.minLength) e = s + 30;
    if (e > PlannerMath.dayEnd) {
      e = PlannerMath.dayEnd;
      s = min(s, PlannerMath.dayEnd - PlannerMath.minLength);
    }
    _autoScroll?.cancel();
    setState(() {
      _create = null;
      _pointer = null;
      _draft = Draft(
        serial: ++_draftSerial,
        day: _days[create.dayIndex],
        start: s,
        end: e,
        asEvent: commandHeld(),
      );
    });
  }

  void _columnTapped(DayKey day, Offset global) {
    if (_isDragging) return;
    final again = _secondTap('column');
    _closeDraft();
    _store.selection = {};
    setState(() {
      _renamingId = null;
      if (again) {
        // A double tap makes a 30-minute block.
        final y = _inViewport(global).dy + _scrollY;
        final s = PlannerMath.clampMove(
          start: PlannerMath.snap(_geo.minute(y), step: PlannerMath.step),
          length: 30,
        );
        _draft = Draft(serial: ++_draftSerial, day: day, start: s, end: s + 30);
      }
    });
    if (!again) _focus.requestFocus();
  }

  // The draft

  /// Makes the task (or the event) from the draft. `refocus` gives the keys
  /// back to the grid, as Return does.
  void _commitDraft(
    String text, {
    required int serial,
    required bool command,
    bool refocus = true,
  }) {
    final current = _draft;
    if (current == null || current.serial != serial) return;
    setState(() => _draft = null);
    _store.createFromDraft(
      title: text,
      day: current.day,
      start: current.start,
      end: current.end,
      asEvent: command || current.asEvent,
    );
    if (refocus) _focus.requestFocus();
  }

  /// The draft goes because the user clicked on another place. The text the
  /// user typed is kept.
  void _closeDraft() {
    final current = _draft;
    if (current == null) return;
    if (InlineTitleRules.onBlur(current.text) == BlurAction.commit) {
      _commitDraft(
        current.text,
        serial: current.serial,
        command: false,
        refocus: false,
      );
    }
    if (mounted) setState(() => _draft = null);
  }

  void _cancelDraft(int serial) {
    if (_draft?.serial != serial) return;
    // Esc: the title field still has the keys. Give them to the grid.
    final hadKeys = _focus.hasFocus;
    setState(() => _draft = null);
    if (hadKeys) _focus.requestFocus();
  }

  // Things dropped on a day

  bool _accepts(String raw) =>
      DragPayload.noteId(raw) != null ||
      DragPayload.goalId(raw) != null ||
      raw.startsWith(DragPayload.taskPrefix);

  void _drop(String raw, DayKey day, Offset global) {
    final y = _inViewport(global).dy + _scrollY;
    final minute = PlannerMath.snap(
      _geo.minute(y),
      step: PlannerMath.step,
    ).clamp(0, PlannerMath.dayEnd - PlannerMath.minLength);
    final noteId = DragPayload.noteId(raw);
    if (noteId != null) {
      _store.addNoteToPlanner(noteId, on: day, at: minute);
    } else if (DragPayload.goalId(raw) != null) {
      _store.dropGoalOnPlanner(raw: raw, day: day, minute: minute);
    } else if (raw.startsWith(DragPayload.taskPrefix)) {
      _store.schedule(
        taskId: raw.substring(DragPayload.taskPrefix.length),
        day: day,
        start: minute,
      );
    }
  }

  // Auto-scroll

  /// Scrolls the grid while the pointer is near its top or bottom edge.
  void _startAutoScroll() {
    _autoScroll?.cancel();
    _autoScroll = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final p = _pointer;
      // No scroll while the block is over the strip.
      if (p == null || _overStrip || !_scroll.hasClients) return;
      const edge = 40.0;
      const top = 24.0;
      final y = p.last.dy;
      final height = _scroll.position.viewportDimension;
      var speed = 0.0;
      if (y < edge) {
        speed = -min(top, (edge - y) / edge * top);
      } else if (y > height - edge) {
        speed = min(top, (y - (height - edge)) / edge * top);
      }
      if (speed == 0) return;
      final next = (_scroll.offset + speed).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      if (next == _scroll.offset) return;
      _scroll.jumpTo(next);
      if (_live != null) _refreshLive();
      if (_create != null) _refreshCreate();
    });
  }

  // Keys

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // A title field is open. The keys are for it.
    if (_draft != null || _renamingId != null) return KeyEventResult.ignored;
    final selected = [
      for (final b in _blocks)
        if (_store.selection.contains(b.id)) b,
    ];
    final ids = [for (final b in selected) b.id];
    final key = event.logicalKey;
    final keys = HardwareKeyboard.instance;
    final shift = keys.isShiftPressed;

    if (commandHeld()) {
      if (key == LogicalKeyboardKey.keyD && selected.isNotEmpty) {
        _store.duplicate(blockIds: ids);
      } else if (key == LogicalKeyboardKey.equal ||
          key == LogicalKeyboardKey.add ||
          key == LogicalKeyboardKey.numpadAdd) {
        _store.zoomPlanner(1.2);
      } else if (key == LogicalKeyboardKey.minus ||
          key == LogicalKeyboardKey.numpadSubtract) {
        _store.zoomPlanner(1 / 1.2);
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    if (keys.isControlPressed || keys.isMetaPressed || keys.isAltPressed) {
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.escape) {
      if (_store.selection.isEmpty) return KeyEventResult.ignored;
      _store.selection = {};
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyN && !shift) {
      final today = _store.plannerToday;
      final day = _days.contains(today) ? today : _days.first;
      final slot = _store.nextFreeSlot(
        day: day,
        length: 30,
        workStart: widget.workStart,
        step: PlannerMath.step,
      );
      if (slot == null) return KeyEventResult.ignored;
      setState(() {
        _draft = Draft(
          serial: ++_draftSerial,
          day: day,
          start: slot,
          end: slot + 30,
        );
      });
      _store.selection = {};
      return KeyEventResult.handled;
    }
    if (selected.isEmpty) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final direction = key == LogicalKeyboardKey.arrowUp ? -1 : 1;
      if (shift) {
        // Shorter or longer: the end moves to the next grid line.
        _store.applyEdits(
          [
            for (final b in selected)
              () {
                final r = PlannerMath.resizeBottom(
                  start: b.startMinute,
                  end: b.endMinute,
                  newEnd: PlannerMath.stepped(
                    b.endMinute,
                    by: direction,
                    step: PlannerMath.step,
                  ),
                  step: 1,
                  minLen: PlannerMath.minLength,
                );
                return BlockEdit(id: b.id, day: b.day, start: r.$1, end: r.$2);
              }(),
          ],
          ripple: false,
          name: 'Resize Block',
        );
      } else {
        // The earliest start goes to the next grid line. The other blocks
        // keep their distance to it.
        final minStart = selected.map((b) => b.startMinute).reduce(min);
        final maxEnd = selected.map((b) => b.endMinute).reduce(max);
        final amount =
            PlannerMath.stepped(
              minStart,
              by: direction,
              step: PlannerMath.step,
            ) -
            minStart;
        final d = max(-minStart, min(amount, PlannerMath.dayEnd - maxEnd));
        _store.applyEdits(
          [
            for (final b in selected)
              BlockEdit(
                id: b.id,
                day: b.day,
                start: b.startMinute + d,
                end: b.endMinute + d,
              ),
          ],
          ripple: false,
          name: 'Move Block',
        );
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      final step = key == LogicalKeyboardKey.arrowLeft ? -1 : 1;
      _store.applyEdits(
        [
          for (final b in selected)
            BlockEdit(
              id: b.id,
              day: b.day.adding(days: step),
              start: b.startMinute,
              end: b.endMinute,
            ),
        ],
        ripple: false,
        name: 'Move Block',
      );
      if (_days.length == 1) {
        _store.selectedDay = _store.selectedDay.adding(days: step);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      setState(() => _renamingId = selected.first.id);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      selected.forEach(_toggleDone);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _store.deleteBlocks(
        ids,
        name: selected.every((b) => b.isTaskBlock)
            ? 'Unschedule'
            : 'Delete Block',
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // The menu

  Future<T?> _menu<T>(Offset global, List<PopupMenuEntry<T>> items) {
    final theme = GroveTheme.of(context);
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    return showMenu<T>(
      context: context,
      color: theme.solidSurface,
      position: RelativeRect.fromRect(
        global & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: items,
    );
  }

  PopupMenuItem<VoidCallback> _item(
    String label,
    VoidCallback? action, {
    bool more = false,
  }) {
    final theme = GroveTheme.of(context);
    return PopupMenuItem<VoidCallback>(
      value: action,
      enabled: action != null,
      height: 34,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme
                  .body(13)
                  .copyWith(color: action == null ? theme.muted : theme.ink),
            ),
          ),
          if (more) Icon(Icons.chevron_right, size: 16, color: theme.muted),
        ],
      ),
    );
  }

  Future<void> _openMenu(PlannerBlock block, Offset global) async {
    final store = _store;
    final ids = store.selection.contains(block.id)
        ? store.selection.toList()
        : [block.id];
    final taskId = block.taskId;
    final plainEvent = block.kind == EventKind.event && !block.isTaskBlock;
    final action = await _menu<VoidCallback>(global, [
      if (block.isGoalBlock) ...[
        _item('Goal block · ${PlannerMath.duration(block.length)}', null),
        const PopupMenuDivider(),
      ],
      if (plainEvent) ...[
        _item('Edit Event…', () {
          final e = store.event(block.id);
          if (e != null) store.editEvent(e);
        }),
        const PopupMenuDivider(),
      ],
      _item('Duration', () => _openDurations(ids, global), more: true),
      _item('Colour', () => _openColours(ids, global), more: true),
      const PopupMenuDivider(),
      _item('Duplicate', () => store.duplicate(blockIds: ids)),
      _item('Split in Two', () => store.split(blockId: block.id)),
      if (block.isGoalBlock)
        _item(
          block.isDone ? 'Mark Not Done' : 'Mark Done',
          () => store.toggleGoalBlockDone(eventId: block.id),
        ),
      if (taskId != null) ...[
        _item(
          block.isDone ? 'Mark Not Done' : 'Mark Done',
          () => store.toggleDone(taskId: taskId),
        ),
        if (store.focus?.blockId == block.id)
          _item('Stop Focus', store.stopFocus)
        else if (!block.isDone)
          _item('Start Focus', () {
            final e = store.event(block.id);
            if (e != null) store.startFocus(e);
          }),
      ],
      const PopupMenuDivider(),
      if (block.isTaskBlock) ...[
        _item('Unschedule', () => store.deleteBlocks(ids, name: 'Unschedule')),
        if (taskId != null)
          _item('Delete Task', () => store.deleteTask(taskId)),
      ] else if (block.isGoalBlock)
        _item(
          'Delete Goal Block',
          () => store.deleteBlocks(ids, name: 'Delete Goal Block'),
        )
      else
        _item(
          'Delete Event',
          () => store.deleteBlocks(ids, name: 'Delete Event'),
        ),
    ]);
    if (mounted) action?.call();
  }

  Future<void> _openDurations(List<String> ids, Offset global) async {
    final action = await _menu<VoidCallback>(global, [
      for (final m in PlannerLimits.durationChoices)
        _item(
          PlannerMath.duration(m),
          () => _store.setDuration(blockIds: ids, minutes: m),
        ),
    ]);
    if (mounted) action?.call();
  }

  Future<void> _openColours(List<String> ids, Offset global) async {
    final action = await _menu<VoidCallback>(global, [
      for (final name in NamedColors.blockColorNames)
        _item(
          name[0].toUpperCase() + name.substring(1),
          () => _store.setColor(blockIds: ids, name: name),
        ),
    ]);
    if (mounted) action?.call();
  }

  // The layers

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    _motionOn = MotionRules.isOn(
      setting: _store.motionSetting,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
    );
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, box) {
          _gridWidth = box.maxWidth;
          final geo = _geo;
          return Stack(
            children: [
              Positioned.fill(
                child: SingleChildScrollView(
                  key: _viewportKey,
                  controller: _scroll,
                  // The grid must not scroll under a drag.
                  physics: _isDragging
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  child: SizedBox(
                    width: _gridWidth,
                    height: geo.totalHeight,
                    child: Stack(children: _layerWidgets(theme, geo)),
                  ),
                ),
              ),
              if (_blocks.isEmpty && _draft == null && _create == null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Drag a task here, or drag on the grid to plan '
                          'time.',
                          textAlign: TextAlign.center,
                          style: theme.body(13).copyWith(color: theme.muted),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _layerWidgets(GroveTheme theme, PlannerGeometry geo) {
    const gutter = PlannerGeometry.gutterWidth;
    final today = _store.plannerToday;
    final now = _store.plannerNow;
    final todayIndex = _days.indexOf(today);
    final indents = _indents(geo);

    // Later start = on top. The dragged blocks are above all others.
    final ordered = [..._blocks]
      ..sort((a, b) {
        final liveA = _live?.ids.contains(a.id) ?? false;
        final liveB = _live?.ids.contains(b.id) ?? false;
        if (liveA != liveB) return liveA ? 1 : -1;
        return (_layers[a.id]?.order ?? 0).compareTo(_layers[b.id]?.order ?? 0);
      });

    return [
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: _GridLinesPainter(
              hourHeight: geo.hourHeight,
              color: theme.line,
            ),
          ),
        ),
      ),
      for (var h = 1; h < 24; h++)
        Positioned(
          left: 0,
          top: geo.y(h * 60) - 7,
          width: gutter - 10,
          child: IgnorePointer(
            child: Text(
              '${h.toString().padLeft(2, '0')}:00',
              textAlign: TextAlign.right,
              maxLines: 1,
              style: theme
                  .number(10, weight: FontWeight.w500)
                  .copyWith(color: theme.muted, height: 1.4),
            ),
          ),
        ),
      for (final (index, day) in _days.indexed)
        Positioned(
          left: _dayLeft(index),
          top: 0,
          width: _dayWidthAt(index),
          height: geo.totalHeight,
          child: _dayColumn(theme, geo, index, day, isToday: day == today),
        ),
      if (todayIndex >= 0)
        Positioned(
          left: _dayLeft(todayIndex),
          top: 0,
          width: _dayWidthAt(todayIndex),
          height: geo.y(now),
          child: IgnorePointer(
            child: ColoredBox(color: theme.bg.withValues(alpha: 0.35)),
          ),
        ),
      for (final block in ordered) ?_blockWidget(geo, block, indents),
      ?_createRect(theme, geo),
      if (todayIndex >= 0)
        Positioned(
          key: const ValueKey('now-line'),
          left: _dayLeft(todayIndex) - 4,
          top: geo.y(now) - 4.5,
          width: _dayWidthAt(todayIndex) + 4,
          height: 9,
          child: IgnorePointer(
            child: ExcludeSemantics(child: _NowLine(pulses: _motionOn)),
          ),
        ),
      ?_draftWidget(theme, geo),
      ?_liveLabel(theme, geo),
    ];
  }

  Widget _dayColumn(
    GroveTheme theme,
    PlannerGeometry geo,
    int index,
    DayKey day, {
    required bool isToday,
  }) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        if (!_accepts(details.data)) return false;
        setState(() => _targetedDay = day);
        return true;
      },
      onLeave: (_) {
        if (_targetedDay == day) setState(() => _targetedDay = null);
      },
      onAcceptWithDetails: (details) {
        setState(() => _targetedDay = null);
        _drop(details.data, day, details.offset);
      },
      builder: (context, _, _) => _ColumnGestures(
        key: ValueKey('day-column-${day.string}'),
        onTap: (at) => _columnTapped(day, at),
        onDragStart: (at) => _createStart(index, at),
        onDragUpdate: _dragUpdate,
        onDragEnd: _createEnd,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: geo.y(widget.workStart),
              height: max(0, geo.y(widget.workEnd - widget.workStart)),
              child: ColoredBox(color: theme.accent.withValues(alpha: 0.045)),
            ),
            if (_targetedDay == day)
              Positioned.fill(
                child: ColoredBox(color: theme.accent.withValues(alpha: 0.10)),
              ),
            if (index > 0)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 1,
                child: ColoredBox(color: theme.line),
              ),
            if (isToday && _days.length > 1)
              Positioned.fill(
                child: ColoredBox(color: theme.accent.withValues(alpha: 0.06)),
              ),
          ],
        ),
      ),
    );
  }

  /// Blocks that overlap lie on top of each other. Each one starts a little
  /// to the right of the block below it. The points come from the column
  /// width, so they are found here and not in the layout step.
  Map<String, double> _indents(PlannerGeometry geo) {
    final colW = _dayWidth - 9;
    final byId = {for (final b in _blocks) b.id: b};
    final base = min(150.0, max(56.0, colW * 0.45));
    double tight(String id) {
      final b = byId[id];
      if (b == null) return base;
      // A one-row block shows only its title. The block above it moves
      // right by about the width of that title.
      if (b.length < 25 || geo.y(b.length) < 34) {
        return min(colW * 0.5, max(base, 38 + 6.0 * b.title.runes.length));
      }
      // A block that shows a short description keeps the full line clear,
      // as far as the column allows.
      final height = max(PlannerGeometry.minBlockHeight, geo.y(b.length));
      final lines = PlannerLayoutRules.blockTextLines(
        height: height,
        hasSummary: true,
      );
      if (b.summary.isNotEmpty && lines.summary > 0) {
        return max(
          base,
          PlannerLayoutRules.textClearance(
            title: b.title,
            summary: b.summary,
            columnWidth: colW,
          ),
        );
      }
      return base;
    }

    return PlannerMath.indents(
      _layers,
      far: min(16, max(8, colW * 0.10)),
      tight: tight,
      maxIndent: colW * 0.62,
    );
  }

  Widget? _blockWidget(
    PlannerGeometry geo,
    PlannerBlock block,
    Map<String, double> indents,
  ) {
    final shown = _displayed(block);
    final dayIndex = _days.indexOf(shown.day);
    if (dayIndex < 0) return null;
    final layer = shown.day == block.day ? _layers[block.id] : null;
    final indent = layer == null
        ? 0.0
        : (indents[block.id] ?? 0.0).roundToDouble();
    final width = max(20.0, _dayWidthAt(dayIndex) - 9 - indent);
    final height = max(
      PlannerGeometry.minBlockHeight,
      geo.y(shown.end - shown.start) - 1,
    );
    final isLive = _live?.ids.contains(block.id) ?? false;
    return AnimatedPositioned(
      key: ValueKey('block-${block.id}'),
      duration: isLive || !_motionOn
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      left: _dayLeft(dayIndex) + 2 + indent,
      top: geo.y(shown.start),
      width: width,
      height: height,
      child: BlockView(
        block: block,
        start: shown.start,
        end: shown.end,
        size: Size(width, height),
        subtasks: _subtasks[block.taskId] ?? const [],
        isOverlay: (layer?.depth ?? 0) > 0,
        isSelected: _store.selection.contains(block.id),
        isDragging: isLive,
        isRenaming: _renamingId == block.id,
        onTap: () => _blockTapped(block),
        onToggleDone: () => _toggleDone(block),
        onRename: (text) {
          _store.rename(blockId: block.id, to: text);
          setState(() => _renamingId = null);
          _focus.requestFocus();
        },
        onCancelRename: () {
          if (_renamingId != block.id) return;
          final hadKeys = _focus.hasFocus;
          setState(() => _renamingId = null);
          if (hadKeys) _focus.requestFocus();
        },
        onDragStart: (mode, at) => _blockDragStart(block, mode, at),
        onDragUpdate: _dragUpdate,
        onDragEnd: _blockDragEnd,
        onMenu: (at) => unawaited(_openMenu(block, at)),
      ),
    );
  }

  Widget? _createRect(GroveTheme theme, PlannerGeometry geo) {
    final c = _create;
    if (c == null) return null;
    final s = min(c.anchor, c.current);
    final e = max(c.anchor, c.current);
    return Positioned(
      key: const ValueKey('create-rect'),
      left: _dayLeft(c.dayIndex) + 2,
      top: geo.y(s),
      width: _dayWidthAt(c.dayIndex) - 6,
      height: max(4, geo.y(max(e - s, PlannerMath.minLength))),
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.accent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.accent, width: 1.5),
          ),
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minHeight: 0,
              maxHeight: double.infinity,
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Text(
                  PlannerMath.label(
                    start: s,
                    end: max(e, s + PlannerMath.minLength),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  softWrap: false,
                  style: theme
                      .body(10, weight: FontWeight.w700)
                      .copyWith(color: theme.accent),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget? _draftWidget(GroveTheme theme, PlannerGeometry geo) {
    final d = _draft;
    if (d == null) return null;
    final index = _days.indexOf(d.day);
    if (index < 0) return null;
    final width = _dayWidthAt(index) - 6;
    final matches = _store.matchingTasks(d.text, on: d.day);
    return Positioned(
      key: ValueKey('draft-${d.serial}'),
      left: _dayLeft(index) + 2,
      top: geo.y(d.start),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Container(
            key: const ValueKey('planner-draft'),
            width: width,
            height: max(26, geo.y(d.end - d.start)),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: theme.solidSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.accent, width: 2),
            ),
            clipBehavior: Clip.hardEdge,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minHeight: 0,
              maxHeight: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: 1,
                children: [
                  Text(
                    PlannerMath.label(start: d.start, end: d.end),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: theme
                        .body(10, weight: FontWeight.w700)
                        .copyWith(color: theme.accent),
                  ),
                  InlineTitleField(
                    placeholder: d.asEvent ? 'New event' : 'New task',
                    onChanged: (text) => setState(() => d.text = text),
                    onCommit: (text, command) =>
                        _commitDraft(text, serial: d.serial, command: command),
                    onBlurCommit: (text) => _commitDraft(
                      text,
                      serial: d.serial,
                      command: false,
                      refocus: false,
                    ),
                    onCancel: () => _cancelDraft(d.serial),
                  ),
                ],
              ),
            ),
          ),
          if (matches.isNotEmpty)
            Container(
              width: max(160, width),
              decoration: BoxDecoration(
                color: theme.solidSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.line),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1F000000),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
                    child: Text(
                      'Schedule existing task',
                      style: theme
                          .body(10, weight: FontWeight.w700)
                          .copyWith(color: theme.muted),
                    ),
                  ),
                  for (final t in matches)
                    Semantics(
                      button: true,
                      child: GestureDetector(
                        key: ValueKey('suggest-${t.id}'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() => _draft = null);
                          _store.schedule(
                            taskId: t.id,
                            day: d.day,
                            start: d.start,
                            length: d.end - d.start,
                          );
                          _focus.requestFocus();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          child: Text(
                            t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.body(12).copyWith(color: theme.ink),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// The time of the dragged block, next to it.
  Widget? _liveLabel(GroveTheme theme, PlannerGeometry geo) {
    final live = _live;
    final block = live == null ? null : _block(live.primaryId);
    if (block == null) return null;
    final shown = _displayed(block);
    final index = _days.indexOf(shown.day);
    if (index < 0) return null;
    return Positioned(
      key: const ValueKey('live-label'),
      left: _dayLeft(index) + 8,
      top: geo.y(shown.start) - 26 + (shown.start < 40 ? 40 : 0),
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: theme.ink,
            shape: const StadiumBorder(),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              PlannerMath.label(start: shown.start, end: shown.end),
              maxLines: 1,
              style: theme
                  .number(11, weight: FontWeight.w700)
                  .copyWith(color: theme.bg),
            ),
          ),
        ),
      ),
    );
  }
}

/// The gestures of an empty part of a day. A tap clears the selection. A
/// mouse drag makes a block. A finger must press and hold first, so a swipe
/// scrolls the grid.
class _ColumnGestures extends StatelessWidget {
  const _ColumnGestures({
    super.key,
    required this.onTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.child,
  });

  final ValueChanged<Offset> onTap;
  final ValueChanged<Offset> onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: HitTestBehavior.opaque,
    gestures: {
      TapGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            TapGestureRecognizer.new,
            (tap) => tap.onTapUp = (d) => onTap(d.globalPosition),
          ),
      PanGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
            () => PanGestureRecognizer(supportedDevices: mouseKinds),
            (pan) {
              pan.dragStartBehavior = DragStartBehavior.down;
              pan.onStart = (d) => onDragStart(d.globalPosition);
              pan.onUpdate = (d) => onDragUpdate(d.globalPosition);
              pan.onEnd = (_) => onDragEnd();
              pan.onCancel = onDragEnd;
            },
          ),
      LongPressGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(supportedDevices: touchKinds),
            (press) {
              press.onLongPressStart = (d) => onDragStart(d.globalPosition);
              press.onLongPressMoveUpdate = (d) =>
                  onDragUpdate(d.globalPosition);
              press.onLongPressEnd = (_) => onDragEnd();
              press.onLongPressCancel = onDragEnd;
            },
          ),
    },
    child: child,
  );
}

/// Hour lines, and faint half-hour lines.
class _GridLinesPainter extends CustomPainter {
  const _GridLinesPainter({required this.hourHeight, required this.color});

  final double hourHeight;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const gutter = PlannerGeometry.gutterWidth;
    final hour = Paint()
      ..color = color
      ..strokeWidth = 1;
    final half = Paint()
      ..color = color.withValues(alpha: color.a * 0.45)
      ..strokeWidth = 1;
    for (var h = 0; h <= 24; h++) {
      final y = h * hourHeight;
      canvas.drawLine(Offset(gutter - 6, y), Offset(size.width, y), hour);
      if (h == 24) continue;
      final mid = y + hourHeight / 2;
      for (var x = gutter; x < size.width; x += 6) {
        canvas.drawLine(
          Offset(x, mid),
          Offset(min(x + 2, size.width), mid),
          half,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GridLinesPainter old) =>
      old.hourHeight != hourHeight || old.color != color;
}

/// The line for "now": a dot and a 2-point line. It pulses slowly when
/// motion is on and the app is in front.
class _NowLine extends StatefulWidget {
  const _NowLine({required this.pulses});

  final bool pulses;

  @override
  State<_NowLine> createState() => _NowLineState();
}

class _NowLineState extends State<_NowLine>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker = createTicker(_onTick);
  final _opacity = ValueNotifier<double>(1);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sync();
  }

  @override
  void didUpdateWidget(_NowLine old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _sync();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _opacity.dispose();
    super.dispose();
  }

  void _sync() {
    final state = WidgetsBinding.instance.lifecycleState;
    final runs = MotionRules.ambientRuns(
      motionOn: widget.pulses,
      windowIsKey: state == null || state == AppLifecycleState.resumed,
    );
    if (runs && !_ticker.isActive) {
      unawaited(_ticker.start());
    } else if (!runs && _ticker.isActive) {
      _ticker.stop();
      _opacity.value = 1;
    }
  }

  void _onTick(Duration elapsed) {
    final next = PulseMath.opacity(
      elapsed.inMicroseconds / Duration.microsecondsPerSecond,
    );
    // 20 steps a second are enough for a slow pulse.
    if ((next - _opacity.value).abs() >= 0.01) _opacity.value = next;
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final glow = [
      if (theme.glow)
        BoxShadow(color: theme.accent2.withValues(alpha: 0.8), blurRadius: 5),
    ];
    return ValueListenableBuilder<double>(
      valueListenable: _opacity,
      builder: (context, opacity, child) =>
          Opacity(opacity: opacity, child: child),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.accent2,
              shape: BoxShape.circle,
              boxShadow: glow,
            ),
            child: const SizedBox.square(dimension: 9),
          ),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(color: theme.accent2, boxShadow: glow),
              child: const SizedBox(height: 2),
            ),
          ),
        ],
      ),
    );
  }
}
