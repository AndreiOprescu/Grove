import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:grove/data/data.dart';
import 'package:grove/state/state.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/event.dart';
import 'package:grove/core/model/task.dart';
import 'package:grove/core/services/reminder_planner.dart';

export 'package:grove/core/model/block_subtask.dart';
export 'package:grove/core/model/day_key.dart';
export 'package:grove/core/model/event.dart';
export 'package:grove/core/model/goal.dart';
export 'package:grove/core/model/ids.dart';
export 'package:grove/core/model/link.dart';
export 'package:grove/core/model/note.dart';
export 'package:grove/core/model/recurrence.dart';
export 'package:grove/core/model/task.dart';
export 'package:grove/core/model/task_color.dart';
export 'package:grove/core/parsing/at_date.dart';
export 'package:grove/core/parsing/markdown_edit.dart';
export 'package:grove/core/parsing/markdown_spans.dart';
export 'package:grove/core/parsing/note_parser.dart';
export 'package:grove/core/parsing/palette_rules.dart';
export 'package:grove/core/parsing/quick_add_parser.dart';
export 'package:grove/core/parsing/reference_parser.dart';
export 'package:grove/core/parsing/utf16_range.dart';
export 'package:grove/core/planner/planner_layers.dart';
export 'package:grove/core/planner/planner_math.dart';
export 'package:grove/core/recurrence/recurrence_engine.dart';
export 'package:grove/core/services/focus_rules.dart';
export 'package:grove/core/services/garden.dart';
export 'package:grove/core/services/reminder_planner.dart';
export 'package:grove/data/data.dart';
export 'package:grove/state/state.dart';

/// A store on an empty database in memory. It is disposed after the test.
AppStore makeStore({
  Notifier? notifier,
  Prefs? prefs,
  Repos? repos,
  WallTime? clock,
  ReleaseSource? releases,
  WeatherSource? weather,
  LocationSource? location,
  AgentRunner? agentRunner,
  ActivitySource? activity,
  LoginItem? loginItem,
}) {
  final s = AppStore(
    repos: repos ?? Repos(Database.inMemory()),
    notifier: notifier,
    prefs: prefs,
    releaseSource: releases,
    weatherSource: weather,
    locationSource: location,
    agentRunner: agentRunner,
    activitySource: activity,
    loginItem: loginItem,
  );
  s.clockOverride = clock;
  addTearDown(s.dispose);
  return s;
}

/// A notification centre that only writes down what the store asks for.
class FakeNotifier extends Notifier {
  FakeNotifier({
    this.status = NotifyAuthorization.allowed,
    this.answer = NotifyAuthorization.allowed,
  });

  NotifyAuthorization status;
  NotifyAuthorization answer;
  final List<List<Reminder>> sent = [];
  int asked = 0;
  final List<FocusEnd> focusEnds = [];
  int focusCancels = 0;

  @override
  Future<NotifyAuthorization> authorization() async => status;

  @override
  Future<NotifyAuthorization> requestAuthorization() async {
    asked += 1;
    status = answer;
    return answer;
  }

  @override
  Future<void> replaceAll(List<Reminder> reminders) async =>
      sent.add(reminders);

  @override
  Future<void> scheduleFocusEnd(FocusEnd end) async => focusEnds.add(end);

  @override
  Future<void> cancelFocusEnd() async => focusCancels += 1;
}

/// A short way to write a day.
DayKey d(String s) => DayKey(s);

List<String> titles(Iterable<TaskItem> tasks) => [
  for (final t in tasks) t.title,
];

List<String> ids(Iterable<TaskItem> tasks) => [for (final t in tasks) t.id];

List<String> eventTitles(Iterable<EventItem> events) => [
  for (final e in events) e.title,
];

/// Waits for real time to pass (timers in the store use the real clock).
Future<void> wait(int milliseconds) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

