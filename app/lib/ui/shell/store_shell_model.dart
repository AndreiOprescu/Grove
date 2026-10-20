// The shell on the real app store (milestone F5). Most store methods are
// Dart extension methods, so the store cannot implement `ShellModel` itself.
import 'package:flutter/foundation.dart';

import '../../state/state.dart';
import 'shell_model.dart';

/// A [ShellModel] that passes every read and every action to an [AppStore].
/// It keeps nothing. The one who made the store closes it.
class StoreShellModel implements ShellModel {
  const StoreShellModel(this.store);

  final AppStore store;

  @override
  void addListener(VoidCallback listener) => store.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => store.removeListener(listener);

  @override
  Screen get screen => store.screen;

  @override
  set screen(Screen value) => store.screen = value;

  @override
  LeftPane? get leftPane => store.leftPane;

  @override
  ThemeId get themeId => store.themeId;

  @override
  AppearanceMode get appearance => store.appearance;

  @override
  bool get motionSetting => store.motionSetting;

  @override
  double get intensity => store.intensity;

  @override
  String? get toast => store.toast;

  @override
  void showToday() => store.showToday();

  @override
  void showTasks() => store.showTasks();

  @override
  void toggleLeftPane(LeftPane pane) => store.toggleLeftPane(pane);

  @override
  void showLeftPane(LeftPane pane) => store.showLeftPane(pane);

  @override
  void setTheme(ThemeId id) => store.setTheme(id);

  @override
  void nextTheme() => store.nextTheme();

  @override
  void setAppearance(AppearanceMode mode) => store.setAppearance(mode);

  @override
  void setMotion(bool on) => store.setMotion(on);

  @override
  void showToast(String text) => store.showToast(text);
}
