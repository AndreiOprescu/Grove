import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/agent/agent_policy.dart';
import '../core/agent/agent_runner.dart';

/// The real door to the `claude` command on a computer (ADR 0004).
///
/// - `claude` is looked for only in known places, never on the PATH.
/// - It starts with no shell, in a new temp folder, which is deleted at the
///   end. The folder is empty but for copies of the files the person linked
///   (ADR 0005).
/// - Cancel and the time limit stop it and the processes it started (its
///   MCP servers, found with `pgrep -P`): SIGTERM, then SIGKILL after
///   [killWait]. On Windows `taskkill /T /F` stops it and its children.
class ClaudeCliRunner extends AgentRunner {
  ClaudeCliRunner({
    Map<String, String>? environment,
    bool? windows,
    List<String>? systemPaths,
    this.killWait = const Duration(seconds: 3),
    this.probeTimeout = const Duration(seconds: 60),
  }) : environment = environment ?? Platform.environment,
       windows = windows ?? Platform.isWindows,
       systemPaths =
           systemPaths ??
           ((windows ?? Platform.isWindows) ? const [] : defaultSystemPaths);

  /// The places outside the home folder where an install puts `claude`.
  static const defaultSystemPaths = [
    '/opt/homebrew/bin/claude',
    '/usr/local/bin/claude',
  ];

  /// The folders a program needs to start its own helpers (node, git...).
  /// A Mac app that starts from the Finder has almost no PATH.
  static const extraPath = [
    '/usr/bin',
    '/bin',
    '/usr/sbin',
    '/sbin',
    '/opt/homebrew/bin',
    '/usr/local/bin',
  ];

  /// The environment of this app: HOME, USERPROFILE and PATH are read from it.
  final Map<String, String> environment;
  final bool windows;
  final List<String> systemPaths;

  /// How long a stopped process gets to end before it is killed.
  final Duration killWait;

  /// How long the probe waits for its first line.
  final Duration probeTimeout;

  /// The places where `claude` may be, the first one first. On Windows only
  /// `claude.exe`: a `.cmd` file needs a shell.
  List<String> get candidates {
    if (windows) {
      final profile = environment['USERPROFILE'];
      return [
        if (profile != null && profile.isNotEmpty)
          '$profile\\.local\\bin\\claude.exe',
        ...systemPaths,
      ];
    }
    final home = environment['HOME'];
    return [
      if (home != null && home.isNotEmpty) '$home/.local/bin/claude',
      ...systemPaths,
    ];
  }

  @override
  Future<String?> locate() async {
    for (final path in candidates) {
      try {
        final stat = await FileStat.stat(path);
        if (stat.type != FileSystemEntityType.file) continue;
        // Some x bit must be set on a Mac or Linux.
        if (!windows && stat.mode & 0x49 == 0) continue;
        return path;
      } on FileSystemException {
        continue;
      }
    }
    return null;
  }

  /// The environment of a run: this app's, with the folder of [exe] and the
  /// usual system folders added to PATH.
  Map<String, String> runEnvironment(String exe) {
    final sep = windows ? ';' : ':';
    final cut = exe.lastIndexOf(windows ? RegExp(r'[\\/]') : RegExp('/'));
    final dir = cut <= 0 ? null : exe.substring(0, cut);
    final key = windows
        ? environment.keys.firstWhere(
            (k) => k.toUpperCase() == 'PATH',
            orElse: () => 'PATH',
          )
        : 'PATH';
    final parts = <String>[];
    for (final p in [
      ?dir,
      ...(environment[key] ?? '').split(sep),
      if (!windows) ...extraPath,
    ]) {
      if (p.isNotEmpty && !parts.contains(p)) parts.add(p);
    }
    return {key: parts.join(sep)};
  }

  @override
  AgentProcess start(
    String exe,
    List<String> args, {
    required String stdin,
    required Duration timeout,
    List<AgentFile> files = const [],
    void Function(String line)? onLine,
  }) => _CliProcess(this, exe, args, stdin, timeout, files, onLine).._run();

