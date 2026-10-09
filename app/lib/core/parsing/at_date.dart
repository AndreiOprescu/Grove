import '../model/day_key.dart';
import '../planner/planner_math.dart';
import 'markdown_edit.dart';
import 'note_parser.dart';
import 'quick_add_parser.dart';

/// An `@date time` token in a line of a note, like `@fri 3pm` or
/// `@tomorrow 14:00 for 1h` (PLAN §5.5 item 2).
class AtDate {
  const AtDate({
    required this.range,
    this.day,
    this.startMinute,
    this.durationMin,
  });

  /// The whole token, from the `@` to the last word it uses. UTF-16 offsets in the line.
  final Utf16Range range;

  /// The day. Null when the token has only a time (`@3pm`): the caller picks the day.
  final DayKey? day;

  /// Minute of the day. Null for a token with a day and no time.
  final int? startMinute;
  final int? durationMin;

  @override
  bool operator ==(Object other) =>
      other is AtDate &&
      other.range == range &&
      other.day == day &&
      other.startMinute == startMinute &&
      other.durationMin == durationMin;

  @override
  int get hashCode => Object.hash(range, day, startMinute, durationMin);
}

/// Space or tab, like Foundation's `CharacterSet.whitespaces` (Unicode Zs plus tab).
bool isSpaceOrTab(int c) =>
    c == 0x20 ||
    c == 0x09 ||
    c == 0xA0 ||
    c == 0x1680 ||
    (c >= 0x2000 && c <= 0x200A) ||
    c == 0x202F ||
    c == 0x205F ||
    c == 0x3000;

abstract final class AtDateParser {
  /// The longest phrase that can follow the `@`. "next week" or "in 3 days 3pm for 1h" are the long ones.
  static const _maxWords = 7;

  /// The first `@` token in the line that holds a day or a time. The `@` must start the line
  /// or follow a space, so an e-mail address is never a token. The token uses the same words
  /// as quick-add.
  static AtDate? find(String line, {DayKey? today}) {
    final day = today ?? DayKey.today();
    var at = 0;
    while (at < line.length) {
      final found = line.indexOf('@', at);
      if (found < 0) return null;
      at = found + 1;
      if (found > 0 && !isSpaceOrTab(line.codeUnitAt(found - 1))) continue;
      final hit = _token(line, found, day);
      if (hit != null) return hit;
    }
    return null;
  }

  /// The words after the `@`, each with its end offset.
  static List<({String text, int end})> _words(String line, int start) {
    final out = <({String text, int end})>[];
    var i = start;
    while (i < line.length && out.length < _maxWords) {
      while (i < line.length && isSpaceOrTab(line.codeUnitAt(i))) {
        i += 1;
      }
      final from = i;
      while (i < line.length && !isSpaceOrTab(line.codeUnitAt(i))) {
        i += 1;
      }
      if (i > from) out.add((text: line.substring(from, i), end: i));
    }
    return out;
  }

  static AtDate? _token(String line, int start, DayKey today) {
    final list = _words(line, start + 1);
    final parser = QuickAddParser(today: today);
    for (var k = list.length; k >= 1; k--) {
      final phrase = list.take(k).map((w) => w.text).join(' ');
      // The phrase counts only when the parser reads every word of it and nothing
      // but a day, a time or a length.
      final r = parser.parse('X $phrase');
      if (r.title != 'X' ||
          r.tags.isNotEmpty ||
          r.priority != 0 ||
          r.listName != null ||
          r.recurrence != null ||
          r.due != null ||
          (r.planDate == null && r.startMinute == null)) {
        continue;
      }
      final end = list[k - 1].end;
      // A time with no day word gets today from quick-add, so ask if a day word was there.
      return AtDate(
        range: Utf16Range(start, end - start),
        day: r.namedADay ? r.planDate : null,
        startMinute: r.startMinute,
        durationMin: r.durationMin,
      );
    }
    return null;
  }
}

/// What one `@date` line of a note becomes when it goes to the planner (PLAN §5.5 item 2).
/// This is only text work. The store makes the event or the task.
class AtDatePlan {
  const AtDatePlan({
    required this.title,
    required this.day,
    required this.isTask,
    required this.head,
    this.startMinute,
    this.durationMin,
    this.taskId,
  });

  /// The words of the line with the token, the list marker and the hidden task mark taken out.
  final String title;
  final DayKey day;

  /// Minute of the day. Null when the token named a day and no time.
  final int? startMinute;

  /// Minutes the user asked for ("for 1h"). Null when the user did not say.
  final int? durationMin;

  /// The line is an open check box. It makes a task and a block. Any other line makes an event.
  final bool isTask;

