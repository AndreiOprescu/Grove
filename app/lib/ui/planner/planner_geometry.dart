// Port of Sources/Grove/Planner/PlannerGeometry.swift: the sizes of the
// time grid, and how many text rows fit in a block.
import 'dart:math';

/// Minutes to points and back, for one zoom level.
class PlannerGeometry {
  const PlannerGeometry({this.hourHeight = defaultHourHeight});

  static const defaultHourHeight = 64.0;
  static const minHourHeight = 36.0;
  static const maxHourHeight = 160.0;

  /// The column with the hour labels.
  static const gutterWidth = 52.0;

  /// How far day column [index] starts after the gutter, on a whole point.
  /// Text that starts on a part of a point is drawn soft, and each system
  /// draws it its own way.
  static double dayOffset(double dayWidth, int index) =>
      (index * dayWidth).roundToDouble();

  /// The width of day column [index]: from its whole point to the next one.
  static double dayWidthAt(double dayWidth, int index) =>
      dayOffset(dayWidth, index + 1) - dayOffset(dayWidth, index);

  /// A block is never drawn shorter than this.
  static const minBlockHeight = 22.0;

  /// The row with the time and the title of a block. A block that starts
  /// inside this row of another block would hide its title.
  static const titleRowHeight = 32.0;

  final double hourHeight;

  static double clampHour(double height) =>
      min(maxHourHeight, max(minHourHeight, height));

  /// The grid always covers 00:00–24:00.
  double get totalHeight => hourHeight * 24;

  double y(int minute) => minute / 60 * hourHeight;

  int minute(double y) => (y / hourHeight * 60).round();

  /// The minutes that the shortest drawn block covers.
  int get minDrawnMinutes => (minBlockHeight * 60 / hourHeight).ceil();

  /// The minutes that the title row covers.
  int get tightMinutes => (titleRowHeight * 60 / hourHeight).ceil();
}

/// The text rows of one block.
class BlockRows {
  const BlockRows({
    required this.title,
    this.summary = 0,
    this.subtasks = 0,
    this.moreRow = false,
    this.badge = false,
  });

  /// Lines for the title.
  final int title;

  /// Lines for the short description. 0 hides it.
  final int summary;

  /// How many subtasks get a row.
  final int subtasks;

  /// A last row says how many subtasks have no row ("+3 more").
  final bool moreRow;

  /// No row is free. The title row shows a count ("1/4").
  final bool badge;

  /// The subtasks with no row.
  int hidden(int total) => max(0, total - subtasks);

  @override
  bool operator ==(Object other) =>
      other is BlockRows &&
      other.title == title &&
      other.summary == summary &&
      other.subtasks == subtasks &&
      other.moreRow == moreRow &&
      other.badge == badge;

  @override
  int get hashCode => Object.hash(title, summary, subtasks, moreRow, badge);

  @override
  String toString() =>
      'BlockRows(title: $title, summary: $summary, subtasks: $subtasks, '
      'moreRow: $moreRow, badge: $badge)';
}

/// One subtask as a block shows it.
class BlockSubtask {
  const BlockSubtask({
    required this.id,
    required this.title,
    required this.isDone,
  });

  final String id;
  final String title;
  final bool isDone;
}

/// The texts for subtasks that have no row. Swift: `SubtaskRules.moreLabel`
/// and `SubtaskRules.badge`.
abstract final class SubtaskLabels {
  /// "+3 more" under the subtasks that show. "1/4 subtasks" when none shows.
  static String more({
    required int hidden,
    required int shown,
    required int done,
    required int total,
  }) => shown == 0 ? '$done/$total subtasks' : '+$hidden more';

  /// "1/4" in the title row.
  static String badge({required int done, required int total}) =>
      '$done/$total';
}

abstract final class PlannerLayoutRules {
  /// The height of one line of the short description.
  static const summaryLineHeight = 14.0;

  /// The lines a block of `height` points gives to its title and to its
  /// short description. The time row and the padding take 28 points. A line
  /// takes 15.
  static ({int title, int summary}) blockTextLines({
    required double height,
    required bool hasSummary,
  }) {
    final lines = max(1, ((height - 28) / 15).truncate() + 1);
    if (!hasSummary || lines < 2) return (title: lines, summary: 0);
    final title = min(2, lines - 1);
    return (title: title, summary: lines - title);
  }

  /// The rows of a block that has subtasks. The title keeps one line. The
  /// short description keeps one line. Subtasks take the lines that are
  /// left. Lines that are still free go back to the title and the
  /// description.
  static BlockRows blockRows({
    required double height,
    required bool hasSummary,
    required int subtaskCount,
  }) {
    final old = blockTextLines(height: height, hasSummary: hasSummary);
    if (subtaskCount <= 0) {
      return BlockRows(title: old.title, summary: old.summary);
    }
    final summary = old.summary > 0 ? 1 : 0;
    final left = old.title + old.summary - 1 - summary;
    if (left <= 0) return BlockRows(title: 1, summary: summary, badge: true);
    if (left < subtaskCount) {
      return BlockRows(
        title: 1,
        summary: summary,
        subtasks: left - 1,
        moreRow: true,
      );
    }
    final rest = left - subtaskCount;
    if (summary > 0) {
      final more = min(1, rest);
      return BlockRows(
        title: 1 + more,
        summary: summary + rest - more,
        subtasks: subtaskCount,
      );
    }
    return BlockRows(title: 1 + rest, subtasks: subtaskCount);
  }

  /// The minutes at the top of a block that another block must not cover.
  /// A block that shows its short description keeps one more line clear.
  static int tightMinutes({
    required double hourHeight,
    required double blockHeight,
    required bool hasSummary,
  }) {
    final shows =
        hasSummary &&
        blockTextLines(height: blockHeight, hasSummary: true).summary > 0;
    final points =
        PlannerGeometry.titleRowHeight + (shows ? summaryLineHeight : 0);
    return (points * 60 / hourHeight).ceil();
  }

  /// How far right a block on top must start, so the text of the block
  /// below stays readable. Never more than half the column.
  static double textClearance({
    required String title,
    required String summary,
    required double columnWidth,
  }) => min(
    columnWidth * 0.5,
    max(38 + 6.0 * title.runes.length, 28 + 5.6 * summary.runes.length),
  );
}
