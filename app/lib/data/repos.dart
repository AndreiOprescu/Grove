import '../core/model/day_key.dart';
import '../core/model/event.dart';
import '../core/model/goal.dart';
import '../core/model/link.dart';
import '../core/model/note.dart';
import '../core/model/recurrence.dart';
import '../core/model/task.dart';
import '../core/parsing/note_parser.dart';
import '../core/parsing/reference_parser.dart';
import 'attachment_repo.dart';
import 'database.dart';
import 'reference_indexer.dart';
import 'search_index.dart';

/// Builds `INSERT … ON CONFLICT(id) DO UPDATE` so a save never deletes and
/// re-creates a row (a REPLACE would fire ON DELETE CASCADE and wipe child rows).
String _upsertSql(String table, List<String> cols) {
  final marks = List.filled(cols.length, '?').join(',');
  final sets = cols.skip(1).map((c) => '$c=excluded.$c').join(',');
  return 'INSERT INTO $table (${cols.join(',')}) VALUES ($marks) '
      'ON CONFLICT(${cols.first}) DO UPDATE SET $sets';
}

T _enumOr<T extends Enum>(List<T> values, String name, T fallback) =>
    values.asNameMap()[name] ?? fallback;

DayKey? _day(String? s) => s == null ? null : DayKey(s);

String _dayStart(DayKey d) => '${d.string}T00:00';

// Tasks.

class TaskRepo {
  TaskRepo(this.db, this.search);

  final Database db;
  final SearchIndex search;

  static const _cols = [
    'id',
    'title',
    'notes',
    'list_id',
    'parent_id',
    'priority',
    'status',
    'bucket',
    'plan_date',
    'plan_week',
    'due',
    'estimate_min',
    'recurrence',
    'source_note_id',
    'sort',
    'created_at',
    'updated_at',
    'completed_at',
    'summary',
    'color',
  ];
  static final _select = 'SELECT ${_cols.join(',')} FROM tasks';
  static final _upsert = _upsertSql('tasks', _cols);

  static TaskItem _map(Row r) => TaskItem(
    id: r.text(0),
    title: r.text(1),
    notes: r.text(2),
    listId: r.optText(3),
    parentId: r.optText(4),
    priority: r.asInt(5),
    status: _enumOr(TaskStatus.values, r.text(6), TaskStatus.open),
    bucket: _enumOr(TaskBucket.values, r.text(7), TaskBucket.inbox),
    planDate: _day(r.optText(8)),
    planWeek: _day(r.optText(9)),
    due: r.optText(10),
    estimateMin: r.asInt(11),
    recurrence: RecurrenceRule.fromJson(r.optText(12)),
    sourceNoteId: r.optText(13),
    sort: r.asDouble(14),
    createdAt: r.text(15),
    updatedAt: r.text(16),
    completedAt: r.optText(17),
    summary: r.text(18),
    color: r.text(19),
  );

  List<TaskItem> _where(String clause, [List<Object?> args = const []]) =>
      db.query('$_select $clause', args, _map);

  /// Insert or update. Refreshes `updatedAt`.
  void save(TaskItem task) {
    final t = task.copyWith(updatedAt: Stamp.now());
    db.transaction(() {
      db.execute(_upsert, [
        t.id,
        t.title,
        t.notes,
        t.listId,
        t.parentId,
        t.priority,
        t.status.name,
        t.bucket.name,
        t.planDate?.string,
        t.planWeek?.string,
        t.due,
        t.estimateMin,
        t.recurrence?.json(),
        t.sourceNoteId,
        t.sort,
        t.createdAt,
        t.updatedAt,
        t.completedAt,
        t.summary,
        t.color,
      ]);
      search.upsert(ItemType.task, t.id, t.title, searchBody(t));
    });
  }

  /// How many tasks are finished. The garden plant grows with this number.
  int doneCount() =>
      db.queryOne(
        "SELECT COUNT(*) FROM tasks WHERE status = 'done'",
        const [],
        (r) => r.asInt(0),
      ) ??
      0;

  TaskItem? get(String id) => _where('WHERE id = ?', [id]).firstOrNull;

