import '../model/day_key.dart';
import '../model/recurrence.dart';
import '../model/task.dart';
import '../planner/planner_math.dart';

enum ChipKind { date, time, duration, repeats, due, list, tag, priority }

/// One small label shown under the quick-add field for each thing the parser understood.
class QuickAddChip {
  const QuickAddChip(this.kind, this.text);

  final ChipKind kind;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is QuickAddChip && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() => 'QuickAddChip($kind, $text)';
}

class QuickAddResult {
  QuickAddResult({
    required this.title,
    this.bucket = TaskBucket.inbox,
    this.planDate,
    this.planWeek,
    this.due,
    this.startMinute,
    this.durationMin,
    this.tags = const [],
    this.priority = 0,
    this.listName,
    this.recurrence,
    this.chips = const [],
    this.namedADay = false,
  });

  final String title;
  final TaskBucket bucket;
  final DayKey? planDate;
  final DayKey? planWeek;
  final String? due;

  /// Minute of the day when the task should get a time block.
  final int? startMinute;
  final int? durationMin;
  final List<String> tags;
  final int priority;

  /// Name of an existing list (fuzzy matched from `/name`).
  final String? listName;
  final RecurrenceRule? recurrence;
  final List<QuickAddChip> chips;

  /// True when the text named a day or a week (`fri`, `tomorrow`, `next week`).
  /// A time alone gives today without this.
  final bool namedADay;

  QuickAddResult _withChips(List<QuickAddChip> chips) => QuickAddResult(
    title: title,
    bucket: bucket,
    planDate: planDate,
    planWeek: planWeek,
    due: due,
    startMinute: startMinute,
    durationMin: durationMin,
    tags: tags,
    priority: priority,
    listName: listName,
    recurrence: recurrence,
    chips: List.unmodifiable(chips),
    namedADay: namedADay,
  );

  /// Length of the time block: the stated length, or 30 minutes.
  int get blockMinutes => durationMin ?? 30;
  int? get blockEnd {
    final start = startMinute;
    return start == null ? null : _min(1440, start + blockMinutes);
  }
}

/// Turns one line of text ("Call mum tomorrow 6pm for 20m #home !2") into a task.
/// Matched words are removed from the title. Words it does not know stay in the title.
class QuickAddParser {
  const QuickAddParser({required this.today, this.lists = const []});

  final DayKey today;
  final List<String> lists;

  QuickAddResult parse(String input) {
    final trimmed = input.split(_space).where((w) => w.isNotEmpty).join(' ');
    final run = _Run(trimmed.isEmpty ? <String>[] : trimmed.split(' '), this)
      ..scan();
    final result = run.finish();
    // Nothing left to be a title: keep exactly what was typed and apply nothing.
    return result.title.isEmpty ? QuickAddResult(title: trimmed) : result;
  }

  // Word lists.

  static const weekdayNames = <String, int>{
    'mon': 1, 'monday': 1, 'tue': 2, 'tues': 2, 'tuesday': 2, //
    'wed': 3, 'weds': 3, 'wednesday': 3,
    'thu': 4, 'thur': 4, 'thurs': 4, 'thursday': 4, 'fri': 5, 'friday': 5,
    'sat': 6, 'saturday': 6, 'sun': 7, 'sunday': 7,
  };
  static const monthNames = <String, int>{
    'jan': 1, 'january': 1, 'feb': 2, 'february': 2, 'mar': 3, 'march': 3, //
    'apr': 4, 'april': 4, 'may': 5, 'jun': 6, 'june': 6, 'jul': 7, 'july': 7,
    'aug': 8, 'august': 8, 'sep': 9, 'sept': 9, 'september': 9,
    'oct': 10, 'october': 10, 'nov': 11, 'november': 11,
    'dec': 12, 'december': 12,
  };
  static const weekdayShort = [
    '', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun', //
  ];
  static const monthShort = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static final _space = RegExp(r'\s+');
  static final _clock12 = RegExp(r'^(\d{1,2})(?::(\d{2}))?(am|pm)$');
  static final _clock24 = RegExp(r'^(\d{1,2}):(\d{2})$');
  static final _clockAfterAt = RegExp(r'^(\d{1,2})(?::(\d{2}))?(am|pm)?$');
  static final _slashDate = RegExp(r'^(\d{1,2})/(\d{1,2})$');
  static final _hoursMinutes = RegExp(
    r'^(\d+(?:\.\d+)?)(?:h|hr|hrs)(?:(\d+)(?:m|min|mins)?)?$',
  );
  static final _minutesOnly = RegExp(r'^(\d+)(?:m|min|mins)$');
  static final _plainNumber = RegExp(r'^\d+(?:\.\d+)?$');
  static final _tagWord = RegExp(r'^#([A-Za-z][A-Za-z0-9_-]*)$');
  static final _intWord = RegExp(r'^[+-]?\d+$');
}

