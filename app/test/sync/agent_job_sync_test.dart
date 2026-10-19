import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// The jobs of the agent (table `agent_jobs`, shared migration 11, sync
// migration 6) sync like every other row: a phone makes a job, the Mac runs
// it, and the phone sees the result (ADR 0004).

void main() {
  late MemoryRemote remote;
  late Device phone, mac;

  setUp(() {
    remote = MemoryRemote();
    phone = Device(remote);
    mac = Device(remote);
  });

  test('a job made on the phone reaches the Mac, and its result comes '
      'back', () async {
    phone.later();
    phone.repos.tasks.save(TaskItem(id: 'T1', title: 'Plan the trip'));
    phone.repos.agentJobs.insert(
      AgentJob(
        id: 'J1',
        taskId: 'T1',
        instructions: 'Short',
        emailAccess: true,
      ),
    );
    expect(phone.waiting, contains('agent_jobs saved'));
    await settle([phone, mac]);
    expect(mac.repos.agentJobs.queued().single.instructions, 'Short');
    expect(mac.repos.agentJobs.get('J1')!.emailAccess, isTrue);

    mac.later();
    expect(mac.repos.agentJobs.claim('J1', 'Mac'), isTrue);
    mac.repos.notes.save(Note(id: 'N1', title: 'Agent: Plan the trip'));
    mac.repos.agentJobs.setStatus(
      'J1',
      AgentStatus.done,
      resultJson: '{"summary":"ok"}',
      resultNoteId: 'N1',
    );
    await settle([phone, mac]);
    final j = phone.repos.agentJobs.get('J1')!;
    expect(j.status, AgentStatus.done);
    expect(j.runnerDevice, 'Mac');
    expect(j.resultNoteId, 'N1');
    expect(phone.repos.notes.get('N1')?.title, 'Agent: Plan the trip');
    expectSame([phone, mac]);
  });

  test('a cancel on the phone reaches the Mac', () async {
    phone.later();
    phone.repos.tasks.save(TaskItem(id: 'T1', title: 'Plan'));
    phone.repos.agentJobs.insert(AgentJob(id: 'J1', taskId: 'T1'));
    await settle([phone, mac]);
    mac.later();
    mac.repos.agentJobs.claim('J1', 'Mac');
    await settle([phone, mac]);

    phone.later();
    phone.repos.agentJobs.setStatus('J1', AgentStatus.cancelRequested);
    await settle([phone, mac]);
    expect(mac.repos.agentJobs.get('J1')!.status, AgentStatus.cancelRequested);
    expectSame([phone, mac]);
  });

  test('a deleted task takes its jobs away on the other device too', () async {
    phone.later();
    phone.repos.tasks.save(TaskItem(id: 'T1', title: 'Plan'));
    phone.repos.agentJobs.insert(AgentJob(id: 'J1', taskId: 'T1'));
    await settle([phone, mac]);
    expect(mac.repos.agentJobs.get('J1'), isNotNull);

    phone.later();
    phone.repos.tasks.delete('T1');
    expect(phone.waiting, contains('agent_jobs gone'));
    await settle([phone, mac]);
    expect(mac.repos.agentJobs.get('J1'), isNull);
    expectSame([phone, mac]);
  });

  test('a database from before the agent gets the table in the sync', () {
    final dir = Directory.systemTemp.createTempSync('grove-agent-sync-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/a.sqlite';
    var db = Database.open(path);
    Repos(db).tasks.save(TaskItem(id: 'T1', title: 'Plan'));
    // Take the database back to shared schema 10 and sync schema 5.
    db.executeScript('''
      DROP TABLE agent_jobs;
      PRAGMA user_version = 10;
      UPDATE sync_meta SET value = '5' WHERE key = 'schema';
      DELETE FROM sync_meta WHERE key = 'triggers';
    ''');
    db.execute('DELETE FROM outbox');
    db.close();

    db = Database.open(path);
    addTearDown(db.close);
    expect(db.userVersion, Migrations.all.length);
    expect(db.syncVersion, SyncMigrations.all.length);
    final cols = db.query(
      'PRAGMA table_info(agent_jobs)',
      const [],
      (r) => r.text(1),
    );
    expect(cols, containsAll(['deleted', 'user_id', 'updated_at']));
    expect(cols.where((c) => c == 'updated_at'), hasLength(1));
    final r = Repos(db);
    r.agentJobs.insert(AgentJob(id: 'J1', taskId: 'T1'));
    expect(Outbox(db).entries().map((e) => e.table), ['agent_jobs']);
  });
}
