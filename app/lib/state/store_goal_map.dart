part of 'app_store.dart';

/// What the user says about a square when a block that holds it is ticked.
enum SquareAnswerKind { done, startWaiting, notYet }

class SquareAnswer {
  const SquareAnswer(this.kind, {this.waitMinutes});

  static const done = SquareAnswer(SquareAnswerKind.done);
  static const notYet = SquareAnswer(SquareAnswerKind.notYet);

  final SquareAnswerKind kind;

  /// For a wait: how long. Null keeps the length that the square has.
  final int? waitMinutes;
}

/// Projects and their goal maps (ADR 0008). A project is finished when its
/// root square is ticked. Every write is a single undo step.
extension AppStoreGoalMap on AppStore {
  /// A wait that the user did not give a length.
  static const defaultWaitMinutes = 3 * 24 * 60;

  // Reading

  /// The map of a project, or null when the goal has no squares.
  GoalGraph? goalGraph(String goalId) {
    final squares = _try(() => repos.goalSquares.forGoal(goalId));
    if (squares == null || squares.isEmpty) return null;
    final links =
        _try(() => repos.goalSquares.linksForGoal(goalId)) ??
        const <SquareLink>[];
    return GoalGraph.build(goalId, squares, links);
  }

  GoalSquare? goalSquare(String id) => _try(() => repos.goalSquares.get(id));

  /// True when the root of the project is ticked.
  bool isProjectFinished(String goalId) =>
      goalSquare(GoalSquare.rootIdOf(goalId))?.isDone ?? false;

  /// The squares that a block holds.
  List<GoalSquare> squaresOfBlock(String eventId) =>
      _try(() => repos.goalSquares.forEvents([eventId]))?[eventId] ?? const [];

  /// The squares that a block holds and that are not done. Ticking the block
  /// asks about these.
  List<GoalSquare> openSquaresOfBlock(String eventId) => [
    for (final s in squaresOfBlock(eventId))
      if (!s.isDone) s,
  ];

  /// How many blocks hold a square.
  int blockCountOfSquare(String id) =>
      _try(() => repos.goalSquares.blocksOf(id))?.length ?? 0;

  /// The minutes of all the blocks of a project, on any day, and the length
  /// of each ticked step that no ticked block holds. It is never stored.
  int projectMinutes(String goalId, {bool doneOnly = false}) =>
      (_try(() => repos.goals.totalMinutes(goalId, doneOnly: doneOnly)) ?? 0) +
      (_try(() => repos.goals.stepMinutes(goalId)) ?? 0);

  /// How far a project is.
  ProjectProgress projectProgress(GoalItem g) {
    final graph = goalGraph(g.id);
    return ProjectProgress(
      steps: graph?.stepCount ?? 0,
      stepsDone: graph == null ? 0 : graph.stepCount - graph.openCount,
      doneMinutes: projectMinutes(g.id, doneOnly: true),
      workMinutes: g.workMinutes,
      isFinished: isProjectFinished(g.id),
    );
  }

  /// The open squares that a block of the project can take, Ready ones first:
  /// those on no block. None when the block holds a step already.
  List<GoalSquare> freeSquares(String eventId) {
    final goalId = event(eventId)?.goalId;
    final graph = goalId == null ? null : goalGraph(goalId);
    if (graph == null || !blockCanTakeStep(eventId)) return const [];
    final held = {
      for (final id in graph.ids)
        if (blockCountOfSquare(id) > 0) id,
    };
    return [
      for (final id in [
        ...graph.readyIds,
        ...graph.waitingIds,
        ...graph.laterIds,
      ])
        if (!held.contains(id)) graph.square(id),
    ];
  }

  /// The goal that the Goals screen shows. Its first project, or its first
  /// goal, when the user did not pick one or the goal is gone.
  GoalItem? get shownMapGoal {
    final all = goals();
    return all.where((g) => g.id == _shownMapGoalId).firstOrNull ??
        all.where((g) => g.isProject).firstOrNull ??
        all.firstOrNull;
  }

  /// Shows the goal on the Goals screen, on that screen or not.
  void showMapGoal(String goalId) {
    _shownMapGoalId = goalId;
    _changed();
  }