int _min(int a, int b) => a < b ? a : b;

/// Like Swift `Int(_:)`: digits with an optional sign, nothing else.
int? _int(String? s) =>
    s != null && QuickAddParser._intWord.hasMatch(s) ? int.tryParse(s) : null;

sealed class _DateKind {
  const _DateKind();
}

class _Day extends _DateKind {
  const _Day(this.day);
  final DayKey day;
}

class _Week extends _DateKind {
  const _Week(this.week);
  final DayKey week;
}

class _Someday extends _DateKind {
  const _Someday();
}

/// One pass over the words.
class _Run {
  _Run(this.tokens, this.parser)
    : used = List.filled(tokens.length, false),
      clean = tokens.map(_cleaned).toList();

  final List<String> tokens;
  final QuickAddParser parser;
  final List<String> clean;
  final List<bool> used;

  _DateKind? dateKind;
  int? startMinute;
  (int, int)? timeRange;
  int? duration;
  RecurrenceRule? recurrence;
  String? recurrenceText;
  String? due;
  final List<String> tags = [];
  int? priority;
  String? listName;

  /// Lowercase, and without a trailing comma or full stop.
  static String _cleaned(String token) {
    var t = token.toLowerCase();
    while (t.length > 1 && ',.;:'.contains(t[t.length - 1])) {
      t = t.substring(0, t.length - 1);
    }
    return t;
  }

  String? word(int i) => i < clean.length && !used[i] ? clean[i] : null;

  void take(int start, int count) {
    for (var k = start; k < start + count; k++) {
      used[k] = true;
    }
  }

  void scan() {
    var i = 0;
    while (i < tokens.length) {
      if (used[i]) {
        i += 1;
        continue;
      }
      final consumed =
          tryEvery(i) ??
          tryDue(i) ??
          tryDate(i) ??
          tryTime(i) ??
          tryDuration(i) ??
          tryTag(i) ??
          tryPriority(i) ??
          tryList(i) ??
          0;
      i += consumed > 1 ? consumed : 1;
    }
  }

  static List<String?>? groups(RegExp re, String s) {
    final m = re.firstMatch(s);
    if (m == null) return null;
    return [for (var g = 0; g <= m.groupCount; g++) m.group(g)];
  }

  // every …

  int? tryEvery(int i) {
    final a = word(i + 1);
    if (recurrence != null || word(i) != 'every' || a == null) return null;
    RecurrenceRule rule;
    String text;
    var count = 2;
    switch (a) {
      case 'day' || 'days':
        rule = RecurrenceRule(freq: Freq.daily);
        text = 'Every day';
      case 'weekday' || 'weekdays':
        rule = RecurrenceRule(freq: Freq.weekly, weekdays: [1, 2, 3, 4, 5]);
        text = 'Every weekday';
      case 'week' || 'weeks':
        rule = RecurrenceRule(freq: Freq.weekly);
        text = 'Every week';
      case 'month' || 'months':
        rule = RecurrenceRule(freq: Freq.monthly);
        text = 'Every month';
      case 'year' || 'years':
        rule = RecurrenceRule(freq: Freq.yearly);
        text = 'Every year';
      default:
        final d = QuickAddParser.weekdayNames[a];
        final n = _int(a);
        final unit = word(i + 2);
        if (d != null) {
          rule = RecurrenceRule(freq: Freq.weekly, weekdays: [d]);
          text = 'Every ${QuickAddParser.weekdayShort[d]}';
        } else if (n != null && n >= 1 && unit != null) {
          count = 3;
          final freq = switch (unit) {
            'day' || 'days' => Freq.daily,
            'week' || 'weeks' => Freq.weekly,
            'month' || 'months' => Freq.monthly,
            'year' || 'years' => Freq.yearly,
            _ => null,
          };
          if (freq == null) return null;
          rule = RecurrenceRule(freq: freq, interval: n);
          text = 'Every $n ${unit.endsWith('s') ? unit : '${unit}s'}';
        } else {
          return null;
        }
    }
    recurrence = rule;
    recurrenceText = text;
    take(i, count);
    return count;
  }

