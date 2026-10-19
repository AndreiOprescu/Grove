// The agent in the store (ADR 0004): the switches, the jobs, and the worker
// of the computer that runs them, with a fake `claude`.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'sync_support.dart';

AgentRunOutput answer(Map<String, Object?> result) => AgentRunOutput(
  exitCode: 0,
  stdout: jsonEncode({
    'type': 'result',
    'subtype': 'success',
    'is_error': false,
    'structured_output': result,
  }),
  stderr: '',
);

const plainResult = {'summary': 'Done it.'};

String initLine({
  String status = 'connected',
  List<String> tools = const [
    'WebSearch',
    'mcp__claude_ai_Gmail__search_threads',
    'mcp__claude_ai_Gmail__send_message',
    'mcp__claude_ai_Drive__list_files',
  ],
}) => jsonEncode({
  'type': 'system',
  'subtype': 'init',
  'tools': tools,
  'mcp_servers': [
    {'name': 'claude.ai Gmail', 'status': status},
  ],
});

/// The value after [flag] in [args].
String? flagValue(List<String> args, String flag) {
  final i = args.indexOf(flag);
  return i < 0 || i + 1 >= args.length ? null : args[i + 1];
}

void main() {
  late ManualTimers timers;

  setUp(() => timers = ManualTimers());

  /// A store with [runner], once it looked for `claude`. The runner switch
  /// is on unless [prefs] says else.
  Future<AppStore> open(
    FakeAgentRunner? runner, {
    Map<String, Object?> prefs = const {'agent.runner': true},
    Repos? repos,
  }) async {
    final s = makeStore(
      agentRunner: runner,
      prefs: MemoryPrefs(prefs),
      repos: repos,
    );
    s.newTimer = timers.start;
    await s.agentWork;
    return s;
  }

  TaskItem addTask(AppStore s, String title, {String notes = ''}) {
    final t = TaskItem(title: title, notes: notes);
    s.repos.tasks.save(t);
    return t;
  }

  AgentJob job(AppStore s, String id) => s.repos.agentJobs.get(id)!;

  group('the switches', () {
    test('all three are off at first, also on a computer', () async {
      final s = await open(FakeAgentRunner(), prefs: const {});
      expect(s.agentEnabled, isFalse);
      expect(s.agentRunnerOn, isFalse);
      expect(s.agentEmailOn, isFalse);
    });

    test('they are saved in the prefs of this device', () async {
      final prefs = MemoryPrefs();
      final s = makeStore(prefs: prefs);
      s
        ..setAgentEnabled(true)
        ..setAgentRunner(true)
        ..setAgentEmail(true);
      expect(prefs.getBool('agent.enabled'), isTrue);
      expect(prefs.getBool('agent.runner'), isTrue);
      expect(prefs.getBool('agent.email'), isTrue);
      final again = makeStore(prefs: prefs);
      expect(again.agentEnabled, isTrue);
      expect(again.agentRunnerOn, isTrue);
      expect(again.agentEmailOn, isTrue);
    });

    test('a phone has no runner: it cannot run, and says why', () async {
      final s = await open(null);
      expect(s.canRunAgent, isFalse);
      expect(s.agentHelp, SettingsRules.agentNoRunner);
    });

    test('a computer with no claude cannot run, and says why', () async {
      final s = await open(FakeAgentRunner(exe: null));
      expect(s.canRunAgent, isFalse);
      expect(s.agentHelp, SettingsRules.agentNotFound);
    });

    test('a computer with claude can run; no help text', () async {
      final s = await open(FakeAgentRunner());
      expect(s.canRunAgent, isTrue);
      expect(s.agentHelp, isNull);
    });

    test('turning the runner on looks for claude again', () async {
      final runner = FakeAgentRunner(exe: null);
      final s = await open(runner, prefs: const {});
      expect(s.canRunAgent, isFalse);
      runner.exe = '/now/claude';
      s.setAgentRunner(true);
      await s.agentWork;
      expect(runner.locates, 2);
      expect(s.canRunAgent, isTrue);
    });
  });

  group('jobs', () {
    test('delegate makes a queued job that syncs', () async {
      final s = await open(null);
      final t = addTask(s, 'Book the dentist');
      final id = s.delegateToAgent(
        t.id,
        instructions: '  Thursday morning  ',
        email: true,
      );
      final j = job(s, id);
      expect(j.status, AgentStatus.queued);
      expect(j.taskId, t.id);
      expect(j.instructions, 'Thursday morning');
      expect(j.emailAccess, isTrue);
      expect(s.agentJobFor(t.id)?.id, id);
      expect(s.agentJobFor('nothing'), isNull);
    });

    test('a job for a task that is gone is not saved', () async {
      final s = await open(null);
      expect(s.delegateToAgent(newId()), '');
      expect(s.errorMessage, isNotNull);
    });

    test('cancel of a queued job is at once', () async {
      final s = await open(FakeAgentRunner(), prefs: const {});
      final t = addTask(s, 'Write the plan');
      final id = s.delegateToAgent(t.id);
      s.cancelAgentJob(id);
      expect(job(s, id).status, AgentStatus.cancelled);
      expect(job(s, id).error, AgentNote.cancelled);
    });
  });

  group('the worker', () {
    test('does nothing when the runner switch is off', () async {
      final runner = FakeAgentRunner(output: answer(plainResult));
      final s = await open(runner, prefs: const {});
      final t = addTask(s, 'Write the plan');
      final id = s.delegateToAgent(t.id);
      await s.runAgentQueue();
      expect(runner.calls, isEmpty);
      expect(job(s, id).status, AgentStatus.queued);
    });

    test('does nothing when this computer has no claude', () async {
      final runner = FakeAgentRunner(exe: null, output: answer(plainResult));
      final s = await open(runner);
      final t = addTask(s, 'Write the plan');
      final id = s.delegateToAgent(t.id);
      await s.runAgentQueue();
      expect(runner.calls, isEmpty);
      expect(job(s, id).status, AgentStatus.queued);
    });

    test('a done job leaves a result note and a document note, linked to '
        'the task and made safe', () async {
      final runner = FakeAgentRunner(
        output: answer({
          'summary': 'I wrote the plan.\n- [ ] sneaky task',
          'steps': ['Searched the web', '[ ] not a box'],
          'document': {
            'title': 'Plan [[for]] X',
            'markdown': '# Plan\n- [ ] buy milk\nSee [[Secret|abc]]',
          },
          'email_draft': {
            'to': 'ann@example.com',
            'subject': 'The plan',
            'body': 'Hi Ann,\nhere it is.',
          },
          'text_draft': {'to': '+44 7700 900123', 'body': 'Plan is ready'},
          'questions': ['Which day?'],
          'sources': ['https://example.com'],
        }),
      );
      final s = await open(runner);
      final t = addTask(s, 'Write the plan', notes: 'For the trip');
      final tasksBefore = s.repos.tasks.all().length;
      final id = s.delegateToAgent(t.id, instructions: 'One page');
      await s.agentWork;

      final j = job(s, id);
      expect(j.status, AgentStatus.done);
      expect(j.runnerDevice, s.prefs.getString('agent.device'));
      expect(j.finishedAt, isNotNull);
      final call = runner.calls.single;
      expect(call.exe, '/fake/claude');
      expect(call.timeout, AgentPolicy.timeout);
      expect(call.args, AgentPolicy.args(email: false));
      expect(call.stdin, contains('Write the plan'));
      expect(call.stdin, contains('For the trip'));
      expect(call.stdin, contains('One page'));

      final result = s.agentResult(j)!;
      expect(result.summary, startsWith('I wrote the plan.'));
      expect(result.emailDraft?.to, 'ann@example.com');

      final note = s.note(j.resultNoteId!)!;
      expect(note.title, 'Agent: Write the plan');
      final body = note.body;
      for (final part in [
        '## Summary',
        '## Steps',
        '## Email draft',
        'To: ann@example.com',
        'Subject: The plan',
        '## Text draft',
        'To: +44 7700 900123',
        '## Questions',
        'Which day?',
        '## Sources',
      ]) {
        expect(body, contains(part));
      }
      expect(body, isNot(contains('- [ ]')));
      final links = s.linkedItems(ItemRef(ItemType.task, t.id));
      final linkedNotes = [
        for (final l in links)
          if (l.ref.type == ItemType.note) s.note(l.id)!,
      ];
      expect(linkedNotes.map((n) => n.id), contains(note.id));
      final doc = linkedNotes.firstWhere((n) => n.id != note.id);
      expect(doc.title, 'Plan [ [for]] X');
      expect(doc.body, contains('# Plan'));
      expect(doc.body, isNot(contains('- [ ]')));
      expect(doc.body, isNot(contains('[[Secret')));
      // The result note links to the document, and to nothing the agent
      // wrote.
      expect(s.linkedItems(ItemRef(ItemType.note, doc.id)).map((l) => l.id), [
        note.id,
      ]);
      // No task came from the text of the agent.
      expect(s.repos.tasks.all().length, tasksBefore);
      // A write of the agent is not undone by Undo.
      expect(s.undoStack, isEmpty);
      expect(s.agentJobFor(t.id)?.status, AgentStatus.done);
    });

    test('an answer Grove cannot read: the job failed, no note', () async {
      final runner = FakeAgentRunner(
        output: const AgentRunOutput(
          exitCode: 0,
          stdout: 'not json',
          stderr: '',
        ),
      );
      final s = await open(runner);
      final t = addTask(s, 'Write the plan');
      final notesBefore = s.repos.notes.all().length;
      final id = s.delegateToAgent(t.id);
      await s.agentWork;
      final j = job(s, id);
      expect(j.status, AgentStatus.failed);
      expect(j.error, isNotEmpty);
      expect(j.resultNoteId, isNull);
      expect(s.repos.notes.all().length, notesBefore);
    });

    test('no answer at all: failed, with what claude said', () async {
      final runner = FakeAgentRunner(
        output: const AgentRunOutput(
          exitCode: 1,
          stdout: '',
          stderr: 'Not logged in',
        ),
      );
      final s = await open(runner);
      final id = s.delegateToAgent(addTask(s, 'X').id);
      await s.agentWork;
      expect(job(s, id).status, AgentStatus.failed);
      expect(job(s, id).error, AgentNote.noAnswer('Not logged in'));
    });

    test('a time out: failed, with a plain message', () async {
      final runner = FakeAgentRunner(
        output: const AgentRunOutput(
          exitCode: -15,
          stdout: '',
          stderr: '',
          timedOut: true,
        ),
      );
      final s = await open(runner);
      final id = s.delegateToAgent(addTask(s, 'X').id);
      await s.agentWork;
      expect(job(s, id).status, AgentStatus.failed);
      expect(job(s, id).error, AgentNote.timedOut);
    });

    test('a job with email on a computer where email is off runs without '
        'Gmail, and says so', () async {
      final runner = FakeAgentRunner(
        initLine: initLine(),
        output: answer(plainResult),
      );
      final s = await open(runner);
      final id = s.delegateToAgent(addTask(s, 'Reply to Ann').id, email: true);
      await s.agentWork;
      expect(runner.probes, isEmpty);
      final args = runner.calls.single.args;
      expect(args, AgentPolicy.args(email: false));
      expect(args.join(' '), isNot(contains('Gmail')));
      expect(runner.calls.single.stdin, contains('cannot read email'));
      final j = job(s, id);
      expect(j.status, AgentStatus.done);
      expect(s.agentResult(j)!.questions, [AgentNote.emailNotAllowed]);
      expect(
        s.note(j.resultNoteId!)!.body,
        contains(AgentNote.emailNotAllowed),
      );
    });

    test(
      'a job with email, and email on: only the read tools of Gmail',
      () async {
        final runner = FakeAgentRunner(
          initLine: initLine(),
          output: answer(plainResult),
        );
        final s = await open(
          runner,
          prefs: const {'agent.runner': true, 'agent.email': true},
        );
        final id = s.delegateToAgent(
          addTask(s, 'Reply to Ann').id,
          email: true,
        );
        await s.agentWork;
        expect(runner.probes.single, AgentPolicy.probeArgs());
        final args = runner.calls.single.args;
        expect(
          flagValue(args, '--allowedTools'),
          'WebSearch,mcp__claude_ai_Gmail__search_threads',
        );
        expect(
          flagValue(args, '--disallowedTools')!.split(','),
          unorderedEquals([
            'mcp__claude_ai_Gmail__send_message',
            'mcp__claude_ai_Drive__list_files',
          ]),
        );
        expect(args, isNot(contains('WebFetch')));
        expect(job(s, id).status, AgentStatus.done);
        expect(s.agentResult(job(s, id))!.questions, isEmpty);
      },
    );

    test(
      'Gmail that needs a login: the job fails and says how to fix it',
      () async {
        final runner = FakeAgentRunner(
          initLine: initLine(status: 'needs-auth', tools: const ['WebSearch']),
          output: answer(plainResult),
        );
        final s = await open(
          runner,
          prefs: const {'agent.runner': true, 'agent.email': true},
        );
        final id = s.delegateToAgent(
          addTask(s, 'Reply to Ann').id,
          email: true,
        );
        await s.agentWork;
        expect(runner.calls, isEmpty);
        expect(job(s, id).status, AgentStatus.failed);
        expect(job(s, id).error, AgentPolicy.gmailNotReady);
      },
    );

    test('a cancel from another device stops claude', () async {
      final runner = FakeAgentRunner();
      final s = await open(runner);
      final id = s.delegateToAgent(addTask(s, 'X').id);
      await pumpEventQueue();
      expect(runner.processes, hasLength(1));
      expect(job(s, id).status, AgentStatus.running);
      // The cancel arrives with a sync pull.
      s.repos.agentJobs.setStatus(id, AgentStatus.cancelRequested);
      timers.pass(AppStoreAgent.agentPoll);
      await s.agentWork;
      expect(runner.processes.single.cancels, 1);
      expect(job(s, id).status, AgentStatus.cancelled);
      expect(job(s, id).resultNoteId, isNull);
    });

    test('a cancel on this device stops claude at once', () async {
      final runner = FakeAgentRunner();
      final s = await open(runner);
      final id = s.delegateToAgent(addTask(s, 'X').id);
      await pumpEventQueue();
      s.cancelAgentJob(id);
      expect(runner.processes.single.cancels, 1);
      await s.agentWork;
      expect(job(s, id).status, AgentStatus.cancelled);
    });

    test('one job at a time, the oldest first', () async {
      final runner = FakeAgentRunner();
      final s = await open(runner);
      final first = s.delegateToAgent(addTask(s, 'First').id);
      final second = s.delegateToAgent(addTask(s, 'Second').id);
      await pumpEventQueue();
      expect(runner.calls.single.stdin, contains('First'));
      expect(job(s, second).status, AgentStatus.queued);
      runner.processes.single.finish(answer(plainResult));
      await pumpEventQueue();
      expect(job(s, first).status, AgentStatus.done);
      expect(runner.calls, hasLength(2));
      runner.processes.last.finish(answer(plainResult));
      await s.agentWork;
      expect(job(s, second).status, AgentStatus.done);
    });

    test('a job that synced in runs at the one-minute check', () async {
      final runner = FakeAgentRunner(output: answer(plainResult));
      final s = await open(runner);
      final t = addTask(s, 'From the phone');
      final j = AgentJob(taskId: t.id);
      s.repos.agentJobs.insert(j);
      expect(runner.calls, isEmpty);
      timers.pass(AppStoreAgent.agentTick);
      await pumpEventQueue();
      await s.agentWork;
      expect(job(s, j.id).status, AgentStatus.done);
    });

    test('a job this device ran when Grove closed is failed at the next '
        'start; the job of another device stays', () async {
      final repos = Repos(Database.inMemory());
      final t = TaskItem(title: 'X');
      repos.tasks.save(t);
      final mine = AgentJob(
        taskId: t.id,
        status: AgentStatus.running,
        runnerDevice: 'this-mac',
      );
      final other = AgentJob(
        taskId: t.id,
        status: AgentStatus.running,
        runnerDevice: 'other-mac',
      );
      repos.agentJobs
        ..insert(mine)
        ..insert(other);
      final s = await open(
        FakeAgentRunner(),
        repos: repos,
        prefs: const {'agent.device': 'this-mac'},
      );
      expect(job(s, mine.id).status, AgentStatus.failed);
      expect(job(s, mine.id).error, AgentNote.crashed);
      expect(job(s, other.id).status, AgentStatus.running);
    });

    test('closing the store stops claude', () async {
      final runner = FakeAgentRunner();
      // Not `makeStore`: this test closes the store itself.
      final s = AppStore(
        repos: Repos(Database.inMemory()),
        agentRunner: runner,
        prefs: MemoryPrefs({'agent.runner': true}),
      );
      s.newTimer = timers.start;
      await s.agentWork;
      s.delegateToAgent(addTask(s, 'X').id);
      await pumpEventQueue();
      s.dispose();
      expect(runner.processes.single.cancels, 1);
    });

    test('the phone delegates, the Mac runs it after a sync pull, and the '
        'phone sees the result note', () async {
      final world = World();
      const email = 'ann@example.com';
      final phone = world.device(signedIn: email);
      final runner = FakeAgentRunner(output: answer(plainResult));
      final mac = world.device(
        signedIn: email,
        agentRunner: runner,
        prefs: MemoryPrefs({'agent.runner': true}),
      );
      await world.pass(Duration.zero);
      await mac.store.agentWork;
      final t = TaskItem(title: 'Plan the trip');
      phone.store.repos.tasks.save(t);
      final id = phone.store.delegateToAgent(t.id);
      await world.pass(phone.store.syncDelay);
      expect(runner.calls, isEmpty);

      await mac.store.syncNow();
      await mac.store.agentWork;
      expect(runner.calls, hasLength(1));
      expect(mac.store.repos.agentJobs.get(id)!.status, AgentStatus.done);

      await world.pass(mac.store.syncDelay);
      await phone.store.syncNow();
      final j = phone.store.agentJobFor(t.id)!;
      expect(j.status, AgentStatus.done);
      expect(phone.store.note(j.resultNoteId!)?.title, 'Agent: Plan the trip');
    });
  });
}
