// The window of "Ask the agent…" (ADR 0004): a form to give a task to the
// agent, the state of its job, and the result with the drafts. The agent
// reads and drafts only. Grove opens a draft in Mail or Messages, and the
// person presses Send there.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../planner/planner_dialogs.dart';
import '../tasks/task_widgets.dart';
import '../theme/check_box.dart';
import '../theme/grove_theme.dart';
import '../theme/panel.dart';

/// Opens a draft of the agent in Mail (`mailto:`) or Messages (`sms:`).
/// False when the system could not.
typedef DraftOpener = Future<bool> Function(Uri url);

/// True for the two kinds of address a draft opens with: `mailto:` and
/// `sms:`. Grove opens nothing else from the agent.
bool isDraftLink(Uri url) => url.isScheme('mailto') || url.isScheme('sms');

/// The window to pick one file for a chat of the agent. Gives its path, or
/// null when the person closed the window.
typedef AgentFilePicker = Future<String?> Function();

/// Gives the opener of Mail and Messages and the file window to the agent
/// screens. The app gives the real ones (`main.dart`); a test gives fakes,
/// or none.
class AgentTools extends InheritedWidget {
  const AgentTools({
    super.key,
    this.openDraft,
    this.pickFile,
    required super.child,
  });

  /// With null the window hides "Open in Mail" and "Open in Messages".
  final DraftOpener? openDraft;

  /// With null the Agents screen hides "Add a file…".
  final AgentFilePicker? pickFile;

  static AgentTools? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AgentTools>();

  @override
  bool updateShouldNotify(AgentTools oldWidget) =>
      oldWidget.openDraft != openDraft || oldWidget.pickFile != pickFile;
}

/// Shows the agent window of the task `taskId`. The future ends when the
/// window is closed.
Future<void> showAgentDialog(
  BuildContext context,
  AppStore store,
  String taskId,
) {
  final openDraft = AgentTools.maybeOf(context)?.openDraft;
  return showDialog<void>(
    context: context,
    builder: (context) =>
        AgentDialog(store: store, taskId: taskId, openDraft: openDraft),
  );
}

/// The agent window of one task. It follows the newest job of the task as
/// it syncs: a form when there is none, then waiting, working, and the
/// result or the error.
class AgentDialog extends StatefulWidget {
  const AgentDialog({
    super.key,
    required this.store,
    required this.taskId,
    this.openDraft,
  });

  final AppStore store;
  final String taskId;
  final DraftOpener? openDraft;

  static const safety = 'The agent reads and drafts. It never sends.';
  static const emailOffHere =
      'Email is off on this device. The computer that runs the agent decides.';
  static const waiting = 'Waiting for your computer…';
  static const turnOnRunner =
      "Turn on 'This device runs agent tasks' on your Mac or PC.";
  static const working = 'The agent is working…';
  static const stopping = 'Stopping…';
  static const copied = 'Copied.';
  static const unreadable = 'Grove cannot read the result of the agent.';
  static const taskGone = 'The task is gone.';

  static String couldNotOpen(String app) =>
      'Grove could not open $app. You can copy the text.';

  @override
  State<AgentDialog> createState() => _AgentDialogState();
}

class _AgentDialogState extends State<AgentDialog> {
  final _instructions = TextEditingController();
  bool _email = false;

  /// The person pressed "Ask again" or "Try again": the form shows, also
  /// with a finished job.
  bool _asking = false;
  bool _showSteps = false;

  /// A short line after Copy, or after an app that did not open.
  String? _message;

  AppStore get _store => widget.store;

  @override
  void dispose() {
    _instructions.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop();

  void _start() {
    final id = _store.delegateToAgent(
      widget.taskId,
      instructions: _instructions.text,
      email: _email,
    );
    // An error is in `errorMessage`; the app shows it over the window.
    if (id.isEmpty) return;
    setState(() {
      _asking = false;
      _showSteps = false;
      _message = null;
      _instructions.clear();
      _email = false;
    });
  }

  void _askAgain() => setState(() {
    _asking = true;
    _message = null;
  });

  Future<void> _open(Uri url, String app) async {
    final open = widget.openDraft;
    if (open == null || !isDraftLink(url)) return;
    var opened = false;
    try {
      opened = await open(url);
    } on Object {
      opened = false;
    }
    if (!mounted) return;
    setState(() => _message = opened ? null : AgentDialog.couldNotOpen(app));
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) setState(() => _message = AgentDialog.copied);
  }

  void _openNote(String id) {
    _store.openNote(id);
    _close();
  }

  /// The chat of [job] on the Agents screen: the live steps, and a reply.
  DialogButton? _inAgents(AgentJob job) => _store.agentEnabled
      ? DialogButton(
          key: const ValueKey('agent-open-chat'),
          label: 'Open in Agents',
          onTap: () {
            _store.showAgentJob(job.id);
            _close();
          },
        )
      : null;