  /// Case-insensitive exact title match. Open tasks first, then the most recently edited.
  TaskItem? byTitle(String title) => _where(
    "WHERE title = ? COLLATE NOCASE ORDER BY (status = 'open') DESC, "
    'updated_at DESC',
    [title],
  ).firstOrNull;

  void delete(String id) {
    db.transaction(() {
      // Subtasks and blocks go through ON DELETE CASCADE. Clean their search rows first.
      final doomed = db.query('SELECT id FROM tasks WHERE parent_id = ?', [
        id,
      ], (r) => r.text(0));
      final blocks = db.query('SELECT id FROM events WHERE task_id = ?', [
        id,
      ], (r) => r.text(0));
      for (final s in doomed) {
        search.remove(ItemType.task, s);
      }
      for (final b in blocks) {
        search.remove(ItemType.event, b);
      }
      db.execute('DELETE FROM tasks WHERE id = ?', [id]);
      search.remove(ItemType.task, id);
    });
  }

  /// Top-level tasks planned for a day (not cancelled).
  List<TaskItem> forDay(DayKey day) => _where(
    "WHERE bucket = 'day' AND plan_date = ? AND parent_id IS NULL AND "
    "status != 'cancelled' ORDER BY sort, created_at, rowid",
    [day.string],
  );

  /// Tasks with a day inside the closed range.
  List<TaskItem> inRange(DayKey from, DayKey to) => _where(
    'WHERE plan_date >= ? AND plan_date <= ? AND parent_id IS NULL AND '
    "status != 'cancelled' ORDER BY plan_date, sort, created_at, rowid",
    [from.string, to.string],
  );

  /// "Sometime this week" tasks (no day yet).
  List<TaskItem> forWeek(DayKey monday) => _where(
    "WHERE bucket = 'week' AND plan_week = ? AND parent_id IS NULL AND "
    "status != 'cancelled' ORDER BY sort, created_at, rowid",
    [monday.string],
  );

  List<TaskItem> inbox() => _where(
    "WHERE bucket = 'inbox' AND parent_id IS NULL AND status = 'open' "
    'ORDER BY sort, created_at, rowid',
  );

  List<TaskItem> someday() => _where(
    "WHERE bucket = 'someday' AND parent_id IS NULL AND status = 'open' "
    'ORDER BY sort, created_at, rowid',
  );

  /// Every open top-level task, whatever its bucket. The Planner screen's task list.
  List<TaskItem> openTopLevel() => _where(
    "WHERE status = 'open' AND parent_id IS NULL "
    'ORDER BY sort, created_at, rowid',
  );

  /// Open tasks planned for a day before [before].
  List<TaskItem> overdue({required DayKey before}) => _where(
    "WHERE status = 'open' AND bucket = 'day' AND plan_date < ? AND "
    'parent_id IS NULL ORDER BY plan_date, sort',
    [before.string],
  );

  /// Open tasks whose due date has a time ("YYYY-MM-DDTHH:MM"). These are the tasks that can remind.
  List<TaskItem> openWithTimedDue() =>
      _where("WHERE status = 'open' AND due LIKE '%T%' ORDER BY due");

  List<TaskItem> subtasks(String parentId) => _where(
    'WHERE parent_id = ? ORDER BY sort, created_at, rowid',
    [parentId],
  );

  List<TaskItem> completedOn(DayKey day) => completed(from: day, to: day);

  List<TaskItem> completed({required DayKey from, required DayKey to}) =>
      _where(
        "WHERE status = 'done' AND completed_at >= ? AND completed_at < ? "
        'ORDER BY completed_at',
        ['${from.string}T00:00:00', '${to.adding(days: 1).string}T00:00:00'],
      );

  List<TaskItem> inList(String listId) => _where(
    "WHERE list_id = ? AND parent_id IS NULL AND status = 'open' "
    'ORDER BY sort, created_at, rowid',
    [listId],
  );

  List<TaskItem> withTag(String name) => _where(
    'WHERE id IN (SELECT task_id FROM task_tags JOIN tags ON tags.id = tag_id '
    "WHERE tags.name = ?) AND status = 'open' ORDER BY sort, created_at, rowid",
    [name],
  );

