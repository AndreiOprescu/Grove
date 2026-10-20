// Port of Sources/Grove/Layouts/SpreadRules.swift: the numbers and the words
// of the Day Spread (PLAN §8, layout B). Plain values, so the tests need no
// screen.
import 'package:grove/state/state.dart';

abstract final class SpreadRules {
  /// The task list on the left is 300 to 420 points wide. The user drags its
  /// edge.
  static const tasksMin = 300.0;
  static const tasksMax = 420.0;
  static const tasksDefault = 340.0;

  /// The note column has one width. The timeline in the centre takes what
  /// is left.
  static const noteWidth = 340.0;
  static const timelineMinimum = 280.0;
  static const gap = 12.0;
  static const side = 16.0;

  /// Where the width of the task list is kept.
  static const tasksWidthKey = 'spread.tasksWidth';

  /// The window width where the widest task list still leaves the timeline
  /// its minimum.
  static double get minimumWindowWidth =>
      2 * side + 2 * gap + tasksMax + timelineMinimum + noteWidth;

  static double clampTasks(double width) =>
      width < tasksMin ? tasksMin : (width > tasksMax ? tasksMax : width);

  /// The widths of the three columns in a screen `width` points wide.
  /// `tasks` is the width the user asked for. The timeline keeps its
  /// minimum: the task list gets narrower first. When the three do not fit
  /// (a window the Mac app does not allow), the note column goes: `note` is
  /// 0. All are whole points.
  static ({double tasks, double timeline, double note}) columns({
    required double width,
    required double tasks,
  }) {
    final wanted = clampTasks(tasks).roundToDouble();
    final three = width - 2 * side - 2 * gap - noteWidth;
    if (three - tasksMin >= timelineMinimum) {
      final list = wanted > three - timelineMinimum
          ? (three - timelineMinimum).floorToDouble()
          : wanted;
      return (
        tasks: list,
        timeline: (three - list).floorToDouble(),
        note: noteWidth,
      );
    }
    final two = width - 2 * side - gap;
    final list = two - tasksMin >= timelineMinimum
        ? (wanted > two - timelineMinimum
              ? (two - timelineMinimum).floorToDouble()
              : wanted)
        : tasksMin;
    final timeline = (two - list).floorToDouble();
    return (tasks: list, timeline: timeline < 0 ? 0 : timeline, note: 0);
  }

  /// The widths when a left panel is open: the panel stands in the place of
  /// the task list, so the screen has the timeline and the note only. The
  /// note column goes when the timeline would lose its minimum.
  static ({double timeline, double note}) columnsBesidePane({
    required double width,
  }) {
    final two = width - 2 * side - gap - noteWidth;
    if (two >= timelineMinimum) {
      return (timeline: two.floorToDouble(), note: noteWidth);
    }
    final one = (width - 2 * side).floorToDouble();
    return (timeline: one < 0 ? 0 : one, note: 0);
  }

  /// The "Today / Tomorrow" switch of the header, in a desktop window. Both
  /// words fit in each theme. A phone gives the switch its own row.
  static const daySwitchWidth = 188.0;

  /// The height of the touch area of the switch. The control looks smaller:
  /// the rest of the area is empty space over and under it. The same height
  /// as a dock button on a phone.
  static const daySwitchTouch = 40.0;

  /// The room of the plant in the header: a whole number, so the switch on
  /// its left starts on a whole point.
  static const plantSlot = 36.0;

  /// The line under the big date.
  static String subtitle({
    required bool isToday,
    required String greeting,
    required PlantProgress progress,
  }) {
    if (isToday) return '$greeting · ${progress.growthText}';
    return progress.total == 0
        ? 'Nothing planned'
        : '${progress.percent}% of the day grown';
  }

  /// The line under the date in the tomorrow view. It names the day, so the
  /// screen cannot be read as today. No greeting and no growth: both belong
  /// to today.
  static String tomorrowSubtitle(PlantProgress progress) =>
      switch (progress.total) {
        0 => 'Tomorrow · No tasks yet',
        1 => 'Tomorrow · 1 task planned',
        final n => 'Tomorrow · $n tasks planned',
      };
}
