import 'dart:convert';

import '../core/model/day_key.dart';
import '../core/model/goal.dart';
import '../core/model/goal_square.dart';
import 'database.dart';

/// The squares of projects, the links between them and the blocks that hold
/// them (ADR 0008).
class GoalSquareRepo {
  GoalSquareRepo(this.db);

  final Database db;

  static const _cols =
      'id, goal_id, title, done_at, wait_minutes, wait_started_at, sort, '
      'created_at, updated_at, length_minutes';
  static const _select = 'SELECT $_cols FROM goal_squares';
  static const _order = 'ORDER BY sort, created_at, rowid';

  static GoalSquare _map(Row r) => GoalSquare(
    id: r.text(0),
    goalId: r.text(1),
    title: r.text(2),
    doneAt: r.optText(3),
    waitMinutes: r.optInt(4),
    waitStartedAt: r.optText(5),
    sort: r.asDouble(6),
    createdAt: r.text(7),
    updatedAt: r.text(8),
    lengthMinutes: r.optInt(9),
  );

  /// Insert or update. Refreshes `updatedAt`. It never deletes the row, so
  /// the links and blocks of the square stay. Throws when the goal does not
  /// exist (foreign key).
  void save(GoalSquare square) {
    final s = square.copyWith(updatedAt: Stamp.now());
    db.execute(
      'INSERT INTO goal_squares ($_cols) VALUES (?,?,?,?,?,?,?,?,?,?) '
      'ON CONFLICT(id) DO UPDATE SET goal_id=excluded.goal_id, '
      'title=excluded.title, done_at=excluded.done_at, '
      'wait_minutes=excluded.wait_minutes, '
      'wait_started_at=excluded.wait_started_at, sort=excluded.sort, '
      'created_at=excluded.created_at, updated_at=excluded.updated_at, '
      'length_minutes=excluded.length_minutes',
      [
        s.id,
        s.goalId,
        s.title,
        s.doneAt,
        s.waitMinutes,
        s.waitStartedAt,
        s.sort,
        s.createdAt,
        s.updatedAt,
        s.lengthMinutes,
      ],
    );
  }

  GoalSquare? get(String id) =>
      db.query('$_select WHERE id = ?', [id], _map).firstOrNull;

  /// The squares of one goal, the root too.
  List<GoalSquare> forGoal(String goalId) =>
      db.query('$_select WHERE goal_id = ? $_order', [goalId], _map);

  /// The root squares of many goals, by goal id. A goal with no root has no
  /// entry.
  Map<String, GoalSquare> roots(Iterable<String> goalIds) {
    final ids = goalIds.map(GoalSquare.rootIdOf).toList();
    if (ids.isEmpty) return const {};
    final rows = db.query(
      '$_select WHERE id IN (SELECT value FROM json_each(?))',
      [jsonEncode(ids)],
      _map,
    );
    return {for (final s in rows) s.goalId: s};
  }

  /// Deletes the square. Its links and block rows go with it (the database
  /// does that). The blocks stay.
  void delete(String id) =>
      db.execute('DELETE FROM goal_squares WHERE id = ?', [id]);

  /// All links with one end in this goal. `GoalGraph` drops the ones that
  /// cannot stand.
  List<SquareLink> linksForGoal(String goalId) => db.query(
    'SELECT child_id, parent_id FROM square_links WHERE child_id IN '
    '(SELECT id FROM goal_squares WHERE goal_id = ?1) OR parent_id IN '
    '(SELECT id FROM goal_squares WHERE goal_id = ?1)',
    [goalId],
    (r) => SquareLink(childId: r.text(0), parentId: r.text(1)),
  );

  void addLink(SquareLink link) => db.execute(
    'INSERT OR IGNORE INTO square_links (child_id, parent_id) VALUES (?, ?)',
    [link.childId, link.parentId],
  );

  void removeLink(SquareLink link) => db.execute(
    'DELETE FROM square_links WHERE child_id = ? AND parent_id = ?',
    [link.childId, link.parentId],
  );

  /// Puts a square in a block. Throws when either one does not exist.
  void addBlock(String squareId, String eventId) => db.execute(
    'INSERT OR IGNORE INTO square_blocks (square_id, event_id) VALUES (?, ?)',
    [squareId, eventId],
  );

  void removeBlock(String squareId, String eventId) => db.execute(
    'DELETE FROM square_blocks WHERE square_id = ? AND event_id = ?',
    [squareId, eventId],
  );

  /// The blocks that hold a square.
  List<String> blocksOf(String squareId) => db.query(
    'SELECT event_id FROM square_blocks WHERE square_id = ? ORDER BY event_id',
    [squareId],
    (r) => r.text(0),
  );

  /// The block rows of one goal.
  List<SquareBlock> blocksForGoal(String goalId) => db.query(
    'SELECT square_id, event_id FROM square_blocks WHERE square_id IN '
    '(SELECT id FROM goal_squares WHERE goal_id = ?)',
    [goalId],
    (r) => SquareBlock(squareId: r.text(0), eventId: r.text(1)),
  );

