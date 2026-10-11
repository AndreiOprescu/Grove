// The idle check of the shell gaps (docs/acceptance/F12-shell-gaps.md): what
// Grove costs while its window is in front and nobody touches it. Run it
// with `./scripts/flutter_idle.sh`, which builds this file in profile mode
// and reads the processor time of the process from outside.
//
// It does what `lib/main.dart` does, with these changes:
// - The data is in its own new folder in the temporary folder of the system
//   (`grove-idle-check`). It never touches the data of Grove.
// - No notification goes to the system, no tray icon, no sync.
//
// - The app always behaves as in front (`resumed`): all its clocks run. The
//   check is started from a shell while a person uses the Mac, so the system
//   often tells it `hidden` or `inactive`, or nothing. The state the system
//   told is in each line (`told`), and it is not used.
//
// Every 5 seconds it prints one line: how many frames the engine drew and
// the mean time to build one and to raster one. It quits by itself.
//
// The environment picks the case:
// - GROVE_IDLE_MOTION=off      the Motion setting is off
// - GROVE_IDLE_SCREEN=<name>   planner (default), today, calendar, notes,
//                              garden
// - GROVE_IDLE_THEME=<id>      the theme, by its id
// - GROVE_IDLE_SECONDS=<n>     how long it runs (default 40)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:grove/state/state.dart' hide MotionRules;
import 'package:grove/ui/store_app.dart';
import 'package:grove/ui/theme/fonts.dart';

const _mode = kReleaseMode
    ? 'release'
    : kProfileMode
    ? 'profile'
    : 'debug';

void _say(Map<String, Object?> values) {
  stdout.writeln('GROVE_IDLE ${jsonEncode(values)}');
}

double _ms(int micros, int frames) =>
    frames == 0 ? 0 : (micros / frames / 10).round() / 100;

void main() {
  final env = Platform.environment;
  final sep = Platform.pathSeparator;
  final dir = '${Directory.systemTemp.path}${sep}grove-idle-check';
  final seconds = int.tryParse(env['GROVE_IDLE_SECONDS'] ?? '') ?? 40;

  final binding = WidgetsFlutterBinding.ensureInitialized();
  String? told;
  SystemChannels.lifecycle.setMessageHandler((message) async {
    told = message;
    return null;
  });
  binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  registerFontLicenses();
  final folder = Directory(dir);
  if (folder.existsSync()) folder.deleteSync(recursive: true);
  folder.createSync(recursive: true);
  final store = AppStore.open(
    dataDir: dir,
    notifier: NullNotifier(),
    prefs: MemoryPrefs(),
  );
  if (env['GROVE_IDLE_MOTION'] == 'off') store.setMotion(false);
  final theme = ThemeId.values.asNameMap()[env['GROVE_IDLE_THEME']];
  if (theme != null) store.setTheme(theme);
  final screen = Screen.values.asNameMap()[env['GROVE_IDLE_SCREEN']];
  if (screen != null) store.screen = screen;

  var frames = 0;
  var build = 0;
  var raster = 0;
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final timing in timings) {
      frames++;
      build += timing.buildDuration.inMicroseconds;
      raster += timing.rasterDuration.inMicroseconds;
    }
  });

  _say({
    'step': 'start',
    'mode': _mode,
    'pid': pid,
    'folder': dir,
    'motion': store.motionSetting,
    'theme': store.themeId.name,
    'screen': store.screen.name,
  });

  const every = 5;
  var ticks = 0;
  Timer.periodic(const Duration(seconds: every), (timer) {
    ticks++;
    _say({
      'step': 'idle',
      'at_s': ticks * every,
      'frames_per_s': (frames / every * 10).round() / 10,
      'build_ms': _ms(build, frames),
      'raster_ms': _ms(raster, frames),
      'state': binding.lifecycleState?.name,
      // What the system said. `null` is: nothing.
      'told': told,
    });
    frames = 0;
    build = 0;
    raster = 0;
    if (ticks * every >= seconds) {
      timer.cancel();
      store.dispose();
      exit(0);
    }
  });

  runApp(StoreApp(store: store));
}
