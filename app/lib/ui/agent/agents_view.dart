// The Agents screen (ADR 0005): every chat with the agent, live. On the
// left the chats, sorted into Running, Needs you, Done and Stopped; on the
// right a new chat (a greeting and a big text box) or the open chat: the
// messages, each step of the agent as it works, and the results with their
// drafts and proposals. The agent reads and drafts only. A proposal changes
// the plan only when the person presses Apply.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../planner/planner_dialogs.dart';
import '../shell/shell_layout.dart';
import '../tasks/task_widgets.dart';
import '../theme/check_box.dart';
import '../theme/grove_theme.dart';
import '../theme/panel.dart';
import 'agent_dialog.dart';
import 'agent_pickers.dart';

/// The group of a chat in the list on the left.
enum AgentSection {
  running('Running'),
  needsYou('Needs you'),
  done('Done'),
  stopped('Stopped');

  const AgentSection(this.title);

  final String title;

  /// Queued and running jobs run; a done job with questions needs the
  /// person; failed and cancelled jobs stopped.
  static AgentSection of(AgentJob job, AgentResult? result) =>
      switch (job.status) {
        AgentStatus.queued ||
        AgentStatus.running ||
        AgentStatus.cancelRequested => running,
        AgentStatus.done =>
          result != null && result.questions.isNotEmpty ? needsYou : done,
        AgentStatus.failed || AgentStatus.cancelled => stopped,
      };
}

/// A ready-made first message on the new-chat page.
class AgentHelper {
  const AgentHelper(this.label, this.message, {this.plan = false});

  final String label;
  final String message;

  /// The helper needs to see the plan: the plan switch turns on.
  final bool plan;
}

class AgentsView extends StatefulWidget {
  const AgentsView({super.key, required this.store});

  final AppStore store;

  /// From this width on, the list of chats has a column of its own.
  static const twoColumns = 760.0;

  /// The width of the list of chats.
  static const listWidth = 260.0;

  /// A chat is never wider than this.
  static const chatWidth = 760.0;

  /// How often a device that does not run the agent syncs while a job
  /// works on another computer, so the steps show.
  static const watchEvery = Duration(seconds: 10);

  static const helpers = [
    AgentHelper(
      'Fix my day',
      'I am behind today. Look at my plan and propose a new plan for the '
          'rest of the day that fits.',
      plan: true,
    ),
    AgentHelper(
      'Split a big task',
      'Split the linked task into small steps of 30 minutes or less.',
    ),
    AgentHelper(
      'Get a task ready',
      'Get the linked task ready: find what I need, and draft what I must '
          'send.',
    ),
    AgentHelper(
      'Find tasks in a document',
      'Read the linked document. Find the tasks and the dates in it, and '
          'propose them as new tasks.',
    ),
    AgentHelper(
      'Watch my deadlines',
      'Look at my deadlines for the next two weeks. Tell me what is at risk, '
          'and propose plan changes.',
      plan: true,
    ),
    AgentHelper(
      'Weekly review',
      'Review my week: what I did, what slipped, and a plan for next week.',
      plan: true,
    ),
  ];

  static String greeting(int hour) => hour < 12
      ? 'Good morning'
      : hour < 18
      ? 'Good afternoon'
      : 'Good evening';

  /// The guardrails of a chat, in one line.
  static String rules({required bool plan, required bool email}) =>
      'Reads and drafts only · Plan ${plan ? 'on' : 'off'} · '
      'Email ${email ? 'on' : 'off'} · Stops after 30 min';

  static String statusLabel(AgentStatus status) => switch (status) {
    AgentStatus.queued => 'Waiting',
    AgentStatus.running => 'Working',
    AgentStatus.cancelRequested => 'Stopping',
    AgentStatus.done => 'Done',
    AgentStatus.failed => 'Failed',
    AgentStatus.cancelled => 'Stopped',
  };

  static const untitled = 'Chat';
  static const notApplied =
      'Grove could not apply this. The task may be '
      'gone or done.';
  static const fileElsewhere = 'on another computer';

