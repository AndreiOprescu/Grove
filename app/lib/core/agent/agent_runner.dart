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

/// The door to the `claude` command (ADR 0004). Grove starts it with no
/// shell, in an empty folder. A test uses a fake one.
abstract class AgentRunner {
  /// The full path of `claude`, or null when this computer does not have it.
  Future<String?> locate();

  /// Starts [exe] with [args] and writes [stdin] to it, then closes stdin.
  /// The process is stopped after [timeout].
  AgentProcess start(
    String exe,
    List<String> args, {
    required String stdin,
    required Duration timeout,
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
  }) => throw UnsupportedError('This device cannot run the agent.');

  @override
  Future<String?> probeInit(String exe, List<String> args) async => null;
}
