part of 'app_store.dart';

class _AgentState {
  bool enabled = false;
  bool runner = false;
  bool email = false;

  /// True after the first look for `claude` ended.
  bool looked = false;

  /// The full path of `claude`, or null when it was not found.
  String? exe;

  /// The look for `claude` and the run of the queue. Tests wait on it.
  Future<void>? work;

  /// Something asked for a run while one was busy: look at the queue again.
  bool again = false;

  /// Rises with each new look for `claude`. An older look is dropped.
  int lookTurn = 0;

  /// The one-minute check of the queue.
  _Sleep? tick;

  /// The job that runs now on this device, and its process.
  String? liveJob;
  AgentProcess? live;

  /// The chat open on the Agents screen. Null: the new-chat page.
  String? shown;
}

/// The agent (ADR 0004, 0005): any device makes a job (a chat, maybe for a
/// task), the job syncs, and the computer with "This device runs agent
/// tasks" on runs it with the `claude` command. One job at a time. Each
/// message of the person, each step of a run and each result is an
/// [AgentEvent], so a phone can watch. A job of a task also leaves a note
/// linked to the task (and a document note when the agent wrote one).
///
/// Writes of the agent are not on the undo stack: they come from the
/// background, like rows a sync pulls in, and an undo must not delete a
/// result the person did not make by hand.
extension AppStoreAgent on AppStore {
  static const _enabledKey = 'agent.enabled';
  static const _runnerKey = 'agent.runner';
  static const _emailKey = 'agent.email';

  /// The id of this device in `runner_device`. Made the first time this
  /// device takes a job; kept in the prefs of this device.
  static const _deviceKey = 'agent.device';

  /// How often a computer that runs agent tasks looks at the queue while
  /// Grove is open. A sync pull also starts a look.
  static const agentTick = Duration(minutes: 1);

  /// How often a running job is read again, to see a cancel from another
  /// device.
  static const agentPoll = Duration(seconds: 3);

  // The switches (per device, all off at first)

  /// "Use the agent": the task menus show "Ask the agent…".
  bool get agentEnabled => _agent.enabled;

  /// "This device runs agent tasks".
  bool get agentRunnerOn => _agent.runner;

  /// "Let the agent read my email" on this runner.
  bool get agentEmailOn => _agent.email;

  /// This device has the `claude` command, so it can run agent tasks.
  bool get canRunAgent => agentRunner != null && _agent.exe != null;

  /// A plain help text for the runner switch, or null when this device can
  /// run agent tasks.
  String? get agentHelp => SettingsRules.agentHelp(
    computer: agentRunner != null,
    looked: _agent.looked,
    found: _agent.exe != null,
  );

  void setAgentEnabled(bool on) {
    _agent.enabled = on;
    prefs.set(_enabledKey, on);
    if (!on && _screen == Screen.agents) screen = Screen.today;
    _changed();
  }

  /// The screens in the switch: the Agents screen only when the agent is
  /// on.
  List<Screen> get screens => [
    ...Screen.always,
    if (agentEnabled) Screen.agents,
  ];

  /// The chat open on the Agents screen, or null for the new-chat page. A
  /// chat that is gone (a sync deleted it) reads as null.
  String? get shownAgentJob {
    final id = _agent.shown;
    return id != null && agentJob(id) != null ? id : null;
  }

  /// Opens the chat [jobId] on the Agents screen; null opens the new-chat
  /// page.
  void showAgentJob(String? jobId) {
    _agent.shown = jobId;
    if (agentEnabled) screen = Screen.agents;
    _changed();
  }

  /// True when the file of [link] is on this computer, so the agent here
  /// can read it.
  bool agentFileHere(AgentLink link) =>
      link.kind == AgentLinkKind.file &&
      canLinkAgentFiles &&
      link.device == _agentDevice;

  /// On: Grove looks for `claude` again (it may be installed now), then runs
  /// the queue. Off: the one-minute check stops. A job that runs now goes on
  /// to its end.
  void setAgentRunner(bool on) {
    _agent.runner = on;
    prefs.set(_runnerKey, on);
    _changed();
    if (on) {
      _agentThen(_agentLook);
    } else {
      _agentStopTick();
    }
  }

  void setAgentEmail(bool on) {
    _agent.email = on;
    prefs.set(_emailKey, on);
    _changed();
  }