/// Timers that run only when a test says that time passed. Give [start] to
/// `AppStore.newTimer`: then no wait of the store depends on the real clock,
/// and a test cannot fail on a slow machine.
class ManualTimers {
  Duration _now = Duration.zero;
  final _timers = <_ManualTimer>[];

  /// How many timers wait for their time.
  int get waiting => _timers.length;

  /// A timer that calls [callback] one time, when [length] has passed.
  Timer start(Duration length, void Function() callback) {
    final timer = _ManualTimer(this, _now + length, callback);
    _timers.add(timer);
    return timer;
  }

  /// Lets [time] pass. Each timer whose time comes runs now, the earliest
  /// first. What a timer starts with `await` or `then` runs after this call:
  /// give the event loop one turn (`World.pass` does both).
  void pass(Duration time) {
    final end = _now + time;
    while (true) {
      _ManualTimer? next;
      for (final t in _timers) {
        if (t.due <= end && (next == null || t.due < next.due)) next = t;
      }
      if (next == null) break;
      _now = next.due;
      next._run();
    }
    _now = end;
  }
}

class _ManualTimer implements Timer {
  _ManualTimer(this._owner, this.due, this._callback);

  final ManualTimers _owner;
  final Duration due;
  final void Function() _callback;
  int _ticks = 0;

  void _run() {
    _owner._timers.remove(this);
    _ticks = 1;
    _callback();
  }

  @override
  void cancel() => _owner._timers.remove(this);

  @override
  bool get isActive => _owner._timers.contains(this);

  @override
  int get tick => _ticks;
}

/// A release source that gives what the test puts in it.
class FakeReleases implements ReleaseSource {
  FakeReleases([this.release]);

  ReleaseInfo? release;
  bool fails = false;
  int asked = 0;

  @override
  Future<ReleaseInfo?> latest() async {
    asked++;
    if (fails) throw Exception('no network');
    return release;
  }
}

ReleaseInfo release(String version) => ReleaseInfo(
  version: AppVersion.parse(version)!,
  pageUrl: 'https://github.com/AndreiOprescu/Grove/releases/tag/v$version',
  files: {
    'grove-macos.zip':
        'https://github.com/AndreiOprescu/Grove/releases/download/v$version/grove-macos.zip',
  },
);

/// A forecast that only writes down what the store asks for. Each day from
/// [from] has rain, a low of 9° and a high of 14°, unless [days] says other.
class FakeWeather implements WeatherSource {
  FakeWeather({required this.from, this.count = 16, this.towns = const []});

  final DayKey from;
  final int count;
  final List<WeatherPlace> towns;
  Map<DayKey, DayWeather>? days;

  /// Set to make the next questions fail.
  Object? error;

  /// Each position asked for.
  final List<(double, double)> asked = [];
  final List<String> searched = [];

  /// Set to hold the answer until the test completes it.
  Completer<void>? gate;

  @override
  Future<Map<DayKey, DayWeather>> forecast(double lat, double lon) async {
    asked.add((lat, lon));
    await gate?.future;
    final e = error;
    if (e != null) throw e;
    return days ??
        {
          for (var i = 0; i < count; i++)
            from.adding(days: i): DayWeather(
              day: from.adding(days: i),
              condition: WeatherCondition.rain,
              low: 9,
              high: 14,
            ),
        };
  }

  @override
  Future<List<WeatherPlace>> search(String name) async {
    searched.add(name);
    final e = error;
    if (e != null) throw e;
    return towns;
  }
}

/// The position of this device in a test.
class FakeLocation implements LocationSource {
  FakeLocation([this.answer = const LocationAnswer.at(51.5072, -0.1276)]);

  LocationAnswer answer;
  int asked = 0;

  @override
  Future<LocationAnswer> here() async {
    asked += 1;
    return answer;
  }
}

/// One call of [FakeAgentRunner.start].
class AgentCall {
  AgentCall(this.exe, this.args, this.stdin, this.timeout);

