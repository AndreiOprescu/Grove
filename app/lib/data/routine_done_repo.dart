import 'dart:convert';

import '../core/model/day_key.dart';
import '../core/model/routine.dart';
import 'database.dart';

/// The done days of routine tasks. Every one is kept.
class RoutineDoneRepo {
  RoutineDoneRepo(this.db);

  final Database db;

  static const _cols = 'id, task_id, day, event_id, done_at';
  static const _select = 'SELECT $_cols FROM routine_done';
  static const _order = 'ORDER BY day, done_at, rowid';

  static RoutineDone _map(Row r) => RoutineDone(
    id: r.text(0),
    taskId: r.text(1),
    day: DayKey(r.text(2)),
    eventId: r.optText(3),
    doneAt: r.text(4),
  );

  /// Insert or update. Throws when the task does not exist (foreign key).
  void save(RoutineDone x) => db.execute(
    'INSERT INTO routine_done ($_cols) VALUES (?, ?, ?, ?, ?) '
    'ON CONFLICT(id) DO UPDATE SET task_id = excluded.task_id, '
    'day = excluded.day, event_id = excluded.event_id, '
    'done_at = excluded.done_at',
    [x.id, x.taskId, x.day.string, x.eventId, x.doneAt],
  );

  RoutineDone? get(String id) =>
      db.query('$_select WHERE id = ?', [id], _map).firstOrNull;

  /// The done days of one task, oldest first.
  List<RoutineDone> forTask(String taskId) =>
      db.query('$_select WHERE task_id = ? $_order', [taskId], _map);

  /// The done days of many tasks in one query, by task id. A task with none
  /// has no entry.
  Map<String, List<RoutineDone>> forTasks(Iterable<String> taskIds) {
    final ids = taskIds.toList();
    final out = <String, List<RoutineDone>>{};
    if (ids.isEmpty) return out;
    final rows = db.query(
      '$_select WHERE task_id IN (SELECT value FROM json_each(?)) $_order',
      [jsonEncode(ids)],
      _map,
    );
    for (final x in rows) {
      (out[x.taskId] ??= []).add(x);
    }
    return out;
  }

  /// The done rows that point at these blocks, by event id.
  Map<String, RoutineDone> forEvents(Iterable<String> eventIds) {
    final ids = eventIds.toList();
    if (ids.isEmpty) return const {};
    final rows = db.query(
      '$_select WHERE event_id IN (SELECT value FROM json_each(?)) $_order',
      [jsonEncode(ids)],
      _map,
    );
    return {for (final x in rows) x.eventId!: x};
  }

  void delete(String id) =>
      db.execute('DELETE FROM routine_done WHERE id = ?', [id]);
}
