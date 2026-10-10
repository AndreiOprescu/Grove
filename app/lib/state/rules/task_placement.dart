import '../../core/model/day_key.dart';

/// Where a task lives. Used by quick add defaults, moves and drops.
sealed class TaskPlacement {
  const TaskPlacement();

  static const TaskPlacement inbox = InboxPlacement();
  static const TaskPlacement someday = SomedayPlacement();
  const factory TaskPlacement.day(DayKey day) = DayPlacement;

  /// Any day of the week; stored as the Monday.
  const factory TaskPlacement.week(DayKey day) = WeekPlacement;
}

class InboxPlacement extends TaskPlacement {
  const InboxPlacement();

  @override
  String toString() => 'inbox';
}

class SomedayPlacement extends TaskPlacement {
  const SomedayPlacement();

  @override
  String toString() => 'someday';
}

class DayPlacement extends TaskPlacement {
  const DayPlacement(this.day);

  final DayKey day;

  @override
  bool operator ==(Object other) => other is DayPlacement && other.day == day;

  @override
  int get hashCode => Object.hash('day', day);

  @override
  String toString() => 'day($day)';
}

class WeekPlacement extends TaskPlacement {
  const WeekPlacement(this.day);

  final DayKey day;

  @override
  bool operator ==(Object other) => other is WeekPlacement && other.day == day;

  @override
  int get hashCode => Object.hash('week', day);

  @override
  String toString() => 'week($day)';
}