  /// Goes to the Goals screen, and shows the goal.
  void openGoalMap(String goalId) {
    _shownMapGoalId = goalId;
    screen = Screen.goals;
  }

  // Writing: the project

  /// A new project with its root square. No field is needed.
  GoalItem? addProject({
    String title = '',
    String notes = '',
    String color = '',
    String doneWhen = '',
    int? workMinutes,
    DayKey? dueDay,
    String why = '',
  }) {
    final g = GoalItem(
      title: GoalRules.cleanTitle(title),
      notes: notes,
      color: TaskColor.isValid(color) ? color : '',
      sort: _nextGoalSort(),
      type: GoalType.project,
      doneWhen: doneWhen,
      workMinutes: workMinutes,
      dueDay: dueDay,
      why: why,
    );
    final m = Mutation('New Project')
      ..goals.add((before: null, after: g))
      ..squares.add((
        before: null,
        after: GoalSquare(
          id: GoalSquare.rootIdOf(g.id),
          goalId: g.id,
          title: g.title,
        ),
      ));
    return commit(m) ? g : null;
  }

  /// Changes the fields that are given. Pass null to empty [workMinutes] or
  /// [dueDay]. The title can be empty: no field is needed.
  void updateProject(
    String id, {
    String? title,
    String? notes,
    String? color,
    String? doneWhen,
    Object? workMinutes = keep,
    Object? dueDay = keep,
    String? why,
  }) {
    final old = goal(id);
    if (old == null) return;
    final g = old.copyWith(
      title: title == null ? null : GoalRules.cleanTitle(title),
      notes: notes,
      color: color != null && TaskColor.isValid(color) ? color : null,
      doneWhen: doneWhen,
      workMinutes: workMinutes,
      dueDay: dueDay,
      why: why,
    );
    if (g == old) return;
    final m = Mutation('Edit Project')..goals.add((before: old, after: g));
    final root = goalSquare(GoalSquare.rootIdOf(id));
    if (root != null && root.title != g.title) {
      m.squares.add((before: root, after: root.copyWith(title: g.title)));
    }
    commit(m);
  }

  /// Turns a habit into a project. Its subtasks become squares under the root.
  /// Its blocks and points stay. There is no way back but undo.
  void makeProject(String goalId) {
    final g = goal(goalId);
    if (g == null || g.isProject) return;
    final m = Mutation('Make It a Project')
      ..goals.add((before: g, after: g.copyWith(type: GoalType.project)));
    final rootId = GoalSquare.rootIdOf(goalId);
    if (goalSquare(rootId) == null) {
      m.squares.add((
        before: null,
        after: GoalSquare(id: rootId, goalId: goalId, title: g.title),
      ));
    }
    final plan = _try(() => repos.goalSquares.conversionOf(goalId));
    if (plan != null) {
      for (final s in plan.squares) {
        m.squares.add((before: null, after: s));
      }
      for (final l in plan.links) {
        m.squareLinks.add((link: l, add: true));
      }
      for (final b in plan.blocks) {
        m.squareBlocks.add((block: b, add: true));
      }
      for (final id in plan.subtaskIds) {
        final sub = _try(() => repos.goalSubtasks.get(id));
        if (sub != null) m.goalSubtasks.add((before: sub, after: null));
      }
    }
    commit(m);
  }

  // Writing: the map

  /// A new square that must be done before [parentId]. Null when the parent
  /// is gone.
  /// A new loose square on the map of [goalId]: no line yet (ADR 0008).
  GoalSquare? addLooseSquare(String goalId, {String title = ''}) {
    final graph = goalGraph(goalId);
    if (graph == null) return null;
    final m = _newSquare(graph, parentId: null, title: title);
    return commit(m) ? m.squares.single.after : null;
  }

  GoalSquare? addSquare({required String parentId, String title = ''}) {
    final parent = goalSquare(parentId);
    if (parent == null) return null;
    final graph = goalGraph(parent.goalId);
    if (graph == null) return null;
    final m = _newSquare(graph, parentId: parentId, title: title);
    return commit(m) ? m.squares.single.after : null;
  }