  /// Copies [files] into [dir], with the names of
  /// [AgentPolicy.fileNames], the ones the prompt gives. A file that is gone
  /// is left out.
  static Future<void> _copyFiles(Directory dir, List<AgentFile> files) async {
    final names = AgentPolicy.fileNames([for (final f in files) f.name]);
    for (final (i, f) in files.indexed) {
      final name = names[i];
      try {
        await File(f.path).copy('${dir.path}${Platform.pathSeparator}$name');
      } on FileSystemException {
        // Gone: the agent is told the names it can read, and this one is
        // not there.
      }
    }
  }

  @override
  Future<String?> probeInit(String exe, List<String> args) async {
    Directory? tmp;
    Process? process;
    try {
      tmp = await Directory.systemTemp.createTemp('grove-agent-');
      final p = process = await Process.start(
        exe,
        args,
        workingDirectory: tmp.path,
        environment: runEnvironment(exe),
        runInShell: false,
      );
      p.stderr.listen((_) {}, onError: (_) {});
      _writeStdin(p, AgentPolicy.probePrompt);
      return await p.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .firstWhere((l) => l.trim().isNotEmpty)
          .timeout(probeTimeout);
    } on Object {
      // No line, a time out, or `claude` did not start.
      return null;
    } finally {
      final p = process;
      if (p != null) {
        unawaited(_stop(p));
        await p.exitCode.timeout(killWait * 2, onTimeout: () => -1);
      }
      await _delete(tmp);
    }
  }

  /// The pids in the output of `pgrep`, one a line. Other lines are left
  /// out.
  static List<int> parsePids(String text) => [
    for (final line in text.split('\n'))
      if (int.tryParse(line.trim()) case final pid? when pid > 0) pid,
  ];

  /// Asks [p] and every process under it (the MCP servers of `claude`) to
  /// stop, and kills those still there after [killWait]. The processes
  /// under it are found first: once [p] ends, they have another parent.
  Future<void> _stop(Process p) async {
    if (windows) {
      await Process.run('taskkill', [
        '/PID',
        '${p.pid}',
        '/T',
        '/F',
      ]).then((_) {}, onError: (_) {});
      return;
    }
    var ended = false;
    unawaited(p.exitCode.then((_) => ended = true, onError: (_) {}));
    final tree = await _under(p.pid);
    p.kill(ProcessSignal.sigterm);
    _signal(tree, ProcessSignal.sigterm);
    await Future<void>.delayed(killWait);
    // A process started since the first look, while [p] still ran.
    if (!ended) {
      for (final pid in await _under(p.pid)) {
        if (!tree.contains(pid)) tree.add(pid);
      }
      p.kill(ProcessSignal.sigkill);
    }
    _signal(tree, ProcessSignal.sigkill);
  }

  /// Every process under [pid]: its children, theirs, and so on. `pgrep`
  /// is a program of the system, so no shell is needed.
  static Future<List<int>> _under(int pid) async {
    final out = <int>[];
    final next = [pid];
    while (next.isNotEmpty && out.length < 200) {
      final parent = next.removeLast();
      try {
        final r = await Process.run('/usr/bin/pgrep', ['-P', '$parent']);
        for (final child in parsePids('${r.stdout}')) {
          if (child == pid || out.contains(child)) continue;
          out.add(child);
          next.add(child);
        }
      } on Object {
        // No pgrep: only [pid] itself is stopped.
      }
    }
    return out;
  }

  static void _signal(List<int> pids, ProcessSignal signal) {
    for (final pid in pids) {
      try {
        Process.killPid(pid, signal);
      } on Object {
        // Gone already.
      }
    }
  }

  static void _writeStdin(Process p, String text) {
    // A process that ends before it reads its input closes the pipe. That
    // is not an error of the run.
    unawaited(p.stdin.done.then((_) {}, onError: (_) {}));
    try {
      p.stdin.add(utf8.encode(text));
      unawaited(p.stdin.close().then((_) {}, onError: (_) {}));
    } on Object {
      // The pipe is already closed.
    }
  }

