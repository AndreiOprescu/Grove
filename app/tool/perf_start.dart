// The speed check of milestone F12, part 1: how long Grove takes to start
// with a full store, and how much memory it uses. Run it with
// `./scripts/flutter_perf.sh macos`, which builds this file in release mode.
//
// It does what `lib/main.dart` does, with two changes:
// - The data is in its own folder in the temporary folder of the system
//   (`grove-perf`). It never touches the data of Grove.
// - No notification goes to the system (`NullNotifier`). The real notifier
//   would put reminders for the made-up events in the notification centre
//   and take out the real ones of Grove.
//
// The mode comes from the environment variable GROVE_PERF:
// - `seed`  makes the folder again with the data of `perf_data.dart`, and
//           quits. With GROVE_PERF_EMPTY=1 it makes the store of a new user
//           (3 lists, 3 sample tasks), to see what the data adds.
// - `start` (the default) shows the app, waits 3 seconds, prints one line
//           and quits.
// - `walk`  the same, then opens each screen and each left panel, and
//           prints the memory again.
// GROVE_PERF_T0 is the time just before the start of the process, in
// microseconds since 1970. With it the line has `start_ms`: from there to
// the first frame on the screen.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/data/data.dart';
import 'package:grove/services/services.dart';
import 'package:grove/state/state.dart' hide MotionRules;
import 'package:grove/ui/store_app.dart';
import 'package:grove/ui/theme/fonts.dart';
import 'package:path_provider/path_provider.dart';

import 'perf_data.dart';

const _mode = kReleaseMode
    ? 'release'
    : kProfileMode
    ? 'profile'
    : 'debug';

void _say(String step, Map<String, Object?> values) {
  stdout.writeln('GROVE_PERF ${jsonEncode({'step': step, ...values})}');
}

double _mb(int bytes) => (bytes / (1024 * 1024) * 10).round() / 10;

Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

Future<void> main() async {
  final env = Platform.environment;
  final sep = Platform.pathSeparator;
  final dir = '${Directory.systemTemp.path}${sep}grove-perf';
  final mode = env['GROVE_PERF'] ?? 'start';

  if (mode == 'seed') {
    final folder = Directory(dir);
    if (folder.existsSync()) folder.deleteSync(recursive: true);
    folder.createSync(recursive: true);
    final db = Database.open('$dir${sep}grove.sqlite');
    final repos = Repos(db);
    if (env['GROVE_PERF_EMPTY'] == '1') {
      // The store of a new user, to see what the data adds.
      FirstRun.seedIfNew(repos, today: DayKey.today());
      repos.settings.set(PerfData.seededKey, 'empty');
    } else {
      PerfData.seed(repos, today: DayKey.today());
    }
    _say('seed', {'folder': dir, ...PerfData.counts(repos)});
    db.close();
    exit(0);
  }

  // From here: the lines of `lib/main.dart`.
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  // The real app asks the system for its folder. Ask too, so the wait is in
  // the number.
  await getApplicationSupportDirectory();
  final prefs = FilePrefs('$dir${sep}prefs.json');
  final sync = await SupabaseBackend.start(SyncConfig.fromEnvironment);
  final store = AppStore.open(
    dataDir: dir,
    notifier: NullNotifier(),
    prefs: prefs,
    sync: sync,
  );
  if (!PerfData.isSeeded(store.repos)) {
    _say('error', {'message': 'no data in $dir: run with GROVE_PERF=seed'});
    exit(1);
  }
  AppServices.forThisDevice(store).start();
  runApp(StoreApp(store: store));

  await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
  final firstFrame = DateTime.now().microsecondsSinceEpoch;
  final t0 = int.tryParse(env['GROVE_PERF_T0'] ?? '');
  await _wait(3000);
  // PLAN.md §10: the tasks of a day in less than 50 ms with 1 000 tasks.
  // 20 reads of the tasks of today; the slowest one is in the line.
  final today = DayKey.today();
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  var slowest = 0;
  for (var i = 0; i < 20; i++) {
    final clock = Stopwatch()..start();
    store.repos.tasks.forDay(today);
    if (clock.elapsedMicroseconds > slowest) {
      slowest = clock.elapsedMicroseconds;
    }
  }
  _say('start', {
    'mode': _mode,
    'start_ms': t0 == null ? null : ((firstFrame - t0) / 100).round() / 10,
    'tasks_of_day_ms': (slowest / 10).round() / 100,
    'rss_mb': _mb(ProcessInfo.currentRss),
    'screen': store.screen.name,
    // The memory of the pictures on the GPU grows with the pixels of the
    // window, so the line says how many there are.
    'window_pixels':
        '${view.physicalSize.width.round()}x${view.physicalSize.height.round()}',
    'pixel_ratio': view.devicePixelRatio,
    'app_state': WidgetsBinding.instance.lifecycleState?.name,
  });

  if (mode == 'walk') {
    // The script reads the memory of the process from outside in this wait.
    await _wait(6000);
    for (final screen in [
      Screen.planner,
      Screen.calendar,
      Screen.notes,
      Screen.today,
      Screen.planner,
    ]) {
      store.screen = screen;
      await _wait(1500);
    }
    for (final pane in LeftPane.values) {
      store.showLeftPane(pane);
      await _wait(1500);
    }
    final notes = store.notes();
    store.screen = Screen.notes;
    for (final note in notes.take(5)) {
      store.openNote(note.id);
      await _wait(700);
    }
    // Back to the first state, so the next start is the same.
    store
      ..leftPane = null
      ..screen = Screen.today;
    await _wait(3000);
    _say('walk', {
      'mode': _mode,
      'rss_mb': _mb(ProcessInfo.currentRss),
      'max_rss_mb': _mb(ProcessInfo.maxRss),
    });
    await _wait(6000);
  }
  exit(0);
}
