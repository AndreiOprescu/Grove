import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/model/block_subtask.dart';
import '../core/model/day_key.dart';
import '../core/model/event.dart';
import '../core/model/goal.dart';
import '../core/model/ids.dart';
import '../core/model/link.dart';
import '../core/model/note.dart';
import '../core/model/recurrence.dart';
import '../core/model/task.dart';
import '../core/model/task_color.dart';
import '../core/parsing/at_date.dart';
import '../core/parsing/note_parser.dart';
import '../core/parsing/palette_rules.dart';
import '../core/parsing/quick_add_parser.dart';
import '../core/parsing/reference_parser.dart';
import '../core/planner/planner_math.dart';
import '../core/recurrence/recurrence_engine.dart';
import '../core/services/focus_rules.dart';
import '../core/services/reminder_planner.dart';
import '../data/data.dart';
import 'editor_services.dart';
import 'mutation.dart';
import 'notifier.dart';
import 'prefs.dart';
import 'rules/all_tasks_rules.dart';
import 'rules/block_subtask_row.dart';
import 'rules/calendar_rules.dart';
import 'rules/day_range.dart';
import 'rules/day_rules.dart';
import 'rules/drag_payload.dart';
import 'rules/goal_rules.dart';
import 'rules/inspector_options.dart';
import 'rules/left_pane.dart';
import 'rules/meeting_note.dart';
import 'rules/mood.dart';
import 'rules/notes_rules.dart';
import 'rules/now_next.dart';
import 'rules/plant_math.dart';
import 'rules/planner_block.dart';
import 'rules/settings_rules.dart';
import 'rules/subtask_rules.dart';
import 'rules/task_placement.dart';
import 'rules/text.dart';
import 'screen.dart';
import 'theme_id.dart';

part 'store_appearance.dart';
part 'store_at_date.dart';
part 'store_block_subtasks.dart';
part 'store_calendar.dart';
part 'store_daily.dart';
part 'store_data.dart';
part 'store_editor.dart';
part 'store_events.dart';
part 'store_focus.dart';
part 'store_goals.dart';
part 'store_meeting.dart';
part 'store_menu_bar.dart';
part 'store_navigation.dart';
part 'store_note_tasks.dart';
part 'store_notes.dart';
part 'store_palette.dart';
part 'store_planner.dart';
part 'store_reminders.dart';
part 'store_roll_over.dart';
part 'store_tasks.dart';
part 'store_welcome.dart';

/// Runs a read. A read that fails gives null, so the screen shows nothing
/// instead of a crash.
T? _try<T>(T? Function() body) {
  try {
    return body();
  } on Exception {
    return null;
  }
}

/// A wait that can be cut short.
class _Sleep {
  _Sleep(Duration length) {
    _timer = Timer(length, _finish);
  }

  late final Timer _timer;
  final _completer = Completer<void>();

  Future<void> get done => _completer.future;

  void _finish() {
    if (!_completer.isCompleted) _completer.complete();
  }

  void cancel() {
    _timer.cancel();
    _finish();
  }
}

/// The state of the app: what is selected, what is on screen, and every change
/// to the data. Each change is a [Mutation], so it can be undone.
///
/// The parts are in the `store_*.dart` files, one per area.
class AppStore extends ChangeNotifier {
  AppStore({
    required this.repos,
    Notifier? notifier,
    Prefs? prefs,
    this.dataDir,
    this._errorMessage,
  }) : notifier = notifier ?? NullNotifier(),
       prefs = prefs ?? MemoryPrefs() {
    final p = this.prefs;
    _themeId = ThemeId.fromSaved(p.getString('appearance.theme'));
    _motionSetting = p.getBool('appearance.motion') ?? true;
    _appearance = AppearanceMode.fromSaved(p.getString('appearance.mode'));
    _notifyEnabled = p.getBool('notifications.enabled') ?? true;
    final lead = p.getInt('notifications.lead');
    _notifyLead = lead != null && ReminderPlanner.leadChoices.contains(lead)
        ? lead
        : ReminderPlanner.defaultLead;
    this.notifier.onOpen = (day, ref) =>
        openFromNotification(day: day, ref: ref);
    this.notifier.onFocusDone = focusDoneFromNotification;
    _welcomeVisible = FirstRun.welcomeVisible(repos);
  }

