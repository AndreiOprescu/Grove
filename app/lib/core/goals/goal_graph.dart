import '../model/goal_square.dart';

/// What the user can do with a square now. Only [done] closes it: a dim
/// [notReady] square can still be planned and ticked.
enum SquareState { done, waiting, ready, notReady }

/// Links to write and links to delete, in one edit.
class GraphEdit {
  const GraphEdit({this.add = const [], this.remove = const []});

  final List<SquareLink> add;
  final List<SquareLink> remove;

  bool get isEmpty => add.isEmpty && remove.isEmpty;
}

/// The goal map as the rules and the layout read it.
///
/// Each device keeps the map right, but a sync merge can make a loop or
/// leave a square with no parent. So the rows are only an input. This class
/// ignores links that cannot stand, drops the link that closes a loop and
/// joins a lost square to the root. Every square then has a path to the root
/// and no path goes in a circle (ADR 0008). The same rows give the same graph
/// on every device, in any order.
class GoalGraph {
  GoalGraph._(
    this.goalId,
    this.rootId,
    this._squares,
    this._parents,
    this._children,
    this.droppedLinks,
    this.addedLinks,
  ) {
    _ranks = {for (final id in _squares.keys) id: _rankOf(id)};
  }

  factory GoalGraph.build(
    String goalId,
    Iterable<GoalSquare> squares,
    Iterable<SquareLink> links,
  ) {
    final rootId = GoalSquare.rootIdOf(goalId);
    final byId = {
      for (final s in squares)
        if (s.goalId == goalId) s.id: s,
    };
    byId[rootId] ??= GoalSquare(id: rootId, goalId: goalId, title: '');

    final sorted = links.toSet().toList()
      ..sort(
        (a, b) => a.childId != b.childId
            ? a.childId.compareTo(b.childId)
            : a.parentId.compareTo(b.parentId),
      );
    final dropped = <SquareLink>[];
    final added = <SquareLink>[];
    final valid = <String, List<String>>{for (final id in byId.keys) id: []};
    final hasParent = <String>{};
    for (final l in sorted) {
      final fine =
          l.childId != l.parentId &&
          l.childId != rootId &&
          byId.containsKey(l.childId) &&
          byId.containsKey(l.parentId);
      if (!fine) {
        dropped.add(l);
        continue;
      }
      valid[l.parentId]!.add(l.childId);
      hasParent.add(l.childId);
    }

    final children = <String, List<String>>{for (final id in byId.keys) id: []};
    final parents = <String, List<String>>{for (final id in byId.keys) id: []};
    final seen = <String>{};
    final onPath = <String>{};

    void walk(String id) {
      seen.add(id);
      onPath.add(id);
      for (final child in valid[id]!) {
        if (onPath.contains(child)) {
          dropped.add(SquareLink(childId: child, parentId: id));
          continue;
        }
        children[id]!.add(child);
        parents[child]!.add(id);
        if (!seen.contains(child)) walk(child);
      }
      onPath.remove(id);
    }

    walk(rootId);
    final ids = byId.keys.toList()..sort();
    while (true) {
      final left = ids.where((id) => !seen.contains(id)).toList();
      if (left.isEmpty) break;
      // A square with no parent at all goes first. Only a loop has none.
      final lost = left.firstWhere(
        (id) => !hasParent.contains(id),
        orElse: () => left.first,
      );
      added.add(SquareLink(childId: lost, parentId: rootId));
      children[rootId]!.add(lost);
      parents[lost]!.add(rootId);
      onPath.add(rootId);
      walk(lost);
      onPath.remove(rootId);
    }

    for (final list in children.values) {
      list.sort();
    }
    for (final list in parents.values) {
      list.sort();
    }
    dropped.sort((a, b) => a.toString().compareTo(b.toString()));
    return GoalGraph._(goalId, rootId, byId, parents, children, dropped, added);
  }

  final String goalId;
  final String rootId;
  final Map<String, GoalSquare> _squares;
  final Map<String, List<String>> _parents;
  final Map<String, List<String>> _children;

  /// Links in the rows that the graph does not use.
  final List<SquareLink> droppedLinks;