  // Jobs

  /// The newest job of the task, or null.
  AgentJob? agentJobFor(String taskId) =>
      _try(() => repos.agentJobs.forTask(taskId));

  /// The result of a done job, or null.
  AgentResult? agentResult(AgentJob job) {
    final text = job.resultJson;
    if (text == null) return null;
    return _try(() {
      final json = jsonDecode(text);
      return json is Map<String, Object?> ? AgentResult.fromJson(json) : null;
    });
  }

  /// Every job, the newest change first: the chats of the Agents screen.
  List<AgentJob> agentJobs() => _try(repos.agentJobs.all) ?? const <AgentJob>[];

  AgentJob? agentJob(String id) => _try(() => repos.agentJobs.get(id));

  /// The lines of a chat, in order.
  List<AgentEvent> agentEvents(String jobId) =>
      _try(() => repos.agentEvents.forJob(jobId)) ?? const <AgentEvent>[];

  /// The result in a result line, or null.
  AgentResult? agentEventResult(AgentEvent event) {
    if (event.kind != AgentEventKind.result) return null;
    return _try(() {
      final json = jsonDecode(event.body);
      return json is Map<String, Object?> ? AgentResult.fromJson(json) : null;
    });
  }

  /// The document note that a result line made, or null.
  String? agentEventDocument(AgentEvent event) => _agentEventId(event, _docKey);

  /// The result note (of a job of a task) that a result line made, or null.
  String? agentEventNote(AgentEvent event) => _agentEventId(event, _noteKey);

  static const _docKey = 'grove_document_note';
  static const _noteKey = 'grove_result_note';

  String? _agentEventId(AgentEvent event, String key) {
    if (event.kind != AgentEventKind.result) return null;
    return _try(() {
      final json = jsonDecode(event.body);
      return json is Map<String, Object?> && json[key] is String
          ? json[key] as String
          : null;
    });
  }

  /// The keys of the proposals of a result line that the person applied.
  Set<String> agentApplied(AgentEvent event) => {
    for (final k in event.label.split(','))
      if (k.trim().isNotEmpty) k.trim(),
  };

  /// Gives the task to the agent: a queued job that syncs to the computer
  /// that runs agent tasks. [email]: the person allows the agent to read
  /// their email for this task. Returns the id of the job, or an empty text
  /// when it could not be saved ([errorMessage] says why).
  String delegateToAgent(
    String taskId, {
    String instructions = '',
    bool email = false,
  }) => _agentNewJob(
    AgentJob(
      taskId: taskId,
      title: AgentNote.chatTitle(task(taskId)?.title ?? ''),
      instructions: instructions.trim(),
      emailAccess: email,
    ),
    instructions.trim().isEmpty ? AgentNote.workOnTask : instructions.trim(),
  );

  /// Starts a chat on the Agents screen: a queued job with the first
  /// message. [links]: notes, tasks and files the agent may read. [email]
  /// and [plan]: the person lets the agent read their email, or see their
  /// plan. Returns the id of the job, or an empty text when the message is
  /// empty or could not be saved.
  String startAgentChat(
    String text, {
    List<AgentLink> links = const [],
    bool email = false,
    bool plan = false,
    String? taskId,
  }) {
    final message = text.trim();
    if (message.isEmpty) return '';
    return _agentNewJob(
      AgentJob(
        taskId: taskId,
        title: AgentNote.chatTitle(message),
        instructions: message,
        emailAccess: email,
        planAccess: plan,
        links: links,
      ),
      message,
    );
  }

  String _agentNewJob(AgentJob job, String message) {
    try {
      repos.db.transaction(() {
        repos.agentJobs.insert(job);
        repos.agentEvents.insert(
          AgentEvent(
            jobId: job.id,
            seq: 1,
            kind: AgentEventKind.ask,
            body: message,
          ),
        );
      });
    } on Exception catch (e) {
      errorMessage = 'Could not save: $e';
      return '';
    }
    _bump();
    if (_agentCanWork) unawaited(runAgentQueue());
    return job.id;
  }

