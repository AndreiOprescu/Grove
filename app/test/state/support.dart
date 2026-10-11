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
}) {
  final s = AppStore(
    repos: repos ?? Repos(Database.inMemory()),
    notifier: notifier,
    prefs: prefs,
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
