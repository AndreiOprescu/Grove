/// How one run of `claude` ended.
class AgentRunOutput {
  const AgentRunOutput({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.timedOut = false,
    this.cancelled = false,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  /// The run took longer than its time limit and was stopped.
  final bool timedOut;

  /// [AgentProcess.cancel] stopped the run.
  final bool cancelled;

  @override
  bool operator ==(Object other) =>
      other is AgentRunOutput &&
      other.exitCode == exitCode &&
      other.stdout == stdout &&
      other.stderr == stderr &&
      other.timedOut == timedOut &&
      other.cancelled == cancelled;

  @override
  int get hashCode =>
      Object.hash(exitCode, stdout, stderr, timedOut, cancelled);

  @override
  String toString() =>
      'AgentRunOutput($exitCode, timedOut: $timedOut, cancelled: $cancelled)';
}

/// One `claude` process that was started.
abstract class AgentProcess {
  /// Completes when the process ended: by itself, at its time limit, or
  /// after [cancel].
  Future<AgentRunOutput> get done;

  /// Stops the process. Safe to call more than once, and after the end.
  void cancel();
}

/// A file that goes into the folder of a run, so the agent can read it.
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
/// shell, in an empty folder. A test uses a fake one.
abstract class AgentRunner {
  /// The full path of `claude`, or null when this computer does not have it.
  Future<String?> locate();

  /// Starts [exe] with [args] and writes [stdin] to it, then closes stdin.
  /// The process is stopped after [timeout]. [files] are copied into the
  /// folder of the run first (ADR 0005). [onLine] gets each line of the
  /// output while the run goes on.
  AgentProcess start(
    String exe,
    List<String> args, {
    required String stdin,
    required Duration timeout,
    List<AgentFile> files = const [],
    void Function(String line)? onLine,
  });

  /// Starts [exe] with [args], returns the first line it prints, and stops
  /// it. Null when it printed nothing. Used for the `init` event, which
  /// lists the tools, before the model is called.
  Future<String?> probeInit(String exe, List<String> args);
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
    List<AgentFile> files = const [],
    void Function(String line)? onLine,
  }) => throw UnsupportedError('This device cannot run the agent.');

  @override
  Future<String?> probeInit(String exe, List<String> args) async => null;
}