  /// A new message in a finished chat: the job goes back in the queue. The
  /// new [links] join the old ones. False when the message is empty, or the
  /// job is gone or still works.
  bool askAgentAgain(
    String jobId,
    String text, {
    List<AgentLink> links = const [],
    bool? email,
    bool? plan,
  }) {
    final message = text.trim();
    final job = agentJob(jobId);
    if (message.isEmpty || job == null || !job.status.isFinished) return false;
    final all = [
      ...job.links,
      for (final l in links)
        if (!job.links.any((o) => o.kind == l.kind && o.id == l.id)) l,
    ];
    var ok = false;
    try {
      repos.db.transaction(() {
        ok = repos.agentJobs.requeue(
          jobId,
          emailAccess: email ?? job.emailAccess,
          planAccess: plan ?? job.planAccess,
          links: all,
        );
        if (!ok) return;
        repos.agentEvents.insert(
          AgentEvent(
            jobId: jobId,
            seq: repos.agentEvents.nextSeq(jobId),
            kind: AgentEventKind.ask,
            body: message,
          ),
        );
      });
    } on Exception catch (e) {
      errorMessage = 'Could not save: $e';
      return false;
    }
    if (!ok) return false;
    _bump();
    if (_agentCanWork) unawaited(runAgentQueue());
    return true;
  }

  /// The folder of the copies of linked files, on a computer.
  String? get _agentFilesDir {
    final dir = dataDir;
    if (dir == null || agentRunner == null) return null;
    return '$dir${Platform.pathSeparator}Agent files';
  }

  /// This device can link files: it is a computer with a data folder.
  bool get canLinkAgentFiles => _agentFilesDir != null;

  /// Copies the file at [path] into the agent files folder of this computer
  /// and gives the link for a chat. Files do not sync: only this computer
  /// can give the file to the agent (ADR 0005). Null when the copy failed.
  Future<AgentLink?> linkAgentFile(String path) async {
    final dir = _agentFilesDir;
    if (dir == null) return null;
    final name = AgentPolicy.safeName(path);
    final id = newId();
    final sep = Platform.pathSeparator;
    try {
      await Directory('$dir$sep$id').create(recursive: true);
      await File(path).copy('$dir$sep$id$sep$name');
    } on FileSystemException catch (e) {
      errorMessage = 'Could not add the file: ${e.message}';
      _changed();
      return null;
    }
    return AgentLink(
      kind: AgentLinkKind.file,
      id: id,
      name: name,
      device: _agentDevice,
    );
  }

  /// Applies one proposal of a result line: [key] is
  /// [AgentResult.planKey] or [AgentResult.taskKey]. One undo step. False
  /// when it was applied before, or the task is gone.
  bool applyAgentChange(String eventId, String key) {
    final event = _try(() => repos.agentEvents.get(eventId));
    if (event == null) return false;
    final result = agentEventResult(event);
    final applied = agentApplied(event);
    if (result == null || applied.contains(key)) return false;
    final index = int.tryParse(key.substring(1));
    if (index == null || index < 0) return false;
    var done = false;
    if (key.startsWith('p') && index < result.planChanges.length) {
      final c = result.planChanges[index];
      final t = task(c.taskId);
      if (t == null || t.status != TaskStatus.open) return false;
      schedule(taskId: c.taskId, day: c.day, start: c.start, length: c.minutes);
      done = true;
    } else if (key.startsWith('t') && index < result.newTasks.length) {
      final n = result.newTasks[index];
      final parent = n.parentTaskId;
      if (parent != null && task(parent) == null) return false;
      final title = n.title.length > 200 ? n.title.substring(0, 200) : n.title;
      var t = TaskItem(
        title: title,
        parentId: parent,
        estimateMin: n.minutes ?? 30,
        sort: _nextSort(),
      );
      if (n.day case final day?) t = planned(t, on: day);
      done = commit(
        Mutation(parent == null ? 'New Task' : 'New Subtask')
          ..tasks.add((before: null, after: t)),
      );
    }
    if (!done) return false;
    _try(
      () => repos.agentEvents.update(
        event.copyWith(label: ({...applied, key}).join(',')),
      ),
    );
    _bump();
    return true;
  }

