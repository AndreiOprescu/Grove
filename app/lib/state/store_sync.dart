part of 'app_store.dart';

/// Which box the login form shows.
enum LoginStep {
  /// The box for the email address.
  email,

  /// The email is sent. The box for the code of the email.
  code,
}

/// The answer to the question of the first login (question card Q-4).
enum FirstSyncChoice {
  /// "Use the data of the account": the data of this device is replaced.
  useAccount,

  /// "Add the data of this device to the account": nothing is replaced.
  addDevice,
}

/// What the sync does now, for one line on a screen.
enum SyncStatus {
  /// This build has no keys. Grove works with no sync.
  off,
  signedOut,

  /// Signed in. Grove looks what the account holds.
  checking,

  /// Signed in. Grove waits for the answer to the first-login question.
  question,
  syncing,

  /// The last sync did not work. See `syncError`.
  error,

  /// Signed in and the last sync worked.
  upToDate,
}

class _SyncState {
  SyncEngine? engine;
  StreamSubscription<Account?>? listener;
  Account? account;
  LoginStep step = LoginStep.email;
  String email = '';
  bool loginBusy = false;
  String? loginError;
  bool checking = false;
  bool question = false;

  /// The database is tied to the account. A sync can run.
  bool ready = false;
  bool syncing = false;
  String? error;
  List<String> skipped = const [];
  _Sleep? soon;

  /// Rises when the account changes. A late answer for the account before
  /// is dropped.
  int turn = 0;
  Future<void>? task;
}

/// The sync of this device with the account (cross-platform plan F11): the
/// login, the first-login question, when a sync runs, and what a screen can
/// show.
///
/// The database stays the source of truth. A sync runs after the login,
/// some seconds after a change ([AppStore.syncDelay]), and when
/// [syncNow] is called (the app does that on a timer and when it comes back
/// to the front, see `lib/services/sync_schedule.dart`).
extension AppStoreSync on AppStore {
  static const _lastSyncKey = 'sync.lastAt';

  // What a screen can show

  /// False: this build has no keys for a Supabase project, so there is no
  /// login and no sync.
  bool get syncAvailable => syncBackend != null;

  /// The person who is signed in, or null.
  Account? get syncAccount => _sync.account;
  bool get isSignedIn => _sync.account != null;

  LoginStep get loginStep => _sync.step;

  /// The address the login email went to.
  String get loginEmail => _sync.email;

  /// True while an email is sent or a code is checked.
  bool get loginBusy => _sync.loginBusy;
  String? get loginError => _sync.loginError;

  /// True: the device and the account both have data, and the person must
  /// choose ([answerFirstSync]). No sync runs before the answer.
  bool get firstSyncQuestion => _sync.question;

  bool get isSyncing => _sync.syncing;

  /// Why the last sync did not work, as a line for the screen. Null when it
  /// worked.
  String? get syncError => _sync.error;

  /// The rows of the last sync that this app could not use.
  List<String> get syncSkipped => _sync.skipped;

