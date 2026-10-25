import '../../core/model/day_key.dart';
import '../../core/model/note.dart';
import '../../core/model/notebook.dart';
import '../../core/parsing/markdown_plain.dart';
import '../../core/parsing/note_parser.dart';
import 'text.dart';

/// The kinds of [NoteSection].
enum NoteSectionKind {
  all,
  inbox,
  daily,
  weekly,
  pinned,
  meetings,
  withTasks,
  archive,
  notebook,
  tag,
}

/// Which notes the list shows: a section of the notes sidebar, one notebook,
/// or one tag.
class NoteSection {
  const NoteSection._(this.kind, [this._value]);

  /// The notes of one notebook.
  const NoteSection.notebook(String id) : this._(NoteSectionKind.notebook, id);

  /// Notes that have this tag.
  const NoteSection.tag(String name) : this._(NoteSectionKind.tag, name);

  /// Every note that is not archived.
  static const all = NoteSection._(NoteSectionKind.all);

  /// Plain notes in no notebook that are not meeting notes.
  static const inbox = NoteSection._(NoteSectionKind.inbox);
  static const daily = NoteSection._(NoteSectionKind.daily);
  static const weekly = NoteSection._(NoteSectionKind.weekly);
  static const pinned = NoteSection._(NoteSectionKind.pinned);

  /// Notes linked to an event.
  static const meetings = NoteSection._(NoteSectionKind.meetings);

  /// Notes with a task that is still open.
  static const withTasks = NoteSection._(NoteSectionKind.withTasks);

  /// The archived notes. They show nowhere else.
  static const archive = NoteSection._(NoteSectionKind.archive);

  /// The sections that are always in the sidebar, in sidebar order.
  static const fixed = [
    all,
    inbox,
    daily,
    weekly,
    pinned,
    meetings,
    withTasks,
    archive,
  ];

  final NoteSectionKind kind;
  final String? _value;

  /// Set for a tag section only.
  String? get tagName => kind == NoteSectionKind.tag ? _value : null;

  /// Set for a notebook section only.
  String? get notebookId => kind == NoteSectionKind.notebook ? _value : null;

  @override
  bool operator ==(Object other) =>
      other is NoteSection && other.kind == kind && other._value == _value;

  @override
  int get hashCode => Object.hash(kind, _value);

  @override
  String toString() => _value == null ? kind.name : '${kind.name}($_value)';
}

/// What the sections need to know beyond the notes themselves. The store
/// reads both sets with one query each.
class NoteFacts {
  const NoteFacts({
    this.meetingIds = const {},
    this.openTaskNoteIds = const {},
  });

  /// Notes linked to an event, either way.
  final Set<String> meetingIds;

  /// Notes that a task that is still open came from.
  final Set<String> openTaskNoteIds;
}

/// A run of notes under one heading: a date group ("Today") or a section of
/// a notebook ([sectionId]; the notes in no section have the label '').
class NoteGroup {
  const NoteGroup({required this.label, required this.notes, this.sectionId});

  final String label;
  final String? sectionId;
  final List<Note> notes;

  @override
  String toString() => 'NoteGroup($label, ${notes.length})';
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

  /// True for a daily note with nothing of its own: no mood, no pin, and
  /// no line that is not a line of [template] or of the first template
  /// (blank lines and the headings do not count). Grove does not keep such
  /// a note.
  static bool isEmptyDaily(Note n, {required String template}) {
    if (n.kind != NoteKind.daily || n.mood != null || n.pinned) return false;
    final given = {
      for (final t in [template, NotesRules.template(NoteKind.daily)])
        for (final l in t.split('\n')) l.trim(),
    };
    return NoteParser.withoutMarkers(n.body)
        .split('\n')
        .map((l) => l.trim())
        .every((l) => l.isEmpty || given.contains(l));
  }

  /// True when note [n] shows in section [s].
  static bool inSection(
    Note n,
    NoteSection s, {
    NoteFacts facts = const NoteFacts(),
    required List<String> Function(String noteId) tagsOf,
  }) {
    if (s.kind == NoteSectionKind.archive) return n.archived;
    if (n.archived) return false;
    return switch (s.kind) {
      NoteSectionKind.all => true,
      NoteSectionKind.inbox =>
        n.kind == NoteKind.note &&
            n.notebookId == null &&
            !facts.meetingIds.contains(n.id),
      NoteSectionKind.daily => n.kind == NoteKind.daily,
      NoteSectionKind.weekly => n.kind == NoteKind.weekly,
      NoteSectionKind.pinned => n.pinned,
      NoteSectionKind.meetings => facts.meetingIds.contains(n.id),
      NoteSectionKind.withTasks => facts.openTaskNoteIds.contains(n.id),
      NoteSectionKind.notebook => n.notebookId == s.notebookId,
      NoteSectionKind.tag => tagsOf(
        n.id,
      ).any((t) => t.toLowerCase() == (s.tagName ?? '').toLowerCase()),
      NoteSectionKind.archive => n.archived,
    };
  }

  /// Keeps the notes the section allows. The order stays as given.
  static List<Note> filter(
    List<Note> notes,
    NoteSection s, {
    NoteFacts facts = const NoteFacts(),
    required List<String> Function(String noteId) tagsOf,
  }) => [
    for (final n in notes)
      if (inSection(n, s, facts: facts, tagsOf: tagsOf)) n,
  ];

