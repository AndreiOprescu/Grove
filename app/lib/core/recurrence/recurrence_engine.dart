import '../model/day_key.dart';
import '../model/event.dart';
import '../model/recurrence.dart';

/// The id of one occurrence of a repeating event: `<series id>@<date>`.
/// An occurrence is not stored. Only a detached copy (one the user changed
/// alone) has its own row and id.
abstract final class OccurrenceId {
  static String make({required String series, required DayKey day}) =>
      '$series@${day.string}';

  static ({String series, DayKey day})? parse(String id) {
    final at = id.lastIndexOf('@');
    if (at <= 0) return null;
    final day = DayKey.parse(id.substring(at + 1));
    if (day == null) return null;
    return (series: id.substring(0, at), day: day);
  }
}

/// Repeat rules. Port of `RecurrenceEngine.swift`.
/// [next] gives the next date for a repeating task. [occurrences] and
/// [expand] give the dates and events of a repeating event inside a range.
abstract final class RecurrenceEngine {
  /// The first date after [after] that the rule produces. Null when it falls
  /// after the rule's end date. Monthly rules keep the day and clamp short
  /// months (31 Jan → 28 Feb).
  static DayKey? next({required DayKey after, required RecurrenceRule rule}) {
    final date = after;
    final DayKey result;
    switch (rule.freq) {
      case Freq.daily:
        result = date.adding(days: rule.interval);
      case Freq.weekly:
        final days = _chosenDays(rule);
        final wanted = days.isEmpty ? [date.weekdayIndex] : days;
        final later = wanted.where((d) => d > date.weekdayIndex);
        if (later.isNotEmpty) {
          result = date.adding(days: later.first - date.weekdayIndex);
        } else {
          // No more chosen days this week: jump `interval` weeks ahead.
          result = date.weekStart().adding(
            days: rule.interval * 7 + wanted.first - 1,
          );
        }
      case Freq.monthly:
        result = _addMonths(date, rule.interval);
      case Freq.yearly:
        result = _addMonths(date, rule.interval * 12);
    }
    final until = rule.until;
    if (until != null && result > until) return null;
    return result;
  }

  /// Calendar month add that clamps the day to the target month's length.
  static DayKey _addMonths(DayKey date, int months) {
    final (y, m) = _monthOf(date, months);
    final last = DayKey.ymd(y, m, 1).daysInMonth;
    return DayKey.ymd(y, m, date.day < last ? date.day : last);
  }

  static List<int> _chosenDays(RecurrenceRule rule) =>
      (rule.weekdays ?? const <int>[])
          .where((d) => d >= 1 && d <= 7)
          .toSet()
          .toList()
        ..sort();

  // Events

  /// The dates the rule produces from [from] to [to], oldest first, without
  /// the [exdates].
  ///
  /// Monthly and yearly rules skip a month or year that has no such day.
  /// A removed date still counts toward `count`.
  static List<DayKey> occurrences({
    required RecurrenceRule rule,
    required DayKey seriesStart,
    required DayKey from,
    required DayKey to,
    Set<DayKey> exdates = const {},
  }) {
    final until = rule.until;
    final limit = until != null && until < to ? until : to;
    if (seriesStart > limit) return [];
    final step = rule.interval < 1 ? 1 : rule.interval;
    var period = rule.count == null
        ? _firstPeriod(rule.freq, step, seriesStart, from)
        : 0;
    var produced = 0;
    final out = <DayKey>[];
    while (_periodStart(rule.freq, step, seriesStart, period) <= limit) {
      for (final day in _slots(rule, step, seriesStart, period)) {
        if (day > limit) return out;
        produced += 1;
        final count = rule.count;
        if (count != null && produced > count) return out;
        if (day >= from && !exdates.contains(day)) out.add(day);
      }
      period += 1;
    }
    return out;
  }

  /// The event of a series on one day. Same time of day, same length.
  /// Its id is an [OccurrenceId].
  static EventItem occurrence({required EventItem of, required DayKey on}) {
    final series = of;
    return series.copyWith(
      id: OccurrenceId.make(series: series.id, day: on),
      start: WallTime(day: on, minute: series.start.minute),
      end: WallTime(
        day: on.adding(days: series.start.day.daysUntil(series.end.day)),
        minute: series.end.minute,
      ),
      recurrence: null,
      seriesId: series.id,
      originalDate: on,
    );
  }

  /// Every event of the series that begins inside the range, or began
  /// before it and runs into it. A one-off copy that replaced a day is a
  /// stored event; it is not here.
  static List<EventItem> expand(
    EventItem series, {
    required Set<DayKey> exdates,
    required DayKey from,
    required DayKey to,
  }) {
    final rule = series.recurrence;
    if (rule == null) return [];
    final days = series.start.day.daysUntil(series.end.day);
    final span = days < 0 ? 0 : days;
    return occurrences(
      rule: rule,
      seriesStart: series.start.day,
      from: from.adding(days: -span),
      to: to,
      exdates: exdates,
    ).map((d) => occurrence(of: series, on: d)).toList();
  }

  // Walking the periods. A period is one step of the rule: a day, a week,
  // a month or a year, counted from the series start.

  static int _firstPeriod(Freq freq, int step, DayKey start, DayKey from) {
    final n = switch (freq) {
      Freq.daily => start.daysUntil(from) ~/ step,
      Freq.weekly => start.weekStart().daysUntil(from.weekStart()) ~/ 7 ~/ step,
      Freq.monthly =>
        ((from.year - start.year) * 12 + from.month - start.month) ~/ step,
      Freq.yearly => (from.year - start.year) ~/ step,
    };
    return n < 0 ? 0 : n;
  }

  /// The earliest day period [k] can hold. Used to know when to stop.
  static DayKey _periodStart(Freq freq, int step, DayKey start, int k) {
    switch (freq) {
      case Freq.daily:
        return start.adding(days: k * step);
      case Freq.weekly:
        return start.weekStart().adding(days: k * step * 7);
      case Freq.monthly:
        final (y, m) = _monthOf(start, k * step);
        return DayKey.ymd(y, m, 1);
      case Freq.yearly:
        return DayKey.ymd(start.year + k * step, 1, 1);
    }
  }

  static (int, int) _monthOf(DayKey start, int plus) {
    final total = start.month - 1 + plus;
    return (start.year + total ~/ 12, total % 12 + 1);
  }

  /// The days period [k] produces, oldest first, never before the start.
  static List<DayKey> _slots(
    RecurrenceRule rule,
    int step,
    DayKey start,
    int k,
  ) {
    switch (rule.freq) {
      case Freq.daily:
        return [start.adding(days: k * step)];
      case Freq.weekly:
        final chosen = _chosenDays(rule);
        final wanted = chosen.isEmpty ? [start.weekdayIndex] : chosen;
        final monday = start.weekStart().adding(days: k * step * 7);
        return wanted
            .map((d) => monday.adding(days: d - 1))
            .where((d) => d >= start)
            .toList();
      case Freq.monthly:
        final (y, m) = _monthOf(start, k * step);
        return _real(y, m, start.day);
      case Freq.yearly:
        return _real(start.year + k * step, start.month, start.day);
    }
  }

  static List<DayKey> _real(int year, int month, int day) =>
      day <= DayKey.ymd(year, month, 1).daysInMonth
      ? [DayKey.ymd(year, month, day)]
      : [];
}
