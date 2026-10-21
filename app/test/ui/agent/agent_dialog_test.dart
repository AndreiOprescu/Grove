// The window of "Ask the agent…" (ADR 0004): the form, the states of a job,
// and the result with its drafts. The tests give a fake opener, so no test
// opens Mail or Messages.
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/agent/agent_dialog.dart';
import 'package:grove/ui/store_app.dart';

import '../planner/planner_support.dart' hide rightClick;
import '../tasks/tasks_support.dart' show addTask, rowFinder;

final dialog = find.byType(AgentDialog);

Finder keyed(String key) => find.byKey(ValueKey(key));

/// A store on a phone (no runner) with "Use the agent" on, and the Tasks
/// panel open. "Now" is Wednesday at 10:00.
AppStore agentStore({
  FakeAgentRunner? runner,
  bool runnerOn = false,
  bool emailOn = false,
  bool enabled = true,
}) {
  final store = makeStore(
    prefs: MemoryPrefs({
      'appearance.motion': false,
      'agent.enabled': enabled,
      'agent.runner': runnerOn,
      'agent.email': emailOn,
    }),
    clock: WallTime(day: wednesday, minute: 10 * 60),
    agentRunner: runner,
  );
  // The one-minute check and the poll of a running job never fire.
  store.newTimer = ManualTimers().start;
  store
    ..selectedDay = wednesday
    ..screen = Screen.planner
    ..leftPane = LeftPane.tasks;
  return store;
}

/// The task of each test, in the Inbox, so the Tasks panel lists it.
void addSam(AppStore store) =>
    addTask(store, 'Email Sam', id: 'sam', bucket: TaskBucket.inbox);

/// The opener of Mail and Messages. It writes down each address.
class FakeOpener {
  final opened = <Uri>[];
  bool works = true;

  Future<bool> call(Uri url) async {
    opened.add(url);
    return works;
  }
}

Future<void> pumpAgentApp(
  WidgetTester tester,
  AppStore store, {
  DraftOpener? openDraft,
}) async {
  tester.view.physicalSize = const Size(1100, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    StoreApp(key: UniqueKey(), store: store, openDraft: openDraft),
  );
  // Take the tree down at the end, before the store is closed.
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pumpAndSettle();
}

/// A right click on the task, then "Ask the agent…".
Future<void> openAgent(WidgetTester tester) async {
  await tester.tap(rowFinder('sam'), buttons: kSecondaryMouseButton);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Ask the agent…'));
  await tester.pumpAndSettle();
  expect(dialog, findsOneWidget);
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(keyed(key));
  await tester.pumpAndSettle();
  await tester.tap(keyed(key));
  await tester.pumpAndSettle();
}

Finder inDialog(Finder what) => find.descendant(of: dialog, matching: what);

const draft = EmailDraft(
  to: 'sam@example.com',
  subject: 'The plan',
  body: 'Hi Sam,\nhere is the plan.',
);
const text = TextDraft(to: '+44 7700 900123', body: 'On my way.');

const fullResult = AgentResult(
  summary: 'I wrote to Sam about the plan.',
  steps: ['Read the task', 'Wrote the email'],
  emailDraft: draft,
  textDraft: text,
  questions: ['Which day suits Sam?'],
  sources: ['https://example.com/plan'],
);

/// A done job of the task, with its result note.
AgentJob addDone(AppStore store, {AgentResult result = fullResult}) {
  // Saved straight away: newNote would open the Notes screen.
  final note = Note(title: 'Agent: Email Sam', body: 'Result');
  store.repos.notes.save(note);
  final job = AgentJob(
    taskId: 'sam',
    status: AgentStatus.done,
    resultJson: jsonEncode(result.toJson()),
    resultNoteId: note.id,
  );
  store.repos.agentJobs.insert(job);
  return job;
}

AgentJob addJob(AppStore store, AgentStatus status, {String? error}) {
  final job = AgentJob(
    taskId: 'sam',
    status: status,
    runnerDevice: status == AgentStatus.queued ? null : 'mac',
    error: error,
  );
  store.repos.agentJobs.insert(job);
  return job;
}

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

/// Writes down what goes to the clipboard.
List<String> watchClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

