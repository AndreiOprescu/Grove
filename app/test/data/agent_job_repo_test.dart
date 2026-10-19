import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/agent/agent_models.dart';
import 'package:grove/core/model/note.dart';
import 'package:grove/core/model/task.dart';
import 'package:grove/data/data.dart';

import 'helpers.dart';

// The jobs of the agent (shared migration 11, ADR 0004). A job belongs to a
// task and goes with it. Only one runner can take a queued job.

Repos withTask() {
  final r = makeRepos();
  r.tasks.save(TaskItem(id: 'T1', title: 'Plan the trip'));
  return r;
}

AgentJob job(String id, {String task = 'T1', String at = '2026-10-19T09:00'}) =>
    AgentJob(
      id: id,
      taskId: task,
      instructions: 'Keep it short',
      createdAt: '$at:00',
    );

void main() {
  test(
    'the agent jobs are migration 11, and the database is at the newest',
    () {
      final db = makeRepos().db;
      expect(Migrations.all[10], contains('CREATE TABLE agent_jobs'));
      expect(db.userVersion, Migrations.all.length);
    },
  );

  test('a job is saved and read back with every field', () {
    final r = withTask();
    r.notes.save(Note(id: 'N1', title: 'Result'));
    final j = AgentJob(
      id: 'J1',
      taskId: 'T1',
      instructions: 'Use the web',
      emailAccess: true,
      status: AgentStatus.done,
      runnerDevice: 'Mac',
      resultJson: '{"summary":"ok"}',
      error: 'none',
      resultNoteId: 'N1',
      createdAt: '2026-10-19T09:00:00',
      updatedAt: '2026-10-19T09:05:00',
      finishedAt: '2026-10-19T09:05:00',
    );
    r.agentJobs.insert(j);
    expect(r.agentJobs.get('J1'), j);
    expect(r.agentJobs.get('nope'), isNull);
  });

  test('the status is kept as text', () {
    final r = withTask();
    r.agentJobs.insert(job('J1').copyWith(status: AgentStatus.cancelRequested));
    final code = r.db.queryOne('SELECT status FROM agent_jobs WHERE id = ?', [
      'J1',
    ], (row) => row.text(0));
    expect(code, 'cancel_requested');
    expect(AgentStatus.fromCode('something new'), AgentStatus.failed);
    for (final s in AgentStatus.values) {
      expect(AgentStatus.fromCode(s.code), s);
    }
  });

  test('forTask gives the newest job of the task', () {
    final r = withTask();
    r.tasks.save(TaskItem(id: 'T2', title: 'Other'));
    r.agentJobs.insert(job('OLD', at: '2026-10-19T08:00'));
    r.agentJobs.insert(job('NEW', at: '2026-10-19T10:00'));
    r.agentJobs.insert(job('X', task: 'T2', at: '2026-10-19T11:00'));
    expect(r.agentJobs.forTask('T1')?.id, 'NEW');
    expect(r.agentJobs.forTask('T3'), isNull);
  });

  test('queued gives the waiting jobs, the oldest first', () {
    final r = withTask();
    r.agentJobs.insert(job('B', at: '2026-10-19T10:00'));
    r.agentJobs.insert(job('A', at: '2026-10-19T08:00'));
    r.agentJobs.insert(
      job('C', at: '2026-10-19T07:00').copyWith(status: AgentStatus.running),
    );
    expect(r.agentJobs.queued().map((j) => j.id), ['A', 'B']);
    expect(r.agentJobs.withStatus(AgentStatus.running).map((j) => j.id), ['C']);
  });

  test('setStatus keeps what it is not given, and stamps the end', () {
    final r = withTask();
    r.agentJobs.insert(job('J1'));
    expect(r.agentJobs.setStatus('J1', AgentStatus.running), isTrue);
    var j = r.agentJobs.get('J1')!;
    expect(j.status, AgentStatus.running);
    expect(j.finishedAt, isNull);

    r.agentJobs.setStatus(
      'J1',
      AgentStatus.done,
      resultJson: jsonEncode({'summary': 'ok'}),
    );
    j = r.agentJobs.get('J1')!;
    expect(j.status, AgentStatus.done);
    expect(j.resultJson, '{"summary":"ok"}');
    expect(j.error, isNull);
    expect(j.finishedAt, isNotNull);
    expect(j.instructions, 'Keep it short');
  });

  test('setStatus with from changes only a job in one of those states', () {
    final r = withTask();
    r.agentJobs.insert(job('J1').copyWith(status: AgentStatus.done));
    expect(
      r.agentJobs.setStatus(
        'J1',
        AgentStatus.cancelRequested,
        from: {AgentStatus.queued, AgentStatus.running},
      ),
      isFalse,
    );
    expect(r.agentJobs.get('J1')!.status, AgentStatus.done);
    expect(r.agentJobs.setStatus('nope', AgentStatus.failed), isFalse);
  });

  test('a job can be claimed once: the second runner gets nothing', () {
    final r = withTask();
    r.agentJobs.insert(job('J1'));
    expect(r.agentJobs.claim('J1', 'Mac'), isTrue);
    expect(r.agentJobs.claim('J1', 'Other Mac'), isFalse);
    final j = r.agentJobs.get('J1')!;
    expect(j.status, AgentStatus.running);
    expect(j.runnerDevice, 'Mac');
    expect(r.agentJobs.claim('nope', 'Mac'), isFalse);
  });

  test('two connections to one file: only one claim wins', () {
    final dir = tempDir('grove-agent-');
    final path = join(dir, 'a.sqlite');
    final a = Repos(Database.open(path));
    a.tasks.save(TaskItem(id: 'T1', title: 'Plan'));
    a.agentJobs.insert(job('J1'));
    final b = Repos(Database.open(path));
    final wins = [a.agentJobs.claim('J1', 'A'), b.agentJobs.claim('J1', 'B')];
    expect(wins, [true, false]);
    expect(b.agentJobs.get('J1')!.runnerDevice, 'A');
    a.db.close();
    b.db.close();
  });

  test('a cancelled or finished job cannot be claimed', () {
    final r = withTask();
    for (final s in [
      AgentStatus.cancelRequested,
      AgentStatus.cancelled,
      AgentStatus.done,
      AgentStatus.failed,
    ]) {
      r.agentJobs.insert(job(s.code).copyWith(status: s));
      expect(r.agentJobs.claim(s.code, 'Mac'), isFalse, reason: s.code);
    }
  });

  test('the jobs go with their task; a deleted result note empties the '
      'pointer', () {
    final r = withTask();
    r.notes.save(Note(id: 'N1', title: 'Result'));
    r.agentJobs.insert(job('J1').copyWith(resultNoteId: 'N1'));
    r.notes.delete('N1');
    expect(r.agentJobs.get('J1')!.resultNoteId, isNull);
    r.tasks.delete('T1');
    expect(r.agentJobs.get('J1'), isNull);
  });

  test('the export has the jobs and the import puts them back', () {
    final a = withTask();
    a.agentJobs.insert(job('J1').copyWith(emailAccess: true));
    final file = DataExport.export(a.db);
    final obj = jsonDecode(file) as Map<String, Object?>;
    final rows = (obj['tables'] as Map)['agent_jobs'] as List;
    expect((rows.single as Map)['email_access'], 1);
    final b = makeRepos();
    DataExport.importData(file, b);
    expect(b.agentJobs.get('J1'), a.agentJobs.get('J1'));
  });
}
