import 'package:grove/services/services.dart';

export 'package:grove/services/services.dart';

export '../state/support.dart';

/// A notification centre in memory. It keeps what the notifier asks for.
class FakeGateway implements NotificationGateway {
  FakeGateway({this.allowed = true, this.answer = true});

  /// What the system says now.
  bool allowed;

  /// What the user says to the question.
  bool answer;

  /// A notification the user clicked to open the app.
  NoteResponse? launch;

  /// Calls that fail from now on, by name ("pending", "schedule", ...).
  final Set<String> broken = {};

  /// Set false for a system that lists only the ids (Windows).
  bool listsText = true;

  final Map<int, NoteRequest> scheduled = {};
  final List<String> calls = [];
  int starts = 0;
  int questions = 0;
  void Function(NoteResponse response)? _onResponse;

  void _call(String name) {
    if (broken.contains(name)) throw StateError('$name is broken');
  }

  /// The user clicks a notification, or a button on it.
  void click({String? payload, String? actionId}) =>
      _onResponse!(NoteResponse(payload: payload, actionId: actionId));

  /// The schedule and cancel calls since the last time, then forgets them.
  List<String> takeCalls() {
    final result = [...calls];
    calls.clear();
    return result;
  }

  @override
  Future<void> start(void Function(NoteResponse response) onResponse) async {
    starts++;
    _call('start');
    _onResponse = onResponse;
  }

  @override
  Future<bool> permitted() async {
    _call('permitted');
    return allowed;
  }

  @override
  Future<bool> requestPermission() async {
    questions++;
    _call('requestPermission');
    return allowed = answer;
  }

  @override
  Future<List<PendingNote>> pending() async {
    _call('pending');
    return [
      for (final r in scheduled.values)
        listsText
            ? PendingNote(
                id: r.id,
                title: r.title,
                body: r.body,
                payload: r.payload,
              )
            : PendingNote(id: r.id),
    ];
  }

  @override
  Future<void> schedule(NoteRequest request) async {
    _call('schedule');
    calls.add('schedule ${request.id}');
    scheduled[request.id] = request;
  }

  @override
  Future<void> cancel(int id) async {
    _call('cancel');
    calls.add('cancel $id');
    scheduled.remove(id);
  }

  @override
  Future<NoteResponse?> launchResponse() async {
    _call('launchResponse');
    return launch;
  }
}

/// A tray that keeps what the service shows.
class FakeTray implements TrayGateway {
  FakeTray({this.supported = true});

  bool supported;
  bool visible = false;
  String tooltip = '';
  List<TrayEntry> menu = const [];
  int menus = 0;
  void Function()? _onClick;

  /// The menu as text. A line the user cannot click is in brackets.
  List<String> get lines => [
    for (final e in menu)
      e.isSeparator ? '---' : (e.onTap == null ? '(${e.label})' : e.label),
  ];

  /// The user clicks a line of the menu.
  void tap(String label) => menu.firstWhere((e) => e.label == label).onTap!();

  /// The user clicks the icon.
  void clickIcon() => _onClick?.call();

  @override
  bool show({required String tooltip, void Function()? onClick}) {
    if (!supported) return false;
    visible = true;
    this.tooltip = tooltip;
    _onClick = onClick;
    return true;
  }

  @override
  void setMenu(List<TrayEntry> entries) {
    menus++;
    menu = entries;
  }

  @override
  void setTooltip(String text) => tooltip = text;

  @override
  void dispose() => visible = false;
}