void main() {
  group('the form', () {
    testWidgets('shows the task, the box, the email check box and the safety '
        'line', (tester) async {
      final store = agentStore();
      addSam(store);
      await pumpAgentApp(tester, store);
      await openAgent(tester);

      expect(inDialog(find.text('Email Sam')), findsOneWidget);
      expect(inDialog(keyed('agent-instructions')), findsOneWidget);
      expect(
        inDialog(find.text('Allow reading my email for this task')),
        findsOneWidget,
      );
      expect(inDialog(find.text(AgentDialog.safety)), findsOneWidget);
      // Email is off on this device: the window says who decides.
      expect(inDialog(find.text(AgentDialog.emailOffHere)), findsOneWidget);
    });

    testWidgets('no email hint when this device lets the agent read email', (
      tester,
    ) async {
      final store = agentStore(emailOn: true);
      addSam(store);
      await pumpAgentApp(tester, store);
      await openAgent(tester);
      expect(find.text(AgentDialog.emailOffHere), findsNothing);
    });

    testWidgets('Start gives the task to the agent with the words and the '
        'email choice', (tester) async {
      final store = agentStore();
      addSam(store);
      await pumpAgentApp(tester, store);
      await openAgent(tester);

      await tester.enterText(
        find.descendant(
          of: keyed('agent-instructions'),
          matching: find.byType(EditableText),
        ),
        'Use his work address.',
      );
      await tapKey(tester, 'agent-email');
      await tapKey(tester, 'agent-start');

      final job = store.agentJobFor('sam')!;
      expect(job.instructions, 'Use his work address.');
      expect(job.emailAccess, isTrue);
      expect(job.status, AgentStatus.queued);
      // The window now shows the job.
      expect(inDialog(find.text(AgentDialog.waiting)), findsOneWidget);
    });

    testWidgets('email stays off unless the box is ticked', (tester) async {
      final store = agentStore(emailOn: true);
      addSam(store);
      await pumpAgentApp(tester, store);
      await openAgent(tester);
      await tapKey(tester, 'agent-start');
      expect(store.agentJobFor('sam')!.emailAccess, isFalse);
    });

    testWidgets('Cancel closes the window and makes no job', (tester) async {
      final store = agentStore();
      addSam(store);
      await pumpAgentApp(tester, store);
      await openAgent(tester);
      await tapKey(tester, 'agent-close');
      expect(dialog, findsNothing);
      expect(store.agentJobFor('sam'), isNull);
    });
  });

  group('the states of a job', () {
    testWidgets('queued: waiting, with the runner hint, and Cancel job', (
      tester,
    ) async {
      final store = agentStore();
      addSam(store);
      final job = addJob(store, AgentStatus.queued);
      await pumpAgentApp(tester, store);
      await openAgent(tester);

      expect(inDialog(find.text(AgentDialog.waiting)), findsOneWidget);
      expect(inDialog(find.text(AgentDialog.turnOnRunner)), findsOneWidget);

      await tapKey(tester, 'agent-cancel-job');
      expect(store.repos.agentJobs.get(job.id)!.status, AgentStatus.cancelled);
      expect(inDialog(find.text(AgentNote.cancelled)), findsOneWidget);
      expect(inDialog(keyed('agent-try-again')), findsOneWidget);
    });

    testWidgets('queued on the computer that runs jobs: no runner hint', (
      tester,
    ) async {
      // The switch is on, but Claude Code is not found: the job waits.
      final store = agentStore(
        runner: FakeAgentRunner(exe: null),
        runnerOn: true,
      );
      addSam(store);
      addJob(store, AgentStatus.queued);
      await pumpAgentApp(tester, store);
      await openAgent(tester);
      expect(inDialog(find.text(AgentDialog.waiting)), findsOneWidget);
      expect(find.text(AgentDialog.turnOnRunner), findsNothing);
    });

    testWidgets('running: working, and Cancel job asks to stop', (
      tester,
    ) async {
      final store = agentStore();
      addSam(store);
      final job = addJob(store, AgentStatus.running);
      await pumpAgentApp(tester, store);
      await openAgent(tester);

      expect(inDialog(find.text(AgentDialog.working)), findsOneWidget);
      await tapKey(tester, 'agent-cancel-job');
      expect(
        store.repos.agentJobs.get(job.id)!.status,
        AgentStatus.cancelRequested,
      );
      expect(inDialog(find.text(AgentDialog.stopping)), findsOneWidget);
      expect(keyed('agent-cancel-job'), findsNothing);
    });

    testWidgets('failed: the error in plain words, and Try again', (
      tester,
    ) async {
      final store = agentStore();
      addSam(store);
      addJob(store, AgentStatus.failed, error: AgentPolicy.gmailNotReady);
      await pumpAgentApp(tester, store);
      await openAgent(tester);

      expect(inDialog(find.text(AgentPolicy.gmailNotReady)), findsOneWidget);
      await tapKey(tester, 'agent-try-again');
      expect(inDialog(keyed('agent-instructions')), findsOneWidget);
      await tapKey(tester, 'agent-start');
      expect(store.agentJobFor('sam')!.status, AgentStatus.queued);
    });

    testWidgets('a run on this computer ends with the result in the window', (
      tester,
    ) async {
      final runner = FakeAgentRunner(
        output: answer({
          'summary': 'Sent nothing. Drafted it.',
          'steps': ['Read the task'],
        }),
      );
      final store = agentStore(runner: runner, runnerOn: true);
      addSam(store);
      await pumpAgentApp(tester, store);
      await openAgent(tester);
      await tapKey(tester, 'agent-start');
      await tester.pumpAndSettle();

      expect(runner.calls, hasLength(1));
      expect(store.agentJobFor('sam')!.status, AgentStatus.done);
      expect(inDialog(find.text('Sent nothing. Drafted it.')), findsOneWidget);
    });
  });

  group('the result', () {
    testWidgets('the summary, the steps, the drafts, the questions and the '
        'sources', (tester) async {
      final store = agentStore();
      addSam(store);
      addDone(store);
      await pumpAgentApp(tester, store, openDraft: FakeOpener().call);
      await openAgent(tester);

      expect(inDialog(find.text(fullResult.summary)), findsOneWidget);
      // The steps are folded at first.
      expect(find.text('Wrote the email'), findsNothing);
      await tapKey(tester, 'agent-steps');
      expect(inDialog(find.textContaining('Wrote the email')), findsOneWidget);

      final to = tester.widget<Text>(keyed('agent-email-to'));
      expect(to.data, 'To: sam@example.com');
      expect(to.style!.fontWeight, FontWeight.w700);
      expect(to.style!.fontSize, greaterThanOrEqualTo(16));
      expect(inDialog(find.text('The plan')), findsOneWidget);
      expect(inDialog(find.text(draft.body)), findsOneWidget);

      final textTo = tester.widget<Text>(keyed('agent-text-to'));
      expect(textTo.data, 'To: +44 7700 900123');
      expect(textTo.style!.fontWeight, FontWeight.w700);
      expect(inDialog(find.text('On my way.')), findsOneWidget);

      expect(
        inDialog(find.textContaining('Which day suits Sam?')),
        findsOneWidget,
      );
      expect(
        inDialog(find.textContaining('https://example.com/plan')),
        findsOneWidget,
      );
    });

    testWidgets('Open in Mail and Open in Messages open the drafts', (
      tester,
    ) async {
      final store = agentStore();
      addSam(store);
      addDone(store);
      final opener = FakeOpener();
      await pumpAgentApp(tester, store, openDraft: opener.call);
      await openAgent(tester);

      await tapKey(tester, 'agent-open-mail');
      await tapKey(tester, 'agent-open-messages');
      expect(opener.opened, [
        AgentPolicy.mailtoUri(draft),
        AgentPolicy.smsUri(text),
      ]);
      expect(opener.opened.first.scheme, 'mailto');
      expect(opener.opened.last.scheme, 'sms');
      // Nothing is sent: the window stays, with the drafts.
      expect(dialog, findsOneWidget);
    });

    testWidgets('a system that cannot open Mail says so', (tester) async {
      final store = agentStore();
      addSam(store);
      addDone(store);
      final opener = FakeOpener()..works = false;
      await pumpAgentApp(tester, store, openDraft: opener.call);
      await openAgent(tester);

      await tapKey(tester, 'agent-open-mail');
      expect(
        inDialog(find.text(AgentDialog.couldNotOpen('Mail'))),
        findsOneWidget,
      );
    });

    testWidgets('no opener: no Open buttons, Copy still works', (tester) async {
      final store = agentStore();
      addSam(store);
      addDone(store);
      final copied = watchClipboard(tester);
      await pumpAgentApp(tester, store);
      await openAgent(tester);

      expect(keyed('agent-open-mail'), findsNothing);
      expect(keyed('agent-open-messages'), findsNothing);
      await tapKey(tester, 'agent-copy-email');
      await tapKey(tester, 'agent-copy-text');
      expect(copied, [draft.body, text.body]);
      expect(inDialog(find.text(AgentDialog.copied)), findsOneWidget);
    });

    testWidgets('Open note shows the result note and closes the window', (
      tester,
    ) async {
      final store = agentStore();
      addSam(store);
      final job = addDone(store);
      await pumpAgentApp(tester, store);
      await openAgent(tester);

      await tapKey(tester, 'agent-open-note');
      expect(dialog, findsNothing);
      expect(store.screen, Screen.notes);
      expect(store.selectedNoteId, job.resultNoteId);
    });

    testWidgets('Ask again shows the form', (tester) async {
      final store = agentStore();
      addSam(store);
      addDone(store);
      await pumpAgentApp(tester, store);
      await openAgent(tester);

      await tapKey(tester, 'agent-ask-again');
      expect(inDialog(keyed('agent-instructions')), findsOneWidget);
      await tapKey(tester, 'agent-start');
      expect(store.agentJobFor('sam')!.status, AgentStatus.queued);
    });
  });
}
