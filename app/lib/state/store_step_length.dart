part of 'app_store.dart';

/// One step: a square of a project or a goal subtask of a habit.
typedef GoalStep = ({bool square, String id});

/// A step and its block have the same length, both ways (owner, 2026-11-06).
/// A block holds one step at most, and a step sits on one block at most. The
/// link holds only for such a pair: an old block with many steps is free.
///
/// Every saved change goes through [_linkStepLengths], so a resize on the
/// grid, the duration menu, the event editor and the Goals screen all keep
/// the pair the same, in the same undo step.
extension AppStoreStepLength on AppStore {
  /// The shortest length a step can have, as for a block.
  static const minLength = 5;

  /// Sets how long a square takes. Null clears it. Its block follows.
  void setSquareLength(String id, int? minutes) {
    final old = goalSquare(id);
    if (old == null || old.isRoot) return;
    final length = _cleanLength(minutes);
    if (length == old.lengthMinutes) return;
    commit(
      Mutation(
        'Change Length',
      )..squares.add((before: old, after: old.copyWith(lengthMinutes: length))),
    );
  }

  /// Sets how long a goal subtask takes. Null clears it. Its block follows.
  void setGoalSubtaskLength(String id, int? minutes) {
    final old = _try(() => repos.goalSubtasks.get(id));
    if (old == null) return;
    final length = _cleanLength(minutes);
    if (length == old.lengthMinutes) return;
    commit(
      Mutation('Change Length')
        ..goalSubtasks.add((
          before: old,
          after: old.copyWith(lengthMinutes: length),
        )),
    );
  }

  int? _cleanLength(int? minutes) => minutes == null || minutes <= 0
      ? null
      : min(1440, max(minLength, minutes));

  /// The step that a block holds when it holds exactly one, as the database
  /// has it now. Null for an empty block or an old block with many steps.
  GoalStep? soleStepOfBlock(String eventId) {
    final steps = _stepsOfBlock(eventId, Mutation(''));
    return steps.length == 1 ? steps.single : null;
  }

  /// True when the block can take [step]: it holds no other step.
  bool blockCanTakeStep(String eventId, {String? squareId, String? subtaskId}) {
    final steps = _stepsOfBlock(eventId, Mutation(''));
    return steps.every((s) => s.square ? s.id == squareId : s.id == subtaskId);
  }

  /// The stored block that holds only [step], when the step sits on only
  /// it. Dragging the step again moves this block.
  EventItem? _ownBlockOfStep(GoalStep step) {
    final id = _soleBlockOf(step, Mutation(''));
    if (id == null || _pairOf(id, Mutation('')) == null) return null;
    return event(id);
  }

  /// Moves a step's block to [day] at [start]. Its length stays.
  void _moveStepBlock(
    EventItem block, {
    required DayKey day,
    required int start,
    required String name,
  }) {
    final length = block.durationMinutes;
    final from = max(0, min(start, 1440 - length));
    final moved = block.copyWith(
      start: WallTime(day: day, minute: from),
      end: WallTime(day: day, minute: from + length),
    );
    if (commit(Mutation(name)..events.add((before: block, after: moved)))) {
      selection = {block.id};
    }
  }

  // The link, run by `commit`.

  void _linkStepLengths(Mutation m) {
    // Block changes first, then step changes, then steps put in a block.
    final fromBlocks = <String>[
      for (final c in m.events)
        if (c.before != null &&
            c.after != null &&
            c.after!.goalId != null &&
            !c.after!.allDay &&
            c.before!.durationMinutes != c.after!.durationMinutes)
          c.after!.id,
    ];
    final fromSteps = <GoalStep>[
      for (final c in m.squares)
        if (c.after != null &&
            c.before?.lengthMinutes != c.after!.lengthMinutes)
          (square: true, id: c.after!.id),
      for (final c in m.goalSubtasks)
        if (c.after != null &&
            c.before?.lengthMinutes != c.after!.lengthMinutes)
          (square: false, id: c.after!.id),
    ];
    final placed = <(String, GoalStep)>[
      for (final c in m.squareBlocks)
        if (c.add) (c.block.eventId, (square: true, id: c.block.squareId)),
      for (final c in m.goalSubtasks)
        if (c.after?.eventId != null && c.after!.eventId != c.before?.eventId)
          (c.after!.eventId!, (square: false, id: c.after!.id)),
    ];
    if (fromBlocks.isEmpty && fromSteps.isEmpty && placed.isEmpty) return;

    final stepsChanged = {for (final s in fromSteps) _key(s)};
    final blocksChanged = {...fromBlocks};

    for (final id in fromBlocks) {
      final step = _pairOf(id, m);
      if (step == null || stepsChanged.contains(_key(step))) continue;
      final block = _blockAfter(id, m)!;
      _setStepLength(m, step, block.durationMinutes);
    }
    for (final step in fromSteps) {
      final blockId = _soleBlockOf(step, m);
      if (blockId == null || blocksChanged.contains(blockId)) continue;
      if (_pairOf(blockId, m) == null) continue;
      final length = _lengthAfter(step, m);
      if (length != null) _setBlockLength(m, blockId, length);
    }
    for (final (blockId, step) in placed) {
      if (blocksChanged.contains(blockId) ||
          stepsChanged.contains(_key(step))) {
        continue;
      }
      final pair = _pairOf(blockId, m);
      if (pair == null || _key(pair) != _key(step)) continue;
      final length = _lengthAfter(step, m);
      final block = _blockAfter(blockId, m)!;
      if (length == null) {
        _setStepLength(m, step, block.durationMinutes);
      } else {
        _setBlockLength(m, blockId, length);
      }
    }
  }

