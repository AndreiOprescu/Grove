import 'dart:convert';

import '../core/model/day_key.dart';
import '../core/services/persona.dart';
import 'database.dart';

/// The skills of the persona. A skill is never deleted, only hidden.
class SkillRepo {
  SkillRepo(this.db);

  final Database db;

  static const _cols =
      'id, name, sort, hidden, builtin, created_at, updated_at';

  static SkillItem _map(Row r) => SkillItem(
    id: r.text(0),
    name: r.text(1),
    sort: r.asDouble(2),
    hidden: r.asBool(3),
    builtin: r.asBool(4),
    createdAt: r.text(5),
    updatedAt: r.text(6),
  );

  /// All skills, hidden ones too, in list order.
  List<SkillItem> all() => db.query(
    'SELECT $_cols FROM skills ORDER BY sort, created_at, rowid',
    const [],
    _map,
  );

  SkillItem? get(String id) => db.query(
    'SELECT $_cols FROM skills WHERE id = ?',
    [id],
    _map,
  ).firstOrNull;

  /// Insert or update. Refreshes `updatedAt`.
  void save(SkillItem skill) {
    final s = skill.copyWith(updatedAt: Stamp.now());
    db.execute(
      'INSERT INTO skills ($_cols) VALUES (?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(id) DO UPDATE SET name = excluded.name, '
      'sort = excluded.sort, hidden = excluded.hidden, '
      'updated_at = excluded.updated_at',
      [s.id, s.name, s.sort, s.hidden, s.builtin, s.createdAt, s.updatedAt],
    );
  }

  /// Only for the undo of a new skill. The user hides a skill instead: a
  /// delete would also delete its earnings.
  void delete(String id) => db.execute('DELETE FROM skills WHERE id = ?', [id]);

  /// Puts back any built-in skill that is missing (an import of an older
  /// file). Like the rows of migration 10, it gets no outbox line: every
  /// device has it already, and it must never win over a rename from another
  /// device.
  void ensureBuiltins() {
    for (final s in PersonaRules.builtins) {
      if (get(s.id) != null) continue;
      db.execute('INSERT INTO skills ($_cols) VALUES (?, ?, ?, ?, ?, ?, ?)', [
        s.id,
        s.name,
        s.sort,
        false,
        true,
        s.createdAt,
        s.createdAt,
      ]);
      db.execute("DELETE FROM outbox WHERE tbl = 'skills' AND pk = ?", [s.id]);
    }
  }
}

/// The rewards on tasks and goals.
class RewardRepo {
  RewardRepo(this.db);

  final Database db;

  static const _cols = 'id, task_id, goal_id, skill_id, points';
  static const _order = 'ORDER BY rowid';

  static RewardItem _map(Row r) => RewardItem(
    id: r.text(0),
    taskId: r.optText(1),
    goalId: r.optText(2),
    skillId: r.text(3),
    points: r.asInt(4),
  );

  /// Insert or update. Throws when the task, goal or skill is gone.
  void save(RewardItem x) => db.execute(
    'INSERT INTO rewards ($_cols) VALUES (?, ?, ?, ?, ?) '
    'ON CONFLICT(id) DO UPDATE SET points = excluded.points',
    [x.id, x.taskId, x.goalId, x.skillId, x.points],
  );

  RewardItem? get(String id) => db.query(
    'SELECT $_cols FROM rewards WHERE id = ?',
    [id],
    _map,
  ).firstOrNull;

  List<RewardItem> forTask(String taskId) => db.query(
    'SELECT $_cols FROM rewards WHERE task_id = ? $_order',
    [taskId],
    _map,
  );

  List<RewardItem> forGoal(String goalId) => db.query(
    'SELECT $_cols FROM rewards WHERE goal_id = ? $_order',
    [goalId],
    _map,
  );

  /// The rewards of many tasks in one query, by task id. A task with none
  /// has no entry.
  Map<String, List<RewardItem>> forTasks(Iterable<String> taskIds) =>
      _forMany('task_id', taskIds, (x) => x.taskId!);

  /// The rewards of many goals in one query, by goal id.
  Map<String, List<RewardItem>> forGoals(Iterable<String> goalIds) =>
      _forMany('goal_id', goalIds, (x) => x.goalId!);

  Map<String, List<RewardItem>> _forMany(
    String column,
    Iterable<String> ids,
    String Function(RewardItem) key,
  ) {
    final list = ids.toList();
    final out = <String, List<RewardItem>>{};
    if (list.isEmpty) return out;
    final rows = db.query(
      'SELECT $_cols FROM rewards '
      'WHERE $column IN (SELECT value FROM json_each(?)) $_order',
      [jsonEncode(list)],
      _map,
    );
    for (final x in rows) {
      (out[key(x)] ??= []).add(x);
    }
    return out;
  }

  void delete(String id) =>
      db.execute('DELETE FROM rewards WHERE id = ?', [id]);
}

/// The log of earned points.
class EarningRepo {
  EarningRepo(this.db);

  final Database db;

  static const _cols =
      'id, skill_id, points, source_kind, source_id, title, earned_at';

  static EarningItem _map(Row r) => EarningItem(
    id: r.text(0),
    skillId: r.text(1),
    points: r.asInt(2),
    source: EarningSource.fromCode(r.text(3)),
    sourceId: r.text(4),
    title: r.text(5),
    earnedAt: r.text(6),
  );

  void save(EarningItem x) => db.execute(
    'INSERT INTO earnings ($_cols) VALUES (?, ?, ?, ?, ?, ?, ?) '
    'ON CONFLICT(id) DO UPDATE SET points = excluded.points, '
    'title = excluded.title, earned_at = excluded.earned_at',
    [x.id, x.skillId, x.points, x.source.code, x.sourceId, x.title, x.earnedAt],
  );

  /// The earnings of one ticked task or goal block.
  List<EarningItem> forSource(EarningSource source, String sourceId) =>
      db.query(
        'SELECT $_cols FROM earnings WHERE source_kind = ? AND source_id = ? '
        'ORDER BY rowid',
        [source.code, sourceId],
        _map,
      );

  /// The newest earnings first.
  List<EarningItem> recent({int limit = 20}) => db.query(
    'SELECT $_cols FROM earnings ORDER BY earned_at DESC, rowid DESC LIMIT ?',
    [limit],
    _map,
  );

  /// The points of each skill. A skill with no earnings has no entry.
  Map<String, int> pointsBySkill() => {
    for (final (id, sum) in db.query(
      'SELECT skill_id, SUM(points) FROM earnings GROUP BY skill_id',
      const [],
      (r) => (r.text(0), r.asInt(1)),
    ))
      id: sum,
  };

  void delete(String id) =>
      db.execute('DELETE FROM earnings WHERE id = ?', [id]);
}
