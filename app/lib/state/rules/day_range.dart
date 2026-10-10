import '../../core/model/day_key.dart';

/// Some days in a row, the first and the last included.
class DayRange {
  const DayRange(this.first, this.last);

  /// One day only.
  const DayRange.single(DayKey day) : first = day, last = day;

  final DayKey first;
  final DayKey last;

  bool contains(DayKey day) => day >= first && day <= last;

  /// Every day in the range, in order. Empty when [last] is before [first].
  List<DayKey> get days => first.rangeThrough(last);

  @override
  bool operator ==(Object other) =>
      other is DayRange && other.first == first && other.last == last;

  @override
  int get hashCode => Object.hash(first, last);

  @override
  String toString() => '$first...$last';
}