  /// Opens the database in [dataDir] and does the launch steps: the daily
  /// backup, the sweep of unused images, and the sample data of a new database.
  /// When the file cannot be opened, the store works in memory and says so.
  factory AppStore.open({
    required String dataDir,
    Notifier? notifier,
    Prefs? prefs,
  }) {
    final sep = Platform.pathSeparator;
    try {
      Directory(dataDir).createSync(recursive: true);
      final db = Database.open('$dataDir${sep}grove.sqlite');
      final repos = Repos(db);
      _try(
        () => Backup.runDaily(
          db,
          directory: '$dataDir${sep}Backups',
          today: DayKey.today(),
        ),
      );
      // After the backup: drop images that no text uses and that are over a day old.
      _try(() => repos.attachments.sweepOrphans());
      // A brand new database gets the three lists and the sample tasks. Before
      // anything else writes to it.
      _try(() => FirstRun.seedIfNew(repos, today: DayKey.today()));
      return AppStore(
        repos: repos,
        notifier: notifier,
        prefs: prefs ?? FilePrefs('$dataDir${sep}prefs.json'),
        dataDir: dataDir,
      );
    } on Exception {
      return AppStore(
        repos: Repos(Database.inMemory()),
        notifier: notifier,
        prefs: prefs,
        errorMessage:
            'Grove could not open its database. Changes will not be saved.',
      );
    }
  }

  final Repos repos;
  final Notifier notifier;

  /// Small settings of this device. Not in the database.
  final Prefs prefs;

  /// The folder with `grove.sqlite` and `Backups`. Null for a store in memory.
  final String? dataDir;

  /// How many days ahead Grove sets reminders.
  static const reminderDays = 14;

  /// How many rows the palette shows.
  static const paletteItemLimit = 10;

