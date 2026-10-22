part of 'app_store.dart';

class _SleepState {
  /// What the device says about reading its use history.
  ActivityAccess access = ActivityAccess.unsupported;

  /// When the nights were last learned. A look sooner than
  /// [AppStoreSleep.sleepThrottle] after it reads nothing.
  DateTime? lastLook;

  /// The next alarm of this device. Kept in memory only: it never syncs.
  DateTime? nextAlarm;

  /// The look that runs now. Tests wait on it.
  Future<void>? work;

  /// The Mac says it is used again.
  StreamSubscription<void>? changes;

  /// "Open Grove at login" on the Mac, and why the last change failed.
  LoginItemStatus login = LoginItemStatus.unsupported;
  String? loginProblem;
}

/// The bedtime reminder (ADR 0006): Grove learns when the owner usually
/// falls asleep from the use of the phone and the Mac, and asks to plan
/// tomorrow some time before.
///
/// A night is one settings row (see [SleepNightRules]); each device writes
/// only its own part. Only these times leave the device, never what was
/// used. The rows and the two switches are written straight, not as undo
/// steps: they are not edits of the person.
extension AppStoreSleep on AppStore {
  static const _enabledKey = 'bedtime.enabled';
  static const _leadKey = 'bedtime.lead';

  /// Set after the first start of Grove on a Mac turned "Open Grove at
  /// login" on. A setting of this device.
  static const _loginAskedKey = 'mac.openAtLogin.asked';

  /// How long a look at the use history counts. A forced look reads anyway.
  static const sleepThrottle = Duration(minutes: 10);

  /// "Remind me to plan tomorrow before bed". On until the person turns it
  /// off on any device.
  bool get bedtimeEnabled => _try(() => repos.settings.get(_enabledKey)) != '0';

  void setBedtimeEnabled(bool on) {
    _setSleepSetting(_enabledKey, on ? '1' : '0');
  }

  /// Minutes before the usual bedtime, one of [BedtimePlanner.leadChoices].
  int get bedtimeLead {
    final v = int.tryParse(_try(() => repos.settings.get(_leadKey)) ?? '');
    return v != null && BedtimePlanner.leadChoices.contains(v)
        ? v
        : BedtimePlanner.defaultLead;
  }

  /// Only the choices on the list count (60, 90, 120).
  void setBedtimeLead(int minutes) {
    if (!BedtimePlanner.leadChoices.contains(minutes)) return;
    _setSleepSetting(_leadKey, '$minutes');
  }

  void _setSleepSetting(String key, String value) {
    try {
      repos.settings.set(key, value);
    } on Exception catch (e) {
      errorMessage = 'Could not save: $e';
      return;
    }
    _bump();
    scheduleReminderRefresh();
  }

  /// Can Grove read the use history of this device?
  ActivityAccess get activityAccess => _sleep.access;

  Future<void> refreshActivityAccess() async {
    final source = activitySource;
    if (source == null) return;
    try {
      _sleep.access = await source.access();
    } on Object {
      _sleep.access = ActivityAccess.unsupported;
    }
    _changed();
  }

  /// The page of the system where the person allows Usage access.
  Future<void> openActivityAccessSettings() async {
    try {
      await activitySource?.openAccessSettings();
    } on Object {
      // Nothing opens.
    }
  }

  /// The look at the use history that runs now, or null. Tests wait on it.
  Future<void>? get sleepWork => _sleep.work;

  /// Learns the last nights from the use of this device and saves the ones
  /// that changed. Looks at most once in [sleepThrottle] unless [force].
  /// Never throws: a failed look must not stop the reminders.
  Future<void> updateSleepNights({bool force = false}) {
    final previous = _sleep.work;
    return _sleep.work = () async {
      // One look at a time.
      await previous;
      await _lookAtUse(force: force);
    }();
  }

  Future<void> _lookAtUse({required bool force}) async {
    final source = activitySource;
    if (source == null || _disposed) return;
    final now = clockNow();
    final last = _sleep.lastLook;
    if (!force &&
        last != null &&
        !now.isBefore(last) &&
        now.difference(last) < sleepThrottle) {
      return;
    }
    try {
      // The next alarm needs no Usage access.
      _sleep.nextAlarm = await source.nextAlarm();
      final access = await source.access();
      if (access != _sleep.access) {
        _sleep.access = access;
        _changed();
      }
      if (access != ActivityAccess.granted) return;
      _sleep.lastLook = now;
      final today = DayKey.fromDate(now);
      final from = today.adding(days: -9).date.add(const Duration(hours: 12));
      final events = await source.events(from, now);
      if (_disposed) return;
      var wrote = false;
      for (var i = 8; i >= 1; i--) {
        final night = today.adding(days: -i);
        final part = SleepNightRules.derivePart(events, night, now);
        if (part == null) continue;
        final key = SleepNightRules.key(night);
        final json = SleepNightRules.merge(
          repos.settings.get(key),
          night,
          source.name,
          part,
        );
        if (json == null) continue;
        repos.settings.set(key, json);
        wrote = true;
      }
      if (wrote) _bump();
    } on Object catch (error) {
      assert(() {
        debugPrint('Grove sleep: $error');
        return true;
      }());
    }
  }