  @override
  State<AgentsView> createState() => _AgentsViewState();
}

class _AgentsViewState extends State<AgentsView> {
  final _search = TextEditingController();
  Timer? _watch;

  /// The step groups that show all their steps, by the id of their first
  /// step.
  final _open = <String>{};

  /// A short line after Copy, an app that did not open, or an Apply that
  /// did not work.
  String? _message;

  AppStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    _watch = Timer.periodic(AgentsView.watchEvery, (_) => _look());
  }

  @override
  void dispose() {
    _watch?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// A job works on another computer: sync, so its steps show here.
  void _look() {
    if (_store.isDisposed || _store.agentRunnerOn) return;
    if (_store.agentJobs().any((j) => !j.status.isFinished)) {
      unawaited(_store.syncNow());
    }
  }

  void _show(String? jobId) => setState(() {
    _message = null;
    _store.showAgentJob(jobId);
  });

  String _title(AgentJob job) {
    if (job.title.trim().isNotEmpty) return job.title;
    final task = job.taskId == null ? null : _store.task(job.taskId!);
    return task?.title ?? AgentsView.untitled;
  }

  @override
  Widget build(BuildContext context) => StoreBuilder(
    store: _store,
    builder: (context) {
      final phone =
          ShellRules.layoutFor(MediaQuery.sizeOf(context).width) ==
          ShellLayout.phone;
      final shown = _store.shownAgentJob;
      return LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth < AgentsView.twoColumns) {
            return shown == null
                ? _scroll(
                    phone,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 18,
                      children: [_home(context), _list(context, null)],
                    ),
                  )
                : _scroll(phone, _thread(context, shown, back: true));
          }
          final theme = GroveTheme.of(context);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: AgentsView.listWidth,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 6, 12, 24),
                  child: _list(context, shown),
                ),
              ),
              VerticalDivider(width: 1, thickness: 1, color: theme.line),
              Expanded(
                child: _scroll(
                  phone,
                  shown == null
                      ? _home(context)
                      : _thread(context, shown, back: false),
                ),
              ),
            ],
          );
        },
      );
    },
  );

  Widget _scroll(bool phone, Widget child) {
    final side = phone ? 12.0 : 24.0;
    return SingleChildScrollView(
      child: WholeCenter(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AgentsView.chatWidth),
          child: Padding(
            padding: EdgeInsets.fromLTRB(side, 6, side, phone ? 12 : 24),
            child: child,
          ),
        ),
      ),
    );
  }

  // The list of chats

  Widget _list(BuildContext context, String? shown) {
    final theme = GroveTheme.of(context);
    final words = _search.text.trim().toLowerCase();
    final groups = {for (final s in AgentSection.values) s: <AgentJob>[]};
    for (final job in _store.agentJobs()) {
      final text = '${_title(job)} ${job.instructions}'.toLowerCase();
      if (words.isNotEmpty && !text.contains(words)) continue;
      groups[AgentSection.of(job, _store.agentResult(job))]!.add(job);
    }
    final heading = theme
        .body(11, weight: FontWeight.w600)
        .copyWith(color: theme.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        _Row(
          key: const ValueKey('agents-new'),
          label: 'New chat',
          icon: Icons.add,
          selected: shown == null,
          onTap: () => _show(null),
        ),
        GroveField(
          key: const ValueKey('agents-search'),
          controller: _search,
          placeholder: 'Search chats',
          boxed: true,
          leading: Icon(Icons.search, size: 14, color: theme.muted),
          onChanged: (_) => setState(() {}),
        ),
        for (final MapEntry(key: section, value: jobs) in groups.entries)
          if (jobs.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(section.title, style: heading),
            ),
            for (final job in jobs)
              _Row(
                key: ValueKey('agents-job-${job.id}'),
                label: _title(job),
                icon: _statusIcon(job.status),
                selected: job.id == shown,
                onTap: () => _show(job.id),
              ),
          ],
      ],
    );
  }

  static IconData _statusIcon(AgentStatus status) => switch (status) {
    AgentStatus.queued => Icons.hourglass_empty,
    AgentStatus.running => Icons.autorenew,
    AgentStatus.cancelRequested => Icons.stop_circle_outlined,
    AgentStatus.done => Icons.check_circle_outline,
    AgentStatus.failed => Icons.error_outline,
    AgentStatus.cancelled => Icons.block,
  };

  // A new chat

  Widget _home(BuildContext context) {
    final theme = GroveTheme.of(context);
    final hour =
        (_store.clockOverride?.minute ??
            DateTime.now().hour * 60 + DateTime.now().minute) ~/
        60;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 14,
      children: [
        const SizedBox(height: 24),
        Center(
          child: ThemedHeading(
            '${AgentsView.greeting(hour)}, ${_store.personaName}',
            26,
          ),
        ),
        Center(
          child: Text(
            'What can the agent do for you?',
            style: theme.body(13).copyWith(color: theme.muted),
          ),
        ),
        AgentComposer(
          key: const ValueKey('agents-composer'),
          store: _store,
          keyName: 'agents',
          placeholder: 'Ask the agent…',
          minLines: 4,
          helpers: AgentsView.helpers,
          onSend: (text, links, {required plan, required email}) {
            final id = _store.startAgentChat(
              text,
              links: links,
              plan: plan,
              email: email,
            );
            if (id.isEmpty) return false;
            _show(id);
            return true;
          },
        ),
      ],
    );
  }

  // A chat

  Widget _thread(BuildContext context, String jobId, {required bool back}) {
    final theme = GroveTheme.of(context);
    final job = _store.agentJob(jobId);
    if (job == null) return const SizedBox.shrink();
    final events = _store.agentEvents(jobId);
    final small = theme.body(11).copyWith(color: theme.muted);
    final message = _message;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        if (back)
          Align(
            alignment: Alignment.centerLeft,
            child: TextTap(
              key: const ValueKey('agents-back'),
              label: '‹ Chats',
              onTap: () => _show(null),
            ),
          ),
        Row(
          spacing: 10,
          children: [
            Expanded(child: ThemedHeading(_title(job), 20)),
            _StatusPill(status: job.status),
            if (job.status == AgentStatus.queued ||
                job.status == AgentStatus.running)
              DialogButton(
                key: const ValueKey('agents-stop'),
                label: 'Stop',
                onTap: () => _store.cancelAgentJob(job.id),
              ),
          ],
        ),
        Text(
          AgentsView.rules(plan: job.planAccess, email: job.emailAccess),
          key: const ValueKey('agents-rules'),
          style: small,
        ),
        if (job.links.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final l in job.links) _linkChip(context, l)],
          ),
        for (final item in _lines(events))
          item is List<AgentEvent>
              ? _steps(context, job, item)
              : _line(context, item as AgentEvent),
        if (!job.status.isFinished) ..._working(context, job),
        if (message != null)
          Text(message, key: const ValueKey('agents-message'), style: small),
        if (job.status.isFinished)
          AgentComposer(
            key: ValueKey('agents-reply-$jobId'),
            store: _store,
            keyName: 'agents-reply',
            placeholder: 'Reply to the agent…',
            minLines: 2,
            plan: job.planAccess,
            email: job.emailAccess,
            onSend: (text, links, {required plan, required email}) {
              setState(() => _message = null);
              return _store.askAgentAgain(
                jobId,
                text,
                links: links,
                plan: plan,
                email: email,
              );
            },
          ),
      ],
    );
  }

  /// The lines of a chat, with the steps in a row kept together.
  static List<Object> _lines(List<AgentEvent> events) {
    final out = <Object>[];
    for (final e in events) {
      if (e.kind == AgentEventKind.step) {
        final last = out.isEmpty ? null : out.last;
        if (last is List<AgentEvent>) {
          last.add(e);
        } else {
          out.add([e]);
        }
      } else {
        out.add(e);
      }
    }
    return out;
  }

  Widget _linkChip(BuildContext context, AgentLink link) {
    final theme = GroveTheme.of(context);
    final elsewhere =
        link.kind == AgentLinkKind.file && !_store.agentFileHere(link);
    return _Chip(
      icon: _linkIcon(link.kind),
      label: elsewhere
          ? '${link.name} (${AgentsView.fileElsewhere})'
          : link.name,
      color: elsewhere ? theme.muted : theme.ink,
    );
  }

  Widget _line(BuildContext context, AgentEvent e) {
    final theme = GroveTheme.of(context);
    return switch (e.kind) {
      AgentEventKind.ask => Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.line),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SelectableText(
                e.body,
                style: theme.body(13).copyWith(color: theme.ink),
              ),
            ),
          ),
        ),
      ),
      AgentEventKind.stopped => Row(
        key: ValueKey('agents-stopped-${e.id}'),
        spacing: 8,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.stop_circle_outlined, size: 15, color: theme.muted),
          Expanded(
            child: Text(
              e.body,
              style: theme.body(13).copyWith(color: theme.muted),
            ),
          ),
        ],
      ),
      AgentEventKind.result => _result(context, e),
      AgentEventKind.step => _steps(context, null, [e]),
    };
  }

  // The steps

  /// Shows the last [_shortSteps] steps of a group; a click shows all.
  static const _shortSteps = 3;

  Widget _steps(BuildContext context, AgentJob? job, List<AgentEvent> steps) {
    final theme = GroveTheme.of(context);
    final id = steps.first.id;
    final all = _open.contains(id);
    final shown = all || steps.length <= _shortSteps
        ? steps
        : steps.sublist(steps.length - _shortSteps);
    final hidden = steps.length - shown.length;
    final small = theme.body(12).copyWith(color: theme.muted);
    return Column(
      key: ValueKey('agents-steps-$id'),
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        if (steps.length > _shortSteps)
          TextTap(
            key: ValueKey('agents-steps-toggle-$id'),
            label: all
                ? 'Show fewer steps'
                : 'Show all ${steps.length} steps ($hidden more)',
            onTap: () => setState(() => all ? _open.remove(id) : _open.add(id)),
          ),
        for (final s in shown)
          Row(
            spacing: 8,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _stepIcon(s.label),
                size: 14,
                color: s.label == AgentStep.blocked
                    ? theme.accent
                    : theme.muted,
              ),
              Expanded(
                child: Text(
                  s.body,
                  maxLines: all ? 6 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: small,
                ),
              ),
            ],
          ),
      ],
    );
  }

  static IconData _stepIcon(String label) => switch (label) {
    AgentStep.search => Icons.search,
    AgentStep.web => Icons.public,
    AgentStep.file => Icons.description_outlined,
    AgentStep.mail => Icons.mail_outline,
    AgentStep.think => Icons.psychology_outlined,
    AgentStep.blocked => Icons.block,
    _ => Icons.build_outlined,
  };

  static IconData _linkIcon(AgentLinkKind kind) => switch (kind) {
    AgentLinkKind.note => Icons.sticky_note_2_outlined,
    AgentLinkKind.task => Icons.check_box_outlined,
    AgentLinkKind.file => Icons.attach_file,
  };

  /// The row under a job that is not finished.
  List<Widget> _working(BuildContext context, AgentJob job) {
    final theme = GroveTheme.of(context);
    final motion =
        _store.motionSetting && !MediaQuery.disableAnimationsOf(context);
    final (icon, text) = switch (job.status) {
      AgentStatus.queued => (Icons.hourglass_empty, AgentDialog.waiting),
      AgentStatus.cancelRequested => (
        Icons.stop_circle_outlined,
        AgentDialog.stopping,
      ),
      _ => (null, AgentDialog.working),
    };
    return [
      Row(
        key: const ValueKey('agents-working'),
        spacing: 8,
        children: [
          SizedBox.square(
            dimension: 14,
            child: icon == null && motion
                ? CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.accent,
                    backgroundColor: theme.surface2,
                  )
                : Icon(icon ?? Icons.autorenew, size: 14, color: theme.muted),
          ),
          Expanded(
            child: Text(text, style: theme.body(13).copyWith(color: theme.ink)),
          ),
        ],
      ),
      if (job.status == AgentStatus.queued && !_store.agentRunnerOn)
        Text(
          AgentDialog.turnOnRunner,
          style: theme.body(11).copyWith(color: theme.muted),
        ),
    ];
  }

  // A result

  Future<void> _openDraft(Uri url, String app) async {
    final open = AgentTools.maybeOf(context)?.openDraft;
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

  void _apply(AgentEvent e, String key) {
    final ok = _store.applyAgentChange(e.id, key);
    setState(() => _message = ok ? null : AgentsView.notApplied);
  }

  Widget _result(BuildContext context, AgentEvent e) {
    final theme = GroveTheme.of(context);
    final result = _store.agentEventResult(e);
    final body = theme.body(13).copyWith(color: theme.ink);
    final small = theme.body(11).copyWith(color: theme.muted);
    final heading = theme
        .body(12, weight: FontWeight.w600)
        .copyWith(color: theme.muted);
    if (result == null) return Text(AgentDialog.unreadable, style: body);
    final doc = _store.agentEventDocument(e);
    final note = _store.agentEventNote(e);
    final email = result.emailDraft;
    final text = result.textDraft;
    final canOpen = AgentTools.maybeOf(context)?.openDraft != null;
    final applied = _store.agentApplied(e);
    Widget apply(String key) => applied.contains(key)
        ? Text('Applied', key: ValueKey('agents-applied-$key'), style: small)
        : DialogButton(
            key: ValueKey('agents-apply-$key'),
            label: 'Apply',
            primary: true,
            onTap: () => _apply(e, key),
          );
    Widget proposal(String key, String line) => Row(
      spacing: 10,
      children: [
        Expanded(child: Text(line, style: body)),
        apply(key),
      ],
    );
    return Panel(
      key: ValueKey('agents-result-${e.id}'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            SelectableText(result.summary, style: body),
            if ((doc != null && _store.note(doc) != null) ||
                (note != null && _store.note(note) != null))
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (doc != null && _store.note(doc) != null)
                    DialogButton(
                      key: const ValueKey('agents-open-document'),
                      label: 'Open document',
                      onTap: () => _store.openNote(doc),
                    ),
                  if (note != null && _store.note(note) != null)
                    DialogButton(
                      key: const ValueKey('agents-open-note'),
                      label: 'Open note',
                      onTap: () => _store.openNote(note),
                    ),
                ],
              ),
            if (email != null)
              DraftCard(
                toKey: const ValueKey('agents-email-to'),
                to: email.to,
                subject: email.subject,
                body: email.body,
                buttons: [
                  if (canOpen)
                    DialogButton(
                      key: const ValueKey('agents-open-mail'),
                      label: 'Open in Mail',
                      primary: true,
                      onTap: () => unawaited(
                        _openDraft(AgentPolicy.mailtoUri(email), 'Mail'),
                      ),
                    ),
                  DialogButton(
                    key: const ValueKey('agents-copy-email'),
                    label: 'Copy',
                    onTap: () => unawaited(_copy(email.body)),
                  ),
                ],
              ),
            if (text != null)
              DraftCard(
                toKey: const ValueKey('agents-text-to'),
                to: text.to,
                body: text.body,
                buttons: [
                  if (canOpen)
                    DialogButton(
                      key: const ValueKey('agents-open-messages'),
                      label: 'Open in Messages',
                      primary: true,
                      onTap: () => unawaited(
                        _openDraft(AgentPolicy.smsUri(text), 'Messages'),
                      ),
                    ),
                  DialogButton(
                    key: const ValueKey('agents-copy-text'),
                    label: 'Copy',
                    onTap: () => unawaited(_copy(text.body)),
                  ),
                ],
              ),
            if (result.planChanges.isNotEmpty) ...[
              Text('Plan changes', style: heading),
              for (final (i, c) in result.planChanges.indexed)
                proposal(
                  AgentResult.planKey(i),
                  '${_store.task(c.taskId)?.title ?? AgentDialog.taskGone} · '
                  '${NotesRules.shortDate(c.day)} at '
                  '${AgentTime.format(c.start)} · ${c.minutes} min',
                ),
            ],
            if (result.newTasks.isNotEmpty) ...[
              Text('New tasks', style: heading),
              for (final (i, t) in result.newTasks.indexed)
                proposal(
                  AgentResult.taskKey(i),
                  [
                    t.title,
                    if (t.day case final day?) NotesRules.shortDate(day),
                    if (t.minutes case final m?) '$m min',
                  ].join(' · '),
                ),
            ],
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
                style: small,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What the composer sends. True when the message was saved: the box
/// empties.
typedef AgentSend = bool Function(
  String text,
  List<AgentLink> links, {
  required bool plan,
  required bool email,
});

/// The text box of a chat: "+" to link notes, tasks and files, the plan
/// and email switches, and Send.
class AgentComposer extends StatefulWidget {
  const AgentComposer({
    super.key,
    required this.store,
    required this.keyName,
    required this.placeholder,
    required this.onSend,
    this.minLines = 3,
    this.plan = false,
    this.email = false,
    this.helpers = const [],
  });

  final AppStore store;

  /// The start of the keys of its parts, for tests.
  final String keyName;
  final String placeholder;
  final AgentSend onSend;
  final int minLines;

  /// The switches at first.
  final bool plan;
  final bool email;

  /// Ready-made messages under the box. A click puts one in the box.
  final List<AgentHelper> helpers;

  @override
  State<AgentComposer> createState() => _AgentComposerState();
}

class _AgentComposerState extends State<AgentComposer> {
  final _text = TextEditingController();
  final _links = <AgentLink>[];
  late bool _plan = widget.plan;
  late bool _email = widget.email;

  AppStore get _store => widget.store;
  String get _k => widget.keyName;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final ok = widget.onSend(
      _text.text,
      List.of(_links),
      plan: _plan,
      email: _email,
    );
    if (!ok || !mounted) return;
    setState(() {
      _text.clear();
      _links.clear();
    });
  }

  void _add(AgentLink? link) {
    if (link == null || !mounted) return;
    if (_links.any((l) => l.kind == link.kind && l.id == link.id)) return;
    setState(() => _links.add(link));
  }

  Future<void> _file(AgentFilePicker pick) async {
    final path = await pick();
    if (path == null) return;
    _add(await _store.linkAgentFile(path));
  }

  void _menu(BuildContext context) {
    final pick = AgentTools.maybeOf(context)?.pickFile;
    final box = context.findRenderObject()! as RenderBox;
    showGroveMenu(context, box.localToGlobal(Offset(0, box.size.height)), [
      MenuLine(
        'Link a note…',
        () => unawaited(pickAgentNote(context, _store).then(_add)),
      ),
      MenuLine(
        'Link a task…',
        () => unawaited(pickAgentTask(context, _store).then(_add)),
      ),
      if (pick != null && _store.canLinkAgentFiles)
        MenuLine('Add a file…', () => unawaited(_file(pick))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final small = theme.body(11).copyWith(color: theme.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.line),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 6,
              children: [
                GroveField(
                  key: ValueKey('$_k-text'),
                  controller: _text,
                  placeholder: widget.placeholder,
                  fill: theme.surface,
                  minLines: widget.minLines,
                  maxLines: 12,
                  newlines: true,
                ),
                if (_links.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final l in _links)
                        _Chip(
                          key: ValueKey('$_k-link-${l.id}'),
                          icon: _AgentsViewState._linkIcon(l.kind),
                          label: l.name,
                          color: theme.ink,
                          onRemove: () => setState(() => _links.remove(l)),
                        ),
                    ],
                  ),
                Row(
                  spacing: 8,
                  children: [
                    Builder(
                      builder: (context) => _IconTap(
                        key: ValueKey('$_k-plus'),
                        icon: Icons.add,
                        label: 'Link a note, a task or a file',
                        onTap: () => _menu(context),
                      ),
                    ),
                    _Switch(
                      key: ValueKey('$_k-plan'),
                      label: 'Plan',
                      tooltip: 'The agent may see your tasks and events.',
                      isOn: _plan,
                      onTap: () => setState(() => _plan = !_plan),
                    ),
                    _Switch(
                      key: ValueKey('$_k-email'),
                      label: 'Email',
                      tooltip: 'The agent may read your email.',
                      isOn: _email,
                      onTap: () => setState(() => _email = !_email),
                    ),
                    const Spacer(),
                    DialogButton(
                      key: ValueKey('$_k-send'),
                      label: 'Send',
                      primary: true,
                      onTap: _send,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_email && !_store.agentEmailOn)
          Text(AgentDialog.emailOffHere, style: small),
        if (widget.helpers.isNotEmpty)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (i, h) in widget.helpers.indexed)
                _Chip(
                  key: ValueKey('$_k-helper-$i'),
                  icon: Icons.auto_awesome_outlined,
                  label: h.label,
                  color: theme.ink,
                  onTap: () => setState(() {
                    _text.text = h.message;
                    if (h.plan) _plan = true;
                  }),
                ),
            ],
          ),
        Text(AgentDialog.safety, textAlign: TextAlign.center, style: small),
      ],
    );
  }
}

