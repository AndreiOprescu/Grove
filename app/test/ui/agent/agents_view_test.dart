// The Agents screen (ADR 0005): the list of chats, a new chat with "+" and
// the switches, the live steps, Stop, the results with Apply, and a reply.
// No test runs `claude`: the jobs and their lines are put in the database.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/agent/agent_dialog.dart';
import 'package:grove/ui/agent/agents_view.dart';
import 'package:grove/ui/store_app.dart';

import '../planner/planner_support.dart' hide rightClick;

Finder keyed(String key) => find.byKey(ValueKey(key));

/// A store on a device that does not run the agent, with the agent on and
/// the Agents screen open. "Now" is Wednesday at 10:00.
AppStore agentsStore({FakeAgentRunner? runner, String? dataDir}) {
  final store = makeStore(
    prefs: MemoryPrefs({'appearance.motion': false, 'agent.enabled': true}),
    clock: WallTime(day: wednesday, minute: 10 * 60),
    agentRunner: runner,
    dataDir: dataDir,
  );
  store.newTimer = ManualTimers().start;
  store.screen = Screen.agents;
  return store;
}

Future<void> pumpAgents(
  WidgetTester tester,
  AppStore store, {
  Size size = const Size(1100, 900),
  AgentFilePicker? pickFile,
  AgentPathOpener? openFile,
  AgentPathOpener? showFolder,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    StoreApp(
      key: UniqueKey(),
      store: store,
      pickAgentFile: pickFile,
      openAgentFile: openFile,
      showAgentFolder: showFolder,
    ),
  );
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(keyed(key));
  await tester.pumpAndSettle();
  await tester.tap(keyed(key));
  await tester.pumpAndSettle();
}

/// A chat with its first message.
AgentJob addChat(
  AppStore store, {
  String id = 'J1',
  String title = 'Find a hotel',
  AgentStatus status = AgentStatus.queued,
  AgentResult? result,
}) {
  final job = AgentJob(
    id: id,
    taskId: null,
    title: title,
    instructions: title,
    status: status,
    runnerDevice: status == AgentStatus.queued ? null : 'mac',
    resultJson: result == null ? null : jsonEncode(result.toJson()),
  );
  store.repos.agentJobs.insert(job);
  store.repos.agentEvents.insert(
    AgentEvent(jobId: id, seq: 1, kind: AgentEventKind.ask, body: title),
  );
  return job;
}

void addLine(
  AppStore store,
  String jobId,
  AgentEventKind kind, {
  String? id,
  String label = '',
  String body = '',
}) => store.repos.agentEvents.insert(
  AgentEvent(
    id: id,
    jobId: jobId,
    seq: store.repos.agentEvents.nextSeq(jobId),
    kind: kind,
    label: label,
    body: body,
  ),
);