  // due …

  int? tryDue(int i) {
    if (due != null || word(i) != 'due') return null;
    final hit = dateAt(i + 1);
    final kind = hit?.kind;
    if (hit == null || kind is! _Day) return null;
    var count = 1 + hit.used;
    var text = kind.day.string;
    final t = timeAt(i + count);
    if (t != null) {
      text += 'T${PlannerMath.clock(t.minute)}';
      count += t.used;
    }
    due = text;
    take(i, count);
    return count;
  }

  // dates

  ({_DateKind kind, int used})? dateAt(int i) {
    final t = word(i);
    if (t == null) return null;
    final today = parser.today;
    switch (t) {
      case 'today' || 'tod':
        return (kind: _Day(today), used: 1);
      case 'tomorrow' || 'tmr' || 'tmrw':
        return (kind: _Day(today.adding(days: 1)), used: 1);
      case 'someday':
        return (kind: const _Someday(), used: 1);
      case 'next' when word(i + 1) == 'week':
        return (kind: _Week(today.weekStart().adding(days: 7)), used: 2);
      case 'this' when word(i + 1) == 'week':
        return (kind: _Week(today.weekStart()), used: 2);
      case 'in':
        final n = _int(word(i + 1));
        final unit = word(i + 2);
        if (n == null || n < 0 || unit == null) return null;
        return switch (unit) {
          'day' || 'days' => (kind: _Day(today.adding(days: n)), used: 3),
          'week' || 'weeks' => (kind: _Day(today.adding(days: n * 7)), used: 3),
          _ => null,
        };
    }
    final wd = QuickAddParser.weekdayNames[t];
    if (wd != null) {
      final delta = (wd - today.weekdayIndex + 7) % 7;
      return (kind: _Day(today.adding(days: delta)), used: 1);
    }
    final g = groups(QuickAddParser._slashDate, t);
    if (g != null) {
      final d = _int(g[1]), m = _int(g[2]);
      if (d != null && m != null) {
        final day = resolve(day: d, month: m);
        return day == null ? null : (kind: _Day(day), used: 1);
      }
    }
    final asDay = _int(t);
    final nextMonth = QuickAddParser.monthNames[word(i + 1)];
    if (asDay != null && nextMonth != null) {
      final day = resolve(day: asDay, month: nextMonth);
      return day == null ? null : (kind: _Day(day), used: 2);
    }
    final month = QuickAddParser.monthNames[t];
    final nextDay = _int(word(i + 1));
    if (month != null && nextDay != null) {
      final day = resolve(day: nextDay, month: month);
      return day == null ? null : (kind: _Day(day), used: 2);
    }
    return null;
  }

  /// This year, or next year when the day has already passed.
  /// Null for a day that does not exist.
  DayKey? resolve({required int day, required int month}) {
    if (month < 1 || month > 12 || day < 1) return null;
    final year = parser.today.year;
    if (day > DayKey.ymd(year, month, 1).daysInMonth) return null;
    final candidate = DayKey.ymd(year, month, day);
    if (candidate >= parser.today) return candidate;
    if (day > DayKey.ymd(year + 1, month, 1).daysInMonth) return null;
    return DayKey.ymd(year + 1, month, day);
  }