  /// The text the search index holds for a task (the title is stored beside it).
  static String searchBody(TaskItem t) =>
      '${t.summary} ${ReferenceParser.searchText(t.notes)}';

  List<TaskItem> all() => _where('ORDER BY created_at');

  int openCount() =>
      db.queryOne(
        "SELECT COUNT(*) FROM tasks WHERE status = 'open'",
        const [],
        (r) => r.asInt(0),
      ) ??
      0;

  /// Number of open top-level tasks per day, for calendar dots.
  Map<DayKey, int> openCounts({required DayKey from, required DayKey to}) => {
    for (final (day, n) in db.query(
      "SELECT plan_date, COUNT(*) FROM tasks WHERE status = 'open' AND "
      'parent_id IS NULL AND plan_date >= ? AND plan_date <= ? '
      'GROUP BY plan_date',
      [from.string, to.string],
      (r) => (DayKey(r.text(0)), r.asInt(1)),
    ))
      day: n,
  };
}

// Events.

class EventRepo {
  EventRepo(this.db, this.search);

  final Database db;
  final SearchIndex search;

  static const _cols = [
    'id',
    'title',
    'start',
    'end',
    'all_day',
    'kind',
    'task_id',
    'color',
    'location',
    'notes',
    'recurrence',
    'series_id',
    'original_date',
    'created_at',
    'updated_at',
    'goal_id',
    'done_at',
  ];
  static final _select = 'SELECT ${_cols.join(',')} FROM events';
  static final _upsert = _upsertSql('events', _cols);

  static EventItem _map(Row r) {
    final start =
        WallTime.parse(r.text(2)) ?? WallTime(day: DayKey.today(), minute: 0);
    return EventItem(
      id: r.text(0),
      title: r.text(1),
      start: start,
      end: WallTime.parse(r.text(3)) ?? start,
      allDay: r.asBool(4),
      kind: _enumOr(EventKind.values, r.text(5), EventKind.event),
      taskId: r.optText(6),
      color: r.text(7),
      location: r.text(8),
      notes: r.text(9),
      recurrence: RecurrenceRule.fromJson(r.optText(10)),
      seriesId: r.optText(11),
      originalDate: _day(r.optText(12)),
      createdAt: r.text(13),
      updatedAt: r.text(14),
      goalId: r.optText(15),
      doneAt: r.optText(16),
    );
  }

  List<EventItem> _where(String clause, [List<Object?> args = const []]) =>
      db.query('$_select $clause', args, _map);

  void save(EventItem event) {
    final e = event.copyWith(updatedAt: Stamp.now());
    db.transaction(() {
      db.execute(_upsert, [
        e.id,
        e.title,
        e.start.string,
        e.end.string,
        e.allDay,
        e.kind.name,
        e.taskId,
        e.color,
        e.location,
        e.notes,
        e.recurrence?.json(),
        e.seriesId,
        e.originalDate?.string,
        e.createdAt,
        e.updatedAt,
        e.goalId,
        e.doneAt,
      ]);
      if (e.kind == EventKind.event) {
        search.upsert(ItemType.event, e.id, e.title, searchBody(e));
      }
    });
  }

  EventItem? get(String id) => _where('WHERE id = ?', [id]).firstOrNull;

  /// Time blocks that belong to a task, earliest first.
  List<EventItem> blocksForTask(String taskId) =>
      _where('WHERE task_id = ? ORDER BY start', [taskId]);

  /// Time blocks that belong to a goal, earliest first.
  List<EventItem> blocksForGoal(String goalId) =>
      _where('WHERE goal_id = ? ORDER BY start', [goalId]);

  /// Case-insensitive exact title match, most recently edited first.
  EventItem? byTitle(String title) => _where(
    'WHERE title = ? COLLATE NOCASE ORDER BY updated_at DESC',
    [title],
  ).firstOrNull;

  void delete(String id) {
    db.transaction(() {
      db.execute('DELETE FROM events WHERE id = ?', [id]);
      search.remove(ItemType.event, id);
    });
  }