  bool _disposed = false;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _toastTimer?.cancel();
    for (final t in _lingerTimers) {
      t.cancel();
    }
    _reminderSleep?.cancel();
    _freshSleep?.cancel();
    super.dispose();
  }

  // What is on screen

  DayKey _selectedDay = DayKey.today();
  DayKey get selectedDay => _selectedDay;
  set selectedDay(DayKey v) {
    _selectedDay = v;
    _changed();
  }

  /// Bumped after every write so views reload.
  int _revision = 0;
  int get revision => _revision;
  void _bump() {
    _revision += 1;
    _changed();
  }

  /// Tasks just checked off that stay in the open list for a moment, so the
  /// burst can play (see `toggleDone`).
  Set<String> _lingering = {};
  Set<String> get lingering => Set.unmodifiable(_lingering);
  set lingering(Set<String> v) {
    _lingering = {...v};
    _changed();
  }

  final List<Timer> _lingerTimers = [];

  /// Selected planner block ids.
  Set<String> _selection = {};
  Set<String> get selection => Set.unmodifiable(_selection);
  set selection(Set<String> v) {
    _selection = {...v};
    _changed();
  }

  String? _toast;
  String? get toast => _toast;
  set toast(String? v) {
    _toast = v;
    _changed();
  }

  Timer? _toastTimer;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;
  set errorMessage(String? v) {
    _errorMessage = v;
    _changed();
  }

  /// The task shown in the inspector and highlighted in the task list.
  String? _selectedTaskId;
  String? get selectedTaskId => _selectedTaskId;
  set selectedTaskId(String? v) {
    _selectedTaskId = v;
    _changed();
  }

  /// Bumped by "new task". The task list focuses its quick-add field when this
  /// changes, or when the field appears and this is past [quickAddHandled].
  int _quickAddRequest = 0;
  int get quickAddRequest => _quickAddRequest;
  set quickAddRequest(int v) {
    _quickAddRequest = v;
    _changed();
  }

  int quickAddHandled = 0;

  /// The palette is on screen, and the text in its box.
  bool _paletteOpen = false;
  bool get paletteOpen => _paletteOpen;
  set paletteOpen(bool v) {
    _paletteOpen = v;
    _changed();
  }

  String _paletteText = '';
  String get paletteText => _paletteText;
  set paletteText(String v) {
    _paletteText = v;
    _changed();
  }

  /// Bumped by the palette command "Plan my day". The planner opens its plan
  /// when this passes [planMyDayHandled].
  int _planMyDayRequest = 0;
  int get planMyDayRequest => _planMyDayRequest;
  set planMyDayRequest(int v) {
    _planMyDayRequest = v;
    _changed();
  }

  int planMyDayHandled = 0;

  /// Set when a change takes a day past the daily limit. The planner shows it
  /// as an alert.
  String? _overloadWarning;
  String? get overloadWarning => _overloadWarning;
  set overloadWarning(String? v) {
    _overloadWarning = v;
    _changed();
  }

  /// Set when a change touches an event that repeats. The window asks "This
  /// event only / All events".
  RecurringPrompt? _recurringPrompt;
  RecurringPrompt? get recurringPrompt => _recurringPrompt;
  set recurringPrompt(RecurringPrompt? v) {
    _recurringPrompt = v;
    _changed();
  }

  /// The event the editor shows, or null.
  EditingEvent? _editingEvent;
  EditingEvent? get editingEvent => _editingEvent;
  set editingEvent(EditingEvent? v) {
    _editingEvent = v;
    _changed();
  }

  /// The goal block (an event id) whose subtask editor is open, or null.
  String? _editingBlockSubtasks;
  String? get editingBlockSubtasks => _editingBlockSubtasks;
  set editingBlockSubtasks(String? v) {
    _editingBlockSubtasks = v;
    _changed();
  }

  /// Which screen fills the window. The Today screen always shows today, so
  /// coming to it picks today.
  Screen _screen = Screen.today;
  Screen get screen => _screen;
  set screen(Screen v) {
    final old = _screen;
    _screen = v;
    if (v == Screen.today && old != Screen.today) _selectedDay = DayKey.today();
    _changed();
  }

  /// Counts the "go to now" requests. The timeline scrolls to the current time
  /// when it changes.
  int _todayRequest = 0;
  int get todayRequest => _todayRequest;
  set todayRequest(int v) {
    _todayRequest = v;
    _changed();
  }

  /// The note the notes screen shows.
  String? _selectedNoteId;
  String? get selectedNoteId => _selectedNoteId;
  set selectedNoteId(String? v) {
    _selectedNoteId = v;
    _changed();
  }

  NoteFilter _noteFilter = NoteFilter.all;
  NoteFilter get noteFilter => _noteFilter;
  set noteFilter(NoteFilter v) {
    _noteFilter = v;
    _changed();
  }

  String _noteQuery = '';
  String get noteQuery => _noteQuery;
  set noteQuery(String v) {
    _noteQuery = v;
    _changed();
  }

  /// The look of the window and the motion switch. Saved in [prefs] (see
  /// `store_appearance.dart`).
  late ThemeId _themeId;
  ThemeId get themeId => _themeId;
  late bool _motionSetting;
  bool get motionSetting => _motionSetting;

  /// Light, dark or the device's choice. Apart from the theme.
  late AppearanceMode _appearance;
  AppearanceMode get appearance => _appearance;

  /// Reminders (PLAN §5.6). Saved in [prefs]. The switch is on and the lead is
  /// 5 minutes until the user changes them.
  late bool _notifyEnabled;
  bool get notifyEnabled => _notifyEnabled;
  late int _notifyLead;
  int get notifyLead => _notifyLead;

  /// What the system says. It is `notAsked` until Grove asks.
  NotifyAuthorization _notifyStatus = NotifyAuthorization.notAsked;
  NotifyAuthorization get notifyStatus => _notifyStatus;

  /// How long a change waits before the reminders are made again. One second,
  /// so a burst of changes makes one refresh.
  Duration reminderDelay = const Duration(seconds: 1);

  /// A fixed "now" for tests. Null means the real clock.
  WallTime? clockOverride;

  /// The waiting reminder refresh. Tests wait on it.
  Future<void>? reminderTask;
  _Sleep? _reminderSleep;
  _Sleep? _freshSleep;

  /// The welcome card with the three sample tasks is on screen (PLAN §9).
  late bool _welcomeVisible;
  bool get welcomeVisible => _welcomeVisible;

  /// The running focus timer, or null (PLAN §5.1.7).
  FocusSession? _focus;
  FocusSession? get focus => _focus;

  /// The system question that follows the welcome card, and the notification
  /// calls of the focus timer. Tests wait on them.
  Future<void>? welcomeAsk;
  Future<void>? focusNotify;

  final List<Mutation> _undoStack = [];
  final List<Mutation> _redoStack = [];
  List<Mutation> get undoStack => List.unmodifiable(_undoStack);
  List<Mutation> get redoStack => List.unmodifiable(_redoStack);

  /// After an import every id in the window may be gone. Forget what was open,
  /// and the undo history.
  void resetAfterReplace() {
    _undoStack.clear();
    _redoStack.clear();
    _selection = {};
    _selectedTaskId = null;
    _selectedNoteId = null;
    _noteFilter = NoteFilter.all;
    _noteQuery = '';
    _editingEvent = null;
    _editingBlockSubtasks = null;
    _recurringPrompt = null;
    _overloadWarning = null;
    _lingering = {};
    stopFocus();
    _welcomeVisible = FirstRun.welcomeVisible(repos);
    _bump();
    scheduleReminderRefresh();
  }

  // Undo

  String? get undoName => _undoStack.isEmpty ? null : _undoStack.last.name;
  String? get redoName => _redoStack.isEmpty ? null : _redoStack.last.name;

  /// Applies a change, saves it, and records it for undo.
  bool commit(Mutation m) {
    if (m.isEmpty) return false;
    _addSubtasksOfDeletedBlocks(m);
    final days = _plannedDays(m);
    final before = {for (final d in days) d: plannedMinutes(d)};
    if (!_apply(m, forward: true)) return false;
    _warnIfOverloaded(days, before);
    final joined = _undoStack.isEmpty ? null : _undoStack.last.merged(m);
    if (joined != null) {
      _undoStack[_undoStack.length - 1] = joined;
    } else {
      _undoStack.add(m);
    }
    _redoStack.clear();
    if (_undoStack.length > 200) _undoStack.removeAt(0);
    return true;
  }

  /// Deleting a block also deletes its subtasks (the database does that).
  /// This puts them in the change, so undo brings them back.
  void _addSubtasksOfDeletedBlocks(Mutation m) {
    final deleted = [
      for (final e in m.events)
        if (e.after == null) ?e.before?.id,
    ];
    if (deleted.isEmpty) return;
    final subs = _try(() => repos.blockSubtasks.forEvents(deleted));
    if (subs == null || subs.isEmpty) return;
    final listed = {
      for (final c in m.blockSubtasks) ?(c.before ?? c.after)?.id,
    };
    for (final id in deleted) {
      for (final sub in subs[id] ?? const <BlockSubtaskItem>[]) {
        if (listed.add(sub.id)) m.blockSubtasks.add((before: sub, after: null));
      }
    }
  }

  // Busy-day limit

  /// Planned time per day above this many minutes triggers an alert. Default 9 hours.
  int get dailyLimitMinutes {
    final v = prefs.getInt('planner.dailyLimitMin') ?? 0;
    return v > 0 ? v : SettingsRules.defaultDailyLimit;
  }

  /// Minutes of the day that have at least one block. Overlaps count once.
  int plannedMinutes(DayKey day) {
    final covered = <int>{};
    for (final b in blocks(DayRange.single(day))) {
      for (var i = b.startMinute; i < b.endMinute; i++) {
        covered.add(i);
      }
    }
    return covered.length;
  }

  List<DayKey> _plannedDays(Mutation m) {
    final days = <DayKey>{};
    for (final e in m.events) {
      for (final ev in [e.before, e.after]) {
        if (ev != null && !ev.allDay) days.add(ev.start.day);
      }
    }
    return days.toList()..sort();
  }

  /// Alerts only when a change moves a day from within the limit to over it.
  void _warnIfOverloaded(List<DayKey> days, Map<DayKey, int> before) {
    final limit = dailyLimitMinutes;
    for (final day in days) {
      final after = plannedMinutes(day);
      if ((before[day] ?? 0) <= limit && after > limit) {
        overloadWarning =
            '${NotesRules.longDay(day)} has ${PlannerMath.duration(after)} planned. '
            'That is more than ${PlannerMath.duration(limit)}. '
            'Move or shorten something to leave room to rest.';
        return;
      }
    }
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    final m = _undoStack.removeLast();
    if (_apply(m, forward: false)) {
      _redoStack.add(m);
      showToast('Undid ${m.name}');
    }
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    final m = _redoStack.removeLast();
    if (_apply(m, forward: true)) {
      _undoStack.add(m);
      showToast('Redid ${m.name}');
    }
  }

  bool _apply(Mutation m, {required bool forward}) {
    T? target<T>(Change<T> c) => forward ? c.after : c.before;
    T? source<T>(Change<T> c) => forward ? c.before : c.after;
    try {
      repos.db.transaction(() {
        for (final t in m.tasks) {
          final x = target(t);
          if (x != null) repos.tasks.save(x);
        }
        for (final e in m.events) {
          final x = target(e);
          if (x != null) repos.events.save(x);
        }
        // After the events: a subtask needs its block.
        for (final b in m.blockSubtasks) {
          final x = target(b);
          if (x != null) repos.blockSubtasks.save(x);
        }
        for (final n in m.notes) {
          final x = target(n);
          if (x != null) repos.notes.save(x);
        }
        for (final g in m.goals) {
          final x = target(g);
          if (x != null) repos.goals.upsert(x);
        }
        for (final x in forward ? m.exdates : m.exdates.reversed) {
          if (x.add == forward) {
            repos.events.addExdate(x.eventId, x.day);
          } else {
            repos.events.removeExdate(x.eventId, x.day);
          }
        }
        final gone = {
          for (final t in m.tasks)
            if (target(t) == null) ?source(t)?.id,
        };
        for (final c in m.tags) {
          if (gone.contains(c.taskId)) continue;
          repos.tags.setTaskTags(c.taskId, forward ? c.after : c.before);
        }
        for (final b in m.blockSubtasks) {
          final id = source(b)?.id;
          if (target(b) == null && id != null) repos.blockSubtasks.delete(id);
        }
        for (final e in m.events) {
          final id = source(e)?.id;
          if (target(e) == null && id != null) repos.events.delete(id);
        }
        for (final n in m.notes) {
          final id = source(n)?.id;
          if (target(n) == null && id != null) repos.notes.delete(id);
        }
        for (final g in m.goals) {
          final id = source(g)?.id;
          if (target(g) == null && id != null) repos.goals.delete(id);
        }
        for (final t in m.tasks) {
          final id = source(t)?.id;
          if (target(t) == null && id != null) repos.tasks.delete(id);
        }
        _updateReferences(m, forward: forward);
      });
      _bump();
      scheduleReminderRefresh();
      return true;
    } on Exception catch (e) {
      errorMessage = 'Could not save: $e';
      return false;
    }
  }

  /// Keeps `[[mentions]]` in step with a change: links from a changed body,
  /// titles after a rename, and links that point at an item that was just
  /// brought back.
  void _updateReferences(Mutation m, {required bool forward}) {
    for (final t in m.tasks) {
      final now = forward ? t.after : t.before;
      if (now == null) continue;
      final was = forward ? t.before : t.after;
      final ref = ItemRef(ItemType.task, now.id);
      if (was == null || was.notes != now.notes) {
        final canonical = repos.refs.reindex(ref, now.notes);
        if (canonical != now.notes) {
          repos.tasks.save(now.copyWith(notes: canonical));
        }
      }
      if (was == null) repos.refs.rebuildIncoming(ref);
      if (was != null && was.title != now.title) {
        repos.refs.renamed(ref, now.title);
      }
      if (was == null || was.status != now.status) _syncBoxes(now);
    }
    for (final e in m.events) {
      final now = forward ? e.after : e.before;
      // Task blocks hold no text.
      if (now == null || now.kind != EventKind.event) continue;
      final was = forward ? e.before : e.after;
      final ref = ItemRef(ItemType.event, now.id);
      if (was == null || was.notes != now.notes) {
        final canonical = repos.refs.reindex(ref, now.notes);
        if (canonical != now.notes) {
          repos.events.save(now.copyWith(notes: canonical));
        }
      }
      if (was == null) repos.refs.rebuildIncoming(ref);
      if (was != null && was.title != now.title) {
        repos.refs.renamed(ref, now.title);
      }
    }
    for (final n in m.notes) {
      final now = forward ? n.after : n.before;
      if (now == null) continue;
      final was = forward ? n.before : n.after;
      final ref = ItemRef(ItemType.note, now.id);
      if (was == null || was.body != now.body) {
        final canonical = repos.refs.reindex(ref, now.body);
        if (canonical != now.body) {
          repos.notes.save(now.copyWith(body: canonical));
        }
        repos.tags.setNoteTags(now.id, NoteParser.tags(now.body));
      }
      if (was == null) repos.refs.rebuildIncoming(ref);
      if (was != null && was.title != now.title) {
        repos.refs.renamed(ref, now.title);
      }
    }
  }

  /// Puts the cursor in the quick-add field of the screen. The Planner opens
  /// the Tasks panel for it. Today shows its own list (a new task goes to
  /// today), so another panel there is closed.
  void requestQuickAdd() {
    leftPane = screen == Screen.planner ? LeftPane.tasks : null;
    quickAddRequest += 1;
  }

  void showToast(String text) {
    toast = text;
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2200), () => toast = null);
  }

  /// The minute of the day now, from the real clock.
  int nowMinute() {
    final now = DateTime.now();
    return now.hour * 60 + now.minute;
  }
}