  @override
  Widget build(BuildContext context) => StoreBuilder(
    store: _store,
    builder: (context) {
      final job = _store.agentJobFor(widget.taskId);
      final title = _store.task(widget.taskId)?.title;
      final form = job == null || _asking;
      return PlannerSheet(
        width: 440,
        spacing: 10,
        children: [
          const ThemedHeading('Ask the agent', 15),
          _taskLine(context, title),
          if (title == null)
            dialogButtons([
              DialogButton(
                key: const ValueKey('agent-close'),
                label: 'Close',
                onTap: _close,
              ),
            ])
          else if (form)
            ..._form(context)
          else
            ..._job(context, job),
        ],
      );
    },
  );

  Widget _taskLine(BuildContext context, String? title) {
    final theme = GroveTheme.of(context);
    return Text(
      title ?? AgentDialog.taskGone,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: theme
          .body(13, weight: FontWeight.w600)
          .copyWith(color: title == null ? theme.muted : theme.ink),
    );
  }

  TextStyle _small(GroveTheme theme) =>
      theme.body(11).copyWith(color: theme.muted);

  // The form

  List<Widget> _form(BuildContext context) {
    final theme = GroveTheme.of(context);
    const label = 'Allow reading my email for this task';
    void flip() => setState(() => _email = !_email);
    return [
      GroveField(
        key: const ValueKey('agent-instructions'),
        controller: _instructions,
        placeholder: 'Anything the agent should know?',
        boxed: true,
        fill: theme.surface,
        minLines: 4,
        maxLines: 8,
        newlines: true,
        autofocus: true,
      ),
      Semantics(
        container: true,
        checked: _email,
        label: label,
        onTap: flip,
        excludeSemantics: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            key: const ValueKey('agent-email'),
            behavior: HitTestBehavior.opaque,
            onTap: flip,
            child: Row(
              spacing: 8,
              children: [
                CheckBox(isOn: _email, size: 15),
                Expanded(
                  child: Text(
                    label,
                    style: theme.body(13).copyWith(color: theme.ink),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      if (!_store.agentEmailOn)
        Text(AgentDialog.emailOffHere, style: _small(theme)),
      Text(AgentDialog.safety, style: _small(theme)),
      dialogButtons([
        DialogButton(
          key: const ValueKey('agent-close'),
          label: 'Cancel',
          onTap: _close,
        ),
        DialogButton(
          key: const ValueKey('agent-start'),
          label: 'Start',
          primary: true,
          onTap: _start,
        ),
      ]),
    ];
  }

  // A job

  List<Widget> _job(BuildContext context, AgentJob job) {
    final theme = GroveTheme.of(context);
    final close = DialogButton(
      key: const ValueKey('agent-close'),
      label: 'Close',
      onTap: _close,
    );
    final cancelJob = DialogButton(
      key: const ValueKey('agent-cancel-job'),
      label: 'Cancel job',
      onTap: () => _store.cancelAgentJob(job.id),
    );
    final again = DialogButton(
      key: const ValueKey('agent-try-again'),
      label: 'Try again',
      primary: true,
      onTap: _askAgain,
    );
    final chat = _inAgents(job);
    return switch (job.status) {
      AgentStatus.queued => [
        _status(context, Icons.hourglass_empty, AgentDialog.waiting),
        if (!_store.agentRunnerOn)
          Text(AgentDialog.turnOnRunner, style: _small(theme)),
        dialogButtons([close, ?chat, cancelJob]),
      ],
      AgentStatus.running => [
        _status(context, null, AgentDialog.working),
        dialogButtons([close, ?chat, cancelJob]),
      ],
      AgentStatus.cancelRequested => [
        _status(context, Icons.stop_circle_outlined, AgentDialog.stopping),
        dialogButtons([close, ?chat]),
      ],
      AgentStatus.failed || AgentStatus.cancelled => [
        Text(
          job.error ??
              (job.status == AgentStatus.cancelled
                  ? AgentNote.cancelled
                  : AgentDialog.unreadable),
          style: theme.body(13).copyWith(color: theme.ink),
        ),
        dialogButtons([close, again]),
      ],
      AgentStatus.done => _done(context, job),
    };
  }

  /// A line with an icon, or with a turning circle while the agent works.
  Widget _status(BuildContext context, IconData? icon, String text) {
    final theme = GroveTheme.of(context);
    final motion =
        _store.motionSetting && !MediaQuery.disableAnimationsOf(context);
    return Row(
      spacing: 8,
      children: [
        SizedBox.square(
          dimension: 16,
          child: icon == null && motion
              ? CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.accent,
                  backgroundColor: theme.surface2,
                )
              : Icon(
                  icon ?? Icons.autorenew,
                  size: 16,
                  color: icon == null ? theme.accent : theme.muted,
                ),
        ),
        Expanded(
          child: Text(text, style: theme.body(13).copyWith(color: theme.ink)),
        ),
      ],
    );
  }

  // The result

  List<Widget> _done(BuildContext context, AgentJob job) {
    final theme = GroveTheme.of(context);
    final result = _store.agentResult(job);
    final noteId = job.resultNoteId;
    final hasNote = noteId != null && _store.note(noteId) != null;
    final message = _message;
    final buttons = dialogButtons([
      DialogButton(
        key: const ValueKey('agent-close'),
        label: 'Close',
        onTap: _close,
      ),
      DialogButton(
        key: const ValueKey('agent-ask-again'),
        label: 'Ask again',
        onTap: _askAgain,
      ),
      ?_inAgents(job),
      if (hasNote)
        DialogButton(
          key: const ValueKey('agent-open-note'),
          label: 'Open note',
          primary: true,
          onTap: () => _openNote(noteId),
        ),
    ]);
    if (result == null) {
      return [
        Text(
          AgentDialog.unreadable,
          style: theme.body(13).copyWith(color: theme.ink),
        ),
        buttons,
      ];
    }
    final heading = theme
        .body(12, weight: FontWeight.w600)
        .copyWith(color: theme.muted);
    final body = theme.body(13).copyWith(color: theme.ink);
    final email = result.emailDraft;
    final text = result.textDraft;
    final doc = result.document;
    final open = widget.openDraft;
    return [
      SelectableText(result.summary, style: body),
      if (result.steps.isNotEmpty) ...[
        Align(
          alignment: Alignment.centerLeft,
          child: TextTap(
            key: const ValueKey('agent-steps'),
            label: _showSteps
                ? 'Hide the steps'
                : 'Show the steps (${result.steps.length})',
            onTap: () => setState(() => _showSteps = !_showSteps),
          ),
        ),
        if (_showSteps)
          Text(
            [for (final (i, step) in result.steps.indexed) '${i + 1}. $step']
                .join('\n'),
            style: _small(theme),
          ),
      ],
      if (doc != null)
        Text(
          'Document: ${doc.title.trim().isEmpty ? 'Untitled' : doc.title}. '
          'It is its own note, linked from the result note.',
          style: _small(theme),
        ),
      if (email != null)
        DraftCard(
          toKey: const ValueKey('agent-email-to'),
          to: email.to,
          subject: email.subject,
          body: email.body,
          buttons: [
            if (open != null)
              DialogButton(
                key: const ValueKey('agent-open-mail'),
                label: 'Open in Mail',
                primary: true,
                onTap: () =>
                    unawaited(_open(AgentPolicy.mailtoUri(email), 'Mail')),
              ),
            DialogButton(
              key: const ValueKey('agent-copy-email'),
              label: 'Copy',
              onTap: () => unawaited(_copy(email.body)),
            ),
          ],
        ),
      if (text != null)
        DraftCard(
          toKey: const ValueKey('agent-text-to'),
          to: text.to,
          body: text.body,
          buttons: [
            if (open != null)
              DialogButton(
                key: const ValueKey('agent-open-messages'),
                label: 'Open in Messages',
                primary: true,
                onTap: () =>
                    unawaited(_open(AgentPolicy.smsUri(text), 'Messages')),
              ),
            DialogButton(
              key: const ValueKey('agent-copy-text'),
              label: 'Copy',
              onTap: () => unawaited(_copy(text.body)),
            ),
          ],
        ),
      if (message != null)
        Text(
          message,
          key: const ValueKey('agent-message'),
          style: _small(theme),
        ),
      if (result.questions.isNotEmpty) ...[
        Text('Questions', style: heading),
        Text(
          [for (final q in result.questions) '• $q'].join('\n'),
          style: body,
        ),
      ],
      if (result.sources.isNotEmpty) ...[
        Text('Sources', style: heading),
        SelectableText(
          [for (final s in result.sources) '• $s'].join('\n'),
          style: _small(theme),
        ),
      ],
      Text(AgentDialog.safety, style: _small(theme)),
      buttons,
    ];
  }
}

/// A draft of an email or a text message: the person it goes to in large
/// letters, so a wrong one is easy to see, then the text and the buttons.
class DraftCard extends StatelessWidget {
  const DraftCard({
    super.key,
    required this.toKey,
    required this.to,
    this.subject,
    required this.body,
    required this.buttons,
  });

  final Key toKey;
  final String to;
  final String? subject;
  final String body;
  final List<Widget> buttons;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final subject = this.subject;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            Text(
              'To: ${to.trim().isEmpty ? '(nobody yet)' : to}',
              key: toKey,
              style: theme
                  .body(17, weight: FontWeight.w700)
                  .copyWith(color: theme.ink),
            ),
            if (subject != null && subject.trim().isNotEmpty)
              Text(
                subject,
                style: theme
                    .body(13, weight: FontWeight.w600)
                    .copyWith(color: theme.ink),
              ),
            SelectableText(
              body,
              style: theme.body(13).copyWith(color: theme.ink),
            ),
            dialogButtons(buttons),
          ],
        ),
      ),
    );
  }
}
