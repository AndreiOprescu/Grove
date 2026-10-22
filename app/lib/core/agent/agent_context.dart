import '../model/day_key.dart';
import '../model/event.dart';
import '../model/task.dart';
import 'agent_models.dart';

/// One thing on a day of the plan: an event or a block of a task.
class AgentPlanItem {
  const AgentPlanItem({
    required this.day,
    required this.start,
    required this.end,
    required this.title,
    this.taskId,
    this.isDone = false,
  });

  final DayKey day;

  /// Minutes after midnight.
  final int start;
  final int end;
  final String title;

  /// The task of a block. Null for an event.
  final String? taskId;
  final bool isDone;
}

/// Writes the plan of the person as text for the agent (ADR 0005): the
/// next days with their events and blocks, the deadlines, and the open
/// tasks with their ids, so the agent can propose changes.
abstract final class AgentContext {
  /// How many days from today the agent sees.
  static const days = 7;

  /// The most open tasks in the text. The first ones in list order stay.
  static const maxTasks = 150;

  /// The longest title in the text.
  static const _maxTitle = 120;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static String _title(String t) {
    final one = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return one.length > _maxTitle ? '${one.substring(0, _maxTitle)}…' : one;
  }

  static String _day(DayKey d) =>
      '${d.string} ${_weekdays[d.weekdayIndex - 1]}';

  /// The text. [items] and [deadlines] outside the [days] from [today] are
  /// left out, except a deadline that is not done yet and is late.
  static String plan({
    required DayKey today,
    required int nowMinute,
    required List<AgentPlanItem> items,
    required List<EventItem> deadlines,
    required List<TaskItem> openTasks,
  }) {
    final last = today.adding(days: days - 1);
    final out = <String>[
      'Now: ${_day(today)} ${AgentTime.format(nowMinute)}',
      '',
      'Days (events and task blocks):',
    ];
    for (final d in today.rangeThrough(last)) {
      final list = [
        for (final i in items)
          if (i.day == d) i,
      ]..sort((a, b) => a.start.compareTo(b.start));
      out.add(_day(d));
      if (list.isEmpty) out.add('- nothing');
      for (final i in list) {
        final time = '${AgentTime.format(i.start)}–${AgentTime.format(i.end)}';
        final what = i.taskId == null
            ? 'event'
            : 'task ${i.taskId}${i.isDone ? ', done' : ''}';
        out.add('- $time ${_title(i.title)} ($what)');
      }
    }
    final shown = [
      for (final e in deadlines)
        if (e.end.day <= last && (e.end.day >= today || e.doneAt == null)) e,
    ]..sort((a, b) => a.end.compareTo(b.end));
    if (shown.isNotEmpty) {
      out
        ..add('')
        ..add('Deadlines:');
      for (final e in shown) {
        final late = e.doneAt == null && e.end.day < today ? ', late' : '';
        final done = e.doneAt != null ? ', done' : '';
        out.add(
          '- ${e.end.day.string} ${AgentTime.format(e.end.minute)} '
          '${_title(e.title)}$done$late',
        );
      }
    }
    out
      ..add('')
      ..add('Open tasks (id: title; details):');
    if (openTasks.isEmpty) out.add('- none');
    for (final t in openTasks.take(maxTasks)) {
      final details = [
        if (t.planDate case final d?)
          'day ${d.string}'
        else if (t.planWeek case final w?)
          'week of ${w.string}',
        '${t.estimateMin} min',
        if (t.due case final due? when due.isNotEmpty) 'due $due',
        if (t.priority > 0) 'priority ${t.priority}',
        if (t.parentId case final p?) 'subtask of $p',
      ];
      out.add('- ${t.id}: ${_title(t.title)}; ${details.join(', ')}');
    }
    if (openTasks.length > maxTasks) {
      out.add('- … and ${openTasks.length - maxTasks} more');
    }
    return out.join('\n');
  }
}
