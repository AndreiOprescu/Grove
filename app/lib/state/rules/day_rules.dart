import '../../core/model/day_key.dart';
import '../../core/model/event.dart';
import '../../core/model/ids.dart';
import '../../core/model/link.dart';
import '../../core/model/task.dart';
import '../../core/parsing/reference_parser.dart';
import '../../core/planner/planner_math.dart';
import 'calendar_rules.dart';
import 'notes_rules.dart';
import 'text.dart';

enum AgendaKind { event, block, task }

/// One line in the day panel of a daily note.
class AgendaRow {
  const AgendaRow({
    required this.id,
    required this.kind,
    required this.title,
    this.start,
    this.end,
    this.allDay = false,
    this.done = false,
    required this.ref,
  });

  final String id;
  final AgendaKind kind;
  final String title;

  /// Minutes since midnight. Null for an all-day event and for a task that has
  /// no block on the day.
  final int? start;
  final int? end;
  final bool allDay;
  final bool done;

  /// What a click opens.
  final ItemRef ref;

  @override
  bool operator ==(Object other) =>
      other is AgendaRow &&
      other.id == id &&
      other.kind == kind &&
      other.title == title &&
      other.start == start &&
      other.end == end &&
      other.allDay == allDay &&
      other.done == done &&
      other.ref == ref;

  @override
  int get hashCode =>
      Object.hash(id, kind, title, start, end, allDay, done, ref);

  @override
  String toString() => 'AgendaRow($kind, $title, $start-$end)';
}

/// A busy day in the weekly review.
class BusyDay {
  const BusyDay({required this.day, required this.minutes});

  final DayKey day;
  final int minutes;

  @override
  bool operator ==(Object other) =>
      other is BusyDay && other.day == day && other.minutes == minutes;

  @override
  int get hashCode => Object.hash(day, minutes);

  @override
  String toString() => 'BusyDay($day, $minutes)';
}

/// What the week showed, for the review panel and the summary text.
class WeekReview {
  const WeekReview({
    required this.monday,
    required this.done,
    required this.open,
    required this.plannedMinutes,
    required this.doneMinutes,
    this.busiest,
  });

  final DayKey monday;

  /// Tasks finished in the week, in the order they were finished.
  final List<TaskItem> done;

  /// Tasks planned for the week that are still open. Tasks with a day come first.
  final List<TaskItem> open;

  /// Minutes of task blocks in the week.
  final int plannedMinutes;

  /// Minutes of those blocks whose task is done.
  final int doneMinutes;

  /// The day with the most booked time (task blocks and timed events). Null
  /// when no time is booked.
  final BusyDay? busiest;

  @override
  bool operator ==(Object other) =>
      other is WeekReview &&
      other.monday == monday &&
      sameList(other.done, done) &&
      sameList(other.open, open) &&
      other.plannedMinutes == plannedMinutes &&
      other.doneMinutes == doneMinutes &&
      other.busiest == busiest;

  @override
  int get hashCode => Object.hash(
    monday,
    Object.hashAll(done),
    Object.hashAll(open),
    plannedMinutes,
    doneMinutes,
    busiest,
  );
}

/// The rules behind the day panel and the weekly review. No database and no views here.
abstract final class DayRules {
  // The day panel

  /// What a day holds, in the order the panel shows it: all-day events, then
  /// events and task blocks by start time, then the day's tasks that have no
  /// block (open ones first). A task with a block shows once, as its block.
  static List<AgendaRow> agenda({
    required DayKey day,
    required List<EventItem> events,
    required List<TaskItem> dayTasks,
    required TaskItem? Function(String id) taskFor,
  }) {
    final allDay = <AgendaRow>[];
    final timed = <AgendaRow>[];
    final blocked = <String>{};
    for (final e in events) {
      if (!CalendarRules.covers(e, day)) continue;
      final id = e.taskId;
      final t = e.kind == EventKind.block && id != null ? taskFor(id) : null;
      if (t != null && id != null) {
        blocked.add(id);
        timed.add(
          AgendaRow(
            id: e.id,
            kind: AgendaKind.block,
            title: t.title,
            start: _start(e, day),
            end: _end(e, day),
            done: t.isDone,
            ref: ItemRef(ItemType.task, id),
          ),
        );
      } else if (e.allDay) {
        allDay.add(
          AgendaRow(
            id: e.id,
            kind: AgendaKind.event,
            title: e.title,
            allDay: true,
            ref: ItemRef(ItemType.event, e.id),
          ),
        );
      } else {
        timed.add(
          AgendaRow(
            id: e.id,
            kind: AgendaKind.event,
            title: e.title,
            start: _start(e, day),
            end: _end(e, day),
            ref: ItemRef(ItemType.event, e.id),
          ),
        );
      }
    }
    _stableSort(allDay, (a, b) => compareIgnoringCase(a.title, b.title));
    _stableSort(timed, (a, b) {
      final start = (a.start ?? 0).compareTo(b.start ?? 0);
      if (start != 0) return start;
      final end = (a.end ?? 0).compareTo(b.end ?? 0);
      return end != 0 ? end : a.title.compareTo(b.title);
    });
    final loose = dayTasks.where((t) => !blocked.contains(t.id));
    final tasks = [
      ...loose.where((t) => !t.isDone),
      ...loose.where((t) => t.isDone),
    ];
    return [
      ...allDay,
      ...timed,
      for (final t in tasks)
        AgendaRow(
          id: t.id,
          kind: AgendaKind.task,
          title: t.title,
          done: t.isDone,
          ref: ItemRef(ItemType.task, t.id),
        ),
    ];
  }

