import 'dart:async';

import '../core/model/day_key.dart';
import '../core/parsing/palette_rules.dart';
import '../state/state.dart';
import 'tray_gateway.dart';

/// The icon of Grove in the menu bar of the Mac and in the tray of Windows
/// (PLAN §5.7): what is on now, what is next, how much of today is done, and
/// the commands "Open Grove", "New task" and "Quit Grove".
class TrayService {
  TrayService({
    required this.store,
    required this.gateway,
    required this.showWindow,
    required this.quit,
    this.every = const Duration(seconds: 30),
    int Function()? minute,
  }) : _minute = minute ?? store.nowMinute;

  /// The wait after a change in the store. Many changes make one new menu.
  static const settle = Duration(milliseconds: 300);

  /// The longest tooltip. Windows cuts a tooltip at 127 characters.
  static const tooltipLimit = 120;

  final AppStore store;
  final TrayGateway gateway;
  final void Function() showWindow;
  final void Function() quit;
  final Duration every;
  final int Function() _minute;

  Timer? _tick;
  Timer? _settle;
  bool _on = false;
  List<String> _shown = const [];

  /// Shows the icon. Returns false on a system with no tray.
  bool start() {
    if (_on) return true;
    if (!gateway.show(tooltip: 'Grove', onClick: showWindow)) return false;
    _on = true;
    store.addListener(_storeChanged);
    _tick = Timer.periodic(every, (_) => refresh());
    refresh();
    return true;
  }

  void _storeChanged() {
    _settle?.cancel();
    _settle = Timer(settle, refresh);
  }

  /// Builds the menu again when its text is different.
  void refresh() {
    if (!_on) return;
    final lines = store.menuBarLines(minute: _minute());
    final text = [
      lines.now,
      lines.next,
      store.plantProgress(DayKey.today()).growthText,
    ];
    if (_same(text, _shown)) return;
    _shown = text;
    gateway.setMenu([
      for (final line in text) TrayEntry(line),
      const TrayEntry.separator(),
      TrayEntry('Open Grove', onTap: showWindow),
      TrayEntry('New task', onTap: _newTask),
      const TrayEntry.separator(),
      TrayEntry('Quit Grove', onTap: quit),
    ]);
    gateway.setTooltip(_clip('Grove · ${lines.now}'));
  }

  void _newTask() {
    showWindow();
    store.run(PaletteCommandId.newTask);
  }

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String _clip(String text) => text.length <= tooltipLimit
      ? text
      : '${text.substring(0, tooltipLimit - 1)}…';

  void dispose() {
    if (!_on) return;
    _on = false;
    store.removeListener(_storeChanged);
    _tick?.cancel();
    _settle?.cancel();
    gateway.dispose();
  }
}
