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
}

/// The agent (ADR 0004): any device makes a job for a task, the job syncs,
/// and the computer with "This device runs agent tasks" on runs it with the
/// `claude` command. One job at a time. The result is a note linked to the
/// task (and a document note when the agent wrote one), so it syncs too.
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
    _changed();
  }

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

  /// Gives the task to the agent: a queued job that syncs to the computer
  /// that runs agent tasks. [email]: the person allows the agent to read
  /// their email for this task. Returns the id of the job, or an empty text
  /// when it could not be saved ([errorMessage] says why).
  String delegateToAgent(
    String taskId, {
    String instructions = '',
    bool email = false,
  }) {
    final job = AgentJob(
      taskId: taskId,
      instructions: instructions.trim(),
      emailAccess: email,
    );
    try {
      repos.agentJobs.insert(job);
    } on Exception catch (e) {
      errorMessage = 'Could not save: $e';
      return '';
    }
    _bump();
    if (_agentCanWork) unawaited(runAgentQueue());
    return job.id;
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
        changed |=
            _try(
              () => jobs.setStatus(
                j.id,
                cancel ? AgentStatus.cancelled : AgentStatus.failed,
                error: cancel ? AgentNote.cancelled : AgentNote.crashed,
                from: {status},
              ),
            ) ??
            false;
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
      final task = this.task(job.taskId);
      if (task == null) return _agentFail(job.id, AgentNote.taskGone);
      final email = job.emailAccess && agentEmailOn;
      final List<String> args;
      if (email) {
        final line = await runner.probeInit(exe, AgentPolicy.probeArgs());
        if (_disposed) return;
        final init = line == null ? null : AgentPolicy.parseInit(line);
        if (init == null || !init.gmailReady) {
          return _agentFail(job.id, AgentPolicy.gmailNotReady);
        }
        args = AgentPolicy.args(
          email: true,
          gmailReadTools: init.gmailReadTools,
          otherConnectorTools: init.denied,
        );
      } else {
        args = AgentPolicy.args(email: false);
      }
      // A cancel during the probe.
      if (_try(() => jobs.get(job.id))?.status != AgentStatus.running) {
        return _agentCancelled(job.id);
      }
      final notes = [
        task.summary.trim(),
        task.notes.trim(),
      ].where((t) => t.isNotEmpty).join('\n\n');
      final process = _agent.live = runner.start(
        exe,
        args,
        stdin: AgentPolicy.prompt(
          task.title,
          notes,
          job.instructions,
          emailAccess: email,
        ),
        timeout: AgentPolicy.timeout,
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
      switch (AgentPolicy.parse(out.stdout)) {
        case AgentFailed(:final message):
          _agentFail(job.id, message);
        case AgentOk(:final result):
          _agentDone(
            job.id,
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
    if (changed) _bump();
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
    if (changed) _bump();
  }

  /// Saves the result: a document note (when there is one) and the result
  /// note, both linked to the task, then the job is done.
  void _agentDone(String jobId, TaskItem task, AgentResult result) {
    final stamp = clockStamp();
    final doc = result.document;
    final docNote = doc == null
        ? null
        : Note(
            title: AgentNote.documentTitle(task, doc),
            body: AgentNote.documentBody(task, doc),
            createdAt: stamp,
          );
    final note = Note(
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
    m.notes.add((before: null, after: note));
    // Not `commit`: no undo for a write of the agent. `_apply` saves the
    // notes and their links to the task, like any new note.
    if (!_apply(m, forward: true)) {
      return _agentFail(jobId, AgentNote.notSaved);
    }
    final changed =
        _try(
          () => repos.agentJobs.setStatus(
            jobId,
            AgentStatus.done,
            resultJson: jsonEncode(result.toJson()),
            resultNoteId: note.id,
            from: {AgentStatus.running},
          ),
        ) ??
        false;
    if (changed) _bump();
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
