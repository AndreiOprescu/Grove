import 'dart:convert';

import 'day_key.dart';
import 'ids.dart';

enum Freq { daily, weekly, monthly, yearly }

class RecurrenceRule {
  RecurrenceRule({
    required this.freq,
    int interval = 1,
    this.weekdays,
    this.until,
    this.count,
  }) : interval = interval < 1 ? 1 : interval;

  const RecurrenceRule._decoded({
    required this.freq,
    required this.interval,
    this.weekdays,
    this.until,
    this.count,
  });

  final Freq freq;
  final int interval;

  /// 1 = Monday … 7 = Sunday. Only used by weekly rules. Empty/null = same
  /// weekday as the start.
  final List<int>? weekdays;
  final DayKey? until;
  final int? count;

  /// Same keys as Swift's `JSONEncoder`; null fields are left out.
  String json() => jsonEncode({
    'freq': freq.name,
    'interval': interval,
    if (weekdays != null) 'weekdays': weekdays,
    if (until != null) 'until': until!.string,
    if (count != null) 'count': count,
  });

  /// Reads what [json] (or the Swift app) wrote. Null for anything else.
  /// Like Swift's decoder, this does not clamp the interval.
  static RecurrenceRule? fromJson(String? s) {
    if (s == null) return null;
    try {
      final m = jsonDecode(s);
      if (m is! Map<String, Object?>) return null;
      final freq = Freq.values.asNameMap()[m['freq']];
      final interval = m['interval'];
      final weekdays = m['weekdays'];
      final until = m['until'];
      final count = m['count'];
      if (freq == null || interval is! int) return null;
      if (weekdays != null &&
          (weekdays is! List || weekdays.any((w) => w is! int))) {
        return null;
      }
      if (until != null && until is! String) return null;
      if (count != null && count is! int) return null;
      return RecurrenceRule._decoded(
        freq: freq,
        interval: interval,
        weekdays: (weekdays as List?)?.cast<int>(),
        until: until == null ? null : DayKey(until as String),
        count: count as int?,
      );
    } on FormatException {
      return null;
    }
  }

  RecurrenceRule copyWith({
    Freq? freq,
    int? interval,
    Object? weekdays = keep,
    Object? until = keep,
    Object? count = keep,
  }) => RecurrenceRule(
    freq: freq ?? this.freq,
    interval: interval ?? this.interval,
    weekdays: identical(weekdays, keep)
        ? this.weekdays
        : weekdays as List<int>?,
    until: identical(until, keep) ? this.until : until as DayKey?,
    count: identical(count, keep) ? this.count : count as int?,
  );

  @override
  bool operator ==(Object other) =>
      other is RecurrenceRule &&
      other.freq == freq &&
      other.interval == interval &&
      sameList(other.weekdays, weekdays) &&
      other.until == until &&
      other.count == count;

  @override
  int get hashCode => Object.hash(
    freq,
    interval,
    weekdays == null ? null : Object.hashAll(weekdays!),
    until,
    count,
  );
}