  Mutation _newSquare(
    GoalGraph graph, {
    required String? parentId,
    required String title,
  }) {
    final last = graph.ids.fold<double>(
      0,
      (m, id) => max(m, graph.square(id).sort),
    );
    final square = GoalSquare(
      goalId: graph.goalId,
      title: title.trim(),
      sort: last + 1,
    );
    final m = Mutation('New Step')..squares.add((before: null, after: square));
    if (parentId != null) {
      m.squareLinks.add((
        link: SquareLink(childId: square.id, parentId: parentId),
        add: true,
      ));
    }
    _repairLinks(m, graph);
    return m;
  }

  void renameSquare(String id, String title) {
    final old = goalSquare(id);
    if (old == null) return;
    if (old.isRoot) {
      updateProject(old.goalId, title: title);
      return;
    }
    final name = title.trim();
    if (name == old.title) return;
    commit(
      Mutation('Rename Step')
        ..squares.add((before: old, after: old.copyWith(title: name))),
    );
  }

  /// Takes a square off the map. Its children join to its parents, and its
  /// blocks stay. The root cannot go. False when nothing changed.
  bool deleteSquare(String id) {
    final old = goalSquare(id);
    if (old == null) return false;
    final graph = goalGraph(old.goalId);
    final edit = graph?.deleteEdit(id);
    if (graph == null || edit == null) return false;
    final m = Mutation('Delete Step')..squares.add((before: old, after: null));
    _writeEdit(m, graph, edit);
    _repairLinks(m, graph);
    return commit(m);
  }

  /// Makes [child] one more thing to do before [parent]. False when the map
  /// does not allow it.
  bool linkSquares({required String child, required String parent}) {
    final square = goalSquare(child);
    if (square == null) return false;
    final graph = goalGraph(square.goalId);
    if (graph == null || !graph.canLink(child: child, parent: parent)) {
      return false;
    }
    final m = Mutation('Link Steps')
      ..squareLinks.add((
        link: SquareLink(childId: child, parentId: parent),
        add: true,
      ));
    _repairLinks(m, graph);
    return commit(m);
  }

  /// Takes a link away. A square that has no other parent is loose.
  void unlinkSquares({required String child, required String parent}) {
    final square = goalSquare(child);
    if (square == null) return;
    final graph = goalGraph(square.goalId);
    if (graph == null) return;
    final edit = graph.unlinkEdit(child: child, parent: parent);
    if (edit == null || edit.isEmpty) return;
    final m = Mutation('Remove Link');
    _writeEdit(m, graph, edit);
    _repairLinks(m, graph);
    commit(m);
  }

  /// The rows are the input of the map, and `GoalGraph` puts them right when
  /// it reads them. The next edit writes that repair, so undo gets the true
  /// rows. Only rows that really change are in the change.
  void _repairLinks(Mutation m, GoalGraph graph) =>
      _writeEdit(m, graph, graph.repairEdit);

  void _writeEdit(Mutation m, GoalGraph graph, GraphEdit edit) {
    final rows =
        _try(() => repos.goalSquares.linksForGoal(graph.goalId))?.toSet() ??
        const <SquareLink>{};
    final listed = {for (final c in m.squareLinks) c.link};
    for (final link in edit.remove) {
      if (rows.contains(link) && listed.add(link)) {
        m.squareLinks.add((link: link, add: false));
      }
    }
    for (final link in edit.add) {
      if (!rows.contains(link) && listed.add(link)) {
        m.squareLinks.add((link: link, add: true));
      }
    }
  }

  /// Ticks a square, or takes the tick away. Ticking the root finishes the
  /// project. Taking that tick away opens it again.
  void toggleSquareDone(String id) {
    final old = goalSquare(id);
    if (old == null) return;
    final done = old.isDone;
    final name = old.isRoot
        ? (done ? 'Reopen Project' : 'Finish Project')
        : (done ? 'Reopen Step' : 'Complete Step');
    commit(
      Mutation(name)
        ..squares.add((
          before: old,
          after: old.copyWith(doneAt: done ? null : clockStamp()),
        )),
    );
  }