  /// The nights Grove knows, from every device, of the last weeks.
  Map<DayKey, SleepNight> sleepNights() {
    final first = clockToday.adding(days: -(SleepStats.sameWeekdaySpan + 7));
    final rows = _try(
      () => repos.db.query(
        'SELECT key, value FROM settings WHERE key >= ? AND key < ?',
        [SleepNightRules.key(first), SleepNightRules.prefixEnd],
        (r) => SleepNightRules.parse(r.text(0), r.text(1)),
      ),
    );
    return {
      for (final n in (rows ?? const <SleepNight?>[]).nonNulls) n.night: n,
    };
  }

  /// The bedtime reminders of the coming nights, as reminders. Empty when
  /// the switch is off.
  List<Reminder> _bedtimeReminders(WallTime now) {
    final enabled = bedtimeEnabled;
    if (!enabled) return const [];
    final planned = <DayKey, int>{};
    final days = DayRange(now.day, now.day.adding(days: 8));
    for (final e in eventItems(days)) {
      if (e.allDay) continue;
      planned.update(e.start.day, (n) => n + 1, ifAbsent: () => 1);
    }
    return [
      for (final b in BedtimePlanner.plan(
        now: now,
        lead: bedtimeLead,
        enabled: enabled,
        nights: sleepNights(),
        sleepLine: (day) => dayMarker(DayMarkerKind.sleep, day),
        wakeLine: (day) => dayMarker(DayMarkerKind.wake, day),
        plannedCount: (day) => planned[day] ?? 0,
        nextAlarm: _sleep.nextAlarm,
      ))
        b.reminder,
    ];
  }

  /// The usual bedtime of tonight and the time of its reminder, for the
  /// Settings. Before 12:00 tonight is the night that began yesterday.
  ({WallTime bedtime, WallTime reminder}) get usualBedtimeTonight {
    final now = reminderNow();
    final night = now.minute < 12 * 60 ? now.day.adding(days: -1) : now.day;
    final bedtime = BedtimePlanner.bedtime(
      night: night,
      nights: sleepNights(),
      sleepLine: dayMarker(DayMarkerKind.sleep, night),
      wakeLine: dayMarker(DayMarkerKind.wake, night.adding(days: 1)),
      nextAlarm: _sleep.nextAlarm,
    );
    return (
      bedtime: bedtime,
      reminder: ReminderPlanner.shifted(bedtime, by: -bedtimeLead),
    );
  }

  /// A click on a bedtime reminder: the planner on the day to plan, in front.
  void openPlannerFromNotification(DayKey day) {
    _selectedDay = day;
    screen = Screen.planner;
    bringToFront?.call();
  }

  // Open at login (Mac)

  /// "Open Grove at login". `unsupported` when this device has none.
  LoginItemStatus get openAtLogin => _sleep.login;

  /// Why the last change of "Open Grove at login" failed, or null.
  String? get openAtLoginProblem => _sleep.loginProblem;

  /// Asks the Mac again: the person can change it in System Settings.
  Future<void> refreshOpenAtLogin() async {
    final item = loginItem;
    if (item == null) return;
    try {
      _sleep.login = await item.status();
    } on Object {
      // It stays as it was.
    }
    _changed();
  }

  Future<void> setOpenAtLogin(bool on) async {
    final item = loginItem;
    if (item == null) return;
    try {
      _sleep.login = await item.set(on);
      _sleep.loginProblem = _sleep.login == LoginItemStatus.requiresApproval
          ? _approvalText
          : null;
    } on PlatformException catch (e) {
      try {
        _sleep.login = await item.status();
      } on Object {
        // It stays as it was.
      }
      _sleep.loginProblem =
          e.details == 'requiresApproval' ||
              _sleep.login == LoginItemStatus.requiresApproval
          ? _approvalText
          : 'Could not change it: ${e.message ?? e.code}';
    }
    _changed();
  }

  static const _approvalText =
      'Allow Grove in System Settings › General › Login Items.';

  /// The launch steps: the nights of this device are learned, and on the
  /// first start on a Mac open at login is turned on once.
  Future<void> startSleep() async {
    // First, so the reminders of the launch wait for the nights.
    final nights = updateSleepNights(force: true);
    final item = loginItem;
    if (item != null) {
      if (prefs.getBool(_loginAskedKey) != true) {
        prefs.set(_loginAskedKey, true);
        try {
          await item.set(true);
        } on Object {
          // The switch in Settings shows how it is.
        }
      }
      await refreshOpenAtLogin();
    }
    await nights;
  }

  /// Grove is in front again: the night that just ended, and the switch the
  /// person may have changed in System Settings.
  void resumeSleep() {
    unawaited(updateSleepNights(force: true));
    unawaited(refreshOpenAtLogin());
  }

  /// The Mac tells Grove when it is used again (after a sleep or a lock):
  /// the night that just ended is learned at once.
  void _watchActivity() {
    final source = activitySource;
    if (source == null) return;
    try {
      _sleep.changes = source.changes.listen((_) {
        if (_disposed) return;
        unawaited(
          updateSleepNights(force: true).then((_) => scheduleReminderRefresh()),
        );
      });
    } on Object {
      // A source with no news: the nights are learned on the next refresh.
    }
  }

  void _stopSleep() {
    unawaited(_sleep.changes?.cancel());
    _sleep.changes = null;
  }
}
