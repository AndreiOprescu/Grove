// The speed check of milestone F12, part 2: how long each frame takes while
// the planner grid and the long lists scroll, and while a block is dragged.
// The store has the data of `tool/perf_data.dart` (1 000 tasks, a full
// planner week) in a database file, as the real app has.
//
// Run it in profile mode only. Numbers of a debug build mean nothing.
//   ./scripts/flutter_perf.sh macos
//
// It is not in the CI: a CI machine has no real screen and its numbers
// change from run to run.
//
// Each result is one line that starts with GROVE_PERF. The times of a frame
// come from the engine (`FrameTiming`): "build" is the work of Dart for the
// frame, "raster" is the drawing on the GPU thread.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/data/data.dart';
import 'package:grove/state/state.dart' hide MotionRules;
import 'package:grove/ui/notes/notes_view.dart';
import 'package:grove/ui/planner/planner_grid.dart';
import 'package:grove/ui/store_app.dart';
import 'package:grove/ui/tasks/tasks_pane.dart';
import 'package:integration_test/integration_test.dart';

import '../tool/perf_data.dart';

const _mode = kReleaseMode
    ? 'release'
    : kProfileMode
    ? 'profile'
    : 'debug';

/// One frame at 60 frames per second, in microseconds.
const _budget = 16667;

void _say(String step, Map<String, Object?> values) {
  // The line must reach the terminal on each OS, and `print` does.
  // ignore: avoid_print
  print('GROVE_PERF ${jsonEncode({'step': step, 'mode': _mode, ...values})}');
}

double _ms(num micros) => (micros / 10).round() / 100;

/// The value below which `share` of the sorted list lies.
int _percentile(List<int> sorted, double share) =>
    sorted[((sorted.length - 1) * share).round()];

