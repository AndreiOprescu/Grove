part of 'app_store.dart';

/// The theme, light or dark, and the motion switch (PLAN §6, §5.8). They are
/// view settings of this device, so they live in [AppStore.prefs] like the
/// planner settings.
extension AppStoreAppearance on AppStore {
  /// Light, dark or system. Saved.
  void setAppearance(AppearanceMode mode) {
    if (mode == _appearance) return;
    _appearance = mode;
    prefs.set('appearance.mode', mode.id);
    _changed();
  }

  /// Switches live. The screens cross-fade the colours.
  void setTheme(ThemeId id) {
    if (id == _themeId) return;
    _themeId = id;
    prefs.set('appearance.theme', id.id);
    _changed();
  }

  void nextTheme() => setTheme(_themeId.next);

  void setMotion(bool on) {
    _motionSetting = on;
    prefs.set('appearance.motion', on);
    showToast(on ? 'Motion on' : 'Motion off');
  }

  /// How strong the moving circles look, 0 to 1.5. 1 is the theme as designed.
  /// Saved in `appearance.intensity`.
  double get intensity => (prefs.getDouble('appearance.intensity') ?? 1.0)
      .clamp(SettingsRules.minIntensity, SettingsRules.maxIntensity);

  void setIntensity(double value) {
    prefs.set(
      'appearance.intensity',
      value.clamp(SettingsRules.minIntensity, SettingsRules.maxIntensity),
    );
    _changed();
  }

  /// How many of a day's tasks are done. Tasks planned for that day count;
  /// cancelled ones do not.
  PlantProgress plantProgress(DayKey day) {
    final tasks = _try(() => repos.tasks.forDay(day)) ?? const <TaskItem>[];
    return PlantProgress(
      done: tasks.where((t) => t.isDone).length,
      total: tasks.length,
    );
  }

  /// How many tasks are finished. The Garden plant grows with this number.
  int gardenDone() => _try(repos.tasks.doneCount) ?? 0;
}
