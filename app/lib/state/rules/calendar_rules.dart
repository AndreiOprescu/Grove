import 'dart:math';

import '../../core/model/day_key.dart';
import '../../core/model/event.dart';
import '../../core/model/ids.dart';
import '../../core/model/recurrence.dart';

/// What one day shows in the month view and the week strip.
class DayInfo {
  const DayInfo({
    this.events = const [],
    this.openTasks = 0,
    this.hasNote = false,
    this.mood,
  });

  /// Events that touch the day, all-day first. Task blocks are not here: the
  /// task is counted in [openTasks].
  final List<EventItem> events;
  final int openTasks;
  final bool hasNote;

  /// The mood of the day's note, 1 to 3.
  final int? mood;

  int get itemCount => events.length + openTasks;

  DayInfo copyWith({
    List<EventItem>? events,
    int? openTasks,
    bool? hasNote,
    int? mood,
  }) => DayInfo(
    events: events ?? this.events,
    openTasks: openTasks ?? this.openTasks,
    hasNote: hasNote ?? this.hasNote,
    mood: mood ?? this.mood,
  );

  @override
  bool operator ==(Object other) =>
      other is DayInfo &&
      sameList(other.events, events) &&
      other.openTasks == openTasks &&
      other.hasNote == hasNote &&
      other.mood == mood;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(events), openTasks, hasNote, mood);
}

/// The small rules behind the month view and the week strip.
abstract final class CalendarRules {
  /// Six full weeks, Monday first (or Sunday first), that hold the month of [day].
  static List<DayKey> monthGrid(DayKey day, {bool sundayFirst = false}) {
    final first = weekStart(
      DayKey.ymd(day.year, day.month, 1),
      sundayFirst: sundayFirst,
    );
    return [for (var i = 0; i < 42; i++) first.adding(days: i)];
  }

  /// The first day of the week that holds [day]. This is for what the screens
  /// show. Plans for "this week" always run Monday to Sunday (see docs/assumptions.md).
  static DayKey weekStart(DayKey day, {required bool sundayFirst}) =>
      day.weekStart(mondayFirst: !sundayFirst);

  /// The same day number in another month. A short month gives its last day.
  static DayKey addMonths(DayKey day, int months) {
    final index = day.year * 12 + (day.month - 1) + months;
    final first = DayKey.ymd(index ~/ 12, index % 12 + 1, 1);
    return DayKey.ymd(first.year, first.month, min(day.day, first.daysInMonth));
  }

  /// How many event lines fit in a month cell. The day number and the
  /// "+N more" line take 40 points.
  static int pillSlots({required double cellHeight}) =>
      min(3, max(1, ((cellHeight - 40) / 19).truncate()));

  static ({List<EventItem> shown, int hidden}) pills(
    List<EventItem> events, {
    required int slots,
  }) => (
    shown: events.take(max(0, slots)).toList(),
    hidden: max(0, events.length - slots),
  );

  /// All-day events first, then by start.
  static List<EventItem> sorted(List<EventItem> events) {
    final indexed = [for (var i = 0; i < events.length; i++) (i, events[i])];
    indexed.sort((x, y) {
      final a = x.$2, b = y.$2;
      final allDay = (a.allDay ? 0 : 1).compareTo(b.allDay ? 0 : 1);
      if (allDay != 0) return allDay;
      final start = a.start.compareTo(b.start);
      if (start != 0) return start;
      final title = a.title.compareTo(b.title);
      return title != 0 ? title : x.$1.compareTo(y.$1);
    });
    return [for (final x in indexed) x.$2];
  }

  /// Dots under a day in the week strip. At most three.
  static int dots(int count) => min(3, max(0, count));

  /// Does the event touch [day]? A timed event that ends at midnight does not
  /// touch the next day.
  static bool covers(EventItem e, DayKey day) {
    if (day < e.start.day) return false;
    if (e.allDay) return day <= e.end.day;
    return day == e.start.day ||
        WallTime(day: day, minute: 0).compareTo(e.end) < 0;
  }
}