void main() {
  test('a chat is in the right group', () {
    AgentJob job(AgentStatus s) => AgentJob(taskId: null, status: s);
    const plain = AgentResult(summary: 'Done.');
    const asks = AgentResult(summary: 'Done.', questions: ['Which day?']);
    expect(
      AgentSection.of(job(AgentStatus.queued), null),
      AgentSection.running,
    );
    expect(
      AgentSection.of(job(AgentStatus.cancelRequested), null),
      AgentSection.running,
    );
    expect(AgentSection.of(job(AgentStatus.done), plain), AgentSection.done);
    expect(AgentSection.of(job(AgentStatus.done), asks), AgentSection.needsYou);
    expect(
      AgentSection.of(job(AgentStatus.failed), null),
      AgentSection.stopped,
    );
    expect(
      AgentSection.of(job(AgentStatus.cancelled), null),
      AgentSection.stopped,
    );
  });

  test('the screen is in the switch only while the agent is on', () {
    final store = agentsStore();
    expect(store.screens, contains(Screen.agents));
    store.setAgentEnabled(false);
    expect(store.screens, isNot(contains(Screen.agents)));
    expect(store.screen, Screen.today);
    store.screen = Screen.agents;
    expect(store.screen, Screen.today);
  });

  testWidgets('a new chat: the greeting, the box, the helpers and the '
      'safety line', (tester) async {
    final store = agentsStore();
    await pumpAgents(tester, store);
    expect(find.textContaining('Good morning'), findsOneWidget);
    expect(keyed('agents-text'), findsOneWidget);
    expect(find.text('Fix my day'), findsOneWidget);
    expect(find.text(AgentDialog.safety), findsOneWidget);
    // Nothing to send in an empty box.
    await tapKey(tester, 'agents-send');
    expect(store.agentJobs(), isEmpty);
  });

  testWidgets('Send starts a chat and opens it', (tester) async {
    final store = agentsStore();
    await pumpAgents(tester, store);
    await tester.enterText(keyed('agents-text'), 'Find a hotel in Rome');
    await tapKey(tester, 'agents-services');
    await tapKey(tester, 'agents-send');
    final job = store.agentJobs().single;
    expect(job.instructions, 'Find a hotel in Rome');
    expect(job.emailAccess, isTrue);
    expect(job.planAccess, isFalse);
    expect(store.shownAgentJob, job.id);
    expect(keyed('agents-job-${job.id}'), findsOneWidget);
    expect(find.text('Find a hotel in Rome'), findsWidgets);
    expect(find.text('Waiting'), findsOneWidget);
    expect(
      find.text(AgentsView.rules(plan: false, services: true)),
      findsOneWidget,
    );
    expect(find.text(AgentDialog.turnOnRunner), findsOneWidget);
    // The reply box shows only when the job is finished.
    expect(keyed('agents-reply-text'), findsNothing);
  });

  testWidgets('a helper fills the box and turns the plan on', (tester) async {
    final store = agentsStore();
    await pumpAgents(tester, store);
    await tapKey(tester, 'agents-helper-0');
    await tapKey(tester, 'agents-send');
    final job = store.agentJobs().single;
    expect(job.instructions, AgentsView.helpers.first.message);
    expect(job.planAccess, isTrue);
  });

  testWidgets('"+" links a note and a task; a phone has no file', (
    tester,
  ) async {
    final store = agentsStore();
    store.repos.notes.save(Note(id: 'N1', title: 'Trip ideas'));
    store.repos.tasks.save(TaskItem(id: 'T1', title: 'Book flights'));
    await pumpAgents(tester, store, pickFile: () async => '/no/file.pdf');
    await tapKey(tester, 'agents-plus');
    expect(find.text('Add a file…'), findsNothing);
    await tester.tap(find.text('Link a note…'));
    await tester.pumpAndSettle();
    await tester.tap(keyed('agent-pick-N1'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'agents-plus');
    await tester.tap(find.text('Link a task…'));
    await tester.pumpAndSettle();
    await tester.enterText(keyed('agent-pick-search'), 'book');
    await tester.pumpAndSettle();
    await tester.tap(keyed('agent-pick-T1'));
    await tester.pumpAndSettle();
    expect(keyed('agents-link-N1'), findsOneWidget);
    expect(keyed('agents-link-T1'), findsOneWidget);
    await tester.enterText(keyed('agents-text'), 'Plan the trip');
    await tapKey(tester, 'agents-send');
    expect(store.agentJobs().single.links.map((l) => l.id), ['N1', 'T1']);
  });

  testWidgets('a computer links a file: a copy, never the file', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('grove-agents-ui-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/plan.pdf')..writeAsStringSync('PDF');
    final store = agentsStore(
      runner: FakeAgentRunner(exe: null),
      dataDir: dir.path,
    );
    await pumpAgents(tester, store, pickFile: () async => file.path);
    await tapKey(tester, 'agents-plus');
    await tester.runAsync(() async {
      await tester.tap(find.text('Add a file…'));
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(find.text('plan.pdf'), findsOneWidget);
    await tester.enterText(keyed('agents-text'), 'Read it');
    await tapKey(tester, 'agents-send');
    final link = store.agentJobs().single.links.single;
    expect(link.kind, AgentLinkKind.file);
    expect(store.agentFileHere(link), isTrue);
    // The chat shows the file, here on its own computer.
    expect(find.text('plan.pdf'), findsOneWidget);
  });

  group('the files the agent saved', () {
    const id = '0b9f6a52-1c2d-4e3f-8a9b-0c1d2e3f4a5b';
    const result = AgentResult(summary: 'Here is your page.');

    void addDone(AppStore store, {List<String> files = const []}) {
      addChat(store, id: id, status: AgentStatus.done, result: result);
      addLine(
        store,
        id,
        AgentEventKind.result,
        body: jsonEncode({
          ...result.toJson(),
          if (files.isNotEmpty) 'grove_files': files,
        }),
      );
      store.showAgentJob(id);
    }

    testWidgets('on the computer that ran it: a text file opens, any other '
        'file shows its folder, the linked files are not listed', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('grove-agents-ui-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = agentsStore(
        runner: FakeAgentRunner(exe: null),
        dataDir: dir.path,
      );
      addDone(store);
      final folder = store.agentFolder(id)!;
      final sep = Platform.pathSeparator;
      File('$folder${sep}notes.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('# Notes');
      File('$folder${sep}site${sep}index.html')
        ..createSync(recursive: true)
        ..writeAsStringSync('<p>Hi</p>');
      File('$folder${sep}inputs${sep}x.pdf')
        ..createSync(recursive: true)
        ..writeAsStringSync('PDF');
      final opened = <String>[], shown = <String>[];
      await pumpAgents(
        tester,
        store,
        openFile: (path) async {
          opened.add(path);
          return true;
        },
        showFolder: (path) async {
          shown.add(path);
          return true;
        },
      );
      expect(find.text('Here is your page.'), findsOneWidget);
      expect(keyed('agents-file-notes.md'), findsOneWidget);
      expect(keyed('agents-file-site/index.html'), findsOneWidget);
      expect(keyed('agents-file-inputs/x.pdf'), findsNothing);

      await tapKey(tester, 'agents-file-notes.md');
      expect(opened, ['$folder${sep}notes.md']);
      expect(shown, isEmpty);

      // A page is never opened: it could run. The folder of the chat shows
      // instead; never a folder the agent named (a "x.app" would start).
      await tapKey(tester, 'agents-file-site/index.html');
      expect(opened, hasLength(1));
      expect(shown, [folder]);

      await tapKey(tester, 'agents-show-folder');
      expect(shown.last, folder);
    });

    testWidgets('a system that cannot open the file says so', (tester) async {
      final dir = Directory.systemTemp.createTempSync('grove-agents-ui-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = agentsStore(
        runner: FakeAgentRunner(exe: null),
        dataDir: dir.path,
      );
      addDone(store);
      File('${store.agentFolder(id)!}${Platform.pathSeparator}a.txt')
        ..createSync(recursive: true)
        ..writeAsStringSync('A');
      await pumpAgents(
        tester,
        store,
        openFile: (_) async => false,
        showFolder: (_) async => false,
      );
      await tapKey(tester, 'agents-file-a.txt');
      expect(find.text(AgentsView.couldNotOpenFile), findsOneWidget);
    });

    testWidgets('no folder made: no Files part', (tester) async {
      final dir = Directory.systemTemp.createTempSync('grove-agents-ui-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = agentsStore(
        runner: FakeAgentRunner(exe: null),
        dataDir: dir.path,
      );
      addDone(store);
      await pumpAgents(tester, store, showFolder: (_) async => true);
      expect(keyed('agents-files'), findsNothing);
      expect(keyed('agents-show-folder'), findsNothing);
    });

    testWidgets('on another computer: no folder here, so the names from the '
        'result, as plain text (review, 2026-10-27)', (tester) async {
      final dir = Directory.systemTemp.createTempSync('grove-agents-ui-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = agentsStore(
        runner: FakeAgentRunner(exe: null),
        dataDir: dir.path,
      );
      // The chat ran on "mac"; this computer is another one.
      store.prefs.set('agent.device', 'pc');
      addDone(store, files: ['notes.md', 'site/index.html']);
      await pumpAgents(
        tester,
        store,
        openFile: (_) async => true,
        showFolder: (_) async => true,
      );
      expect(
        find.text(AgentsView.filesElsewhere(['notes.md', 'site/index.html'])),
        findsOneWidget,
      );
      expect(keyed('agents-file-notes.md'), findsNothing);
      expect(keyed('agents-show-folder'), findsNothing);
    });

    testWidgets('on the computer that ran it, with its files deleted: no '
        'Files part, it does not say they are elsewhere', (tester) async {
      final dir = Directory.systemTemp.createTempSync('grove-agents-ui-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = agentsStore(
        runner: FakeAgentRunner(exe: null),
        dataDir: dir.path,
      );
      store.prefs.set('agent.device', 'mac');
      addDone(store, files: ['notes.md']);
      await pumpAgents(tester, store, showFolder: (_) async => true);
      expect(keyed('agents-files'), findsNothing);
    });

    testWidgets('on a phone: the names, from the result, as plain text', (
      tester,
    ) async {
      final store = agentsStore();
      addDone(store, files: ['notes.md', 'site/index.html']);
      await pumpAgents(
        tester,
        store,
        openFile: (_) async => true,
        showFolder: (_) async => true,
      );
      expect(keyed('agents-files'), findsOneWidget);
      expect(
        find.text(AgentsView.filesElsewhere(['notes.md', 'site/index.html'])),
        findsOneWidget,
      );
      expect(keyed('agents-file-notes.md'), findsNothing);
      expect(keyed('agents-show-folder'), findsNothing);
    });
  });

  testWidgets('the steps show as they come; a click shows all', (tester) async {
    final store = agentsStore();
    addChat(store, status: AgentStatus.running);
    for (var i = 1; i <= 5; i++) {
      addLine(
        store,
        'J1',
        AgentEventKind.step,
        id: 'S$i',
        label: i == 2 ? AgentStep.web : AgentStep.search,
        body: 'Step $i',
      );
    }
    store.showAgentJob('J1');
    await pumpAgents(tester, store);
    expect(find.text('Working'), findsOneWidget);
    expect(find.text('Step 5'), findsOneWidget);
    expect(find.text('Step 2'), findsNothing);
    await tapKey(tester, 'agents-steps-toggle-S1');
    expect(find.text('Step 1'), findsOneWidget);
    expect(find.text('Step 2'), findsOneWidget);
    // A new step shows at once.
    addLine(store, 'J1', AgentEventKind.step, body: 'Step 6');
    store.showAgentJob('J1');
    await tester.pumpAndSettle();
    expect(find.text('Step 6'), findsOneWidget);
  });

  testWidgets('Stop cancels a queued chat; then the reply box shows', (
    tester,
  ) async {
    final store = agentsStore();
    addChat(store);
    store.showAgentJob('J1');
    await pumpAgents(tester, store);
    await tapKey(tester, 'agents-stop');
    expect(store.agentJob('J1')!.status, AgentStatus.cancelled);
    expect(find.text(AgentNote.cancelled), findsOneWidget);
    expect(find.text('Stopped'), findsWidgets);
    expect(keyed('agents-stop'), findsNothing);
    await tester.enterText(keyed('agents-reply-text'), 'Try again, please');
    await tapKey(tester, 'agents-reply-send');
    expect(store.agentJob('J1')!.status, AgentStatus.queued);
    expect(find.text('Try again, please'), findsOneWidget);
  });

  testWidgets('a result: drafts, questions, and proposals with Apply', (
    tester,
  ) async {
    final store = agentsStore();
    store.repos.tasks.save(TaskItem(id: 'T1', title: 'Call the bank'));
    final result = AgentResult(
      summary: 'Here is a better day.',
      emailDraft: const EmailDraft(
        to: 'sam@example.com',
        subject: 'Hi',
        body: 'Hello',
      ),
      questions: const ['Which hotel?'],
      sources: const ['https://example.com'],
      planChanges: [
        PlanChange(taskId: 'T1', day: wednesday, start: 14 * 60, minutes: 30),
      ],
      newTasks: const [NewTask(title: 'Pack the bags', minutes: 20)],
    );
    addChat(store, status: AgentStatus.done, result: result);
    addLine(
      store,
      'J1',
      AgentEventKind.result,
      id: 'R1',
      body: jsonEncode(result.toJson()),
    );
    store.showAgentJob('J1');
    await pumpAgents(tester, store);
    // A done chat with questions needs the person.
    expect(find.text('Needs you'), findsOneWidget);
    expect(find.text('Here is a better day.'), findsOneWidget);
    expect(find.text('To: sam@example.com'), findsOneWidget);
    expect(find.text('• Which hotel?'), findsOneWidget);
    expect(find.textContaining('Call the bank'), findsOneWidget);
    expect(find.textContaining('14:00'), findsOneWidget);

    await tapKey(tester, 'agents-apply-t0');
    expect(
      store.allOpenTasks().noDay.map((t) => t.title),
      contains('Pack the bags'),
    );
    expect(keyed('agents-applied-t0'), findsOneWidget);
    expect(keyed('agents-apply-t0'), findsNothing);

    await tapKey(tester, 'agents-apply-p0');
    expect(store.task('T1')!.planDate, wednesday);
    expect(keyed('agents-applied-p0'), findsOneWidget);
  });

  testWidgets('a proposal for a task that is gone says so', (tester) async {
    final store = agentsStore();
    final result = AgentResult(
      summary: 'Move it.',
      planChanges: [
        PlanChange(taskId: 'gone', day: wednesday, start: 600, minutes: 30),
      ],
    );
    addChat(store, status: AgentStatus.done, result: result);
    addLine(
      store,
      'J1',
      AgentEventKind.result,
      body: jsonEncode(result.toJson()),
    );
    store.showAgentJob('J1');
    await pumpAgents(tester, store);
    await tapKey(tester, 'agents-apply-p0');
    expect(find.text(AgentsView.notApplied), findsOneWidget);
  });

  testWidgets('the list: groups, search, and New chat', (tester) async {
    final store = agentsStore();
    addChat(store, id: 'A', title: 'Hotel in Rome');
    addChat(store, id: 'B', title: 'Weekly review', status: AgentStatus.failed);
    await pumpAgents(tester, store);
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Stopped'), findsOneWidget);
    await tester.enterText(keyed('agents-search'), 'rome');
    await tester.pumpAndSettle();
    expect(keyed('agents-job-A'), findsOneWidget);
    expect(keyed('agents-job-B'), findsNothing);
    await tapKey(tester, 'agents-job-A');
    expect(store.shownAgentJob, 'A');
    await tapKey(tester, 'agents-new');
    expect(store.shownAgentJob, isNull);
    expect(find.textContaining('Good morning'), findsOneWidget);
  });

  testWidgets('a phone: the list under the box, and Back from a chat', (
    tester,
  ) async {
    final store = agentsStore();
    addChat(store);
    await pumpAgents(tester, store, size: const Size(390, 844));
    expect(keyed('agents-text'), findsOneWidget);
    await tapKey(tester, 'agents-job-J1');
    expect(keyed('agents-text'), findsNothing);
    expect(find.text('Waiting'), findsOneWidget);
    await tapKey(tester, 'agents-back');
    expect(store.shownAgentJob, isNull);
    expect(keyed('agents-text'), findsOneWidget);
  });

  testWidgets('"Open in Agents" in the task window opens the chat', (
    tester,
  ) async {
    final store = agentsStore();
    store.repos.tasks.save(TaskItem(id: 'sam', title: 'Email Sam'));
    final id = store.delegateToAgent('sam');
    store.screen = Screen.planner;
    await pumpAgents(tester, store);
    final context = tester.element(find.byType(Scaffold).first);
    unawaited(showAgentDialog(context, store, 'sam'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'agent-open-chat');
    expect(store.screen, Screen.agents);
    expect(store.shownAgentJob, id);
    expect(find.byType(AgentDialog), findsNothing);
  });
}