  String _key(GoalStep s) => '${s.square ? 'sq' : 'sub'}|${s.id}';

  /// The step of a stored, timed goal block when the block holds only it and
  /// it sits on no other block, after [m].
  GoalStep? _pairOf(String eventId, Mutation m) {
    if (OccurrenceId.parse(eventId) != null) return null;
    final block = _blockAfter(eventId, m);
    if (block == null || block.goalId == null || block.allDay) return null;
    final steps = _stepsOfBlock(eventId, m);
    if (steps.length != 1) return null;
    final step = steps.single;
    return _soleBlockOf(step, m) == eventId ? step : null;
  }

  EventItem? _blockAfter(String id, Mutation m) {
    for (final c in m.events.reversed) {
      if ((c.after ?? c.before)?.id == id) return c.after;
    }
    return event(id);
  }

  List<GoalStep> _stepsOfBlock(String eventId, Mutation m) {
    final squares = {for (final s in squaresOfBlock(eventId)) s.id};
    for (final c in m.squareBlocks) {
      if (c.block.eventId != eventId) continue;
      c.add ? squares.add(c.block.squareId) : squares.remove(c.block.squareId);
    }
    for (final c in m.squares) {
      if (c.after == null && c.before != null) squares.remove(c.before!.id);
    }
    final subs = {for (final s in plannedGoalSubtasks(eventId)) s.id};
    for (final c in m.goalSubtasks) {
      final id = (c.after ?? c.before)!.id;
      if (c.after?.eventId == eventId) {
        subs.add(id);
      } else {
        subs.remove(id);
      }
    }
    return [
      for (final id in squares.toList()..sort()) (square: true, id: id),
      for (final id in subs.toList()..sort()) (square: false, id: id),
    ];
  }

  /// The one block that holds the step after [m], or null for none or many.
  String? _soleBlockOf(GoalStep step, Mutation m) {
    if (!step.square) {
      for (final c in m.goalSubtasks.reversed) {
        if ((c.after ?? c.before)!.id == step.id) return c.after?.eventId;
      }
      return _try(() => repos.goalSubtasks.get(step.id))?.eventId;
    }
    final blocks = {...?_try(() => repos.goalSquares.blocksOf(step.id))};
    for (final c in m.squareBlocks) {
      if (c.block.squareId != step.id) continue;
      c.add ? blocks.add(c.block.eventId) : blocks.remove(c.block.eventId);
    }
    for (final c in m.events) {
      if (c.after == null && c.before != null) blocks.remove(c.before!.id);
    }
    return blocks.length == 1 ? blocks.single : null;
  }

  int? _lengthAfter(GoalStep step, Mutation m) {
    if (step.square) {
      for (final c in m.squares.reversed) {
        if ((c.after ?? c.before)!.id == step.id) return c.after?.lengthMinutes;
      }
      return goalSquare(step.id)?.lengthMinutes;
    }
    for (final c in m.goalSubtasks.reversed) {
      if ((c.after ?? c.before)!.id == step.id) return c.after?.lengthMinutes;
    }
    return _try(() => repos.goalSubtasks.get(step.id))?.lengthMinutes;
  }

  void _setStepLength(Mutation m, GoalStep step, int minutes) {
    final length = _cleanLength(minutes);
    if (step.square) {
      final i = m.squares.lastIndexWhere(
        (c) => (c.after ?? c.before)!.id == step.id,
      );
      if (i >= 0) {
        final c = m.squares[i];
        if (c.after == null) return;
        m.squares[i] = (
          before: c.before,
          after: c.after!.copyWith(lengthMinutes: length),
        );
        return;
      }
      final old = goalSquare(step.id);
      if (old == null || old.lengthMinutes == length) return;
      m.squares.add((before: old, after: old.copyWith(lengthMinutes: length)));
      return;
    }
    final i = m.goalSubtasks.lastIndexWhere(
      (c) => (c.after ?? c.before)!.id == step.id,
    );
    if (i >= 0) {
      final c = m.goalSubtasks[i];
      if (c.after == null) return;
      m.goalSubtasks[i] = (
        before: c.before,
        after: c.after!.copyWith(lengthMinutes: length),
      );
      return;
    }
    final old = _try(() => repos.goalSubtasks.get(step.id));
    if (old == null || old.lengthMinutes == length) return;
    m.goalSubtasks.add((
      before: old,
      after: old.copyWith(lengthMinutes: length),
    ));
  }

  void _setBlockLength(Mutation m, String blockId, int minutes) {
    EventItem resized(EventItem e) => e.copyWith(
      end: WallTime(
        day: e.start.day,
        minute: min(1440, e.start.minute + minutes),
      ),
    );
    final i = m.events.lastIndexWhere(
      (c) => (c.after ?? c.before)?.id == blockId,
    );
    if (i >= 0) {
      final c = m.events[i];
      if (c.after == null) return;
      m.events[i] = (before: c.before, after: resized(c.after!));
      return;
    }
    final old = event(blockId);
    if (old == null || old.durationMinutes == minutes) return;
    m.events.add((before: old, after: resized(old)));
  }
}