  /// One-off events and detached occurrences that touch the closed day range.
  /// Series (events with a recurrence rule) come from [recurringSeries].
  List<EventItem> inRange(DayKey from, DayKey to) => _where(
    'WHERE recurrence IS NULL AND start < ? AND end >= ? ORDER BY start',
    [_dayStart(to.adding(days: 1)), _dayStart(from)],
  );

  List<EventItem> recurringSeries() =>
      _where('WHERE recurrence IS NOT NULL ORDER BY start');

  List<EventItem> forTask(String taskId) => blocksForTask(taskId);

  List<EventItem> detached(String seriesId) =>
      _where('WHERE series_id = ? ORDER BY start', [seriesId]);

  List<DayKey> exdates(String eventId) => db.query(
    'SELECT date FROM event_exdates WHERE event_id = ?',
    [eventId],
    (r) => DayKey(r.text(0)),
  );

  void addExdate(String eventId, DayKey day) => db.execute(
    'INSERT OR IGNORE INTO event_exdates (event_id, date) VALUES (?, ?)',
    [eventId, day.string],
  );

  void removeExdate(String eventId, DayKey day) => db.execute(
    'DELETE FROM event_exdates WHERE event_id = ? AND date = ?',
    [eventId, day.string],
  );

  static String searchBody(EventItem e) =>
      '${ReferenceParser.searchText(e.notes)} ${e.location}';

  List<EventItem> all() => _where('ORDER BY start');
}

// Goals.

class GoalRepo {
  GoalRepo(this.db);

  final Database db;

  static const _cols = [
    'id',
    'title',
    'notes',
    'color',
    'target_min',
    'sort',
    'archived',
    'created_at',
    'updated_at',
    'kind',
    'target_count',
  ];
  static final _select = 'SELECT ${_cols.join(',')} FROM goals';
  static final _upsert = _upsertSql('goals', _cols);

  static GoalItem _map(Row r) => GoalItem(
    id: r.text(0),
    title: r.text(1),
    notes: r.text(2),
    color: r.text(3),
    targetMin: r.asInt(4),
    sort: r.asDouble(5),
    archived: r.asBool(6),
    createdAt: r.text(7),
    updatedAt: r.text(8),
    kind: _enumOr(GoalKind.values, r.text(9), GoalKind.hours),
    targetCount: r.asInt(10),
  );

  /// Insert or update. Refreshes `updatedAt`.
  void upsert(GoalItem goal) {
    final g = goal.copyWith(updatedAt: Stamp.now());
    db.execute(_upsert, [
      g.id,
      g.title,
      g.notes,
      g.color,
      g.targetMin,
      g.sort,
      g.archived,
      g.createdAt,
      g.updatedAt,
      g.kind.name,
      g.targetCount,
    ]);
  }

  GoalItem? get(String id) =>
      db.query('$_select WHERE id = ?', [id], _map).firstOrNull;

  List<GoalItem> all({bool includeArchived = false}) => db.query(
    '$_select${includeArchived ? '' : ' WHERE archived = 0'} '
    'ORDER BY sort, created_at, rowid',
    const [],
    _map,
  );

  /// Deletes the goal. Its blocks stay as plain blocks: they lose the goal
  /// (and any old done time).
  void delete(String id) {
    db.transaction(() {
      db.execute(
        'UPDATE events SET goal_id = NULL, done_at = NULL WHERE goal_id = ?',
        [id],
      );
      db.execute('DELETE FROM goals WHERE id = ?', [id]);
    });
  }

  /// The minutes of the goal's blocks that start on a day of the closed range.
  /// [doneOnly] counts only the blocks that are ticked done.
  int minutes(
    String goalId, {
    required DayKey from,
    required DayKey to,
    bool doneOnly = false,
  }) {
    var sum = 0;
    for (final (s, e) in _blockTimes(goalId, from, to, doneOnly)) {
      final start = WallTime.parse(s), end = WallTime.parse(e);
      if (start == null || end == null) continue;
      sum += EventItem(title: '', start: start, end: end).durationMinutes;
    }
    return sum;
  }

