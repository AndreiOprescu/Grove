import '../core/agent/agent_models.dart';
import '../core/model/day_key.dart';
import 'database.dart';

/// The lines of the chats with the agent (ADR 0005): the messages of the
/// person, the steps of a run and its results. They go with their job.
class AgentEventRepo {
  AgentEventRepo(this.db);

  final Database db;

  static const _cols =
      'id, job_id, line_no, kind, label, body, created_at, updated_at';

  static AgentEvent _map(Row r) => AgentEvent(
    id: r.text(0),
    jobId: r.text(1),
    seq: r.asInt(2),
    kind: AgentEventKind.fromCode(r.text(3)),
    label: r.text(4),
    body: r.text(5),
    createdAt: r.text(6),
    updatedAt: r.text(7),
  );

  /// A new line. Throws when the job is gone.
  void insert(AgentEvent e) => db.execute(
    'INSERT INTO agent_events ($_cols) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    [
      e.id,
      e.jobId,
      e.seq,
      e.kind.code,
      e.label,
      e.body,
      e.createdAt,
      e.updatedAt,
    ],
  );

  AgentEvent? get(String id) => db.query(
    'SELECT $_cols FROM agent_events WHERE id = ?',
    [id],
    _map,
  ).firstOrNull;

  /// The lines of a job, in the order of the chat. Two devices can give the
  /// same place to a line while they are apart; the time then decides.
  List<AgentEvent> forJob(String jobId) => db.query(
    'SELECT $_cols FROM agent_events WHERE job_id = ? '
    'ORDER BY line_no, created_at, rowid',
    [jobId],
    _map,
  );

  /// The place of the next line of a job.
  int nextSeq(String jobId) =>
      db.queryOne(
        'SELECT coalesce(max(line_no), 0) + 1 FROM agent_events WHERE job_id = ?',
        [jobId],
        (r) => r.asInt(0),
      ) ??
      1;

  /// Changes the label and the body of a line.
  void update(AgentEvent e) => db.execute(
    'UPDATE agent_events SET label = ?, body = ?, updated_at = ? WHERE id = ?',
    [e.label, e.body, Stamp.now(), e.id],
  );
}
