import 'dart:math';

import '../../core/model/day_key.dart';
import '../../core/model/goal.dart';
import '../../core/planner/planner_math.dart';
import 'calendar_rules.dart';
import 'day_range.dart';

/// A goal's week: what it counts, how much is done, how much is planned
/// (done blocks included) and the target, all in one unit (minutes or sessions).
class GoalProgress {
  const GoalProgress({
    required this.kind,
    required this.done,
    required this.planned,
    required this.target,
  });

  final GoalKind kind;
  final int done;
  final int planned;
  final int target;

  @override
  bool operator ==(Object other) =>
      other is GoalProgress &&
      other.kind == kind &&
      other.done == done &&
      other.planned == planned &&
      other.target == target;

  @override
  int get hashCode => Object.hash(kind, done, planned, target);

  @override
  String toString() => 'GoalProgress($kind, $done, $planned, $target)';
}

/// The small rules behind goals. Plain functions, so tests can check them.
abstract final class GoalRules {
  /// A target is at least one planner step and at most a whole week, in minutes.
  static const minTarget = PlannerMath.minLength;
  static const maxTarget = 7 * 24 * 60;

  /// The length of a goal block that is dragged into a day, in minutes.
  static const defaultBlockLength = 60;

  /// A new goal asks for 5 hours a week. The stepper in the panel moves in half hours.
  static const defaultTarget = 300;
  static const targetStep = 30;

  static int clampTarget(int minutes) =>
      max(minTarget, min(maxTarget, minutes));

  /// A sessions goal asks for 3 a week. The stepper moves by one, from 1 to 99.
  static const defaultCount = 3;
  static const minCount = 1;
  static const maxCount = 99;

  static int clampCount(int count) => max(minCount, min(maxCount, count));

  /// The goal's weekly target in its own unit: minutes for hours, a count for sessions.
  static int target(GoalItem goal) =>
      goal.kind == GoalKind.hours ? goal.targetMin : goal.targetCount;

  static int defaultTargetFor(GoalKind kind) =>
      kind == GoalKind.hours ? defaultTarget : defaultCount;

  static int clamp(int target, {required GoalKind kind}) =>
      kind == GoalKind.hours ? clampTarget(target) : clampCount(target);

  /// The seven days of the week that holds [day]: Monday to Sunday, or Sunday
  /// to Saturday. This is the week the planner shows (setting `calendar.weekStartsSunday`).
  static DayRange week(DayKey day, {required bool sundayFirst}) {
    final first = CalendarRules.weekStart(day, sundayFirst: sundayFirst);
    return DayRange(first, first.adding(days: 6));
  }

  /// The colour a block of the goal gets: the goal's own colour, or the accent
  /// colour when it has none.
  static String blockColor(GoalItem goal) =>
      goal.color.isEmpty ? 'accent' : goal.color;

  /// A goal title with the white space cut off. Empty when there is nothing to show.
  static String cleanTitle(String title) => title.trim();

  // Panel text

  /// The target after one click on the stepper. Hours: half an hour more or
  /// less, never under half an hour, never over a week. Sessions: one more or
  /// less, from 1 to 99.
  static int stepTarget(int value, {required GoalKind kind, required bool up}) {
    switch (kind) {
      case GoalKind.hours:
        return clampTarget(
          max(targetStep, value + (up ? targetStep : -targetStep)),
        );
      case GoalKind.sessions:
        return clampCount(value + (up ? 1 : -1));
    }
  }

  /// "Hours" or "Sessions", for the picker.
  static String kindName(GoalKind kind) =>
      kind == GoalKind.hours ? 'Hours' : 'Sessions';

  /// Minutes as hours without the unit: "5", "2.5", "0.25". Two decimals at
  /// most, trailing zeros cut.
  static String hours(int minutes) {
    final hundredths = (max(0, minutes) / 60 * 100).round();
    final whole = hundredths ~/ 100, part = hundredths % 100;
    if (part == 0) return '$whole';
    return part % 10 == 0
        ? '$whole.${part ~/ 10}'
        : '$whole.${part < 10 ? '0' : ''}$part';
  }

  static String _sessions(int n) => n == 1 ? 'session' : 'sessions';

  /// "2.5 / 5 h done" or "3 / 5 sessions done". Over the target is fine: "7 / 5 h done".
  static String progressText(GoalProgress p) => switch (p.kind) {
    GoalKind.hours => '${hours(p.done)} / ${hours(p.target)} h done',
    GoalKind.sessions =>
      '${max(0, p.done)} / ${p.target} ${_sessions(p.target)} done',
  };

  /// "4 h planned" or "2 sessions planned": every block of the week, done or
  /// not. "Nothing planned yet" for none.
  static String plannedText(GoalProgress p) {
    if (p.planned <= 0) return 'Nothing planned yet';
    return switch (p.kind) {
      GoalKind.hours => '${hours(p.planned)} h planned',
      GoalKind.sessions => '${p.planned} ${_sessions(p.planned)} planned',
    };
  }

  /// "5 h / week" or "3 sessions / week", next to the stepper.
  static String targetText(GoalKind kind, int target) => switch (kind) {
    GoalKind.hours => '${hours(target)} h / week',
    GoalKind.sessions => '$target ${_sessions(target)} / week',
  };

  /// How far the solid part (done) and the lighter part (planned, done
  /// included) reach, each from 0 to 1. A goal at or over its target shows a full bar.
  static ({double done, double planned}) bar(GoalProgress p) {
    if (p.target <= 0) return (done: 0, planned: 0);
    double part(int v) => min(1, max(0, v / p.target));
    return (done: part(p.done), planned: max(part(p.done), part(p.planned)));
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// The title of the panel's week: "This week" when [today] is in it, else
  /// "5–11 Oct" or "28 Sep–4 Oct".
  static String weekLabel(DayRange week, {required DayKey today}) {
    if (week.contains(today)) return 'This week';
    final first = week.first, last = week.last;
    String name(DayKey d) => _months[max(0, min(11, d.month - 1))];
    if (first.month == last.month) {
      return '${first.day}–${last.day} ${name(last)}';
    }
    return '${first.day} ${name(first)}–${last.day} ${name(last)}';
  }

  /// One sentence for a screen reader: "Read, 2.5 / 5 h done, 4 h planned".
  static String accessibilityText(String title, GoalProgress p) =>
      '$title, ${progressText(p)}, ${plannedText(p)}';
}