  /// Cancel, from any device. A queued job is cancelled at once. A running
  /// job is marked; the computer that runs it stops `claude` (at once when
  /// that is this device).
  void cancelAgentJob(String jobId) {
    final jobs = repos.agentJobs;
    final done =
        _try(
          () => jobs.setStatus(
            jobId,
            AgentStatus.cancelled,
            error: AgentNote.cancelled,
            from: {AgentStatus.queued},
          ),
        ) ??
        false;
    if (done) _agentLine(jobId, AgentEventKind.stopped, AgentNote.cancelled);
    if (!done) {
      final marked =
          _try(
            () => jobs.setStatus(
              jobId,
              AgentStatus.cancelRequested,
              from: {AgentStatus.running},
            ),
          ) ??
          false;
      if (!marked) return;
      if (_agent.liveJob == jobId) _agent.live?.cancel();
    }
    _bump();
  }

  // The worker

  /// The look for `claude` and the run of the queue that go on now, or null.
  Future<void>? get agentWork => _agent.work;

  /// Runs the queued jobs one by one, the oldest first, when this device
  /// runs agent tasks. A call while a run is busy makes that run look at
  /// the queue again, and returns it.
  Future<void> runAgentQueue() {
    final busy = _agent.work;
    if (busy != null) {
      _agent.again = true;
      return busy;
    }
    return _agentTrack(Future(_agentDrain));
  }

  /// Runs [step] after the work that goes on now, so two runs never overlap.
  void _agentThen(Future<void> Function() step) {
    final busy = _agent.work;
    _agentTrack(
      busy == null
          ? Future(step)
          : busy.then((_) {}, onError: (_) {}).then((_) => step()),
    );
  }

  bool get _agentCanWork => !_disposed && _agent.runner && canRunAgent;

  String get _agentDevice {
    final saved = prefs.getString(_deviceKey);
    if (saved != null && saved.isNotEmpty) return saved;
    final id = newId();
    prefs.set(_deviceKey, id);
    return id;
  }

  Future<void> _agentTrack(Future<void> work) {
    late final Future<void> task;
    task = work.whenComplete(() {
      if (!identical(_agent.work, task)) return;
      _agent.work = null;
      // A call came in after the last look at the queue.
      if (_agent.again && _agentCanWork) {
        _agent.again = false;
        unawaited(runAgentQueue());
      }
    });
    _agent.work = task;
    return task;
  }

  /// Reads the switches, finishes the jobs a crash left, and looks for
  /// `claude`. Called by the constructor.
  void _startAgent() {
    final p = prefs;
    _agent
      ..enabled = p.getBool(_enabledKey) ?? false
      ..runner = p.getBool(_runnerKey) ?? false
      ..email = p.getBool(_emailKey) ?? false;
    if (agentRunner == null) return;
    _agentRecover();
    _agentThen(_agentLook);
  }

  void _stopAgent() {
    _agentStopTick();
    _agent.live?.cancel();
  }

  /// A job that this device ran when Grove closed (a crash, or a quit) is
  /// over: `claude` stopped with Grove.
  void _agentRecover() {
    final device = prefs.getString(_deviceKey);
    if (device == null) return;
    final jobs = repos.agentJobs;
    var changed = false;
    for (final status in [AgentStatus.running, AgentStatus.cancelRequested]) {
      for (final j in _try(() => jobs.withStatus(status)) ?? <AgentJob>[]) {
        if (j.runnerDevice != device) continue;
        final cancel = status == AgentStatus.cancelRequested;
        final message = cancel ? AgentNote.cancelled : AgentNote.crashed;
        final stopped =
            _try(
              () => jobs.setStatus(
                j.id,
                cancel ? AgentStatus.cancelled : AgentStatus.failed,
                error: message,
                from: {status},
              ),
            ) ??
            false;
        if (stopped) _agentLine(j.id, AgentEventKind.stopped, message);
        changed |= stopped;
      }
    }
    if (changed) _bump();
  }

  /// Looks for `claude`, then runs the queue when this device runs agent
  /// tasks.
  Future<void> _agentLook() async {
    final runner = agentRunner;
    if (runner == null) return;
    final turn = ++_agent.lookTurn;
    String? exe;
    try {
      exe = await runner.locate();
    } on Exception {
      exe = null;
    }
    if (_disposed || turn != _agent.lookTurn) return;
    _agent
      ..exe = exe
      ..looked = true;
    _changed();
    if (!_agentCanWork) return;
    _agentArmTick();
    await _agentDrain();
  }

  void _agentArmTick() {
    if (_agent.tick != null || _disposed) return;
    final sleep = _agent.tick = _Sleep(agentTick, newTimer);
    sleep.done.then((_) {
      if (!identical(_agent.tick, sleep)) return;
      _agent.tick = null;
      if (!_agentCanWork) return;
      _agentArmTick();
      unawaited(runAgentQueue());
    });
  }