  int? tryDate(int i) {
    if (dateKind != null) return null;
    final hit = dateAt(i);
    if (hit == null) return null;
    dateKind = hit.kind;
    take(i, hit.used);
    return hit.used;
  }

  // times

  ({int minute, int used})? timeAt(int i) {
    final t = word(i);
    if (t == null) return null;
    final g12 = groups(QuickAddParser._clock12, t);
    final h12 = _int(g12?[1]);
    if (g12 != null && h12 != null && h12 >= 1 && h12 <= 12) {
      final m = _int(g12[2] ?? '0') ?? 0;
      if (m >= 60) return null;
      return (minute: _minute(h12, m, g12[3]), used: 1);
    }
    final g24 = groups(QuickAddParser._clock24, t);
    if (g24 != null) {
      final h = _int(g24[1]), m = _int(g24[2]);
      if (h != null && m != null && h < 24 && m < 60) {
        return (minute: h * 60 + m, used: 1);
      }
    }
    final next = word(i + 1);
    if (t == 'at' && next != null) {
      final g = groups(QuickAddParser._clockAfterAt, next);
      final h = _int(g?[1]);
      if (g != null && h != null) {
        final m = _int(g[2] ?? '0') ?? 0;
        if (m >= 60) return null;
        if (g[3] != null) {
          if (h < 1 || h > 12) return null;
        } else if (h >= 24) {
          return null;
        }
        return (minute: _minute(h, m, g[3]), used: 2);
      }
    }
    return null;
  }

  static int _minute(int hour, int minute, String? suffix) {
    var h = hour;
    if (suffix == 'am' && h == 12) h = 0;
    if (suffix == 'pm' && h < 12) h += 12;
    return h * 60 + minute;
  }

  int? tryTime(int i) {
    if (startMinute != null) return null;
    final hit = timeAt(i);
    if (hit == null) return null;
    startMinute = hit.minute;
    timeRange = (i, i + hit.used);
    take(i, hit.used);
    return hit.used;
  }

  // lengths

  int? lengthToken(String t) {
    final gm = groups(QuickAddParser._minutesOnly, t);
    final m = _int(gm?[1]);
    if (m != null) return m;
    final gh = groups(QuickAddParser._hoursMinutes, t);
    final h = gh == null ? null : double.tryParse(gh[1] ?? '');
    if (gh != null && h != null) {
      return (h * 60).round() + (_int(gh[2]) ?? 0);
    }
    return null;
  }

  int? tryDuration(int i) {
    final t = word(i);
    if (duration != null || t == null) return null;
    int? minutes;
    var count = 1;
    final next = word(i + 1);
    if (t == 'for' && next != null) {
      final m = lengthToken(next);
      final unit = word(i + 2);
      if (m != null) {
        minutes = m;
        count = 2;
      } else if (QuickAddParser._plainNumber.hasMatch(next) && unit != null) {
        final n = double.parse(next);
        switch (unit) {
          case 'h' || 'hr' || 'hrs' || 'hour' || 'hours':
            minutes = (n * 60).round();
            count = 3;
          case 'm' || 'min' || 'mins' || 'minute' || 'minutes':
            minutes = n.round();
            count = 3;
        }
      }
    } else {
      minutes = lengthToken(t);
    }
    if (minutes == null || minutes <= 0) return null;
    duration = minutes;
    take(i, count);
    return count;
  }

  // #tag  !2  /list

  int? tryTag(int i) {
    if (used[i]) return null;
    final name = groups(QuickAddParser._tagWord, tokens[i])?[1]?.toLowerCase();
    if (name == null) return null;
    if (!tags.contains(name)) tags.add(name);
    take(i, 1);
    return 1;
  }

  int? tryPriority(int i) {
    if (priority != null || !const ['!1', '!2', '!3'].contains(tokens[i])) {
      return null;
    }
    priority = int.parse(tokens[i].substring(1));
    take(i, 1);
    return 1;
  }

