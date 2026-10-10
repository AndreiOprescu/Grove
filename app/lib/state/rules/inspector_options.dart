import '../../core/model/day_key.dart';
import '../../core/model/recurrence.dart';
import '../../core/model/task.dart';
import 'task_placement.dart';
import 'text.dart';

/// The short description of a task: one short line.
abstract final class SummaryText {
  static const maxLength = 160;

  /// Turns any text into one trimmed line of at most [maxLength] characters.
  static String clean(String raw) {
    final oneLine = splitLines(raw)
        .map(trimSpaces)
        .where((s) => s.isNotEmpty)
        .join(' ');
    return trimSpaces(prefixRunes(oneLine, maxLength));
  }
}

/// The repeat choices in the inspector. Anything else is shown as "Custom" and left alone.
enum RepeatPreset {
  none,
  daily,
  weekdays,
  weekly,
  biweekly,
  monthly,
  yearly,
  custom;

  String get label => switch (this) {
    none => 'Does not repeat',
    daily => 'Every day',
    weekdays => 'Every weekday',
    weekly => 'Every week',
    biweekly => 'Every 2 weeks',
    monthly => 'Every month',
    yearly => 'Every year',
    custom => 'Custom',
  };

  RecurrenceRule? get rule => switch (this) {
    none || custom => null,
    daily => RecurrenceRule(freq: Freq.daily),
    weekdays => RecurrenceRule(freq: Freq.weekly, weekdays: [1, 2, 3, 4, 5]),
    weekly => RecurrenceRule(freq: Freq.weekly),
    biweekly => RecurrenceRule(freq: Freq.weekly, interval: 2),
    monthly => RecurrenceRule(freq: Freq.monthly),
    yearly => RecurrenceRule(freq: Freq.yearly),
  };

  static RepeatPreset of(RecurrenceRule? rule) {
    if (rule == null) return none;
    for (final p in values) {
      if (p != none && p != custom && p.rule == rule) return p;
    }
    return custom;
  }
}

/// Small pure rules behind the inspector fields.
abstract final class InspectorOptions {
  static List<int> estimates({required int including}) =>
      ({15, 30, 45, 60, 90, 120, 180, 240, 300, 480, including}).toList()
        ..sort();

  /// The day part of a due value ("2026-10-05" or "2026-10-05T14:30").
  static DayKey? dueDay(String? due) => due == null
      ? null
      : DayKey.parse(due.length > 10 ? due.substring(0, 10) : due);

  /// A new due day that keeps the clock time of the old value, if it had one.
  static String dueString(DayKey day, {String? keepingTimeOf}) {
    final old = keepingTimeOf;
    if (old != null && old.length > 10) return day.string + old.substring(10);
    return day.string;
  }

  static TaskPlacement placement({
    required TaskBucket bucket,
    required DayKey date,
  }) => switch (bucket) {
    TaskBucket.inbox => TaskPlacement.inbox,
    TaskBucket.someday => TaskPlacement.someday,
    TaskBucket.day => TaskPlacement.day(date),
    TaskBucket.week => TaskPlacement.week(date.weekStart()),
  };
}