  /// How many of the goal's blocks start on a day of the closed range, whatever
  /// their length. [doneOnly] counts only the blocks that are ticked done.
  int sessions(
    String goalId, {
    required DayKey from,
    required DayKey to,
    bool doneOnly = false,
  }) => _blockTimes(goalId, from, to, doneOnly).length;

  List<(String, String)> _blockTimes(
    String goalId,
    DayKey from,
    DayKey to,
    bool doneOnly,
  ) => db.query(
    'SELECT start, end FROM events WHERE goal_id = ? AND start >= ? AND '
    'start < ?${doneOnly ? ' AND done_at IS NOT NULL' : ''}',
    [goalId, _dayStart(from), _dayStart(to.adding(days: 1))],
    (r) => (r.text(0), r.text(1)),
  );
}

// Notes.

class NoteRepo {
  NoteRepo(this.db, this.search);

  final Database db;
  final SearchIndex search;

  static const _cols = [
    'id',
    'title',
    'body',
    'kind',
    'date',
    'pinned',
    'mood',
    'created_at',
    'updated_at',
  ];
  static final _select = 'SELECT ${_cols.join(',')} FROM notes';
  static final _upsert = _upsertSql('notes', _cols);

  static Note _map(Row r) => Note(
    id: r.text(0),
    title: r.text(1),
    body: r.text(2),
    kind: _enumOr(NoteKind.values, r.text(3), NoteKind.note),
    date: _day(r.optText(4)),
    pinned: r.asBool(5),
    mood: r.optInt(6),
    createdAt: r.text(7),
    updatedAt: r.text(8),
  );

  List<Note> _where(String clause, [List<Object?> args = const []]) =>
      db.query('$_select $clause', args, _map);

  /// `touch: false` keeps the edit time. Use it for changes the user did not
  /// make in the note itself.
  void save(Note note, {bool touch = true}) {
    final n = touch ? note.copyWith(updatedAt: Stamp.now()) : note;
    db.transaction(() {
      db.execute(_upsert, [
        n.id,
        n.title,
        n.body,
        n.kind.name,
        n.date?.string,
        n.pinned,
        n.mood,
        n.createdAt,
        n.updatedAt,
      ]);
      search.upsert(ItemType.note, n.id, n.title, searchBody(n));
    });
  }

  Note? get(String id) => _where('WHERE id = ?', [id]).firstOrNull;

  void delete(String id) {
    db.transaction(() {
      db.execute('DELETE FROM notes WHERE id = ?', [id]);
      search.remove(ItemType.note, id);
    });
  }

  static String searchBody(Note n) =>
      ReferenceParser.searchText(NoteParser.withoutMarkers(n.body));

  /// Pinned first, then most recently edited.
  List<Note> all() => _where('ORDER BY pinned DESC, updated_at DESC');

  /// Notes with a check box line that is tied to task [taskId].
  List<Note> withTaskMarker(String taskId) =>
      _where('WHERE instr(body, ?) > 0', [NoteParser.marker(taskId)]);

  Note? daily(DayKey day) =>
      _where("WHERE kind = 'daily' AND date = ?", [day.string]).firstOrNull;

  Note? weekly(DayKey monday) =>
      _where("WHERE kind = 'weekly' AND date = ?", [monday.string]).firstOrNull;

  /// Case-insensitive exact title match, newest first.
  Note? byTitle(String title) => _where(
    'WHERE title = ? COLLATE NOCASE ORDER BY updated_at DESC',
    [title],
  ).firstOrNull;

  List<Note> titles(String prefix, {int limit = 8}) => _where(
    r"WHERE title LIKE ? ESCAPE '\' ORDER BY updated_at DESC LIMIT ?",
    ['${_escapeLike(prefix)}%', limit],
  );

  /// Days that have a daily note with some text beyond the template headings.
  Set<DayKey> daysWithNotes({required DayKey from, required DayKey to}) =>
      db.query(
        "SELECT date FROM notes WHERE kind = 'daily' AND date >= ? AND "
        'date <= ? AND LENGTH(TRIM(REPLACE(REPLACE(REPLACE(REPLACE(body, '
        "'## Plan', ''), '## Notes', ''), '## Reflection', ''), char(10), "
        "''))) > 0",
        [from.string, to.string],
        (r) => DayKey(r.text(0)),
      ).toSet();