  /// When the last sync worked, or null.
  DateTime? get lastSyncAt {
    final ms = prefs.getInt(AppStoreSync._lastSyncKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// How many changes of this device wait for the next sync.
  int get syncWaiting => _try(() => _sync.engine?.outbox.count) ?? 0;

  SyncStatus get syncStatus {
    final s = _sync;
    if (!syncAvailable) return SyncStatus.off;
    if (s.account == null) return SyncStatus.signedOut;
    if (s.question) return SyncStatus.question;
    if (s.syncing) return SyncStatus.syncing;
    if (s.error != null) return SyncStatus.error;
    if (s.checking || !s.ready) return SyncStatus.checking;
    return SyncStatus.upToDate;
  }

  /// The work of the sync that runs now. Tests wait on it.
  Future<void>? get syncTask => _sync.task;

  // Start and stop

  void _startSync() {
    final backend = syncBackend;
    if (backend == null) return;
    _sync.engine = SyncEngine(repos: repos, remote: backend.remote(repos));
    _sync.listener = backend.auth.changes.listen(_accountChanged);
    final account = backend.auth.account;
    if (account != null) _accountChanged(account);
  }

  void _stopSync() {
    _sync.listener?.cancel();
    _sync.listener = null;
    _cancelSoon();
    _sync.turn += 1;
  }

  void _cancelSoon() {
    final sleep = _sync.soon;
    _sync.soon = null;
    sleep?.cancel();
  }

  void _accountChanged(Account? account) {
    final s = _sync;
    if (_disposed || account == s.account) return;
    s
      ..account = account
      ..turn += 1
      ..question = false
      ..checking = false
      ..ready = false
      ..error = null
      ..skipped = const []
      ..loginBusy = false
      ..loginError = null
      ..step = LoginStep.email;
    _cancelSoon();
    _changed();
    if (account != null) _track(_connect());
  }

  void _track(Future<void> work) {
    late final Future<void> task;
    task = work.whenComplete(() {
      if (identical(_sync.task, task)) _sync.task = null;
    });
    _sync.task = task;
  }

  // The login

  /// Sends the login email to [email]. True when it is sent: the form then
  /// asks for the code. False: [loginError] says why.
  Future<bool> sendLoginLink(String email) async {
    final backend = syncBackend;
    final s = _sync;
    if (backend == null || s.loginBusy) return false;
    final address = email.trim();
    if (!_looksLikeEmail(address)) {
      s.loginError = const AuthFailure(AuthProblem.badEmail).message;
      _changed();
      return false;
    }
    s
      ..loginBusy = true
      ..loginError = null;
    _changed();
    try {
      await backend.auth.sendLink(address);
      s
        ..email = address
        ..step = LoginStep.code;
      return true;
    } on AuthFailure catch (e) {
      s.loginError = e.message;
      return false;
    } finally {
      s.loginBusy = false;
      _changed();
    }
  }

  /// Signs in with the code of the email. False: [loginError] says why.
  Future<bool> verifyLoginCode(String code) async {
    final backend = syncBackend;
    final s = _sync;
    if (backend == null || s.loginBusy || s.step != LoginStep.code) {
      return false;
    }
    final digits = code.replaceAll(RegExp(r'\s'), '');
    if (digits.isEmpty) {
      s.loginError = const AuthFailure(AuthProblem.badCode).message;
      _changed();
      return false;
    }
    s
      ..loginBusy = true
      ..loginError = null;
    _changed();
    try {
      await backend.auth.verifyCode(email: s.email, code: digits);
      // A login that tells nothing on `changes` still counts.
      _accountChanged(backend.auth.account);
      return isSignedIn;
    } on AuthFailure catch (e) {
      s.loginError = e.message;
      return false;
    } finally {
      s.loginBusy = false;
      _changed();
    }
  }

  /// Back to the box for the email address.
  void changeLoginEmail() {
    _sync
      ..step = LoginStep.email
      ..loginError = null;
    _changed();
  }

  /// Signs out on this device. The data of this device stays, and so does
  /// the data of the account. No sync runs until the next login.
  Future<void> signOut() async {
    final backend = syncBackend;
    if (backend == null) return;
    try {
      await backend.auth.signOut();
    } on AuthFailure {
      // Signed out on this device all the same.
    }
    _accountChanged(backend.auth.account);
  }

  static bool _looksLikeEmail(String text) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text);

  // The first sync of a device with an account

  /// After a login: is this database tied to the account? If not, find out
  /// if there is a question to ask.
  Future<void> _connect() async {
    final s = _sync;
    final engine = s.engine;
    final account = s.account;
    if (engine == null || account == null) return;
    final turn = s.turn;
    final tied = _try(() => engine.account);
    if (tied == account.userId) {
      s.ready = true;
      _changed();
      return _runSync();
    }
    s
      ..checking = true
      ..error = null;
    _changed();
    try {
      final accountHasData = await engine.remoteHasData();
      if (turn != s.turn) return;
      s.checking = false;
      if (tied == null && !accountHasData) {
        // The first device of the account. Nothing to choose: the data of
        // the device goes to the account.
        engine.addDeviceTo(account.userId);
        s.ready = true;
        _changed();
        await _runSync();
        return;
      }
      if (!engine.hasLocalData) {
        // Nothing on this device that the person made. Nothing to choose.
        _changed();
        await _replace(account, turn);
        return;
      }
      s.question = true;
      _changed();
    } on Exception catch (e) {
      if (turn != s.turn) return;
      s
        ..checking = false
        ..error = _syncMessage(e);
      _changed();
    }
  }

  /// The answer to "this device has data and the account has data too".
  ///
  /// [FirstSyncChoice.useAccount]: a copy of the data of this device is
  /// saved first (`before-sync-<time>.sqlite` in the data folder), then the
  /// data of the account takes its place. [FirstSyncChoice.addDevice]: both stay;
  /// the sample lists and tasks of this device go to the account too.
  Future<void> answerFirstSync(FirstSyncChoice choice) async {
    final s = _sync;
    final engine = s.engine;
    final account = s.account;
    if (engine == null || account == null || !s.question || s.syncing) return;
    final turn = s.turn;
    switch (choice) {
      case FirstSyncChoice.addDevice:
        engine.addDeviceTo(account.userId);
        s
          ..question = false
          ..ready = true;
        _changed();
        final work = _runSync();
        _track(work);
        await work;
      case FirstSyncChoice.useAccount:
        final work = _replace(account, turn);
        _track(work);
        await work;
    }
  }

  Future<void> _replace(Account account, int turn) async {
    final s = _sync;
    final engine = s.engine!;
    s
      ..syncing = true
      ..error = null;
    _changed();
    try {
      final dir = dataDir;
      if (dir != null && engine.hasLocalData) {
        Backup.safetyCopy(
          repos.db,
          directory: dir,
          name: Backup.beforeSyncName(DateTime.now()),
        );
      }
      final report = await engine.replaceWithAccount(account.userId);
      if (_disposed) return;
      // An account with no "seeded" mark must not get the samples again at
      // the next start.
      if (repos.settings.get(FirstRun.doneKey) == null) {
        repos.settings.set(FirstRun.doneKey, '1');
      }
      s
        ..question = false
        ..ready = turn == s.turn
        ..skipped = report.skipped;
      _synced();
      resetAfterReplace();
      showToast('This device has the data of the account now.');
    } on Exception catch (e) {
      // The device keeps its data. The question stays, when there was one.
      s.error = _syncMessage(e);
    } finally {
      s.syncing = false;
      if (!_disposed) _changed();
    }
  }

  // The sync

  /// Syncs now, when a person is signed in and the first-login question is
  /// answered. Never throws: [syncError] says what went wrong.
  Future<void> syncNow() async {
    final s = _sync;
    if (s.engine == null || s.account == null || s.question) return;
    final running = s.task;
    if (running != null) return running;
    final work = s.ready ? _runSync() : _connect();
    _track(work);
    return work;
  }

  /// A change was made. Sends it some seconds later.
  void _syncSoon() {
    final s = _sync;
    if (!s.ready || _disposed) return;
    _cancelSoon();
    final sleep = s.soon = _Sleep(syncDelay, newTimer);
    sleep.done.then((_) {
      if (_disposed || !identical(s.soon, sleep)) return;
      s.soon = null;
      // A change of the screen only (or the rows a pull brought) is nothing
      // to send.
      if (syncWaiting == 0) return;
      syncNow();
    });
  }

  Future<void> _runSync() async {
    final s = _sync;
    final engine = s.engine;
    if (engine == null || !s.ready || s.syncing) return;
    final turn = s.turn;
    var worked = false;
    s.syncing = true;
    _changed();
    try {
      final report = await engine.sync();
      if (_disposed) return;
      worked = true;
      s
        ..error = null
        ..skipped = report.skipped;
      _synced();
      if (report.pulled > 0) _afterPull();
    } on Exception catch (e) {
      if (turn == s.turn) s.error = _syncMessage(e);
    } finally {
      s.syncing = false;
      if (!_disposed) {
        _changed();
        // A change made during the sync waits in the outbox. After an error
        // there is no new try at once: the next change, the timer of the
        // app or "Sync now" starts the next sync.
        if (worked && s.ready && syncWaiting > 0) _syncSoon();
      }
    }
  }

  void _synced() {
    prefs.set(AppStoreSync._lastSyncKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Rows came in from another device. What is open may be gone. The undo
  /// history stays: an undo is a new change, and it travels like any other.
  void _afterPull() {
    final task = _selectedTaskId;
    if (task != null && _try(() => repos.tasks.get(task)) == null) {
      _selectedTaskId = null;
    }
    final note = _selectedNoteId;
    if (note != null && _try(() => repos.notes.get(note)) == null) {
      _selectedNoteId = null;
    }
    _selection = {
      for (final id in _selection)
        if (_try(() => repos.tasks.get(id)) != null) id,
    };
    // Another device can still add block subtasks to a goal block.
    _adoptBlockSubtasks();
    final block = _selectedGoalBlockId;
    if (block != null && event(block)?.goalId == null) {
      _selectedGoalBlockId = null;
    }
    _welcomeVisible = _try(() => FirstRun.welcomeVisible(repos)) ?? false;
    _revision += 1;
    _changed();
    scheduleReminderRefresh();
  }

  static String _syncMessage(Object e) => switch (e) {
    RemoteUnavailable() => 'No connection. Grove syncs when you are online.',
    SchemaMismatch() =>
      'This Grove and the account do not have the same version. '
          'Update Grove on all devices.',
    NotSignedIn() => 'The login ended. Sign in again.',
    _ => 'The sync did not work: $e',
  };
}
