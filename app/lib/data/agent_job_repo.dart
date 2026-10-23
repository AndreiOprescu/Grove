import '../core/agent/agent_models.dart';
import '../core/model/day_key.dart';
import 'database.dart';

/// The jobs of the agent (ADR 0004). A job goes with its task.
class AgentJobRepo {
  AgentJobRepo(this.db);

  final Database db;

  static const _cols =
      'id, task_id, instructions, email_access, status, runner_device, '
      'result_json, error, result_note_id, created_at, updated_at, '
      'finished_at';

  static AgentJob _map(Row r) => AgentJob(
    id: r.text(0),
    taskId: r.text(1),
    instructions: r.text(2),
    emailAccess: r.asBool(3),
    status: AgentStatus.fromCode(r.text(4)),
    runnerDevice: r.optText(5),
    resultJson: r.optText(6),
    error: r.optText(7),
    resultNoteId: r.optText(8),
    createdAt: r.text(9),
    updatedAt: r.text(10),
    finishedAt: r.optText(11),
  );

  /// A new job. Throws when the task is gone.
  void insert(AgentJob j) => db.execute(
    'INSERT INTO agent_jobs ($_cols) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      j.id,
      j.taskId,
      j.instructions,
      j.emailAccess,
      j.status.code,
      j.runnerDevice,
      j.resultJson,
      j.error,
      j.resultNoteId,
      j.createdAt,
      j.updatedAt,
      j.finishedAt,
    ],
  );

  AgentJob? get(String id) => db.query(
    'SELECT $_cols FROM agent_jobs WHERE id = ?',
    [id],
    _map,
  ).firstOrNull;

  /// The newest job of a task, or null when it has none.
  AgentJob? forTask(String taskId) => db.query(
    'SELECT $_cols FROM agent_jobs WHERE task_id = ? '
    'ORDER BY created_at DESC, rowid DESC LIMIT 1',
    [taskId],
    _map,
  ).firstOrNull;

  /// The jobs with [status], the oldest first.
  List<AgentJob> withStatus(AgentStatus status) => db.query(
    'SELECT $_cols FROM agent_jobs WHERE status = ? '
    'ORDER BY created_at, rowid',
    [status.code],
    _map,
  );

  /// The jobs that wait for a runner, the oldest first.
  List<AgentJob> queued() => withStatus(AgentStatus.queued);

  /// Takes a queued job for the runner [device]: it becomes running. Only
  /// one runner can win: false when the job is gone or no longer queued.
  bool claim(String id, String device) {
    db.execute(
      'UPDATE agent_jobs SET status = ?, runner_device = ?, updated_at = ? '
      'WHERE id = ? AND status = ?',
      [
        AgentStatus.running.code,
        device,
        Stamp.now(),
        id,
        AgentStatus.queued.code,
      ],
    );
    return db.changes == 1;
  }

  /// Sets the status. A value that is not given stays as it is. A finished
  /// status also sets `finished_at`. With [from], only a job in one of those
  /// states changes. False when no job changed.
  bool setStatus(
    String id,
    AgentStatus status, {
    String? resultJson,
    String? error,
    String? resultNoteId,
    Set<AgentStatus>? from,
  }) {
    final now = Stamp.now();
    final only = from == null
        ? ''
        : ' AND status IN (${List.filled(from.length, '?').join(', ')})';
    db.execute(
      'UPDATE agent_jobs SET status = ?, '
      'result_json = coalesce(?, result_json), error = coalesce(?, error), '
      'result_note_id = coalesce(?, result_note_id), updated_at = ?, '
      'finished_at = coalesce(?, finished_at) '
      'WHERE id = ?$only',
      [
        status.code,
        resultJson,
        error,
        resultNoteId,
        now,
        status.isFinished ? now : null,
        id,
        ...?from?.map((s) => s.code),
      ],
    );
    return db.changes == 1;
  }
}