  /// Starts the wait of a square now. [minutes] null keeps the length it has.
  void startWaiting(String id, {int? minutes}) {
    final old = goalSquare(id);
    if (old == null || old.isDone || old.isRoot) return;
    commit(
      Mutation('Start Waiting')
        ..squares.add((before: old, after: _waiting(old, minutes))),
    );
  }

  GoalSquare _waiting(GoalSquare old, int? minutes) => old.copyWith(
    waitMinutes: minutes ?? old.waitMinutes ?? defaultWaitMinutes,
    waitStartedAt: clockStamp(),
  );

  /// Ends a wait without a tick: the square is open again.
  void stopWaiting(String id) {
    final old = goalSquare(id);
    if (old == null || old.waitStartedAt == null) return;
    commit(
      Mutation('Stop Waiting')
        ..squares.add((before: old, after: old.copyWith(waitStartedAt: null))),
    );
  }

  // Writing: blocks

  /// Puts a block that holds the square on the grid, and selects it. The block
  /// has the name of the square, so the day says what the time is for, and
  /// the length of the square. A square that is on the planner already
  /// moves with its block: a step sits on one block at most.
  void scheduleSquare({
    required String squareId,
    required DayKey day,
    required int start,
    int length = GoalRules.defaultBlockLength,
  }) {
    final square = goalSquare(squareId);
    final g = square == null ? null : goal(square.goalId);
    if (square == null || g == null) return;
    final step = (square: true, id: squareId);
    final own = _ownBlockOfStep(step);
    if (own != null) {
      _moveStepBlock(own, day: day, start: start, name: 'Move Step');
      return;
    }
    final m = Mutation('Schedule Step');
    // An old block that holds it with other steps lets it go.
    for (final id
        in _try(() => repos.goalSquares.blocksOf(squareId)) ??
            const <String>[]) {
      m.squareBlocks.add((
        block: SquareBlock(squareId: squareId, eventId: id),
        add: false,
      ));
    }
    var e = _newGoalBlock(
      g,
      day: day,
      start: start,
      length: square.lengthMinutes ?? length,
    );
    e = e.copyWith(
      title: square.isRoot || square.title.isEmpty
          ? GoalRules.titleOf(g)
          : square.title,
    );
    m
      ..events.add((before: null, after: e))
      ..squareBlocks.add((
        block: SquareBlock(squareId: squareId, eventId: e.id),
        add: true,
      ));
    if (commit(m)) selection = {e.id};
  }

  /// A square dragged onto the grid. [raw] is the dragged text, [minute] the
  /// snapped minute under the pointer. False when the text is not a square or
  /// the square is gone.
  bool dropSquareOnPlanner({
    required String raw,
    required DayKey day,
    required int minute,
  }) {
    final id = DragPayload.squareId(raw);
    if (id == null || goalSquare(id) == null) return false;
    scheduleSquare(squareId: id, day: day, start: minute);
    return true;
  }

  /// Puts a square in a block of the same goal.
  void addSquareToBlock({required String squareId, required String eventId}) {
    final square = goalSquare(squareId);
    final block = event(eventId);
    if (square == null || block == null || block.goalId != square.goalId) {
      return;
    }
    if (squaresOfBlock(eventId).any((s) => s.id == squareId)) return;
    if (!blockCanTakeStep(eventId, squareId: squareId)) {
      showToast('A block holds one step.');
      return;
    }
    final m = Mutation('Plan Step');
    // A step sits on one block at most: it leaves the one it was on.
    for (final id
        in _try(() => repos.goalSquares.blocksOf(squareId)) ??
            const <String>[]) {
      m.squareBlocks.add((
        block: SquareBlock(squareId: squareId, eventId: id),
        add: false,
      ));
    }
    m.squareBlocks.add((
      block: SquareBlock(squareId: squareId, eventId: eventId),
      add: true,
    ));
    commit(m);
  }

  /// A new loose step, held by the block. Null with no name, when the block
  /// has no project, or when the block holds a step already.
  GoalSquare? addSquareInBlock(String eventId, {required String title}) {
    final name = title.trim();
    final goalId = event(eventId)?.goalId;
    if (name.isEmpty || goalId == null) return null;
    if (!blockCanTakeStep(eventId)) return null;
    final graph = goalGraph(goalId);
    if (graph == null) return null;
    final m = _newSquare(graph, parentId: null, title: name);
    final square = m.squares.single.after!;
    m.squareBlocks.add((
      block: SquareBlock(squareId: square.id, eventId: eventId),
      add: true,
    ));
    return commit(m) ? square : null;
  }

