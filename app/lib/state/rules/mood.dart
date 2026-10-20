import 'dart:math';

import '../../core/model/day_key.dart';
import 'day_range.dart';

/// How a day felt. It is saved in `notes.mood` of the daily note as 1, 2 or 3.
enum Mood {
  rain(1, 'cloud.rain', 'Rough day'),
  cloud(2, 'cloud.sun', 'Okay day'),
  sun(3, 'sun.max', 'Good day');

  const Mood(this.value, this.symbol, this.label);

  /// The number that is stored.
  final int value;

  /// The name of the picture (an SF Symbol name on the Mac).
  final String symbol;
  final String label;

  static Mood? fromValue(int? value) {
    for (final m in values) {
      if (m.value == value) return m;
    }
    return null;
  }
}

/// How many days had each mood: the 3 bars of the Persona screen.
class DayCounts {
  const DayCounts._(this._byMood);

  /// [counts]: the number of days of each stored mood value (1, 2, 3).
  factory DayCounts.from(Map<int, int> counts) =>
      DayCounts._({for (final m in Mood.values) m: counts[m.value] ?? 0});

  static const empty = DayCounts._({});

  final Map<Mood, int> _byMood;

  int of(Mood mood) => _byMood[mood] ?? 0;

  int get total => Mood.values.fold(0, (sum, m) => sum + of(m));

  /// 0 to 1. The biggest count fills its bar, so the others are easy to
  /// compare with it.
  double fill(Mood mood) {
    final most = Mood.values.map(of).fold(0, max);
    return most == 0 ? 0 : of(mood) / most;
  }
}

/// Which days the bars count.
enum DaySpan {
  month('This month'),
  all('All time');

  const DaySpan(this.label);

  final String label;

  /// The days of the span, or null for every day.
  DayRange? range(DayKey today) => switch (this) {
    month => DayRange(
      DayKey.ymd(today.year, today.month, 1),
      DayKey.fromDate(DateTime(today.year, today.month + 1, 0)),
    ),
    all => null,
  };

  /// This month when [name] is not a span.
  static DaySpan fromName(String? name) =>
      values.where((s) => s.name == name).firstOrNull ?? month;
}