  static void _stableSort<T>(List<T> list, int Function(T a, T b) compare) {
    final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
    indexed.sort((x, y) {
      final c = compare(x.$2, y.$2);
      return c != 0 ? c : x.$1.compareTo(y.$1);
    });
    for (var i = 0; i < list.length; i++) {
      list[i] = indexed[i].$2;
    }
  }

  static int _start(EventItem e, DayKey day) =>
      e.start.day == day ? e.start.minute : 0;
  static int _end(EventItem e, DayKey day) =>
      e.end.day == day ? e.end.minute : 1440;

  /// "09:00" or "09:00–10:30" for a timed row. "All day" for an all-day event.
  /// Empty for a task with no block.
  static String timeLabel(AgendaRow row) {
    if (row.allDay) return 'All day';
    final s = row.start, e = row.end;
    if (s == null || e == null) return '';
    return e > s
        ? '${PlannerMath.clock(s)}–${PlannerMath.clock(e == 1440 ? 1439 : e)}'
        : PlannerMath.clock(s);
  }

  /// The clock time a task was finished. `completedAt` is "YYYY-MM-DDTHH:MM:SS".
  static String finishedClock(TaskItem task) {
    final at = task.completedAt;
    if (at == null || at.length < 16) return '';
    return at.substring(11, 16);
  }

  // The weekly review

  static WeekReview review({
    required DayKey monday,
    required List<TaskItem> done,
    required List<TaskItem> openCandidates,
    required List<EventItem> events,
    required TaskItem? Function(String id) taskFor,
  }) {
    final seen = <String>{};
    final stillOpen = [
      for (final t in openCandidates)
        if (t.status == TaskStatus.open && seen.add(t.id)) t,
    ];
    // Tasks with a day first.
    final open = [
      ...stillOpen.where((t) => t.planDate != null),
      ...stillOpen.where((t) => t.planDate == null),
    ];

    var planned = 0, finished = 0;
    final perDay = <DayKey, int>{};
    final sunday = monday.adding(days: 6);
    for (final e in events) {
      if (e.allDay) continue;
      // A block or event that runs past midnight counts on each day it touches.
      for (var day = e.start.day; day <= e.end.day; day = day.adding(days: 1)) {
        final from = day == e.start.day ? e.start.minute : 0;
        final to = day == e.end.day ? e.end.minute : 1440;
        if (to > from && day >= monday && day <= sunday) {
          perDay[day] = (perDay[day] ?? 0) + to - from;
        }
      }
      final id = e.taskId;
      if (e.kind != EventKind.block || id == null) continue;
      final t = taskFor(id);
      if (t == null) continue;
      planned += e.durationMinutes;
      if (t.isDone) finished += e.durationMinutes;
    }
    BusyDay? busiest;
    for (final entry in perDay.entries) {
      if (entry.value <= 0) continue;
      final b = busiest;
      if (b == null ||
          entry.value > b.minutes ||
          (entry.value == b.minutes && entry.key < b.day)) {
        busiest = BusyDay(day: entry.key, minutes: entry.value);
      }
    }
    return WeekReview(
      monday: monday,
      done: done,
      open: open,
      plannedMinutes: planned,
      doneMinutes: finished,
      busiest: busiest,
    );
  }

  // The summary text

  /// The first line of the summary. It marks the block, so a second click can replace it.
  static const summaryHeading = '**Week summary**';

  static String _count(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

  static String _mentions(List<TaskItem> tasks, {int limit = 8}) {
    final shown = tasks
        .take(limit)
        .map((t) => ReferenceParser.mention(title: t.title, id: t.id))
        .join(', ');
    return tasks.length > limit
        ? '$shown and ${tasks.length - limit} more'
        : shown;
  }

  /// Plain Markdown lines with no blank line, so the block can be found again.
  static String summary(WeekReview r) {
    final b = r.busiest;
    return [
      summaryHeading,
      '- Done: ${_count(r.done.length, 'task')}',
      '- Still open: ${_count(r.open.length, 'task')}',
      r.plannedMinutes == 0
          ? '- Time: no task blocks planned'
          : '- Time: ${PlannerMath.duration(r.doneMinutes)} finished of '
                '${PlannerMath.duration(r.plannedMinutes)} planned',
      if (b != null)
        '- Busiest day: ${NotesRules.weekdayName(b.day)}, ${PlannerMath.duration(b.minutes)}',
      if (r.done.isNotEmpty) '- Finished: ${_mentions(r.done)}',
      if (r.open.isNotEmpty) '- Left open: ${_mentions(r.open)}',
    ].join('\n');
  }

  static bool hasSummary(String body) =>
      body.split('\n').any((l) => trimSpaces(l) == summaryHeading);

  /// Puts [block] under the `## Review` heading. A summary that is already
  /// there is replaced. The heading is added at the end when the note has none.
  static String insert(String block, {required String into}) {
    final body = into;
    final lines = body.split('\n');
    final blockLines = block.split('\n');
    bool isBlank(String s) => trimSpaces(s).isEmpty;

    final old = lines.indexWhere((l) => trimSpaces(l) == summaryHeading);
    if (old >= 0) {
      var end = old + 1;
      while (end < lines.length && !isBlank(lines[end])) {
        end += 1;
      }
      lines.replaceRange(old, end, blockLines);
      return lines.join('\n');
    }
    final review = lines.indexWhere((l) => trimSpaces(l) == '## Review');
    if (review >= 0) {
      final next = review + 1;
      final needsGap = next < lines.length && !isBlank(lines[next]);
      lines.insertAll(next, needsGap ? [...blockLines, ''] : blockLines);
      return lines.join('\n');
    }
    var head = body;
    while (head.endsWith('\n')) {
      head = head.substring(0, head.length - 1);
    }
    return '${head.isEmpty ? '' : '$head\n\n'}## Review\n$block\n';
  }
}
