import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/agent/agent_policy.dart';
import '../core/agent/agent_runner.dart';
import '../core/agent/agent_scope.dart';

/// The real door to the `claude` command on a computer (ADR 0004).
///
/// - `claude` is looked for only in known places, never on the PATH.
/// - It starts with no shell, in the folder of the chat (ADR 0008), with
///   copies of the files the person linked in its `inputs` folder
///   (ADR 0005). The folder stays. Before and after the run, links and the
///   files Claude Code would load are removed from it.
/// - It gets only a few names of this app's environment ([keptNames]), so
///   no key or token of the app reaches it.
/// - Its output is kept up to [maxOutput]; more stops it.
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
    this.maxOutput = 20 * 1024 * 1024,
    List<String>? managedSettings,
  }) : environment = environment ?? Platform.environment,
       managedSettings = managedSettings ?? _managedSettings(),
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

  /// The names of the environment a run gets, on a Mac or Linux.
  static const keptNames = [
    'HOME',
    'USER',
    'LOGNAME',
    'PATH',
    'LANG',
    'TMPDIR',
    'SHELL',
  ];

  /// The names of the environment a run gets on Windows (in any case).
  static const keptWindowsNames = [
    'USERPROFILE',
    'APPDATA',
    'LOCALAPPDATA',
    'SystemRoot',
    'TEMP',
    'TMP',
    'HOMEDRIVE',
    'HOMEPATH',
    'USERNAME',
    'PATH',
  ];

  /// The names a run always gets, with their values (ADR 0008).
  ///
  /// `MCP_CONNECTION_NONBLOCKING=false`: `claude -p` 2.1.309 starts the
  /// MCP servers in the background, so its first line (the `init` event
  /// the probe reads) often lists none of them. With this it waits for
  /// them (each one at most 30 seconds), so the probe lists them and a
  /// run with services has their tools from the first turn. Live check,
  /// 2026-10-27. A run without services loads no MCP server, so it waits
  /// for nothing.
  ///
  /// `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`: no memory of Claude Code, in any
  /// run, whatever the settings of the person say. A run with services
  /// could otherwise write it, and it loads into the next run (review,
  /// 2026-10-27; `AgentPolicy.args` also denies its folder).
  static const setNames = {
    'MCP_CONNECTION_NONBLOCKING': 'false',
    'CLAUDE_CODE_DISABLE_AUTO_MEMORY': '1',
  };

  /// The settings files an admin puts on a computer. Claude Code always
  /// loads them, so they are checked like the person's own.
  static List<String> _managedSettings() {
    if (Platform.isMacOS) {
      return const [
        '/Library/Application Support/ClaudeCode/managed-settings.json',
      ];
    }
    if (Platform.isWindows) {
      return const [r'C:\Program Files\ClaudeCode\managed-settings.json'];
    }
    return const ['/etc/claude-code/managed-settings.json'];
  }

  /// The environment of this app: the [keptNames] are read from it.
  final Map<String, String> environment;
  final bool windows;
  final List<String> systemPaths;

  /// How long a stopped process gets to end before it is killed.
  final Duration killWait;

  /// How long the probe waits for its first line.
  final Duration probeTimeout;

  /// The most output a run may print. More stops it.
  final int maxOutput;

  /// The settings files of an admin, read by [settingsProblem] too.
  final List<String> managedSettings;

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

  /// The environment of a run: only the [keptNames] of this app's
  /// ([keptWindowsNames] on Windows), with the folder of [exe] and the usual
  /// system folders added to PATH, and the [setNames].
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
    final kept = {
      for (final n in windows ? keptWindowsNames : keptNames)
        if (n.toUpperCase() != 'PATH') windows ? n.toUpperCase() : n,
    };
    return {
      for (final MapEntry(:key, :value) in environment.entries)
        if (kept.contains(windows ? key.toUpperCase() : key)) key: value,
      key: parts.join(sep),
      ...setNames,
    };
  }

  /// The home folder: where `.claude` is.
  String? get _home {
    final home = environment[windows ? 'USERPROFILE' : 'HOME'];
    return home == null || home.isEmpty ? null : home;
  }

  @override
  Future<String?> settingsProblem() async {
    final home = _home;
    final sep = windows ? r'\' : '/';
    final files = [
      if (home != null)
        for (final name in ['settings.json', 'settings.local.json'])
          ('~$sep.claude$sep$name', '$home$sep.claude$sep$name'),
      for (final m in managedSettings) (m, m),
    ];
    for (final (name, path) in files) {
      final String? text;
      try {
        final f = File(path);
        text = await f.exists() ? await f.readAsString() : null;
      } on FileSystemException {
        return 'Grove could not read $name. Fix that file, or turn off "Use '
            'my services".';
      }
      if (AgentScope.settingsProblem(name, text) case final p?) return p;
    }
    return null;
  }

  @override
  AgentProcess start(
    String exe,
    List<String> args, {
    required String stdin,
    required Duration timeout,
    String? folder,
    List<AgentFile> files = const [],
    void Function(String line)? onLine,
  }) =>
      _CliProcess(this, exe, args, stdin, timeout, folder, files, onLine)
        .._run();

  /// Puts [files] in the `inputs` folder of [dir], with the names of
  /// [AgentPolicy.fileNames], the ones the prompt gives. The folder is made
  /// new each run. A file that is gone is left out.
  static Future<void> _copyFiles(Directory dir, List<AgentFile> files) async {
    final sep = Platform.pathSeparator;
    final inputs = Directory('${dir.path}$sep${AgentScope.inputs}');
    if (await FileSystemEntity.type(inputs.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      await _remove(inputs.path);
    }
    if (files.isEmpty) return;
    await inputs.create();
    final names = AgentPolicy.fileNames([for (final f in files) f.name]);
    for (final (i, f) in files.indexed) {
      try {
        await File(f.path).copy('${inputs.path}$sep${names[i]}');
      } on FileSystemException {
        // Gone: the agent is told the names it can read, and this one is
        // not there.
      }
    }
  }

  /// The most entries a check looks at. A folder with more is too big.
  static const _maxEntries = AgentScope.maxFiles * 10;

  /// Checks [dir] (`AgentScope.audit`): removes the links, odd entries and
  /// files Claude Code would load, and gives what is left. Null when the
  /// folder has too many entries to look at.
  static Future<AgentAudit?> _check(Directory dir) async {
    final sep = Platform.pathSeparator;
    final base = dir.path.endsWith(sep) ? dir.path : '${dir.path}$sep';
    final entries = <AgentEntry>[];
    final kinds = <String, FileSystemEntityType>{};
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (entries.length >= _maxEntries) return null;
      if (!e.path.startsWith(base)) continue;
      final rel = e.path.substring(base.length).replaceAll(sep, '/');
      final type = await FileSystemEntity.type(e.path, followLinks: false);
      kinds[rel] = type;
      entries.add(switch (type) {
        FileSystemEntityType.file => AgentEntry(
          rel,
          AgentEntryKind.file,
          await File(e.path).length(),
        ),
        FileSystemEntityType.directory => AgentEntry(
          rel,
          AgentEntryKind.folder,
        ),
        FileSystemEntityType.link => AgentEntry(rel, AgentEntryKind.link),
        _ => AgentEntry(rel, AgentEntryKind.other),
      });
    }
    // A folder before what is in it, as the audit needs.
    entries.sort((a, b) => a.path.compareTo(b.path));
    final audit = AgentScope.audit(entries);
    for (final rel in audit.remove) {
      await _remove('$base${rel.replaceAll('/', sep)}');
    }
    return audit;
  }

  /// Removes the entry at [path]: a link itself, never what it points to.
  static Future<void> _remove(String path) async {
    try {
      switch (await FileSystemEntity.type(path, followLinks: false)) {
        case FileSystemEntityType.directory:
          await Directory(path).delete(recursive: true);
        case FileSystemEntityType.link:
          await Link(path).delete();
        case FileSystemEntityType.notFound:
          break;
        default:
          await File(path).delete();
      }
    } on FileSystemException {
      // Checked again before the next run.
    }
  }

  /// The folder of a run: [path] made when missing. A link in its place is
  /// removed first.
  static Future<Directory> _folder(String path) async {
    if (await FileSystemEntity.type(path, followLinks: false) ==
        FileSystemEntityType.link) {
      await Link(path).delete();
    }
    return Directory(path).create(recursive: true);
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
        includeParentEnvironment: false,
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
    this.folder,
    this.files,
    this.onLine,
  );

  final ClaudeCliRunner runner;
  final String exe;
  final List<String> args;
  final String stdin;
  final Duration timeout;
  final String? folder;
  final List<AgentFile> files;
  final void Function(String line)? onLine;

  final _done = Completer<AgentRunOutput>();
  Process? _process;
  Timer? _limit;
  bool _stopping = false;
  bool _cancelled = false;
  bool _timedOut = false;
  bool _overflow = false;
  List<String> _files = const [];
  String? _folderProblem;

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
    Directory? tmp, dir;
    final out = StringBuffer(), err = StringBuffer();
    var result = const AgentRunOutput(exitCode: -1, stdout: '', stderr: '');
    try {
      final d = dir = switch (folder) {
        final f? => await ClaudeCliRunner._folder(f),
        null => tmp = await Directory.systemTemp.createTemp('grove-agent-'),
      };
      final before = await ClaudeCliRunner._check(d);
      if (before == null || before.overCap) {
        _folderProblem = AgentScope.tooBig;
        result = const AgentRunOutput(
          exitCode: -1,
          stdout: '',
          stderr: AgentScope.tooBig,
        );
        return;
      }
      await ClaudeCliRunner._copyFiles(d, files);
      if (_cancelled) return;
      final p = _process = await Process.start(
        exe,
        args,
        workingDirectory: d.path,
        environment: runner.runEnvironment(exe),
        includeParentEnvironment: false,
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
          .listen((all) {
            if (_overflow) return;
            var chunk = all;
            final room = runner.maxOutput - out.length;
            if (chunk.length > room) {
              // More than the runner keeps: stop the run.
              chunk = chunk.substring(0, room);
              _overflow = true;
              _stopNow();
            }
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
          .listen((chunk) {
            if (err.length < runner.maxOutput) err.write(chunk);
          }, onError: (_) {})
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
      // The folder is checked, or gone, before the run counts as done.
      if (dir != null && tmp == null && _folderProblem == null) {
        try {
          final after = await ClaudeCliRunner._check(dir);
          if (after == null || after.overCap) {
            _folderProblem = AgentScope.tooBig;
          }
          _files = after?.files ?? const [];
        } on FileSystemException {
          // The folder is checked again before the next run.
        }
      }
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
        files: _files,
        folderProblem: _folderProblem,
        overflow: _overflow,
      ),
    );
  }
}