  /// The squares these blocks hold, in one query, by event id. A block with
  /// none has no entry.
  Map<String, List<GoalSquare>> forEvents(Iterable<String> eventIds) {
    final ids = eventIds.toList();
    final out = <String, List<GoalSquare>>{};
    if (ids.isEmpty) return out;
    final rows = db.query(
      'SELECT b.event_id, s.id, s.goal_id, s.title, s.done_at, s.wait_minutes, '
      's.wait_started_at, s.sort, s.created_at, s.updated_at '
      'FROM square_blocks b JOIN goal_squares s ON s.id = b.square_id '
      'WHERE b.event_id IN (SELECT value FROM json_each(?)) '
      'ORDER BY s.sort, s.created_at, s.rowid',
      [jsonEncode(ids)],
      (r) => (
        r.text(0),
        GoalSquare(
          id: r.text(1),
          goalId: r.text(2),
          title: r.text(3),
          doneAt: r.optText(4),
          waitMinutes: r.optInt(5),
          waitStartedAt: r.optText(6),
          sort: r.asDouble(7),
          createdAt: r.text(8),
          updatedAt: r.text(9),
        ),
      ),
    );
    for (final (eventId, square) in rows) {
      (out[eventId] ??= []).add(square);
    }
    return out;
  }

  /// Turns a habit into a project. Its subtasks become squares under the root
  /// and its blocks stay. The ids come from the goal and the subtasks, so two
  /// devices that do this reach the same rows. A second run finds nothing to
  /// do.
  void convert(GoalItem goal) {
    db.transaction(() {
      db.execute(
        "UPDATE goals SET type = 'project', updated_at = ? WHERE id = ?",
        [Stamp.now(), goal.id],
      );
      _ensureRoot(goal.id, goal.title);
      _adoptSubtasks(goal.id);
    });
  }

  /// Puts the rows right after a pull. Two devices can leave a goal in a
  /// state that neither made:
  /// - a device that did not know about the change to a project saves the
  ///   goal, so the newer row says habit. A root square means it is a project.
  /// - a project with no root row yet gets its root.
  /// - a device that did not know adds a subtask, so the project gets one
  ///   late. It becomes a square.
  ///
  /// Returns true when it changed a row. It is not an undo step.
  bool heal() {
    var changed = false;
    db.transaction(() {
      final habits = db.query(
        "SELECT id FROM goals WHERE COALESCE(type, '') <> 'project' AND id IN "
        "(SELECT goal_id FROM goal_squares WHERE id = 'root:' || goal_id)",
        const [],
        (r) => r.text(0),
      );
      for (final id in habits) {
        db.execute(
          "UPDATE goals SET type = 'project', updated_at = ? WHERE id = ?",
          [Stamp.now(), id],
        );
        changed = true;
      }
      final rootless = db.query(
        "SELECT id, title FROM goals WHERE type = 'project' AND NOT EXISTS "
        "(SELECT 1 FROM goal_squares s WHERE s.id = 'root:' || goals.id)",
        const [],
        (r) => (r.text(0), r.text(1)),
      );
      for (final (id, title) in rootless) {
        _ensureRoot(id, title);
        changed = true;
      }
      final late = db.query(
        'SELECT DISTINCT goal_id FROM goal_subtasks WHERE goal_id IN '
        "(SELECT id FROM goals WHERE type = 'project')",
        const [],
        (r) => r.text(0),
      );
      for (final id in late) {
        _adoptSubtasks(id);
        changed = true;
      }
    });
    return changed;
  }

  void _ensureRoot(String goalId, String title) {
    final id = GoalSquare.rootIdOf(goalId);
    if (get(id) == null) {
      save(GoalSquare(id: id, goalId: goalId, title: title));
    }
  }

  void _adoptSubtasks(String goalId) {
    final plan = conversionOf(goalId);
    plan.squares.forEach(save);
    plan.links.forEach(addLink);
    for (final b in plan.blocks) {
      addBlock(b.squareId, b.eventId);
    }
    for (final id in plan.subtaskIds) {
      db.execute('DELETE FROM goal_subtasks WHERE id = ?', [id]);
    }
  }

  /// What the goal subtasks of a goal become when the goal is a project. It
  /// only reads.
  GoalConversion conversionOf(String goalId) {
    final root = GoalSquare.rootIdOf(goalId);
    final subs = db.query(
      'SELECT id, title, done_at, sort, created_at, event_id, length_minutes '
      'FROM goal_subtasks WHERE goal_id = ? ORDER BY sort, created_at, rowid',
      [goalId],
      (r) => (
        id: r.text(0),
        title: r.text(1),
        doneAt: r.optText(2),
        sort: r.asDouble(3),
        createdAt: r.text(4),
        eventId: r.optText(5),
        lengthMinutes: r.optInt(6),
      ),
    );
    final plan = GoalConversion();
    for (final s in subs) {
      final id = GoalSquare.idFromSubtask(s.id);
      if (get(id) == null) {
        plan.squares.add(
          GoalSquare(
            id: id,
            goalId: goalId,
            title: s.title,
            doneAt: s.doneAt,
            sort: s.sort,
            lengthMinutes: s.lengthMinutes,
            createdAt: s.createdAt,
          ),
        );
        plan.links.add(SquareLink(childId: id, parentId: root));
      }
      if (s.eventId != null) {
        plan.blocks.add(SquareBlock(squareId: id, eventId: s.eventId!));
      }
      plan.subtaskIds.add(s.id);
    }
    return plan;
  }
}

/// The rows that the goal subtasks of a goal become, and the subtasks to take
/// away.
class GoalConversion {
  final squares = <GoalSquare>[];
  final links = <SquareLink>[];
  final blocks = <SquareBlock>[];
  final subtaskIds = <String>[];
}