  /// The mood of each daily note that has one, by day.
  Map<DayKey, int> moods({required DayKey from, required DayKey to}) {
    final out = <DayKey, int>{};
    for (final (day, mood) in db.query(
      "SELECT date, mood FROM notes WHERE kind = 'daily' AND mood IS NOT NULL "
      'AND date >= ? AND date <= ?',
      [from.string, to.string],
      (r) => (DayKey(r.text(0)), r.asInt(1)),
    )) {
      out.putIfAbsent(day, () => mood);
    }
    return out;
  }

  static String _escapeLike(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
}

// Lists, tags, links, settings.

class ListRepo {
  ListRepo(this.db);

  final Database db;

  static final _upsert = _upsertSql('lists', [
    'id',
    'name',
    'emoji',
    'color',
    'sort',
    'archived',
  ]);

  void save(ListItem l) =>
      db.execute(_upsert, [l.id, l.name, l.emoji, l.color, l.sort, l.archived]);

  List<ListItem> all({bool includeArchived = false}) => db.query(
    'SELECT id, name, emoji, color, sort, archived FROM lists '
    '${includeArchived ? '' : 'WHERE archived = 0'} ORDER BY sort, name',
    const [],
    (r) => ListItem(
      id: r.text(0),
      name: r.text(1),
      emoji: r.text(2),
      color: r.text(3),
      sort: r.asInt(4),
      archived: r.asBool(5),
    ),
  );

  ListItem? get(String id) =>
      all(includeArchived: true).where((l) => l.id == id).firstOrNull;

  void delete(String id) => db.execute('DELETE FROM lists WHERE id = ?', [id]);
}

class TagRepo {
  TagRepo(this.db);

  final Database db;

  static final _edges = RegExp(r'^[#\s]+|[#\s]+$');

  /// Finds a tag by name (any letter case) or creates it.
  Tag upsert(String name) {
    final clean = name.replaceAll(_edges, '');
    final found = db.queryOne('SELECT id, name FROM tags WHERE name = ?', [
      clean,
    ], (r) => Tag(id: r.text(0), name: r.text(1)));
    if (found != null) return found;
    final t = Tag(name: clean);
    db.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [t.id, t.name]);
    return t;
  }

  List<Tag> all() => db.query(
    'SELECT id, name FROM tags ORDER BY name',
    const [],
    (r) => Tag(id: r.text(0), name: r.text(1)),
  );

  void setTaskTags(String taskId, List<String> names) =>
      _setTags('task_tags', 'task_id', taskId, names);

  void setNoteTags(String noteId, List<String> names) =>
      _setTags('note_tags', 'note_id', noteId, names);

  void _setTags(String table, String column, String id, List<String> names) {
    db.transaction(() {
      db.execute('DELETE FROM $table WHERE $column = ?', [id]);
      for (final n in names) {
        if (n.isEmpty) continue;
        final t = upsert(n);
        db.execute(
          'INSERT OR IGNORE INTO $table ($column, tag_id) VALUES (?, ?)',
          [id, t.id],
        );
      }
    });
  }

  List<String> tagsForTask(String id) => db.query(
    'SELECT tags.name FROM tags JOIN task_tags ON tags.id = tag_id '
    'WHERE task_id = ? ORDER BY tags.name',
    [id],
    (r) => r.text(0),
  );

  List<String> tagsForNote(String id) => db.query(
    'SELECT tags.name FROM tags JOIN note_tags ON tags.id = tag_id '
    'WHERE note_id = ? ORDER BY tags.name',
    [id],
    (r) => r.text(0),
  );

  /// Every tag that at least one note uses, A to Z.
  List<String> noteTagNames() => db.query(
    'SELECT DISTINCT tags.name FROM tags JOIN note_tags ON tags.id = tag_id '
    'ORDER BY tags.name COLLATE NOCASE',
    const [],
    (r) => r.text(0),
  );
}

class LinkRepo {
  LinkRepo(this.db);

  final Database db;

  static final _types = ItemType.values.asNameMap();

