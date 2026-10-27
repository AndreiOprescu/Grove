import 'agent_policy.dart';
import 'agent_services.dart';

/// How one run of `claude` ended.
class AgentRunOutput {
  const AgentRunOutput({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.timedOut = false,
    this.cancelled = false,
    this.files = const [],
    this.folderProblem,
    this.overflow = false,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  /// The run took longer than its time limit and was stopped.
  final bool timedOut;

  /// [AgentProcess.cancel] stopped the run.
  final bool cancelled;

  /// The files the agent made in its folder, relative to it with `/`
  /// between parts, sorted (ADR 0008). The linked files are not in it.
  final List<String> files;

  /// Why the folder of the run is not fine (too many files), or null.
  final String? folderProblem;

  /// The run printed more than the runner keeps, and was stopped.
  final bool overflow;

  @override
  bool operator ==(Object other) =>
      other is AgentRunOutput &&
      other.exitCode == exitCode &&
      other.stdout == stdout &&
      other.stderr == stderr &&
      other.timedOut == timedOut &&
      other.cancelled == cancelled &&
      _same(other.files, files) &&
      other.folderProblem == folderProblem &&
      other.overflow == overflow;

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    exitCode,
    stdout,
    stderr,
    timedOut,
    cancelled,
    Object.hashAll(files),
    folderProblem,
    overflow,
  );

  @override
  String toString() =>
      'AgentRunOutput($exitCode, timedOut: $timedOut, cancelled: $cancelled, '
      'overflow: $overflow, files: $files, folderProblem: $folderProblem)';
}

/// One `claude` process that was started.
abstract class AgentProcess {
  /// Completes when the process ended: by itself, at its time limit, or
  /// after [cancel].
  Future<AgentRunOutput> get done;

  /// Stops the process. Safe to call more than once, and after the end.
  void cancel();
}

/// A file that goes into the `inputs` folder of a run, so the agent can
/// read it.
class AgentFile {
  const AgentFile({required this.name, required this.path});

  /// The name in the folder of the run.
  final String name;

  /// Where the file is on this computer.
  final String path;

  @override
  bool operator ==(Object other) =>
      other is AgentFile && other.name == name && other.path == path;

  @override
  int get hashCode => Object.hash(name, path);
}

/// The door to the `claude` command (ADR 0004). Grove starts it with no
/// shell, in the folder of the chat (ADR 0008). A test uses a fake one.
abstract class AgentRunner {
  /// The full path of `claude`, or null when this computer does not have it.
  Future<String?> locate();

  /// Starts [exe] with [args] and writes [stdin] to it, then closes stdin.
  /// The process is stopped after [timeout].
  ///
  /// - It runs in [folder], made when missing and kept after the run
  ///   (ADR 0008). Null: a new temp folder, deleted after the run.
  /// - The folder is checked before and after the run
  ///   (`AgentScope.audit`); the output lists the files the agent made.
  /// - [files] are copied into its `inputs` folder first (ADR 0005).
  /// - [onLine] gets each line of the output while the run goes on.
  AgentProcess start(
    String exe,
    List<String> args, {
    required String stdin,
    required Duration timeout,
    String? folder,
    List<AgentFile> files = const [],
    void Function(String line)? onLine,
  });

  /// Starts [exe] with [args], returns the first line it prints, and stops
  /// it. Null when it printed nothing. Used for the `init` event, which
  /// lists the tools, before the model is called.
  Future<String?> probeInit(String exe, List<String> args);

  /// Why the Claude Code settings of the person must not load in a run
  /// with services (`AgentScope.settingsProblem`), or null when they may.
  Future<String?> settingsProblem() async => null;

  /// The MCP servers of the person and their tools: the `init` event of a
  /// probe ([AgentPolicy.probeArgs]). Null when [exe] gave no such line.
  Future<AgentServices?> listServices(String exe) async {
    final line = await probeInit(exe, AgentPolicy.probeArgs());
    return line == null ? null : AgentServices.parseInit(line);
  }
}

/// Has no `claude`. Used on a phone and in tests.
class NullAgentRunner extends AgentRunner {
  @override
  Future<String?> locate() async => null;

  @override
  AgentProcess start(
    String exe,
    List<String> args, {
    required String stdin,
    required Duration timeout,
    String? folder,
    List<AgentFile> files = const [],
    void Function(String line)? onLine,
  }) => throw UnsupportedError('This device cannot run the agent.');

  @override
  Future<String?> probeInit(String exe, List<String> args) async => null;
}