  /// The task that the check box already has.
  final String? taskId;

  /// Indent and list marker, as typed.
  final String head;

  /// An event with a time and no length lasts this long.
  static const eventMinutes = 60;

  /// A task block with a time and no length lasts this long.
  static const blockMinutes = 30;

  @override
  bool operator ==(Object other) =>
      other is AtDatePlan &&
      other.title == title &&
      other.day == day &&
      other.startMinute == startMinute &&
      other.durationMin == durationMin &&
      other.isTask == isTask &&
      other.taskId == taskId &&
      other.head == head;

  @override
  int get hashCode =>
      Object.hash(title, day, startMinute, durationMin, isTask, taskId, head);
}

abstract final class AtDatePlanner {
  static final _endBreaks = RegExp(
    r'^[\n\x0B\x0C\r\u0085\u2028\u2029]+|[\n\x0B\x0C\r\u0085\u2028\u2029]+$',
  );
  static final _manySpaces = RegExp(r'\s{2,}');

  /// Reads one line. Null when it has no `@date` token, no words besides the token,
  /// or is a ticked box. `noteDay` is the day of a daily note: a token with a time and
  /// no day uses it.
  static AtDatePlan? plan(String raw, {DayKey? noteDay, DayKey? today}) {
    final now = today ?? DayKey.today();
    final line = raw.replaceAll(_endBreaks, '');
    final prefix = MarkdownEdit.prefix(line);
    var bodyStart = prefix?.length ?? 0;
    if (prefix == null) {
      while (bodyStart < line.length && line.codeUnitAt(bodyStart) == 0x20) {
        bodyStart += 1;
      }
    }
    var isTask = false;
    if (prefix?.kind == PrefixKind.checklist) {
      if (prefix!.checked) return null;
      isTask = true;
    } else if (line.contains('⟦t:')) {
      return null;
    }
    final hit = AtDateParser.find(line, today: now);
    if (hit == null || hit.range.location < bodyStart) return null;

    var title = line.replaceRange(hit.range.location, hit.range.end, '');
    title = title.substring(
      bodyStart < title.length ? bodyStart : title.length,
    );
    final words = _trimSpaces(
      NoteParser.withoutMarkers(title).replaceAll(_manySpaces, ' '),
    );
    if (words.isEmpty) return null;

    final taskId = isTask
        ? NoteParser.checkboxes(line).firstOrNull?.taskId
        : null;
    return AtDatePlan(
      title: words,
      day: hit.day ?? noteDay ?? now,
      startMinute: hit.startMinute,
      durationMin: hit.durationMin,
      isTask: isTask,
      taskId: taskId,
      head: line.substring(0, bodyStart),
    );
  }

  static String _trimSpaces(String s) {
    var a = 0, b = s.length;
    while (a < b && isSpaceOrTab(s.codeUnitAt(a))) {
      a += 1;
    }
    while (b > a && isSpaceOrTab(s.codeUnitAt(b - 1))) {
      b -= 1;
    }
    return s.substring(a, b);
  }

  /// The minutes the new event or block covers. Null when the plan has no time.
  static ({int start, int end})? span(
    AtDatePlan plan, {
    required int defaultMinutes,
  }) {
    final start = plan.startMinute;
    if (start == null) return null;
    final asked = plan.durationMin ?? defaultMinutes;
    final length = asked < 5 ? 5 : asked;
    final end = start + length;
    return (start: start, end: end > 1440 ? 1440 : end);
  }

  /// "Fri 3 Oct", "Fri 3 Oct, 15:00" or "Fri 3 Oct, 15:00–16:00".
  static String whenLabel(DayKey day, {int? start, int? end}) {
    final label =
        '${QuickAddParser.weekdayShort[day.weekdayIndex]} ${day.day} '
        '${QuickAddParser.monthShort[day.month]}';
    if (start == null) return label;
    final from = '$label, ${PlannerMath.clock(start)}';
    if (end == null || end <= start) return from;
    return '$from–${PlannerMath.clock(end < 1439 ? end : 1439)}';
  }

  /// The line after a check box went to the planner: the words, when, and the hidden mark
  /// of the task. The token is gone. The box keeps its place in the list.
  static String taskLine(
    AtDatePlan plan, {
    required String taskId,
    required String when,
  }) => '${plan.head}${plan.title} · $when ${NoteParser.marker(taskId)}';

  /// The line after an event was made: a link to it, then when. `mention` is `[[Title|ID]]`.
  static String eventLine(
    AtDatePlan plan, {
    required String mention,
    required String when,
  }) => '${plan.head}$mention · $when';
}