  /// Replaces every parsed link that starts at [src] (used each time a body is saved).
  void replaceParsed(ItemRef src, List<ItemRef> targets) {
    db.transaction(() {
      db.execute(
        'DELETE FROM links WHERE src_type = ? AND src_id = ? AND '
        "origin = 'parsed'",
        [src.type.name, src.id],
      );
      for (final t in targets.toSet()) {
        if (t == src) continue;
        db.execute(
          'INSERT OR IGNORE INTO links (src_type, src_id, dst_type, dst_id, '
          "origin) VALUES (?, ?, ?, ?, 'parsed')",
          [src.type.name, src.id, t.type.name, t.id],
        );
      }
    });
  }

  void addManual(ItemRef src, ItemRef dst) => db.execute(
    'INSERT OR IGNORE INTO links (src_type, src_id, dst_type, dst_id, origin) '
    "VALUES (?, ?, ?, ?, 'manual')",
    [src.type.name, src.id, dst.type.name, dst.id],
  );

  void remove(ItemRef src, ItemRef dst) => db.execute(
    'DELETE FROM links WHERE src_type = ? AND src_id = ? AND dst_type = ? AND '
    'dst_id = ?',
    [src.type.name, src.id, dst.type.name, dst.id],
  );

  List<ItemRef> _refs(String sqlText, ItemRef ref) => db
      .query(sqlText, [ref.type.name, ref.id], (r) {
        final type = _types[r.text(0)];
        return type == null ? null : ItemRef(type, r.text(1));
      })
      .whereType<ItemRef>()
      .toList();

  /// Items that link TO [dst].
  List<ItemRef> backlinks(ItemRef dst) => _refs(
    'SELECT src_type, src_id FROM links WHERE dst_type = ? AND dst_id = ?',
    dst,
  );

  /// Items that [src] links to.
  List<ItemRef> outgoing(ItemRef src) => _refs(
    'SELECT dst_type, dst_id FROM links WHERE src_type = ? AND src_id = ?',
    src,
  );
}

class SettingsRepo {
  SettingsRepo(this.db);

  final Database db;

  String? get(String key) => db.queryOne(
    'SELECT value FROM settings WHERE key = ?',
    [key],
    (r) => r.text(0),
  );

  void remove(String key) =>
      db.execute('DELETE FROM settings WHERE key = ?', [key]);

  void set(String key, String value) => db.execute(
    'INSERT INTO settings (key, value) VALUES (?, ?) '
    'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
    [key, value],
  );
}

/// All repositories on one database.
class Repos {
  Repos(this.db)
    : search = SearchIndex(db),
      goals = GoalRepo(db),
      lists = ListRepo(db),
      tags = TagRepo(db),
      links = LinkRepo(db),
      settings = SettingsRepo(db),
      attachments = AttachmentRepo(db) {
    tasks = TaskRepo(db, search);
    events = EventRepo(db, search);
    notes = NoteRepo(db, search);
    refs = ReferenceIndexer(
      db: db,
      tasks: tasks,
      notes: notes,
      events: events,
      links: links,
      search: search,
    );
  }

  final Database db;
  final SearchIndex search;
  late final TaskRepo tasks;
  late final EventRepo events;
  late final NoteRepo notes;
  final GoalRepo goals;
  final ListRepo lists;
  final TagRepo tags;
  final LinkRepo links;
  final SettingsRepo settings;
  final AttachmentRepo attachments;
  late final ReferenceIndexer refs;

  /// Throws the search index away and builds it again from the tables.
  /// Time blocks are not searched, only real events.
  void rebuildSearch() {
    db.transaction(() {
      db.execute('DELETE FROM search');
      for (final t in tasks.all()) {
        search.upsert(ItemType.task, t.id, t.title, TaskRepo.searchBody(t));
      }
      for (final e in events.all()) {
        if (e.kind != EventKind.event) continue;
        search.upsert(ItemType.event, e.id, e.title, EventRepo.searchBody(e));
      }
      for (final n in notes.all()) {
        search.upsert(ItemType.note, n.id, n.title, NoteRepo.searchBody(n));
      }
    });
  }
}
