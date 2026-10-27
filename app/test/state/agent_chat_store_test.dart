// The chats of the Agents screen in the store (ADR 0005): a chat with no
// task, its live lines, a new message after the answer, linked notes and
// files, the plan, and the proposals the person applies.
import 'dart:convert';
import 'dart:io';

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

String toolLine(String name, Map<String, Object?> input) => jsonEncode({
  'type': 'assistant',
  'message': {
    'content': [
      {'type': 'tool_use', 'name': name, 'input': input},
    ],
  },
});

void main() {
  late ManualTimers timers;

  setUp(() => timers = ManualTimers());

  Future<AppStore> open(
    FakeAgentRunner? runner, {
    bool runnerOn = true,
    String? dataDir,
  }) async {
    final s = makeStore(
      agentRunner: runner,
      prefs: MemoryPrefs({'agent.runner': runnerOn}),
      clock: WallTime.parse('2026-10-22T09:00'),
      dataDir: dataDir,
    );
    s.newTimer = timers.start;
    await s.agentWork;
    return s;
  }

  List<AgentEventKind> kinds(AppStore s, String id) => [
    for (final e in s.agentEvents(id)) e.kind,
  ];

  group('a new chat', () {
    test('an empty message makes no chat', () async {
      final s = await open(null);
      expect(s.startAgentChat('   '), '');
      expect(s.agentJobs(), isEmpty);
    });

    test('is a queued job with no task, a title, and the message as its '
        'first line', () async {
      final s = await open(null);
      final id = s.startAgentChat('  Find a hotel in Rome for May  ');
      final j = s.agentJob(id)!;
      expect(j.taskId, isNull);
      expect(j.status, AgentStatus.queued);
      expect(j.title, 'Find a hotel in Rome for May');
      expect(s.agentJobs().map((j) => j.id), [id]);
      final e = s.agentEvents(id).single;
      expect(e.kind, AgentEventKind.ask);
      expect(e.seq, 1);
      expect(e.body, 'Find a hotel in Rome for May');
    });

    test('a long first message gives a short title', () async {
      final s = await open(null);
      final id = s.startAgentChat('word ' * 40);
      expect(s.agentJob(id)!.title.length, lessThanOrEqualTo(61));
    });

    test('runs: the steps show while it works, then the answer; a chat '
        'with no document makes no note', () async {
      final runner = FakeAgentRunner();
      final s = await open(runner);
      final id = s.startAgentChat('Find a hotel');
      await pumpEventQueue();
      final process = runner.processes.single;
      process.say(toolLine('WebSearch', {'query': 'hotels Rome'}));
      process.say('not json');
      expect(kinds(s, id), [AgentEventKind.ask, AgentEventKind.step]);
      final step = s.agentEvents(id).last;
      expect(step.label, AgentStep.search);
      expect(step.body, 'hotels Rome');
      expect(s.agentJob(id)!.status, AgentStatus.running);

      final notesBefore = s.repos.notes.all().length;
      process.finish(answer({'summary': 'Hotel Roma, 90 € a night.'}));
      await s.agentWork;
      final j = s.agentJob(id)!;
      expect(j.status, AgentStatus.done);
      expect(j.resultNoteId, isNull);
      expect(s.repos.notes.all(), hasLength(notesBefore));
      final result = s.agentEvents(id).last;
      expect(result.kind, AgentEventKind.result);
      expect(s.agentEventResult(result)!.summary, 'Hotel Roma, 90 € a night.');
      expect(s.agentEventDocument(result), isNull);
      expect(s.agentEventNote(result), isNull);
      final call = runner.calls.single;
      expect(call.stdin, endsWith('The person now says: Find a hotel'));
      expect(call.stdin, contains('You cannot see the plan of the person.'));
      expect(call.files, isEmpty);
    });

    test('a document becomes a note of its own', () async {
      final runner = FakeAgentRunner()
        ..output = answer({
          'summary': 'Here is the list.',
          'document': {'title': 'Packing list', 'markdown': '- socks'},
        });
      final s = await open(runner);
      final id = s.startAgentChat('Make a packing list');
      await s.agentWork;
      final j = s.agentJob(id)!;
      final result = s.agentEvents(id).last;
      final docId = s.agentEventDocument(result)!;
      expect(j.resultNoteId, docId);
      final doc = s.note(docId)!;
      expect(doc.title, contains('Packing list'));
      expect(doc.body, contains('socks'));
    });

    test(
      'the lines of a run that ends at once come before the answer',
      () async {
        final runner = FakeAgentRunner()
          ..lines = [
            toolLine('WebFetch', {'url': 'https://example.com'}),
          ]
          ..output = answer({'summary': 'ok'});
        final s = await open(runner);
        final id = s.startAgentChat('Look');
        await s.agentWork;
        expect(kinds(s, id), [
          AgentEventKind.ask,
          AgentEventKind.step,
          AgentEventKind.result,
        ]);
        expect(s.agentEvents(id).map((e) => e.seq), [1, 2, 3]);
      },
    );

    test('a run that fails, and a cancel, add a stopped line', () async {
      final runner = FakeAgentRunner()
        ..output = const AgentRunOutput(exitCode: 1, stdout: '', stderr: 'x');
      final s = await open(runner);
      final failed = s.startAgentChat('Look');
      await s.agentWork;
      expect(s.agentJob(failed)!.status, AgentStatus.failed);
      expect(s.agentEvents(failed).last.kind, AgentEventKind.stopped);

      final phone = await open(null);
      final queued = phone.startAgentChat('Wait');
      phone.cancelAgentJob(queued);
      expect(phone.agentJob(queued)!.status, AgentStatus.cancelled);
      expect(phone.agentEvents(queued).last.kind, AgentEventKind.stopped);
      expect(phone.agentEvents(queued).last.body, AgentNote.cancelled);
    });
  });

  group('a new message', () {
    test('only a finished chat takes one; it goes back in the queue, and '
        'the run sees the chat so far', () async {
      final runner = FakeAgentRunner();
      final s = await open(runner);
      final id = s.startAgentChat('Find a hotel');
      await pumpEventQueue();
      expect(s.askAgentAgain(id, 'In Rome'), isFalse);
      runner.processes.single.finish(
        answer({
          'summary': 'Where?',
          'questions': ['Which city?'],
        }),
      );
      await s.agentWork;
      expect(s.askAgentAgain(id, '   '), isFalse);
      expect(s.askAgentAgain('gone', 'Hi'), isFalse);

      runner.output = answer({'summary': 'Hotel Roma.'});
      expect(s.askAgentAgain(id, 'In Rome'), isTrue);
      await s.agentWork;
      expect(s.agentJob(id)!.status, AgentStatus.done);
      expect(kinds(s, id), [
        AgentEventKind.ask,
        AgentEventKind.result,
        AgentEventKind.ask,
        AgentEventKind.result,
      ]);
      final stdin = runner.calls.last.stdin;
      expect(
        stdin,
        contains(
          'The chat so far:\nPerson: Find a hotel\n'
          'You: Where?\nQuestions: Which city?',
        ),
      );
      expect(stdin, endsWith('The person now says: In Rome'));
    });

    test('new links join the old ones, once each', () async {
      final s = await open(null);
      const a = AgentLink(kind: AgentLinkKind.note, id: 'N1', name: 'A');
      const b = AgentLink(kind: AgentLinkKind.task, id: 'T1', name: 'B');
      final id = s.startAgentChat('Hi', links: const [a]);
      s.cancelAgentJob(id);
      expect(s.askAgentAgain(id, 'Again', links: const [a, b]), isTrue);
      expect(s.agentJob(id)!.links, [a, b]);
      expect(s.agentJob(id)!.status, AgentStatus.queued);
    });
  });

  group('what the agent reads', () {
    test('linked notes and tasks are in the prompt as data', () async {
      final runner = FakeAgentRunner()..output = answer({'summary': 'ok'});
      final s = await open(runner);
      s.repos.notes.save(Note(id: 'N1', title: 'Trip', body: 'Rome in May'));
      s.repos.tasks.save(TaskItem(id: 'T1', title: 'Book', notes: 'Cheap'));
      s.startAgentChat(
        'Help',
        links: const [
          AgentLink(kind: AgentLinkKind.note, id: 'N1', name: 'Trip'),
          AgentLink(kind: AgentLinkKind.task, id: 'T1', name: 'Book'),
          AgentLink(kind: AgentLinkKind.note, id: 'gone', name: 'Gone'),
        ],
      );
      await s.agentWork;
      final stdin = runner.calls.single.stdin;
      expect(stdin, contains('<<< Linked note: Trip\nRome in May\n>>>'));
      expect(stdin, contains('<<< Linked task: Book (id T1)'));
      expect(stdin, contains('Cheap'));
      expect(stdin, isNot(contains('Gone')));
    });

    test(
      'with the plan on, the prompt has the plan and its task ids',
      () async {
        final runner = FakeAgentRunner()..output = answer({'summary': 'ok'});
        final s = await open(runner);
        s.repos.tasks.save(TaskItem(id: 'T1', title: 'Essay', estimateMin: 60));
        s.startAgentChat('Fix my day', plan: true);
        await s.agentWork;
        final stdin = runner.calls.single.stdin;
        expect(stdin, contains('The plan:\nNow: 2026-10-22 Thu 09:00'));
        expect(stdin, contains('- T1: Essay; 60 min'));
        expect(stdin, contains('"plan_changes"'));
      },
    );

    test('a file of this computer goes to the run; a file of another '
        'device is named as missing', () async {
      final data = Directory.systemTemp.createTempSync('grove-agent-files-');
      addTearDown(() => data.deleteSync(recursive: true));
      final src = File('${data.path}/My plan.txt')..writeAsStringSync('Plan');
      final runner = FakeAgentRunner()..output = answer({'summary': 'ok'});
      final s = await open(runner, dataDir: data.path);
      expect(s.canLinkAgentFiles, isTrue);
      final link = (await s.linkAgentFile(src.path))!;
      expect(link.kind, AgentLinkKind.file);
      expect(link.name, 'My plan.txt');
      expect(link.device, s.prefs.getString('agent.device'));
      s.startAgentChat(
        'Read it',
        links: [
          link,
          const AgentLink(
            kind: AgentLinkKind.file,
            id: 'X',
            name: 'far.pdf',
            device: 'Other',
          ),
        ],
      );
      await s.agentWork;
      final call = runner.calls.single;
      final file = call.files.single;
      expect(file.name, 'My plan.txt');
      expect(File(file.path).readAsStringSync(), 'Plan');
      final sep = Platform.pathSeparator;
      expect(file.path, startsWith('${data.path}${sep}Agent files$sep'));
      expect(call.args, AgentPolicy.args(email: false, files: true));
      expect(call.stdin, contains('with the Read tool: My plan.txt.'));
      expect(call.stdin, contains('cannot read them: far.pdf'));
    });

    test('a link whose id is not a uuid never reaches a file outside the '
        'agent files folder', () async {
      final data = Directory.systemTemp.createTempSync('grove-agent-files-');
      addTearDown(() => data.deleteSync(recursive: true));
      File('${data.path}/secret.txt').writeAsStringSync('Secret');
      final runner = FakeAgentRunner()..output = answer({'summary': 'ok'});
      final s = await open(runner, dataDir: data.path);
      // The device of this computer.
      final device = (await s.linkAgentFile('${data.path}/secret.txt'))!.device;
      expect(device, isNotNull);
      // A link made on another device (links sync) that claims this one.
      s.startAgentChat(
        'Read it',
        links: [
          AgentLink(
            kind: AgentLinkKind.file,
            id: '..',
            name: 'secret.txt',
            device: device,
          ),
        ],
      );
      await s.agentWork;
      final call = runner.calls.single;
      expect(call.files, isEmpty);
      expect(call.stdin, contains('cannot read them: secret.txt'));
    });

    test('a phone cannot link files', () async {
      final s = await open(null, dataDir: Directory.systemTemp.path);
      expect(s.canLinkAgentFiles, isFalse);
      expect(await s.linkAgentFile('/nope'), isNull);
    });

    test('a file that cannot be copied gives no link and says why', () async {
      final data = Directory.systemTemp.createTempSync('grove-agent-files-');
      addTearDown(() => data.deleteSync(recursive: true));
      final s = await open(FakeAgentRunner(), dataDir: data.path);
      expect(await s.linkAgentFile('${data.path}/missing.txt'), isNull);
      expect(s.errorMessage, startsWith('Could not add the file'));
    });
  });

  group('proposals', () {
    AgentRunOutput proposals() => answer({
      'summary': 'A plan.',
      'plan_changes': [
        {'task_id': 'T1', 'day': '2026-10-22', 'start': '14:00', 'minutes': 45},
      ],
      'new_tasks': [
        {
          'title': 'Outline',
          'parent_task_id': 'T1',
          'minutes': 20,
          'day': '2026-10-23',
        },
      ],
    });

    test('are left out when the plan was not shared', () async {
      final runner = FakeAgentRunner()..output = proposals();
      final s = await open(runner);
      s.repos.tasks.save(TaskItem(id: 'T1', title: 'Essay'));
      final id = s.startAgentChat('Fix my day');
      await s.agentWork;
      final r = s.agentEventResult(s.agentEvents(id).last)!;
      expect(r.planChanges, isEmpty);
      expect(r.newTasks, isEmpty);
    });

    test('Apply puts the task on the planner, once, and undo takes it '
        'back', () async {
      final runner = FakeAgentRunner()..output = proposals();
      final s = await open(runner);
      s.repos.tasks.save(TaskItem(id: 'T1', title: 'Essay'));
      final id = s.startAgentChat('Fix my day', plan: true);
      await s.agentWork;
      final event = s.agentEvents(id).last;
      final day = DayRange(DayKey('2026-10-22'), DayKey('2026-10-22'));
      expect(s.blocks(day), isEmpty);

      expect(s.applyAgentChange(event.id, AgentResult.planKey(0)), isTrue);
      final block = s.blocks(day).single;
      expect(block.taskId, 'T1');
      expect(block.startMinute, 14 * 60);
      expect(block.endMinute, 14 * 60 + 45);
      expect(s.agentApplied(s.agentEvents(id).last), {'p0'});
      expect(s.applyAgentChange(event.id, AgentResult.planKey(0)), isFalse);

      s.undo();
      expect(s.blocks(day), isEmpty);
    });

    test('Apply makes the new subtask, planned on its day; undo takes it '
        'away', () async {
      final runner = FakeAgentRunner()..output = proposals();
      final s = await open(runner);
      s.repos.tasks.save(TaskItem(id: 'T1', title: 'Essay'));
      final id = s.startAgentChat('Split it', plan: true);
      await s.agentWork;
      final event = s.agentEvents(id).last;

      expect(s.applyAgentChange(event.id, AgentResult.taskKey(0)), isTrue);
      final sub = s.subtasks('T1').single;
      expect(sub.title, 'Outline');
      expect(sub.estimateMin, 20);
      expect(sub.planDate, DayKey('2026-10-23'));
      expect(s.agentApplied(s.agentEvents(id).last), {'t0'});

      s.undo();
      expect(s.subtasks('T1'), isEmpty);
    });

    test('a wrong key, or a task that is gone, applies nothing', () async {
      final runner = FakeAgentRunner()..output = proposals();
      final s = await open(runner);
      s.repos.tasks.save(TaskItem(id: 'T1', title: 'Essay'));
      final id = s.startAgentChat('Fix my day', plan: true);
      await s.agentWork;
      final event = s.agentEvents(id).last;
      expect(s.applyAgentChange(event.id, 'p9'), isFalse);
      expect(s.applyAgentChange(event.id, 'x'), isFalse);
      expect(s.applyAgentChange('nope', 'p0'), isFalse);
      expect(s.applyAgentChange(s.agentEvents(id).first.id, 'p0'), isFalse);
      s.repos.tasks.delete('T1');
      expect(s.applyAgentChange(event.id, 'p0'), isFalse);
    });
  });
}