  /// How many notes each fixed section and each notebook has, in one pass.
  /// Every fixed section and every id of [notebookIds] has an entry, 0 when
  /// empty. Tags are not counted.
  static Map<NoteSection, int> counts(
    List<Note> notes, {
    NoteFacts facts = const NoteFacts(),
    Iterable<String> notebookIds = const [],
  }) {
    final out = <NoteSection, int>{
      for (final s in NoteSection.fixed) s: 0,
      for (final id in notebookIds) NoteSection.notebook(id): 0,
    };
    void add(NoteSection s) => out[s] = (out[s] ?? 0) + 1;
    List<String> noTags(String _) => const [];
    for (final n in notes) {
      for (final s in NoteSection.fixed) {
        if (inSection(n, s, facts: facts, tagsOf: noTags)) add(s);
      }
      final book = n.notebookId;
      if (book != null && !n.archived) add(NoteSection.notebook(book));
    }
    return out;
  }

  /// The day a note is listed under: its day for a daily or weekly note,
  /// else the day of its last edit.
  static DayKey listDay(Note n) => n.kind != NoteKind.note && n.date != null
      ? n.date!
      : DayKey(
          n.updatedAt.length >= 10 ? n.updatedAt.substring(0, 10) : n.updatedAt,
        );

  /// The notes in date groups, as of [now]: Upcoming (after this week),
  /// Today, Yesterday, This week, Last week, then one group per month,
  /// newest first ("October", "December 2025" for another year). Weeks start
  /// on Monday. In a group the newest day comes first. An empty group is
  /// left out.
  static List<NoteGroup> dateGroups(List<Note> notes, {required DateTime now}) {
    final today = DayKey.fromDate(now);
    final yesterday = today.adding(days: -1);
    final monday = today.weekStart();
    final lastMonday = monday.adding(days: -7);
    final sunday = monday.adding(days: 6);
    final nowMonths = now.year * 12 + now.month;
    (int, String) groupOf(DayKey d) {
      if (d > sunday) return (0, 'Upcoming');
      if (d == today) return (1, 'Today');
      if (d == yesterday) return (2, 'Yesterday');
      if (d >= monday) return (3, 'This week');
      if (d >= lastMonday) return (4, 'Last week');
      final name = months[d.month - 1];
      return (
        5 + nowMonths - (d.year * 12 + d.month),
        d.year == now.year ? name : '$name ${d.year}',
      );
    }

    String key(Note n) => n.kind != NoteKind.note && n.date != null
        ? n.date!.string
        : n.updatedAt;
    final indexed = [for (var i = 0; i < notes.length; i++) (i, notes[i])]
      ..sort((a, b) {
        final c = key(b.$2).compareTo(key(a.$2));
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    final groups = <(int, String), List<Note>>{};
    for (final (_, n) in indexed) {
      (groups[groupOf(listDay(n))] ??= []).add(n);
    }
    final keys = groups.keys.toList()..sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final k in keys) NoteGroup(label: k.$2, notes: groups[k]!)];
  }

  /// The notes of one notebook in groups: first the notes in no section
  /// (label '', always there; a note whose section is gone is one of them),
  /// then each section in its order, empty ones too. In a group the notes
  /// are in their order.
  static List<NoteGroup> notebookGroups(
    List<Note> notes,
    List<NotebookSection> sections,
  ) {
    final ordered = [for (var i = 0; i < sections.length; i++) (i, sections[i])]
      ..sort((a, b) {
        final c = a.$2.sortOrder.compareTo(b.$2.sortOrder);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    final known = {for (final s in sections) s.id};
    final bySection = <String?, List<Note>>{};
    final sorted = [for (var i = 0; i < notes.length; i++) (i, notes[i])]
      ..sort((a, b) {
        final c = a.$2.sortOrder.compareTo(b.$2.sortOrder);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    for (final (_, n) in sorted) {
      final s = known.contains(n.sectionId) ? n.sectionId : null;
      (bySection[s] ??= []).add(n);
    }
    return [
      NoteGroup(label: '', notes: bySection[null] ?? const []),
      for (final (_, s) in ordered)
        NoteGroup(
          label: s.name,
          sectionId: s.id,
          notes: bySection[s.id] ?? const [],
        ),
    ];
  }

  /// The order for item [id] put at [index] among [others] (in order,
  /// without [id]): halfway between its neighbours, one before the first,
  /// one after the last, or 1 in an empty list. When the neighbours have no
  /// room between them, every item gets a new order 1, 2, 3, … The result
  /// has each item whose order changes.
  static Map<String, double> placeAt(
    String id,
    List<({String id, double order})> others,
    int index,
  ) {
    final at = index.clamp(0, others.length);
    if (others.isEmpty) return {id: 1.0};
    if (at == 0) return {id: others.first.order - 1};
    if (at == others.length) return {id: others.last.order + 1};
    final before = others[at - 1].order, after = others[at].order;
    final mid = (before + after) / 2;
    if (before < mid && mid < after) return {id: mid};
    final ids = [for (final o in others) o.id]..insert(at, id);
    return {for (var i = 0; i < ids.length; i++) ids[i]: (i + 1).toDouble()};
  }

  static final _imageRegex = RegExp(r'!\[[^\]\n]*\]\([^)\n]*\)');
  static final _prefixRegex = RegExp(
    r'^\s*(?:- \[[ xX]\]\s*|[-*]\s+|>\s*|\d+\.\s+)',
  );

  /// One short line for the list: the first line that has words, without marks.
  static String preview(String body, {int limit = 90}) {
    for (final raw in body.split('\n')) {
      if (raw.isEmpty || raw.startsWith('#')) continue;
      var line = MarkdownPlain.text(raw.replaceAll(_imageRegex, ''));
      line = trimSpaces(line.replaceFirst(_prefixRegex, ''));
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