Map<String, Object?> _summary(List<FrameTiming> frames, double seconds) {
  if (frames.length < 2) return {'frames': frames.length};
  List<int> sorted(Iterable<int> values) => values.toList()..sort();
  final build = sorted(frames.map((f) => f.buildDuration.inMicroseconds));
  final raster = sorted(frames.map((f) => f.rasterDuration.inMicroseconds));
  final both = sorted(
    frames.map(
      (f) => f.buildDuration.inMicroseconds + f.rasterDuration.inMicroseconds,
    ),
  );
  final starts = [
    for (final f in frames) f.timestampInMicroseconds(FramePhase.vsyncStart),
  ]..sort();
  final gaps = [
    for (var i = 1; i < starts.length; i++) starts[i] - starts[i - 1],
  ];
  final span = starts.last - starts.first;
  return {
    'frames': frames.length,
    'seconds': (seconds * 10).round() / 10,
    // Frames per second, from the first frame to the last one.
    'fps': span == 0 ? null : ((frames.length - 1) / span * 1e7).round() / 10,
    'build_avg_ms': _ms(build.reduce((a, b) => a + b) / build.length),
    'build_p90_ms': _ms(_percentile(build, 0.9)),
    'build_p99_ms': _ms(_percentile(build, 0.99)),
    'build_max_ms': _ms(build.last),
    'raster_avg_ms': _ms(raster.reduce((a, b) => a + b) / raster.length),
    'raster_p90_ms': _ms(_percentile(raster, 0.9)),
    'raster_p99_ms': _ms(_percentile(raster, 0.99)),
    'raster_max_ms': _ms(raster.last),
    'frame_p99_ms': _ms(_percentile(both, 0.99)),
    'frame_max_ms': _ms(both.last),
    // Frames where build + raster took more than one frame at 60 per second.
    'late_frames': both.where((t) => t > _budget).length,
    // Times when the next frame started more than 1.5 frames (at 60 per
    // second) after the one before: a frame that the screen did not get.
    'long_gaps': gaps.where((g) => g > _budget * 1.5).length,
    'longest_gap_ms': _ms(gaps.reduce((a, b) => a > b ? a : b)),
  };
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Frames come when the app asks for one, as in the real app.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  var finished = false;
  final fromScript = Platform.environment['GROVE_PERF_EXIT'] == '1';

  // A window that is not in view gets no frames, and then the test waits
  // for ever. A full run takes about 90 seconds.
  if (fromScript) {
    Timer(const Duration(minutes: 4), () {
      _say('error', {
        'message':
            'The run did not end in 4 minutes. The window must stay in '
            'view: do not cover it, and stay on its desktop.',
      });
      exit(1);
    });
  }

  // A run from the script ends the process here. `flutter test` must end it
  // itself.
  tearDownAll(() {
    if (fromScript) exit(finished ? 0 : 1);
  });

  testWidgets('frame times with a full store', (tester) async {
    final sep = Platform.pathSeparator;
    final folder = Directory(
      '${Directory.systemTemp.path}${sep}grove-perf-frames',
    );
    if (folder.existsSync()) folder.deleteSync(recursive: true);
    folder.createSync(recursive: true);
    final repos = Repos(Database.open('${folder.path}${sep}grove.sqlite'));
    final today = DayKey.today();
    PerfData.seed(repos, today: today);
    // The settings of a new user: motion is on, so the background moves.
    final store = AppStore(repos: repos, prefs: MemoryPrefs());
    addTearDown(store.dispose);
    store.screen = Screen.planner;

    await tester.pumpWidget(StoreApp(key: UniqueKey(), store: store));
    // Take the tree down at the end, before the store is closed.
    addTearDown(() => tester.pumpWidget(const SizedBox()));

    /// Lets the screen run for a moment. `pumpAndSettle` would never come
    /// back: the background always moves.
    Future<void> rest([int ms = 1200]) async {
      for (var passed = 0; passed < ms; passed += 100) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await rest(2000);
    final view = tester.view;
    final waiting = store.unscheduledTasks(today: today);
    _say('setup', {
      ...PerfData.counts(repos),
      'window':
          '${(view.physicalSize.width / view.devicePixelRatio).round()}x'
          '${(view.physicalSize.height / view.devicePixelRatio).round()}',
      'pixel_ratio': view.devicePixelRatio,
      'display_hz': view.display.refreshRate.round(),
      'os': Platform.operatingSystem,
      'waiting_tasks': waiting.overdue.length + waiting.unscheduled.length,
      'blocks_this_week': store
          .blocks(
            DayRange(today.weekStart(), today.weekStart().adding(days: 6)),
          )
          .length,
    });

    // What the system says about the window during a part: "inactive" =
    // another program has the keyboard, "hidden" = the window is not in
    // view (under another window, or on another desktop). The system gives
    // few frames or none to a window that is not in view, so a part with
    // "hidden" in its line must be taken again.
    final states = <String>[];
    String? stateNow;
    final watch = AppLifecycleListener(
      onStateChange: (state) {
        stateNow = state.name;
        states.add(state.name);
      },
    );
    addTearDown(watch.dispose);

    /// Runs `action` and gives the frames that the screen got during it.
    Future<void> measure(String name, Future<void> Function() action) async {
      states.clear();
      // The state at the start of the part, when the system gave one.
      if (stateNow != null) states.add(stateNow!);
      final frames = <FrameTiming>[];
      void take(List<FrameTiming> some) => frames.addAll(some);
      SchedulerBinding.instance.addTimingsCallback(take);
      var from = 0;
      var to = 0;
      // `watchPerformance` lets the engine make the frames, and waits at the
      // end until the times of all of them are in.
      await binding.watchPerformance(() async {
        from = DateTime.now().microsecondsSinceEpoch;
        // A window that is hidden or under another window gets no frames,
        // and the scroll would wait for ever.
        await action().timeout(
          const Duration(seconds: 60),
          onTimeout: () => fail(
            '"$name" did not end in 60 seconds. '
            'The window must stay in view during the run.',
          ),
        );
        to = DateTime.now().microsecondsSinceEpoch;
      }, reportKey: name);
      SchedulerBinding.instance.removeTimingsCallback(take);
      final during = [
        for (final f in frames)
          if (f.timestampInMicroseconds(FramePhase.rasterFinishWallTime)
              case final at when at >= from && at <= to)
            f,
      ];
      _say('frames', {
        'name': name,
        ..._summary(during, (to - from) / 1e6),
        // Empty, or "resumed" only = the window was in view the whole time.
        'app_states': states.toList(),
      });
    }

    /// The scroll view with the longest way under `within`.
    ScrollPosition longest(Finder within) {
      final all = tester
          .stateList<ScrollableState>(
            find.descendant(of: within, matching: find.byType(Scrollable)),
          )
          .map((s) => s.position)
          .where((p) => p.axis == Axis.vertical)
          .toList();
      expect(all, isNotEmpty, reason: 'no scroll view under $within');
      return all.reduce(
        (a, b) => a.maxScrollExtent >= b.maxScrollExtent ? a : b,
      );
    }

    /// To the end and back, two times, at `speed` points per second.
    Future<void> scroll(ScrollPosition position, double speed) async {
      final end = position.maxScrollExtent;
      expect(end, greaterThan(100), reason: 'the list is too short to scroll');
      final time = Duration(
        milliseconds: (end / speed * 1000).round().clamp(800, 6000),
      );
      position.jumpTo(0);
      for (var pass = 0; pass < 2; pass++) {
        await position.animateTo(end, duration: time, curve: Curves.linear);
        await position.animateTo(0, duration: time, curve: Curves.linear);
      }
    }

    // 1. The planner grid of the week: 7 day columns, every day full.
    final week = longest(find.byType(PlannerGrid));
    await measure('planner_week_scroll', () => scroll(week, 900));

    // 2. A block of today is dragged down, to the next day, and back to one
    // hour under its first place.
    final block = store
        .blocks(DayRange(today, today))
        .where((b) => b.taskId != null && b.endMinute - b.startMinute >= 30)
        .first;
    final hour = store.plannerHourHeight;
    final blockKey = find.byKey(ValueKey('block-${block.id}'));
    week.jumpTo(
      (block.startMinute / 60 * hour - 60).clamp(0, week.maxScrollExtent),
    );
    await rest(300);
    // The grid scrolls by itself when the pointer is 40 points or less from
    // its top or bottom edge, and then the block lands elsewhere. So the
    // block goes 70 points under the top edge, and the drag stays 50 points
    // or more above the bottom edge.
    final viewBox =
        week.context.notificationContext!.findRenderObject()! as RenderBox;
    final viewTop = viewBox.localToGlobal(Offset.zero).dy;
    final viewHeight = week.viewportDimension;
    week.jumpTo(
      (week.pixels + tester.getCenter(blockKey).dy - (viewTop + 70)).clamp(
        0,
        week.maxScrollExtent,
      ),
    );
    await rest(600);
    final from = tester.getCenter(blockKey);
    final column = tester
        .getRect(find.byKey(ValueKey('day-column-${today.string}')))
        .width;
    final reach = (viewTop + viewHeight - 50 - from.dy).clamp(0.0, hour * 2);
    expect(
      reach,
      greaterThanOrEqualTo(hour),
      reason: 'the window is too low for the drag',
    );
    // Sunday is the last column: go to the left there.
    final side = today.weekdayIndex == 7 ? -column : column;
    await measure('planner_block_drag', () async {
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await binding.delayed(const Duration(milliseconds: 50));
      Future<void> go(Offset a, Offset b) async {
        for (var i = 1; i <= 60; i++) {
          await gesture.moveTo(Offset.lerp(a, b, i / 60)!);
          await binding.delayed(const Duration(milliseconds: 16));
        }
      }

      final down = from + Offset(0, reach);
      final across = down + Offset(side, 0);
      final back = from + Offset(0, hour);
      await go(from, down);
      await go(down, across);
      await go(across, back);
      await gesture.up();
      await binding.delayed(const Duration(milliseconds: 300));
    });
    final moved = store
        .blocks(DayRange(today, today))
        .firstWhere((b) => b.id == block.id);
    expect(
      moved.startMinute,
      block.startMinute + 60,
      reason: 'the drag did not move the block by one hour',
    );

    // 3. The Tasks panel at the left of the planner: all waiting tasks.
    store.showTasks();
    await rest();
    final tasks = longest(find.byType(TasksPane));
    await measure('tasks_panel_scroll', () => scroll(tasks, 2500));
    store.leftPane = null;

    // 4. The list of the Notes screen: 270 notes.
    store.screen = Screen.notes;
    await rest();
    final notes = longest(find.byType(NotesView));
    await measure('notes_list_scroll', () => scroll(notes, 2500));

    // 5. The timeline of the Today screen.
    store.screen = Screen.today;
    await rest();
    final day = longest(find.byType(PlannerGrid));
    await measure('today_timeline_scroll', () => scroll(day, 900));

    _say('done', {'rss_mb': (ProcessInfo.currentRss / 104857.6).round() / 10});
    finished = true;
  });
}