  void _agentStopTick() {
    final sleep = _agent.tick;
    _agent.tick = null;
    sleep?.cancel();
  }

  /// Rows came in from another device: maybe a new job, or a cancel.
  void _agentAfterPull() {
    if (_agentCanWork) unawaited(runAgentQueue());
  }

  Future<void> _agentDrain() async {
    final tried = <String>{};
    do {
      _agent.again = false;
      while (_agentCanWork) {
        final queued = _try(repos.agentJobs.queued) ?? const <AgentJob>[];
        final next = queued.where((j) => !tried.contains(j.id)).firstOrNull;
        if (next == null) break;
        tried.add(next.id);
        await _agentRun(next);
      }
    } while (_agent.again && _agentCanWork);
  }

  /// The most step lines of one run. Later steps are not saved.
  static const maxAgentSteps = 300;

  /// Runs one job: claim, (probe for Gmail), `claude`, then the notes.
  Future<void> _agentRun(AgentJob job) async {
    final runner = agentRunner;
    final exe = _agent.exe;
    if (runner == null || exe == null) return;
    final jobs = repos.agentJobs;
    if (!(_try(() => jobs.claim(job.id, _agentDevice)) ?? false)) return;
    _bump();
    _agent.liveJob = job.id;
    try {
      final taskId = job.taskId;
      final task = taskId == null ? null : this.task(taskId);
      if (taskId != null && task == null) {
        return _agentFail(job.id, AgentNote.taskGone);
      }
      final email = job.emailAccess && agentEmailOn;
      final files = _agentFiles(job);
      final List<String> args;
      if (email) {
        final line = await runner.probeInit(exe, AgentPolicy.probeArgs());
        if (_disposed) return;
        final init = line == null ? null : AgentPolicy.parseInit(line);
        // A connection that still starts may bring tools the probe did not
        // see.
        if (init != null && !init.ready) {
          return _agentFail(job.id, AgentPolicy.connectionsStarting);
        }
        if (init == null || !init.gmailReady) {
          return _agentFail(job.id, AgentPolicy.gmailNotReady);
        }
        args = AgentPolicy.args(
          email: true,
          gmailReadTools: init.gmailReadTools,
          otherConnectorTools: init.denied,
          otherServers: init.otherServers,
          files: files.here.isNotEmpty,
        );
      } else {
        args = AgentPolicy.args(email: false, files: files.here.isNotEmpty);
      }
      // A cancel during the probe.
      if (_try(() => jobs.get(job.id))?.status != AgentStatus.running) {
        return _agentCancelled(job.id);
      }
      final stdin = AgentPolicy.chatPrompt(
        _agentBrief(job, task, email: email, files: files),
      );
      var steps = 0;
      final process = _agent.live = runner.start(
        exe,
        args,
        stdin: stdin,
        timeout: AgentPolicy.timeout,
        files: files.here,
        onLine: (line) {
          if (_disposed) return;
          for (final step in AgentPolicy.stepsOf(line)) {
            if (++steps > maxAgentSteps) return;
            _agentLine(job.id, AgentEventKind.step, step.text, step.label);
          }
        },
      );
      final poll = _agentPoll(job.id, process);
      final AgentRunOutput out;
      try {
        out = await process.done;
      } finally {
        poll.stop();
      }
      if (_disposed) return;
      final now = _try(() => jobs.get(job.id));
      if (now == null) return;
      if (out.cancelled || now.status == AgentStatus.cancelRequested) {
        return _agentCancelled(job.id);
      }
      if (out.timedOut) return _agentFail(job.id, AgentNote.timedOut);
      if (out.stdout.trim().isEmpty) {
        return _agentFail(job.id, AgentNote.noAnswer(out.stderr));
      }
      switch (AgentPolicy.parseStream(out.stdout)) {
        case AgentFailed(:final message):
          _agentFail(job.id, message);
        case AgentOk(:final result):
          _agentDone(
            now,
            task,
            AgentResult(
              summary: result.summary,
              steps: result.steps,
              document: result.document,
              emailDraft: result.emailDraft,
              textDraft: result.textDraft,
              questions: [
                ...result.questions,
                if (job.emailAccess && !email) AgentNote.emailNotAllowed,
              ],
              sources: result.sources,
              planChanges: job.planAccess ? result.planChanges : const [],
              newTasks: job.planAccess ? result.newTasks : const [],
            ),
          );
      }
    } on Exception catch (e) {
      if (!_disposed) _agentFail(job.id, 'The agent could not run: $e');
    } finally {
      _agent
        ..liveJob = null
        ..live = null;
    }
  }