  /// Takes a square out of a block. Both stay.
  void removeSquareFromBlock({
    required String squareId,
    required String eventId,
  }) {
    if (!squaresOfBlock(eventId).any((s) => s.id == squareId)) return;
    commit(
      Mutation('Unplan Step')
        ..squareBlocks.add((
          block: SquareBlock(squareId: squareId, eventId: eventId),
          add: false,
        )),
    );
  }

  /// Ticks a block done and does what the user said about each square it
  /// holds. One undo step, so undo takes back the tick and the answers.
  void answerBlockTick({
    required String eventId,
    required Map<String, SquareAnswer> answers,
  }) {
    final old = _try(() => repos.events.get(eventId));
    if (old == null || old.goalId == null) return;
    final m = Mutation('Complete Goal Block')
      ..events.add((
        before: old,
        after: old.copyWith(doneAt: old.doneAt ?? clockStamp()),
      ));
    answers.forEach((id, answer) {
      final square = goalSquare(id);
      if (square == null || square.isDone) return;
      switch (answer.kind) {
        case SquareAnswerKind.done:
          m.squares.add((
            before: square,
            after: square.copyWith(doneAt: clockStamp()),
          ));
        case SquareAnswerKind.startWaiting:
          if (square.isRoot) return;
          m.squares.add((
            before: square,
            after: _waiting(square, answer.waitMinutes),
          ));
        case SquareAnswerKind.notYet:
          break;
      }
    });
    commit(m);
  }

  // Keeping the rows right

  /// See `GoalSquareRepo.heal`. It is not an undo step.
  void _healGoalMaps() => _try(() => repos.goalSquares.heal());

  /// The database takes away the rows of a gone square, goal or block by
  /// itself. This puts them in the change, so undo brings them back.
  void _addMapRowsOfDeletions(Mutation m) {
    final goneGoals = [
      for (final g in m.goals)
        if (g.after == null) ?g.before?.id,
    ];
    final listedSquares = {
      for (final c in m.squares) ?(c.before ?? c.after)?.id,
    };
    for (final id in goneGoals) {
      for (final s
          in _try(() => repos.goalSquares.forGoal(id)) ??
              const <GoalSquare>[]) {
        if (listedSquares.add(s.id)) m.squares.add((before: s, after: null));
      }
    }
    final goneSquares = <String>{};
    final goalsOfGone = <String>{};
    for (final c in m.squares) {
      final before = c.before;
      if (c.after == null && before != null) {
        goneSquares.add(before.id);
        goalsOfGone.add(before.goalId);
      }
    }
    final listedLinks = {for (final c in m.squareLinks) c.link};
    final listedBlocks = {for (final c in m.squareBlocks) c.block};
    for (final id in goalsOfGone) {
      for (final link
          in _try(() => repos.goalSquares.linksForGoal(id)) ??
              const <SquareLink>[]) {
        final touches =
            goneSquares.contains(link.childId) ||
            goneSquares.contains(link.parentId);
        if (touches && listedLinks.add(link)) {
          m.squareLinks.add((link: link, add: false));
        }
      }
      for (final block
          in _try(() => repos.goalSquares.blocksForGoal(id)) ??
              const <SquareBlock>[]) {
        if (goneSquares.contains(block.squareId) && listedBlocks.add(block)) {
          m.squareBlocks.add((block: block, add: false));
        }
      }
    }
    final goneEvents = [
      for (final e in m.events)
        if (e.after == null) ?e.before?.id,
    ];
    if (goneEvents.isEmpty) return;
    final held = _try(() => repos.goalSquares.forEvents(goneEvents));
    held?.forEach((eventId, squares) {
      for (final s in squares) {
        final block = SquareBlock(squareId: s.id, eventId: eventId);
        if (listedBlocks.add(block)) {
          m.squareBlocks.add((block: block, add: false));
        }
      }
    });
  }
}