  static Future<void> _delete(Directory? dir) async {
    if (dir == null) return;
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // Left for the system to clean up.
    }
  }
}

class _CliProcess implements AgentProcess {
  _CliProcess(
    this.runner,
    this.exe,
    this.args,
    this.stdin,
    this.timeout,
    this.files,
    this.onLine,
  );

  final ClaudeCliRunner runner;
  final String exe;
  final List<String> args;
  final String stdin;
  final Duration timeout;
  final List<AgentFile> files;
  final void Function(String line)? onLine;

  final _done = Completer<AgentRunOutput>();
  Process? _process;
  Timer? _limit;
  bool _stopping = false;
  bool _cancelled = false;
  bool _timedOut = false;

  /// How long the output may still come after the process ended. A child of
  /// `claude` that keeps the pipe open must not hold the job.
  static const _drainWait = Duration(seconds: 5);

  @override
  Future<AgentRunOutput> get done => _done.future;

  @override
  void cancel() {
    if (_cancelled || _done.isCompleted) return;
    _cancelled = true;
    _stopNow();
  }

  void _stopNow() {
    final p = _process;
    if (p == null || _stopping) return;
    _stopping = true;
    unawaited(runner._stop(p));
  }

  Future<void> _run() async {
    Directory? tmp;
    final out = StringBuffer(), err = StringBuffer();
    var result = const AgentRunOutput(exitCode: -1, stdout: '', stderr: '');
    try {
      tmp = await Directory.systemTemp.createTemp('grove-agent-');
      await ClaudeCliRunner._copyFiles(tmp, files);
      if (_cancelled) return;
      final p = _process = await Process.start(
        exe,
        args,
        workingDirectory: tmp.path,
        environment: runner.runEnvironment(exe),
        runInShell: false,
      );
      if (_cancelled) _stopNow();
      _limit = Timer(timeout, () {
        if (_done.isCompleted) return;
        _timedOut = true;
        _stopNow();
      });
      // The output is kept as it came. Each whole line also goes to
      // [onLine] at once, so the steps show while the run works.
      var rest = '';
      void say(String l) {
        if (onLine == null || l.trim().isEmpty) return;
        try {
          onLine!(l);
        } on Object {
          // A step that could not be saved does not stop the run.
        }
      }

      final outDone = p.stdout
          .transform(utf8.decoder)
          .listen((chunk) {
            out.write(chunk);
            final lines = '$rest$chunk'.split('\n');
            rest = lines.removeLast();
            lines.forEach(say);
          }, onError: (_) {})
          .asFuture<void>()
          .then((_) => say(rest))
          .catchError((_) {});
      final errDone = p.stderr
          .transform(utf8.decoder)
          .listen(err.write, onError: (_) {})
          .asFuture<void>()
          .catchError((_) {});
      ClaudeCliRunner._writeStdin(p, stdin);
      final code = await p.exitCode;
      await Future.wait([outDone, errDone])
          .timeout(_drainWait, onTimeout: () => const []);
      result = AgentRunOutput(
        exitCode: code,
        stdout: out.toString(),
        stderr: err.toString(),
      );
    } on Object catch (e) {
      result = AgentRunOutput(
        exitCode: -1,
        stdout: out.toString(),
        stderr: 'Could not start $exe: $e',
      );
    } finally {
      _limit?.cancel();
      // The folder is gone before the run counts as done.
      await ClaudeCliRunner._delete(tmp);
      _finish(result);
    }
  }

  void _finish(AgentRunOutput o) {
    if (_done.isCompleted) return;
    _done.complete(
      AgentRunOutput(
        exitCode: o.exitCode,
        stdout: o.stdout,
        stderr: o.stderr,
        timedOut: _timedOut,
        cancelled: _cancelled && !_timedOut,
      ),
    );
  }
}