  /// The linked files of [job]: the ones this computer keeps, and the names
  /// of the ones on another device.
  ({List<AgentFile> here, List<String> elsewhere}) _agentFiles(AgentJob job) {
    final dir = _agentFilesDir;
    final device = prefs.getString(_deviceKey);
    final here = <AgentFile>[], elsewhere = <String>[];
    final sep = Platform.pathSeparator;
    for (final l in job.links) {
      if (l.kind != AgentLinkKind.file) continue;
      final path = '$dir$sep${l.id}$sep${AgentPolicy.safeName(l.name)}';
      // Links sync, so the id may come from anywhere: only a uuid, and a
      // path inside the folder.
      if (dir != null &&
          AgentScope.isId(l.id) &&
          AgentScope.isInside(dir, path, sep: sep) &&
          l.device == device &&
          File(path).existsSync()) {
        here.add(AgentFile(name: l.name, path: path));
      } else {
        elsewhere.add(l.name);
      }
    }
    return (here: here, elsewhere: elsewhere);
  }

  /// What the run knows: the chat so far, the task, the linked notes and
  /// tasks, the files, and the plan when the person shared it.
  AgentBrief _agentBrief(
    AgentJob job,
    TaskItem? task, {
    required bool email,
    required ({List<AgentFile> here, List<String> elsewhere}) files,
  }) {
    final turns = <AgentTurn>[];
    for (final e in agentEvents(job.id)) {
      switch (e.kind) {
        case AgentEventKind.ask:
          turns.add(AgentTurn(person: true, text: e.body));
        case AgentEventKind.result:
          if (agentEventResult(e) case final r?) {
            turns.add(
              AgentTurn(
                person: false,
                text: [
                  r.summary.trim(),
                  if (r.questions.isNotEmpty)
                    'Questions: ${r.questions.join(' / ')}',
                ].join('\n'),
              ),
            );
          }
        case AgentEventKind.step || AgentEventKind.stopped:
          break;
      }
    }
    final linked = <AgentLinkedText>[];
    for (final l in job.links) {
      switch (l.kind) {
        case AgentLinkKind.note:
          final n = _try(() => repos.notes.get(l.id));
          if (n != null) {
            linked.add(
              AgentLinkedText(kind: 'note', name: n.title, text: n.body),
            );
          }
        case AgentLinkKind.task:
          final t = this.task(l.id);
          if (t != null) {
            linked.add(
              AgentLinkedText(
                kind: 'task',
                name: '${t.title} (id ${t.id})',
                text: [t.summary.trim(), t.notes.trim()].join('\n\n'),
              ),
            );
          }
        case AgentLinkKind.file:
          break;
      }
    }
    return AgentBrief(
      turns: turns,
      emailAccess: email,
      taskTitle: task?.title,
      taskNotes: task == null
          ? ''
          : [
              task.summary.trim(),
              task.notes.trim(),
            ].where((t) => t.isNotEmpty).join('\n\n'),
      linked: linked,
      files: AgentPolicy.fileNames([for (final f in files.here) f.name]),
      missingFiles: files.elsewhere,
      plan: job.planAccess ? _agentPlanText() : null,
    );
  }

  /// The plan for the agent: the next days, the deadlines and the open
  /// tasks.
  String _agentPlanText() {
    final now = clockNow();
    final today = DayKey.fromDate(now);
    final range = DayRange(today, today.adding(days: AgentContext.days - 1));
    final open = allOpenTasks();
    final top = [...open.byDay, ...open.noDay];
    final subs = [
      for (final t in top)
        for (final s in subtasks(t.id))
          if (s.status == TaskStatus.open) s,
    ];
    return AgentContext.plan(
      today: today,
      nowMinute: now.hour * 60 + now.minute,
      items: [
        for (final b in blocks(range))
          AgentPlanItem(
            day: b.day,
            start: b.startMinute,
            end: b.endMinute,
            title: b.title,
            taskId: b.taskId,
            isDone: b.isDone,
          ),
      ],
      deadlines: _try(() => repos.events.deadlines()) ?? const [],
      openTasks: [...top, ...subs],
    );
  }