/// When a repeating event stops.
enum RepeatEnds { never, on, after }

/// Changes the event editor makes to its copy of an event.
abstract final class EventDraft {
  static RepeatEnds ends(RecurrenceRule rule) {
    if (rule.until != null) return RepeatEnds.on;
    if (rule.count != null) return RepeatEnds.after;
    return RepeatEnds.never;
  }

  static const _weekdayNames = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  /// The rule in words: "Every 2 weeks", "Every week on Mon, Wed, Fri".
  static String repeatLabel(RecurrenceRule rule) {
    final days = [...?rule.weekdays]..sort();
    if (rule.freq == Freq.weekly &&
        rule.interval == 1 &&
        sameList(days, const [1, 2, 3, 4, 5])) {
      return 'Every weekday';
    }
    final noun = switch (rule.freq) {
      Freq.daily => 'day',
      Freq.weekly => 'week',
      Freq.monthly => 'month',
      Freq.yearly => 'year',
    };
    var text = rule.interval == 1
        ? 'Every $noun'
        : 'Every ${rule.interval} ${noun}s';
    if (rule.freq == Freq.weekly && days.isNotEmpty) {
      text += ' on ${days.map((d) => _weekdayNames[d - 1]).join(', ')}';
    }
    return text;
  }

  /// Turns one weekday on or off. [start] is the weekday of the first event: a
  /// weekly rule without a list means that day. The last day cannot be turned
  /// off. A list that is only the start day becomes "no list".
  static RecurrenceRule toggleWeekday(
    RecurrenceRule rule,
    int weekday, {
    required int start,
  }) {
    final set = {
      ...(rule.weekdays ?? [start]),
    };
    if (set.contains(weekday)) {
      if (set.length > 1) set.remove(weekday);
    } else {
      set.add(weekday);
    }
    final onlyStart = set.length == 1 && set.contains(start);
    return rule.copyWith(weekdays: onlyStart ? null : (set.toList()..sort()));
  }

  /// All-day events keep their days and drop the clock. Turning it off gives
  /// one hour from 09:00 on the first day.
  static EventItem setAllDay(EventItem e, bool on) => on
      ? e.copyWith(
          allDay: true,
          start: WallTime(day: e.start.day, minute: 0),
          end: WallTime(day: e.end.day, minute: 0),
        )
      : e.copyWith(
          allDay: false,
          start: WallTime(day: e.start.day, minute: 9 * 60),
          end: WallTime(day: e.start.day, minute: 10 * 60),
        );

  /// Moves the start and keeps the length. All-day events keep their number of days.
  static EventItem setStart(EventItem e, WallTime to) {
    if (e.allDay) {
      final span = e.start.day.daysUntil(e.end.day);
      return e.copyWith(
        start: WallTime(day: to.day, minute: 0),
        end: WallTime(day: to.day.adding(days: span), minute: 0),
      );
    }
    final int total = to.minute + max<int>(0, e.durationMinutes);
    return e.copyWith(
      start: to,
      end: WallTime(
        day: to.day.adding(days: total ~/ 1440),
        minute: total % 1440,
      ),
    );
  }

  /// An end that is not after the start becomes 30 minutes after it (or the
  /// end of the day). An all-day end before the start becomes the start.
  static EventItem normalize(EventItem e) {
    if (e.allDay) {
      return e.end.compareTo(e.start) < 0 ? e.copyWith(end: e.start) : e;
    }
    if (e.end.compareTo(e.start) <= 0) {
      return e.copyWith(
        end: WallTime(day: e.start.day, minute: min(1440, e.start.minute + 30)),
      );
    }
    return e;
  }

  /// The wall time as a local date and time.
  static DateTime date(WallTime w) =>
      DateTime(w.day.year, w.day.month, w.day.day, 0, w.minute);

  static WallTime wallTime(DateTime date) => WallTime(
    day: DayKey.fromDate(date),
    minute: date.hour * 60 + date.minute,
  );
}
