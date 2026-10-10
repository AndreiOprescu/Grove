import '../../core/model/day_key.dart';
import '../../core/model/note.dart';
import '../../core/parsing/note_parser.dart';
import '../../core/parsing/reference_parser.dart';
import 'text.dart';

/// Which notes the list shows.
class NoteFilter {
  const NoteFilter._(this._kind, [this.tagName]);

  /// Notes that have this tag.
  const NoteFilter.tag(String name) : this._('tag', name);

  static const all = NoteFilter._('all');
  static const daily = NoteFilter._('daily');
  static const weekly = NoteFilter._('weekly');
  static const pinned = NoteFilter._('pinned');

  final String _kind;

  /// Set for a tag filter only.
  final String? tagName;

  @override
  bool operator ==(Object other) =>
      other is NoteFilter && other._kind == _kind && other.tagName == tagName;

  @override
  int get hashCode => Object.hash(_kind, tagName);

  @override
  String toString() => tagName == null ? _kind : 'tag($tagName)';
}

/// The small rules behind the notes screen: titles, templates, the list filter
/// and the preview line. Names are fixed English words so a title never depends
/// on the device's language.
abstract final class NotesRules {
  static const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  static const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  /// "Friday, 2 October 2026"
  static String dailyTitle(DayKey day) =>
      '${weekdays[day.weekdayIndex - 1]}, ${day.day} ${months[day.month - 1]} ${day.year}';

  /// "Friday"
  static String weekdayName(DayKey day) => weekdays[day.weekdayIndex - 1];

  /// "2 Oct"
  static String shortDate(DayKey d) =>
      '${d.day} ${months[d.month - 1].substring(0, 3)}';

  /// "Friday 2 October". For the busy-day warning.
  static String longDay(DayKey d) =>
      '${weekdayName(d)} ${d.day} ${months[d.month - 1]}';

  /// "Fri 2 Oct"
  static String shortDay(DayKey d) =>
      '${weekdayName(d).substring(0, 3)} ${shortDate(d)}';

  /// "Week 40 · 28 Sep – 4 Oct"
  static String weeklyTitle(DayKey monday) =>
      'Week ${weekNumber(monday)} · ${shortDate(monday)} – ${shortDate(monday.adding(days: 6))}';

  /// The calendar week of the year (week 1 holds the first Thursday).
  static int weekNumber(DayKey day) => day.weekOfYear;

  static String template(NoteKind kind) => switch (kind) {
    NoteKind.daily => '## Plan\n\n## Notes\n\n## Reflection\n',
    NoteKind.weekly => '## Goals\n\n## Notes\n\n## Review\n',
    NoteKind.note => '',
  };

  /// Keeps the notes the filter allows. The order stays as given.
  static List<Note> filter(
    List<Note> notes,
    NoteFilter f, {
    required List<String> Function(String noteId) tagsOf,
  }) {
    if (f == NoteFilter.all) return notes;
    if (f == NoteFilter.daily) {
      return [
        for (final n in notes)
          if (n.kind == NoteKind.daily) n,
      ];
    }
    if (f == NoteFilter.weekly) {
      return [
        for (final n in notes)
          if (n.kind == NoteKind.weekly) n,
      ];
    }
    if (f == NoteFilter.pinned) {
      return [
        for (final n in notes)
          if (n.pinned) n,
      ];
    }
    final name = (f.tagName ?? '').toLowerCase();
    return [
      for (final n in notes)
        if (tagsOf(n.id).any((t) => t.toLowerCase() == name)) n,
    ];
  }

  static final _imageRegex = RegExp(r'!\[[^\]\n]*\]\([^)\n]*\)');
  static final _prefixRegex = RegExp(
    r'^\s*(?:- \[[ xX]\]\s*|[-*]\s+|>\s*|\d+\.\s+)',
  );

  /// One short line for the list: the first line that has words, without marks.
  static String preview(String body, {int limit = 90}) {
    for (final raw in body.split('\n')) {
      if (raw.isEmpty || raw.startsWith('#')) continue;
      var line = raw.replaceAll(_imageRegex, '');
      line = line.replaceFirst(_prefixRegex, '');
      line = ReferenceParser.searchText(NoteParser.withoutMarkers(line));
      line = trimSpaces(line.replaceAll('**', '').replaceAll('`', ''));
      if (line.isEmpty) continue;
      return line.runes.length > limit
          ? '${trimSpaces(prefixRunes(line, limit))}…'
          : line;
    }
    return '';
  }

  /// "Ideas copy", then "Ideas copy 2", …
  static String copyTitle(String title, {required Set<String> existing}) {
    final taken = {for (final e in existing) e.toLowerCase()};
    var candidate = '$title copy', n = 2;
    while (taken.contains(candidate.toLowerCase())) {
      candidate = '$title copy $n';
      n += 1;
    }
    return candidate;
  }

  /// "Untitled", then "Untitled 2", …
  static String untitled({required Set<String> existing}) {
    final taken = {for (final e in existing) e.toLowerCase()};
    var candidate = 'Untitled', n = 2;
    while (taken.contains(candidate.toLowerCase())) {
      candidate = 'Untitled $n';
      n += 1;
    }
    return candidate;
  }
}
