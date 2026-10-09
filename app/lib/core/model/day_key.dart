String _pad(int n, int width) => n.toString().padLeft(width, '0');

final _dayPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final _timePattern = RegExp(r'^(\d{1,2}):(\d{1,2})$');

/// A calendar day, stored as "YYYY-MM-DD".
///
/// Day maths runs on UTC midnights, so a daylight saving change never
/// adds or loses a day.
class DayKey implements Comparable<DayKey> {
  const DayKey(this.string);

  /// The calendar day of [date], in the zone [date] is in (local for `DateTime.now()`).
  DayKey.fromDate(DateTime date)
    : string = _format(date.year, date.month, date.day);

  DayKey.ymd(int year, int month, int day) : string = _format(year, month, day);

  /// Day of a UTC midnight. Used by the day maths.
  DayKey._utc(DateTime utc) : string = _format(utc.year, utc.month, utc.day);

  final String string;

  static String _format(int y, int m, int d) =>
      '${_pad(y, 4)}-${_pad(m, 2)}-${_pad(d, 2)}';

  /// Validating parse. Returns null for text that is not a real date.
  static DayKey? parse(String s) {
    final m = _dayPattern.firstMatch(s);
    if (m == null) return null;
    final key = DayKey.ymd(
      int.parse(m[1]!),
      int.parse(m[2]!),
      int.parse(m[3]!),
    );
    return DayKey._utc(key._utcDate) == key ? key : null;
  }

  static DayKey today() => DayKey.fromDate(DateTime.now());

  int get year => int.tryParse(string.substring(0, 4)) ?? 1970;
  int get month => int.tryParse(string.substring(5, 7)) ?? 1;
  int get day => int.tryParse(string.substring(8, 10)) ?? 1;

  DateTime get _utcDate => DateTime.utc(year, month, day);

  /// Midnight at the start of this day, local time.
  DateTime get date => DateTime(year, month, day);

  DayKey adding({required int days}) =>
      DayKey._utc(DateTime.utc(year, month, day + days));

  /// 1 = Monday … 7 = Sunday.
  int get weekdayIndex => _utcDate.weekday;

  DayKey weekStart({bool mondayFirst = true}) {
    final offset = mondayFirst ? weekdayIndex - 1 : weekdayIndex % 7;
    return adding(days: -offset);
  }

  /// Number of days from this day to [other] (positive when [other] is later).
  int daysUntil(DayKey other) => other._utcDate.difference(_utcDate).inDays;

  int get daysInMonth => DateTime.utc(year, month + 1, 0).day;

  /// ISO week number (Monday-first weeks, week 1 holds the first Thursday).
  int get weekOfYear {
    final thursday = adding(days: 4 - weekdayIndex);
    final firstOfYear = DayKey.ymd(thursday.year, 1, 1);
    return firstOfYear.daysUntil(thursday) ~/ 7 + 1;
  }

  List<DayKey> rangeThrough(DayKey end) {
    final out = <DayKey>[];
    for (var d = this; d <= end; d = d.adding(days: 1)) {
      out.add(d);
    }
    return out;
  }

  @override
  int compareTo(DayKey other) => string.compareTo(other.string);
  bool operator <(DayKey other) => compareTo(other) < 0;
  bool operator <=(DayKey other) => compareTo(other) <= 0;
  bool operator >(DayKey other) => compareTo(other) > 0;
  bool operator >=(DayKey other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) => other is DayKey && other.string == string;

  @override
  int get hashCode => string.hashCode;

  @override
  String toString() => string;
}

/// A day plus a minute of the day (0…1440). Stored as "YYYY-MM-DDTHH:MM".
class WallTime implements Comparable<WallTime> {
  const WallTime({required this.day, required this.minute});

  final DayKey day;
  final int minute;

  static WallTime? parse(String s) {
    final parts = s.split('T');
    if (parts.length != 2) return null;
    final day = DayKey.parse(parts[0]);
    final hm = _timePattern.firstMatch(parts[1]);
    if (day == null || hm == null) return null;
    final h = int.parse(hm[1]!), m = int.parse(hm[2]!);
    if (h > 24 || m > 59) return null;
    return WallTime(day: day, minute: h * 60 + m);
  }

  String get string =>
      '${day.string}T${_pad(minute ~/ 60, 2)}:${_pad(minute % 60, 2)}';

  WallTime copyWith({DayKey? day, int? minute}) =>
      WallTime(day: day ?? this.day, minute: minute ?? this.minute);

  @override
  int compareTo(WallTime other) => string.compareTo(other.string);

  @override
  bool operator ==(Object other) =>
      other is WallTime && other.day == day && other.minute == minute;

  @override
  int get hashCode => Object.hash(day, minute);

  @override
  String toString() => string;
}

/// Local timestamps for created/updated columns: "yyyy-MM-ddTHH:mm:ss".
abstract final class Stamp {
  static String now() => fromDate(DateTime.now());

  static String fromDate(DateTime d) =>
      '${DayKey.fromDate(d).string}T${_pad(d.hour, 2)}:${_pad(d.minute, 2)}:${_pad(d.second, 2)}';
}
