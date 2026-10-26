part of 'app_store.dart';

/// Moving around the window. The menu and the screen switch call these.
extension AppStoreNavigation on AppStore {
  /// View ▸ Today. The Planner and the Calendar stay where they are and move
  /// to today. Every other screen goes to the Today screen, and that screen
  /// shows today again. The timeline scrolls to the current time.
  void showToday() {
    _selectedDay = clockToday;
    if (_screen != Screen.planner && _screen != Screen.calendar) {
      _screen = Screen.today;
      _todayScreenDay = null;
    }
    todayRequest += 1;
  }

  /// The day on the Today screen: today, or tomorrow after the "Tomorrow"
  /// switch of its header. The store keeps the day and not a yes or no: after
  /// midnight that day is today, so the screen stays on the day the user
  /// looks at.
  DayKey get todayScreenDay {
    final today = clockToday;
    final chosen = _todayScreenDay;
    return chosen == today.adding(days: 1) ? chosen! : today;
  }

  /// The Today screen shows only tomorrow, to plan the next day. The choice
  /// lasts while the app runs.
  bool get showsTomorrow => todayScreenDay != clockToday;
  set showsTomorrow(bool on) {
    _todayScreenDay = on ? clockToday.adding(days: 1) : null;
    if (_screen == Screen.today) _selectedDay = todayScreenDay;
    _changed();
  }

  /// The panel open on the left of the Today and Planner screens, or null when
  /// none is. Saved in `shell.leftPane`.
  LeftPane? get leftPane =>
      LeftPane.fromSaved(prefs.getString(LeftPane.storageKey));
  set leftPane(LeftPane? pane) {
    prefs.set(LeftPane.storageKey, LeftPane.savedText(pane));
    _changed();
  }

  /// A click on a dock button: the same panel closes, any other one takes the
  /// place of the open one. The screen stays.
  void toggleLeftPane(LeftPane pane) =>
      leftPane = LeftPane.toggled(current: leftPane, tapped: pane);

  /// View ▸ Tasks: the Planner screen with the Tasks panel open.
  void showTasks() {
    leftPane = LeftPane.tasks;
    screen = Screen.planner;
  }

  /// View ▸ Goals Panel and Deadlines Panel: the panel on the screen the user is
  /// on. The Calendar, the Notes and the Garden have no left side, so they go
  /// to the Planner first.
  void showLeftPane(LeftPane pane) {
    leftPane = pane;
    if (!LeftPane.isAvailable(_screen)) screen = Screen.planner;
  }

  /// Opens [day] where it can be seen. Today goes to the Today screen, on
  /// today. Tomorrow stays on the Today screen when that screen shows it. Any
  /// other day opens the Planner on its week.
  void showDay(DayKey day) {
    final today = day == clockToday;
    if (today) _todayScreenDay = null;
    final shown = _screen == Screen.today && day == todayScreenDay;
    _selectedDay = day;
    screen = today || shown ? Screen.today : Screen.planner;
  }

  /// The height of one hour on the planner grid. Saved in `planner.hourHeight`.
  double get plannerHourHeight =>
      prefs.getDouble('planner.hourHeight') ?? PlannerLimits.defaultHourHeight;

  /// View ▸ Zoom In and Zoom Out. The planner reads the new height from the
  /// same setting.
  void zoomPlanner(double factor) {
    final next = plannerHourHeight * factor;
    prefs.set(
      'planner.hourHeight',
      min(PlannerLimits.maxHourHeight, max(PlannerLimits.minHourHeight, next)),
    );
    _changed();
  }

  /// File ▸ New Event: an event of the default length (Settings ▸ Planner, one
  /// hour at first) at the next free time of the chosen day. Its editor opens.
  void newEventNow() {
    // The Calendar and the Notes have no time grid.
    if (_screen != Screen.planner) showDay(_selectedDay);
    final workStart = prefs.getInt('planner.workStart') ?? 9 * 60;
    final length =
        prefs.getInt('planner.defaultLength') ??
        SettingsRules.defaultEventLength;
    final day = _selectedDay;
    final start = nextFreeSlot(
      day: day,
      length: length,
      workStart: workStart,
      step: PlannerMath.step,
    );
    if (start == null || start + length > 1440) {
      showToast('No free time left on this day.');
      return;
    }
    createFromDraft(
      title: 'New event',
      day: day,
      start: start,
      end: start + length,
      asEvent: true,
    );
    final id = _selection.isEmpty ? null : _selection.first;
    final e = id == null ? null : event(id);
    if (e != null) editEvent(e);
  }
}