  int? tryList(int i) {
    final t = tokens[i];
    if (listName != null || t.length <= 1 || !t.startsWith('/')) return null;
    final query = t.substring(1).toLowerCase();
    final names = parser.lists;
    String? first(bool Function(String) test) {
      for (final n in names) {
        if (test(n.toLowerCase())) return n;
      }
      return null;
    }

    final match =
        first((n) => n == query) ??
        first((n) => n.startsWith(query)) ??
        first((n) => n.contains(query));
    if (match == null) return null;
    listName = match;
    take(i, 1);
    return 1;
  }

  // result

  QuickAddResult finish() {
    final today = parser.today;
    final kind = dateKind;
    DayKey? planDate = kind is _Day ? kind.day : null;
    final planWeek = kind is _Week ? kind.week : null;
    final someday = kind is _Someday;
    final rule = recurrence;
    if (rule != null && planDate == null && planWeek == null && !someday) {
      planDate = firstOccurrence(rule, today);
    }
    if (startMinute != null && planDate == null) {
      if (planWeek != null || someday) {
        // A week or someday task has no day, so it cannot have a block.
        // Keep the time as text.
        final r = timeRange;
        if (r != null) {
          for (var k = r.$1; k < r.$2; k++) {
            used[k] = false;
          }
        }
        startMinute = null;
      } else {
        planDate = today;
      }
    }
    final bucket = planDate != null
        ? TaskBucket.day
        : planWeek != null
        ? TaskBucket.week
        : someday
        ? TaskBucket.someday
        : TaskBucket.inbox;

    final title = [
      for (var k = 0; k < tokens.length; k++)
        if (!used[k]) tokens[k],
    ].join(' ');
    final draft = QuickAddResult(
      title: title,
      bucket: bucket,
      planDate: planDate,
      planWeek: planWeek,
      due: due,
      startMinute: startMinute,
      durationMin: duration,
      tags: List.unmodifiable(tags),
      priority: priority ?? 0,
      listName: listName,
      recurrence: recurrence,
      namedADay: kind != null,
    );
    return draft._withChips(chips(draft, someday: someday));
  }

  DayKey firstOccurrence(RecurrenceRule rule, DayKey day) {
    final days = rule.weekdays;
    if (rule.freq != Freq.weekly || days == null || days.isEmpty) return day;
    for (var k = 0; k < 7; k++) {
      final d = day.adding(days: k);
      if (days.contains(d.weekdayIndex)) return d;
    }
    return day;
  }

  List<QuickAddChip> chips(QuickAddResult r, {required bool someday}) {
    final out = <QuickAddChip>[];
    final d = r.planDate, w = r.planWeek;
    if (d != null) {
      out.add(
        QuickAddChip(
          ChipKind.date,
          '${QuickAddParser.weekdayShort[d.weekdayIndex]} ${d.day} '
          '${QuickAddParser.monthShort[d.month]}',
        ),
      );
    } else if (w != null) {
      out.add(
        QuickAddChip(
          ChipKind.date,
          'Week of ${w.day} ${QuickAddParser.monthShort[w.month]}',
        ),
      );
    } else if (someday) {
      out.add(const QuickAddChip(ChipKind.date, 'Someday'));
    }
    final s = r.startMinute, m = r.durationMin, t = recurrenceText;
    final due = r.due, l = r.listName;
    if (s != null) out.add(QuickAddChip(ChipKind.time, PlannerMath.clock(s)));
    if (m != null) {
      out.add(QuickAddChip(ChipKind.duration, PlannerMath.duration(m)));
    }
    if (t != null) out.add(QuickAddChip(ChipKind.repeats, t));
    if (due != null) {
      out.add(QuickAddChip(ChipKind.due, 'Due ${due.replaceAll('T', ' ')}'));
    }
    if (l != null) out.add(QuickAddChip(ChipKind.list, l));
    for (final tag in r.tags) {
      out.add(QuickAddChip(ChipKind.tag, '#$tag'));
    }
    if (r.priority > 0) {
      out.add(QuickAddChip(ChipKind.priority, '!${r.priority}'));
    }
    return out;
  }
}
