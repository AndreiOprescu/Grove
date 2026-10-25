import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import '../data/helpers.dart' show rewindNotebooks;
import 'support.dart';

// The jobs of the agent (table `agent_jobs`, shared migration 12, sync
// migration 6) and their steps (table `agent_events`, shared migration 13,
// sync migration 7) sync like every other row: a phone makes a job, the Mac
// runs it, and the phone sees the steps and the result (ADR 0004, 0005).

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

  test('a database of the deadlines build (PR #37: shared schema 11 with '
      'events.is_deadline, sync schema 5) gets the agent jobs and their '
      'sync triggers', () {
    final dir = Directory.systemTemp.createTempSync('grove-agent-sync-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/a.sqlite';
    var db = Database.open(path);
    Repos(db).tasks.save(TaskItem(id: 'T1', title: 'Plan'));
    Repos(db).events.save(
      EventItem(
        id: 'E1',
        title: 'Essay due',
        start: at('2026-10-20T15:00'),
        end: at('2026-10-20T17:00'),
        isDeadline: true,
      ),
    );
    // Take the database back to what the deadlines build makes: shared
    // migrations 1 to 11 and sync migrations 1 to 5. That build has no
    // sync migration of its own, so only the agent tables and their sync go,
    // and the notebooks (shared 14, sync 8), which came later.
    rewindNotebooks(db);
    db.executeScript('''
      DROP TABLE agent_events;
      DROP TABLE agent_jobs;
      PRAGMA user_version = 11;
      UPDATE sync_meta SET value = '5' WHERE key = 'schema';
      DELETE FROM sync_meta WHERE key = 'triggers';
    ''');
    db.execute('DELETE FROM outbox');
    // The same tables and data columns as shared migrations 1 to 11 run on
    // an empty database.
    final old = raw.sqlite3.openInMemory();
    old.execute(Migrations.all.take(11).join(';'));
    List<String> tablesOf(List<String> names) => [
      for (final n in names)
        if (n != 'outbox' && n != 'sync_meta') n,
    ]..sort();
    const tableSql =
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%'";
    final oldTables = tablesOf([
      for (final r in old.select(tableSql)) r['name'] as String,
    ]);
    expect(oldTables, isNot(contains('agent_jobs')));
    expect(tablesOf(db.query(tableSql, const [], (r) => r.text(0))), oldTables);
    for (final t in oldTables) {
      final added = SyncMigrations.addedColumns[t] ?? const <String>{};
      expect(
        [
          for (final c in db.query(
            'PRAGMA table_info($t)',
            const [],
            (r) => r.text(1),
          ))
            if (!added.contains(c)) c,
        ],
        [for (final r in old.select('PRAGMA table_info($t)')) r['name']],
        reason: t,
      );
    }
    old.close();
    db.close();

    db = Database.open(path);
    addTearDown(db.close);
    expect(db.userVersion, 14);
    expect(db.userVersion, Migrations.all.length);
    expect(db.syncVersion, 8);
    expect(db.syncVersion, SyncMigrations.all.length);
    final cols = db.query(
      'PRAGMA table_info(agent_jobs)',
      const [],
      (r) => r.text(1),
    );
    expect(cols, containsAll(['task_id', 'deleted', 'user_id', 'updated_at']));
    expect(cols.where((c) => c == 'updated_at'), hasLength(1));
    final triggers = db.query(
      "SELECT name FROM sqlite_master WHERE type = 'trigger' "
      "AND tbl_name = 'agent_jobs' ORDER BY name",
      const [],
      (r) => r.text(0),
    );
    expect(triggers, [
      'sync_agent_jobs_delete',
      'sync_agent_jobs_insert',
      'sync_agent_jobs_update',
    ]);
    expect(
      db.query(
        "SELECT name FROM sqlite_master WHERE type = 'trigger' "
        "AND tbl_name = 'agent_events' ORDER BY name",
        const [],
        (r) => r.text(0),
      ),
      [
        'sync_agent_events_delete',
        'sync_agent_events_insert',
        'sync_agent_events_update',
      ],
    );
    // The deadline is kept, and its column is still watched by the sync.
    final r = Repos(db);
    expect(r.events.get('E1')!.isDeadline, isTrue);
    expect(r.events.deadlines().map((e) => e.id), ['E1']);
    expect(Outbox(db).count, 0);
    r.agentJobs.insert(AgentJob(id: 'J1', taskId: 'T1'));
    expect(Outbox(db).entries().map((e) => e.table), ['agent_jobs']);
    db.execute('UPDATE events SET is_deadline = 0 WHERE id = ?', ['E1']);
    expect(
      Outbox(db).entries().map((e) => (e.table, e.key)),
      containsAll([('agent_jobs', 'J1'), ('events', 'E1')]),
    );
  });
}