  final String exe;
  final List<String> args;
  final String stdin;
  final Duration timeout;
}

/// A `claude` process of [FakeAgentRunner]. It ends when the test calls
/// [finish], or at [cancel].
class FakeAgentProcess implements AgentProcess {
  final _done = Completer<AgentRunOutput>();
  int cancels = 0;

  @override
  Future<AgentRunOutput> get done => _done.future;

  bool get isDone => _done.isCompleted;

  void finish(AgentRunOutput out) {
    if (!_done.isCompleted) _done.complete(out);
  }

  @override
  void cancel() {
    cancels += 1;
    finish(
      const AgentRunOutput(
        exitCode: -15,
        stdout: '',
        stderr: '',
        cancelled: true,
      ),
    );
  }
}

/// A `claude` door with scripted answers. It writes down what Grove asks.
class FakeAgentRunner extends AgentRunner {
  FakeAgentRunner({this.exe = '/fake/claude', this.initLine, this.output});

  /// What [locate] finds. Null: this computer has no `claude`.
  String? exe;

  /// The first line of the probe.
  String? initLine;

  /// How each run ends at once. Null: the run waits until the test calls
  /// `FakeAgentProcess.finish` on [processes].
  AgentRunOutput? output;

  int locates = 0;
  final List<List<String>> probes = [];
  final List<AgentCall> calls = [];
  final List<FakeAgentProcess> processes = [];

  @override
  Future<String?> locate() async {
    locates += 1;
    return exe;
  }

  @override
  Future<String?> probeInit(String exe, List<String> args) async {
    probes.add(args);
    return initLine;
  }

  @override
  AgentProcess start(
    String exe,
    List<String> args, {
    required String stdin,
    required Duration timeout,
  }) {
    calls.add(AgentCall(exe, args, stdin, timeout));
    final p = FakeAgentProcess();
    processes.add(p);
    final out = output;
    if (out != null) p.finish(out);
    return p;
  }
}

/// The use history of a device in a test: the events the test puts in it.
class FakeActivity implements ActivitySource {
  FakeActivity({this.name = 'android', this.answer = ActivityAccess.granted});

  @override
  final String name;

  ActivityAccess answer;
  final List<ActivityEvent> log = [];
  DateTime? alarm;

  /// How many times the store read the events, and opened the system page.
  int reads = 0;
  int opened = 0;

  final _changes = StreamController<void>.broadcast();

  /// The device is used again (the Mac woke up).
  void used() => _changes.add(null);

  /// One use from [from] to [to].
  void use(DateTime from, DateTime to) => log
    ..add(ActivityEvent(from, ActivitySignal.useStart))
    ..add(ActivityEvent(to, ActivitySignal.useEnd));

  @override
  Future<ActivityAccess> access() async => answer;

  @override
  Future<void> openAccessSettings() async => opened += 1;

  @override
  Future<List<ActivityEvent>> events(DateTime from, DateTime to) async {
    reads += 1;
    return [
      for (final e in log)
        if (!e.at.isBefore(from) && !e.at.isAfter(to)) e,
    ]..sort((a, b) => a.at.compareTo(b.at));
  }

  @override
  Future<DateTime?> nextAlarm() async => alarm;

  @override
  Stream<void> get changes => _changes.stream;
}

/// "Open Grove at login" in a test.
class FakeLoginItem implements LoginItem {
  FakeLoginItem([this.now = LoginItemStatus.notRegistered]);

  LoginItemStatus now;

  /// Thrown by the next [set], as the Mac does when it says no.
  Object? refusal;
  final List<bool> sets = [];

  @override
  Future<LoginItemStatus> status() async => now;

  @override
  Future<LoginItemStatus> set(bool on) async {
    sets.add(on);
    if (refusal case final r?) throw r;
    return now = on ? LoginItemStatus.enabled : LoginItemStatus.notRegistered;
  }
}
