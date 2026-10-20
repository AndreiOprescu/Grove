// What the app shell needs to know and do: the screen, the open left panel,
// the theme, light or dark, motion, and the short message.
//
// The enums `Screen`, `LeftPane`, `ThemeId` and `AppearanceMode` are the ones
// of the state layer (app/lib/state/), so the engine and the screens share
// one set. This file passes them on.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../state/rules/left_pane.dart';
import '../../state/screen.dart';
import '../theme/theme_spec.dart';

export '../../state/rules/left_pane.dart' show LeftPane;
export '../../state/screen.dart' show Screen;
export '../theme/theme_spec.dart'
    show AppearanceBrightness, AppearanceMode, ThemeId;

/// What the shell reads and does. The shell listens to it and builds again
/// when it changes. `StoreShellModel` (store_shell_model.dart) passes it to
/// the app store. [LocalShellModel] keeps it in memory, for tests and for a
/// shell with no store.
abstract class ShellModel implements Listenable {
  Screen get screen;
  set screen(Screen value);

  /// The open left panel. null is closed.
  LeftPane? get leftPane;

  ThemeId get themeId;
  AppearanceMode get appearance;

  /// The Motion setting.
  bool get motionSetting;

  /// The Accent intensity setting, 0 to 1.5. 1 is the theme as designed.
  double get intensity;

  /// The short message at the bottom of the window. null is none.
  String? get toast;

  /// Cmd/Ctrl+T: the Planner and the Calendar stay open; any other screen
  /// goes to Today.
  void showToday();

  /// Cmd/Ctrl+2: the Planner with the Tasks panel.
  void showTasks();

  /// A click on a dock button.
  void toggleLeftPane(LeftPane pane);

  /// Opens a panel. Screens with no left side go to the Planner first.
  void showLeftPane(LeftPane pane);

  void setTheme(ThemeId id);
  void nextTheme();
  void setAppearance(AppearanceMode mode);
  void setMotion(bool on);
  void showToast(String text);
}

/// A [ShellModel] that lives in memory. Nothing is saved.
class LocalShellModel extends ChangeNotifier implements ShellModel {
  LocalShellModel({
    this._screen = Screen.today,
    this._themeId = ThemeId.initial,
    this._appearance = AppearanceMode.system,
    this._leftPane,
    this._motion = true,
  });

  /// How long a message stays.
  static const toastTime = Duration(milliseconds: 2200);

  Screen _screen;
  LeftPane? _leftPane;
  ThemeId _themeId;
  AppearanceMode _appearance;
  bool _motion;
  String? _toast;
  Timer? _toastTimer;

  @override
  Screen get screen => _screen;

  @override
  set screen(Screen value) {
    if (value == _screen) return;
    _screen = value;
    notifyListeners();
  }

  @override
  LeftPane? get leftPane => _leftPane;

  @override
  ThemeId get themeId => _themeId;

  @override
  AppearanceMode get appearance => _appearance;

  @override
  bool get motionSetting => _motion;

  @override
  double get intensity => 1;

  @override
  String? get toast => _toast;

  @override
  void showToday() {
    if (_screen == Screen.planner || _screen == Screen.calendar) return;
    screen = Screen.today;
  }

  @override
  void showTasks() => _open(LeftPane.tasks, on: Screen.planner);

  @override
  void toggleLeftPane(LeftPane pane) {
    _leftPane = LeftPane.toggled(current: _leftPane, tapped: pane);
    notifyListeners();
  }

  @override
  void showLeftPane(LeftPane pane) =>
      _open(pane, on: LeftPane.isAvailable(_screen) ? _screen : Screen.planner);

  void _open(LeftPane pane, {required Screen on}) {
    if (_screen == on && _leftPane == pane) return;
    _screen = on;
    _leftPane = pane;
    notifyListeners();
  }

  @override
  void setTheme(ThemeId id) {
    if (id == _themeId) return;
    _themeId = id;
    notifyListeners();
  }

  @override
  void nextTheme() => setTheme(_themeId.next);

  @override
  void setAppearance(AppearanceMode mode) {
    if (mode == _appearance) return;
    _appearance = mode;
    notifyListeners();
  }

  @override
  void setMotion(bool on) {
    _motion = on;
    showToast(on ? 'Motion on' : 'Motion off');
  }

  @override
  void showToast(String text) {
    _toast = text;
    _toastTimer?.cancel();
    _toastTimer = Timer(toastTime, () {
      _toast = null;
      notifyListeners();
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }
}