  /// Links the graph uses that are not in the rows.
  final List<SquareLink> addedLinks;

  late final Map<String, int> _ranks;

  Iterable<String> get ids => _squares.keys;
  GoalSquare square(String id) => _squares[id]!;
  bool contains(String id) => _squares.containsKey(id);
  List<String> parentsOf(String id) => _parents[id] ?? const [];
  List<String> childrenOf(String id) => _children[id] ?? const [];

  /// The longest path from each square to the root. The root is 0.
  Map<String, int> get ranks => _ranks;

  int _rankOf(String id) {
    final known = _rankMemo[id];
    if (known != null) return known;
    var rank = 0;
    for (final p in parentsOf(id)) {
      final r = _rankOf(p) + 1;
      if (r > rank) rank = r;
    }
    return _rankMemo[id] = rank;
  }

  final Map<String, int> _rankMemo = {};

  bool reachesRoot(String id) {
    if (id == rootId) return true;
    return parentsOf(id).any(reachesRoot);
  }

  /// Links that the rows must gain or lose to match this graph. The next
  /// edit on the map writes them; a pull does not.
  GraphEdit get repairEdit => GraphEdit(add: addedLinks, remove: droppedLinks);

  SquareState stateOf(String id) {
    final s = square(id);
    if (s.isDone) return SquareState.done;
    if (s.isWaiting) return SquareState.waiting;
    final open = childrenOf(id).any((c) => !square(c).isDone);
    return open ? SquareState.notReady : SquareState.ready;
  }

  List<String> _inState(SquareState state) {
    final out = ids.where((id) => stateOf(id) == state).toList()..sort(_bySort);
    return out;
  }

  int _bySort(String a, String b) {
    final s = square(a).sort.compareTo(square(b).sort);
    return s != 0 ? s : a.compareTo(b);
  }

  /// Squares the user can do now.
  List<String> get readyIds => _inState(SquareState.ready);

  /// Squares with a wait that the user started and did not tick yet.
  List<String> get waitingIds => _inState(SquareState.waiting);

  /// Dim squares: they need something else first.
  List<String> get laterIds => _inState(SquareState.notReady);

  /// All squares but the root: the root is the result, not a step.
  int get stepCount => _squares.length - 1;

  /// The steps that are not ticked yet.
  int get openCount =>
      ids.where((id) => id != rootId && !square(id).isDone).length;

  /// True when [parent] may get [child] as one more thing to do first.
  bool canLink({required String child, required String parent}) {
    if (child == parent || child == rootId) return false;
    if (!contains(child) || !contains(parent)) return false;
    if (parentsOf(child).contains(parent)) return false;
    return !_needs(child, parent);
  }

  /// True when [id] must wait for [other], at any depth.
  bool _needs(String id, String other) {
    for (final c in childrenOf(id)) {
      if (c == other || _needs(c, other)) return true;
    }
    return false;
  }

  /// Deleting [id]: its children join to its parents. Null for the root.
  GraphEdit? deleteEdit(String id) {
    if (id == rootId || !contains(id)) return null;
    final parents = parentsOf(id);
    final children = childrenOf(id);
    return GraphEdit(
      add: [
        for (final c in children)
          for (final p in parents)
            if (!parentsOf(c).contains(p)) SquareLink(childId: c, parentId: p),
      ],
      remove: [
        for (final p in parents) SquareLink(childId: id, parentId: p),
        for (final c in children) SquareLink(childId: c, parentId: id),
      ],
    );
  }

  /// Taking away one link. A square that loses its last parent joins the
  /// root. Null when there is no such link, or when it is the last link to
  /// the root.
  GraphEdit? unlinkEdit({required String child, required String parent}) {
    final parents = parentsOf(child);
    if (!parents.contains(parent)) return null;
    final link = SquareLink(childId: child, parentId: parent);
    if (parents.length > 1) return GraphEdit(remove: [link]);
    if (parent == rootId) return null;
    return GraphEdit(
      add: [SquareLink(childId: child, parentId: rootId)],
      remove: [link],
    );
  }
}