  /// Adds a line to a chat. A line that cannot be saved is left out: the
  /// job goes on.
  void _agentLine(
    String jobId,
    AgentEventKind kind,
    String body, [
    String label = '',
  ]) {
    final saved = _try(() {
      repos.agentEvents.insert(
        AgentEvent(
          jobId: jobId,
          seq: repos.agentEvents.nextSeq(jobId),
          kind: kind,
          label: label,
          body: body,
        ),
      );
      return true;
    });
    if (saved ?? false) _bump();
  }

  /// Reads the job every [agentPoll] while it runs. A cancel that came from
  /// another device (or a job that is gone) stops `claude`.
  _AgentPoll _agentPoll(String jobId, AgentProcess process) {
    final poll = _AgentPoll();
    void arm() {
      final sleep = poll.sleep = _Sleep(agentPoll, newTimer);
      sleep.done.then((_) {
        if (poll.stopped || _disposed) return;
        final status = _try(() => repos.agentJobs.get(jobId))?.status;
        if (status != AgentStatus.running) {
          process.cancel();
          return;
        }
        arm();
      });
    }

    arm();
    return poll;
  }

  void _agentFail(String jobId, String message) {
    if (_disposed) return;
    final changed =
        _try(
          () => repos.agentJobs.setStatus(
            jobId,
            AgentStatus.failed,
            error: message,
            from: {AgentStatus.running, AgentStatus.cancelRequested},
          ),
        ) ??
        false;
    if (changed) _agentLine(jobId, AgentEventKind.stopped, message);
  }

  void _agentCancelled(String jobId) {
    if (_disposed) return;
    final changed =
        _try(
          () => repos.agentJobs.setStatus(
            jobId,
            AgentStatus.cancelled,
            error: AgentNote.cancelled,
            from: {AgentStatus.running, AgentStatus.cancelRequested},
          ),
        ) ??
        false;
    if (changed) {
      _agentLine(jobId, AgentEventKind.stopped, AgentNote.cancelled);
    }
  }

  /// Saves the result: a document note (when there is one), and for a job
  /// of a task the result note, both linked to the task. Then the result
  /// line, and the job is done.
  void _agentDone(AgentJob job, TaskItem? task, AgentResult result) {
    final stamp = clockStamp();
    final doc = result.document;
    final docNote = doc == null
        ? null
        : Note(
            title: task == null
                ? AgentNote.chatDocumentTitle(job.title, doc)
                : AgentNote.documentTitle(task, doc),
            body: task == null
                ? AgentNote.chatDocumentBody(doc)
                : AgentNote.documentBody(task, doc),
            createdAt: stamp,
          );
    final note = task == null
        ? null
        : Note(
            title: AgentNote.title(task),
            body: AgentNote.resultBody(
              task,
              result,
              document: docNote == null
                  ? null
                  : (id: docNote.id, title: docNote.title),
            ),
            createdAt: stamp,
          );
    final m = Mutation('Agent result');
    if (docNote != null) m.notes.add((before: null, after: docNote));
    if (note != null) m.notes.add((before: null, after: note));
    // Not `commit`: no undo for a write of the agent. `_apply` saves the
    // notes and their links to the task, like any new note.
    if (m.notes.isNotEmpty && !_apply(m, forward: true)) {
      return _agentFail(job.id, AgentNote.notSaved);
    }
    final json = jsonEncode(result.toJson());
    final changed =
        _try(
          () => repos.agentJobs.setStatus(
            job.id,
            AgentStatus.done,
            resultJson: json,
            resultNoteId: note?.id ?? docNote?.id,
            from: {AgentStatus.running},
          ),
        ) ??
        false;
    if (!changed) return;
    _agentLine(
      job.id,
      AgentEventKind.result,
      jsonEncode({
        ...result.toJson(),
        _docKey: ?docNote?.id,
        _noteKey: ?note?.id,
      }),
    );
  }
}

class _AgentPoll {
  _Sleep? sleep;
  bool stopped = false;

  void stop() {
    stopped = true;
    sleep?.cancel();
  }
}
