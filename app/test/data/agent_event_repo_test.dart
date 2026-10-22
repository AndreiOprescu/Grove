import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/agent/agent_models.dart';
import 'package:grove/core/model/task.dart';
import 'package:grove/data/data.dart';
import 'package:grove/sync/outbox.dart';

import 'helpers.dart';

// The chats of the agent (shared migration 13, ADR 0005): a job needs no
// task, it has a title, links and a plan switch, and its lines are kept in
// order in `agent_events`.

void main() {
  test('a job with no task is saved, with its title, links and plan '
      'switch', () {
    final r = makeRepos();
    const links = [
      AgentLink(kind: AgentLinkKind.note, id: 'N1', name: 'Trip'),
      AgentLink(kind: AgentLinkKind.file, id: 'F1', name: 'a.pdf', device: 'M'),
    ];
    r.agentJobs.insert(
      AgentJob(
        id: 'J1',
        taskId: null,
        title: 'Find a hotel',
        planAccess: true,
        links: links,
      ),
    );
    final j = r.agentJobs.get('J1')!;
    expect(j.taskId, isNull);
    expect(j.title, 'Find a hotel');
    expect(j.planAccess, isTrue);
    expect(j.links, links);
  });

  test('all jobs, the newest change first', () {
    final r = makeRepos();
    r.agentJobs
      ..insert(
        AgentJob(id: 'A', taskId: null, updatedAt: '2026-10-20T09:00:00'),
      )
      ..insert(
        AgentJob(id: 'B', taskId: null, updatedAt: '2026-10-21T09:00:00'),
      );
    expect(r.agentJobs.all().map((j) => j.id), ['B', 'A']);
    r.agentJobs.setTitle('A', 'New name');
    expect(r.agentJobs.all().map((j) => j.id), ['A', 'B']);
    expect(r.agentJobs.get('A')!.title, 'New name');
  });

  test('only a finished job goes back in the queue', () {
    final r = makeRepos();
    r.agentJobs.insert(AgentJob(id: 'J1', taskId: null));
    const link = AgentLink(kind: AgentLinkKind.task, id: 'T1', name: 'X');
    bool requeue() => r.agentJobs.requeue(
      'J1',
      emailAccess: true,
      planAccess: true,
      links: const [link],
    );
    expect(requeue(), isFalse);
    r.agentJobs.claim('J1', 'Mac');
    expect(requeue(), isFalse);
    r.agentJobs.setStatus('J1', AgentStatus.failed, error: 'Oops');
    expect(requeue(), isTrue);
    final j = r.agentJobs.get('J1')!;
    expect(j.status, AgentStatus.queued);
    expect(j.runnerDevice, isNull);
    expect(j.error, isNull);
    expect(j.finishedAt, isNull);
    expect(j.emailAccess, isTrue);
    expect(j.planAccess, isTrue);
    expect(j.links, [link]);
    expect(requeue(), isFalse);
  });

  test('the lines of a chat come in order, and the next number follows the '
      'last', () {
    final r = makeRepos();
    r.agentJobs.insert(AgentJob(id: 'J1', taskId: null));
    expect(r.agentEvents.nextSeq('J1'), 1);
    r.agentEvents
      ..insert(
        AgentEvent(
          id: 'E2',
          jobId: 'J1',
          seq: 2,
          kind: AgentEventKind.step,
          label: AgentStep.search,
          body: 'hotels',
        ),
      )
      ..insert(
        AgentEvent(id: 'E1', jobId: 'J1', seq: 1, kind: AgentEventKind.ask),
      );
    expect(r.agentEvents.forJob('J1').map((e) => e.id), ['E1', 'E2']);
    expect(r.agentEvents.nextSeq('J1'), 3);
    expect(r.agentEvents.get('E2')!.label, AgentStep.search);

    final e = r.agentEvents.get('E1')!;
    r.agentEvents.update(e.copyWith(label: 'p0', body: 'Hi'));
    expect(r.agentEvents.get('E1')!.label, 'p0');
    expect(r.agentEvents.get('E1')!.body, 'Hi');
  });

  test('a line needs its job, and goes with it', () {
    final r = makeRepos();
    expect(
      () => r.agentEvents.insert(
        AgentEvent(jobId: 'nope', seq: 1, kind: AgentEventKind.ask),
      ),
      throwsA(anything),
    );
    r.tasks.save(TaskItem(id: 'T1', title: 'Plan'));
    r.agentJobs.insert(AgentJob(id: 'J1', taskId: 'T1'));
    r.agentEvents.insert(
      AgentEvent(id: 'E1', jobId: 'J1', seq: 1, kind: AgentEventKind.ask),
    );
    r.tasks.delete('T1');
    expect(r.agentJobs.get('J1'), isNull);
    expect(r.agentEvents.get('E1'), isNull);
  });

  test('a database of the agent build (shared 12, sync 6) keeps its jobs, '
      'and their task becomes optional', () {
    final dir = tempDir('grove-agent-13-');
    final path = join(dir, 'a.sqlite');
    var db = Database.open(path);
    Repos(db).tasks.save(TaskItem(id: 'T1', title: 'Plan'));
    // Take the database back to what the agent build makes: no chat
    // columns, no lines, and a job that needs its task.
    final sql = db
        .queryOne(
          "SELECT sql FROM sqlite_master WHERE name = 'agent_jobs'",
          const [],
          (r) => r.text(0),
        )!
        .replaceFirst(RegExp(r'task_id TEXT\b'), 'task_id TEXT NOT NULL')
        .replaceFirst('agent_jobs', 'agent_jobs_old');
    db.executeScript('''
      DROP TABLE agent_events;
      DROP TRIGGER sync_agent_jobs_insert;
      DROP TRIGGER sync_agent_jobs_update;
      DROP TRIGGER sync_agent_jobs_delete;
      ALTER TABLE agent_jobs DROP COLUMN title;
      ALTER TABLE agent_jobs DROP COLUMN plan_access;
      ALTER TABLE agent_jobs DROP COLUMN links_json;
    ''');
    final cols = db
        .query('PRAGMA table_info(agent_jobs)', const [], (r) => r.text(1))
        .join(', ');
    db.executeScript('''
      ${sql.replaceAll(RegExp(r',\s*title[^,]*|,\s*plan_access[^,]*|,\s*links_json[^,)]*'), '')};
      INSERT INTO agent_jobs_old ($cols) SELECT $cols FROM agent_jobs;
      DROP TABLE agent_jobs;
      ALTER TABLE agent_jobs_old RENAME TO agent_jobs;
      INSERT INTO agent_jobs (id, task_id, instructions, email_access, status,
        created_at, updated_at)
        VALUES ('J1', 'T1', 'Short', 1, 'done', '2026-10-20T09:00:00',
        '2026-10-20T09:00:00');
      PRAGMA user_version = 12;
      UPDATE sync_meta SET value = '6' WHERE key = 'schema';
      DELETE FROM sync_meta WHERE key = 'triggers';
      DELETE FROM outbox;
    ''');
    bool required(Database db) =>
        db
            .query(
              "SELECT \"notnull\" FROM pragma_table_info('agent_jobs') "
              "WHERE name = 'task_id'",
              const [],
              (r) => r.asInt(0),
            )
            .single ==
        1;
    expect(required(db), isTrue);
    db.close();

    db = Database.open(path);
    addTearDown(db.close);
    expect(db.userVersion, 13);
    expect(db.syncVersion, 7);
    expect(required(db), isFalse);
    final r = Repos(db);
    final j = r.agentJobs.get('J1')!;
    expect(j.taskId, 'T1');
    expect(j.instructions, 'Short');
    expect(j.emailAccess, isTrue);
    expect(j.title, '');
    expect(j.links, isEmpty);
    final after = db.query(
      'PRAGMA table_info(agent_jobs)',
      const [],
      (r) => r.text(1),
    );
    expect(after, containsAll(['deleted', 'user_id', 'updated_at', 'title']));
    expect(after.where((c) => c == 'updated_at'), hasLength(1));
    expect(
      db.query(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND tbl_name = 'agent_jobs' AND name NOT LIKE 'sqlite_%' "
        'ORDER BY name',
        const [],
        (r) => r.text(0),
      ),
      containsAll(['agent_jobs_status', 'agent_jobs_task']),
    );
    expect(Outbox(db).count, 0);
    r.agentJobs.insert(AgentJob(id: 'J2', taskId: null));
    r.agentEvents.insert(
      AgentEvent(jobId: 'J2', seq: 1, kind: AgentEventKind.ask),
    );
    expect(Outbox(db).entries().map((e) => e.table), [
      'agent_jobs',
      'agent_events',
    ]);
    // A job of a task still goes with its task.
    r.tasks.delete('T1');
    expect(r.agentJobs.get('J1'), isNull);
  });
}
