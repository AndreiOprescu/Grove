part of 'app_store.dart';

/// A note, task or event that mentions another item.
class LinkedItem {
  const LinkedItem({required this.ref, required this.title});

  final ItemRef ref;
  final String title;

  String get id => ref.id;

  @override
  bool operator ==(Object other) =>
      other is LinkedItem && other.ref == ref && other.title == title;

  @override
  int get hashCode => Object.hash(ref, title);

  @override
  String toString() => 'LinkedItem($ref, $title)';
}

/// Notes: daily and weekly notes, making and editing, the list, and what
/// links where.
extension AppStoreNotes on AppStore {
  // Reading

  Note? note(String id) => _try(() => repos.notes.get(id));

  List<String> noteTags(String id) =>
      _try(() => repos.tags.tagsForNote(id)) ?? const [];

  List<String> allNoteTags() => _try(repos.tags.noteTagNames) ?? const [];

  /// The list on the notes screen: pinned first, then the most recently edited.
  List<Note> notes({NoteFilter filter = NoteFilter.all, String query = ''}) {
    var list = _try(repos.notes.all) ?? const <Note>[];
    final q = query.trim();
    if (q.isNotEmpty) {
      final hits = {
        for (final h
            in _try(
                  () => repos.search.search(
                    q,
                    types: {ItemType.note},
                    limit: 200,
                  ),
                ) ??
                const <SearchHit>[])
          h.ref.id,
      };
      list = [
        for (final n in list)
          if (hits.contains(n.id)) n,
      ];
    }
    return NotesRules.filter(list, filter, tagsOf: noteTags);
  }

  /// Items whose text mentions [ref], tasks and events included.
  List<LinkedItem> linkedItems(ItemRef ref) {
    final from = _try(() => repos.links.backlinks(ref)) ?? const <ItemRef>[];
    final out = <LinkedItem>[];
    for (final src in from) {
      final hit = _try(() => repos.refs.resolveTitle('', id: src.id));
      if (hit != null) out.add(LinkedItem(ref: src, title: hit.title));
    }
    return _sorted(out, (a, b) => compareIgnoringCase(a.title, b.title));
  }

  // Daily and weekly notes

  /// The note of a day. It is made the first time it is asked for. That is not
  /// an edit, so it cannot be undone.
  Note dailyNote(DayKey day) {
    final found = _try(() => repos.notes.daily(day));
    if (found != null) return found;
    final n = Note(
      title: NotesRules.dailyTitle(day),
      body: template(NoteKind.daily),
      kind: NoteKind.daily,
      date: day,
    );
    _try(() => repos.notes.save(n));
    _bump();
    return n;
  }

  /// The note of a day, or null when none was made. This does not make one.
  Note? existingDailyNote(DayKey day) => _try(() => repos.notes.daily(day));

  /// The note of the week that holds [day].
  Note weeklyNote(DayKey day) {
    final monday = day.weekStart();
    final found = _try(() => repos.notes.weekly(monday));
    if (found != null) return found;
    final n = Note(
      title: NotesRules.weeklyTitle(monday),
      body: template(NoteKind.weekly),
      kind: NoteKind.weekly,
      date: monday,
    );
    _try(() => repos.notes.save(n));
    _bump();
    return n;
  }

  void openDailyNote(DayKey day) => openNote(dailyNote(day).id);

  void openWeeklyNote(DayKey day) => openNote(weeklyNote(day).id);

  /// Shows a note on the notes screen. A filter that would hide it is cleared.
  void openNote(String id) {
    if (!notes(filter: _noteFilter, query: _noteQuery).any((n) => n.id == id)) {
      _noteFilter = NoteFilter.all;
      _noteQuery = '';
    }
    _selectedNoteId = id;
    screen = Screen.notes;
  }

  // Making and changing

  Note newNote({String? title, String body = ''}) {
    final existing = {
      for (final n in _try(repos.notes.all) ?? const <Note>[]) n.title,
    };
    final n = Note(
      title: title ?? NotesRules.untitled(existing: existing),
      body: body,
    );
    commit(Mutation('New Note')..notes.add((before: null, after: n)));
    openNote(n.id);
    return n;
  }

  /// Saves the text of a note. Many saves in a row while typing make one undo step.
  void setNoteBody(String id, String text, {DateTime? now}) {
    final old = note(id);
    if (old == null || old.body == text) return;
    final m = Mutation('Edit Note', mergeKey: 'note:$id', at: now)
      ..notes.add((before: old, after: old.copyWith(body: text)));
    commit(m);
  }

  /// A daily or weekly note keeps its title. An empty name is refused.
  void renameNote(String id, {required String to}) {
    final clean = to.trim();
    final old = note(id);
    if (old == null ||
        old.kind != NoteKind.note ||
        clean.isEmpty ||
        clean == old.title) {
      return;
    }
    commit(
      Mutation('Rename Note')
        ..notes.add((before: old, after: old.copyWith(title: clean))),
    );
  }

  void togglePin(String id) {
    final old = note(id);
    if (old == null) return;
    final n = old.copyWith(pinned: !old.pinned);
    commit(
      Mutation(n.pinned ? 'Pin Note' : 'Unpin Note')
        ..notes.add((before: old, after: n)),
    );
  }

  /// A plain copy. The hidden task marks stay with the first note, so one task
  /// never has two lines.
  void duplicateNote(String id) {
    final old = note(id);
    if (old == null) return;
    final existing = {
      for (final n in _try(repos.notes.all) ?? const <Note>[]) n.title,
    };
    final copy = Note(
      title: NotesRules.copyTitle(old.title, existing: existing),
      body: NoteParser.withoutMarkers(old.body),
    );
    commit(Mutation('Duplicate Note')..notes.add((before: null, after: copy)));
    openNote(copy.id);
  }

  void deleteNote(String id) {
    final old = note(id);
    if (old == null) return;
    final list = notes(filter: _noteFilter, query: _noteQuery);
    final m = Mutation('Delete Note')..notes.add((before: old, after: null));
    if (!commit(m)) return;
    if (_selectedNoteId == id) {
      final i = list.indexWhere((n) => n.id == id);
      Note? next;
      if (i >= 0) {
        if (i + 1 < list.length) {
          next = list[i + 1];
        } else if (i > 0) {
          next = list[i - 1];
        }
      }
      selectedNoteId = next?.id;
    }
  }
}