/// A line of the list of chats.
class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? theme.surface2 : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                spacing: 8,
                children: [
                  Icon(icon, size: 14, color: theme.muted),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme
                          .body(
                            13,
                            weight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          )
                          .copyWith(color: theme.ink),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The state of a chat, in a small capsule.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final AgentStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final live = !status.isFinished;
    return DecoratedBox(
      key: const ValueKey('agents-status'),
      decoration: ShapeDecoration(
        color: live ? theme.accent : theme.surface2,
        shape: StadiumBorder(side: BorderSide(color: theme.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Text(
          AgentsView.statusLabel(status),
          style: theme
              .body(11, weight: FontWeight.w600)
              .copyWith(color: live ? theme.bg : theme.muted),
        ),
      ),
    );
  }
}

/// A small capsule with an icon: a link, or a ready-made message.
class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
    this.onRemove,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  /// Shows a small cross that takes the chip away.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final remove = onRemove;
    Widget chip = DecoratedBox(
      decoration: ShapeDecoration(
        color: theme.surface2,
        shape: StadiumBorder(side: BorderSide(color: theme.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(9, 4, 9, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 5,
          children: [
            Icon(icon, size: 13, color: theme.muted),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.body(12).copyWith(color: color),
              ),
            ),
            if (remove != null)
              _IconTap(
                icon: Icons.close,
                size: 12,
                label: 'Remove $label',
                onTap: remove,
              ),
          ],
        ),
      ),
    );
    final tap = onTap;
    if (tap != null) {
      chip = Semantics(
        container: true,
        button: true,
        label: label,
        onTap: tap,
        excludeSemantics: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: tap,
            child: chip,
          ),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: chip,
    );
  }
}

/// A small icon button.
class _IconTap extends StatelessWidget {
  const _IconTap({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = 18,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return Semantics(
      container: true,
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Icon(icon, size: size, color: theme.muted),
            ),
          ),
        ),
      ),
    );
  }
}

/// A switch of the composer: a check box and a word.
class _Switch extends StatelessWidget {
  const _Switch({
    super.key,
    required this.label,
    required this.tooltip,
    required this.isOn,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final bool isOn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return Semantics(
      container: true,
      checked: isOn,
      label: '$label: $tooltip',
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 5,
              children: [
                CheckBox(isOn: isOn, size: 13),
                Text(label, style: theme.body(12).copyWith(color: theme.ink)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
