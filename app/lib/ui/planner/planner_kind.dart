// Port of `PlannerKind` in Sources/Grove/Planner/PlannerView.swift.
import 'package:grove/core/model/day_key.dart';
import 'package:grove/state/state.dart' show CalendarRules;

/// What a top tab shows. Each tab has one fixed view: Today is one day, the
/// Planner is one week, the Calendar is one month.
enum PlannerKind {
  today,
  week,
  month;

  /// The days of the view. Today is today only. The week holds `selected`
  /// and starts on Monday (Sunday with `sundayFirst`). The month is its
  /// six-week grid.
  List<DayKey> days({
    required DayKey selected,
    required DayKey today,
    required bool sundayFirst,
  }) {
    switch (this) {
      case PlannerKind.today:
        return [today];
      case PlannerKind.week:
        final start = CalendarRules.weekStart(
          selected,
          sundayFirst: sundayFirst,
        );
        return [for (var i = 0; i < 7; i++) start.adding(days: i)];
      case PlannerKind.month:
        return CalendarRules.monthGrid(selected, sundayFirst: sundayFirst);
    }
  }

  /// The day after a click on Previous (-1) or Next (+1): a week back or
  /// forward, or a month. Today does not move.
  DayKey moved(DayKey day, {required int by}) => switch (this) {
    PlannerKind.today => day,
    PlannerKind.week => day.adding(days: by * 7),
    PlannerKind.month => CalendarRules.addMonths(day, by),
  };
}
