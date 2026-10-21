part of 'app_store.dart';

/// What the update check found in this run of the app.
class _UpdateState {
  /// The newest release GitHub gave, or null.
  ReleaseInfo? found;

  /// "Later" was picked: no card until the next start.
  bool later = false;
  bool checking = false;
}

/// The update check: Grove asks GitHub for its newest release and shows a
/// card when it is newer than this copy. The person downloads the file and
/// installs it (owner's choice of 2026-10-19). `services/update_check.dart`
/// asks at start and every few hours.
extension AppStoreUpdates on AppStore {
  static const _checkKey = 'updates.check';
  static const _skippedKey = 'updates.skipped';

  /// The version of this copy of Grove.
  AppVersion get currentVersion => AppVersion.parse(GroveCore.version)!;

  /// False in a copy with no [AppStore.releaseSource].
  bool get canCheckForUpdates => releaseSource != null;

  /// The setting "Check for updates". On by default.
  bool get checksForUpdates => prefs.getBool(_checkKey) ?? true;
  set checksForUpdates(bool on) {
    prefs.set(_checkKey, on);
    _changed();
  }

  AppVersion? get _skipped =>
      AppVersion.parse(prefs.getString(_skippedKey) ?? '');

  /// The release the card shows, or null.
  ReleaseInfo? get availableUpdate {
    final found = _updates.found;
    if (found == null || _updates.later) return null;
    return UpdateRules.isNew(found, current: currentVersion, skipped: _skipped)
        ? found
        : null;
  }

  /// Asks GitHub for the newest release. The timer calls it with
  /// [manual] false: nothing then when the setting is off, and an error says
  /// nothing. A check by hand (Settings, the menu) always asks, brings back
  /// a skipped or later version, and gives the words to show.
  Future<String?> checkForUpdates({bool manual = false}) async {
    final source = releaseSource;
    if (source == null || _updates.checking) return null;
    if (!manual && !checksForUpdates) return null;
    _updates.checking = true;
    try {
      final release = await source.latest();
      if (isDisposed) return null;
      if (release != null) _updates.found = release;
      if (!manual) return null;
      final newer = release != null && release.version > currentVersion;
      if (!newer) return 'Grove $currentVersion is the newest version.';
      _updates.later = false;
      prefs.remove(_skippedKey);
      return 'Grove ${release.version} is here.';
    } on Object {
      return manual ? 'Grove could not reach GitHub. Try again later.' : null;
    } finally {
      _updates.checking = false;
      _changed();
    }
  }

  /// "Later": the card goes until Grove starts again.
  void laterUpdate() {
    _updates.later = true;
    _changed();
  }

  /// "Skip this version": the card comes back only for a newer version.
  void skipUpdate() {
    final found = _updates.found;
    if (found == null) return;
    prefs.set(_skippedKey, '${found.version}');
    _changed();
  }
}
