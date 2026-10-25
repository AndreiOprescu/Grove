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

  /// The list on the notes screen for [section]: pinned first, then the
  /// most recently edited; a notebook in its own order. A [query] narrows it
  /// to the notes that the search finds.
  List<Note> notes({NoteSection section = NoteSection.all, String query = ''}) {
    final book = section.notebookId;
    var list = book != null
        ? _try(() => repos.notes.inNotebook(book)) ?? const <Note>[]
        : section == NoteSection.archive
        ? _try(repos.notes.archived) ?? const <Note>[]
        : _try(repos.notes.all) ?? const <Note>[];
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
    final facts = _noteFacts(
      meetings: section == NoteSection.inbox || section == NoteSection.meetings,
      tasks: section == NoteSection.withTasks,
    );
    return NotesRules.filter(list, section, facts: facts, tagsOf: noteTags);
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

  /// Saves a note with the time of the store's clock as its last change
  /// ([AppStore.clockStamp]). The repo alone takes the real clock, so a test
  /// or a picture with a fixed clock would show the real day.
  void _saveNote(Note n) =>
      repos.notes.save(n.copyWith(updatedAt: clockStamp()), touch: false);

  // Daily and weekly notes

  /// The note of a day. It is made the first time it is asked for. That is not
  /// an edit, so it cannot be undone. Grove does not keep it while it has no
  /// text of its own ([forgetEmptyDailyNote]).
  Note dailyNote(DayKey day) {
    final found = _try(() => repos.notes.daily(day));
    if (found != null) return found;
    final n = Note(
      title: NotesRules.dailyTitle(day),
      body: template(NoteKind.daily),
      kind: NoteKind.daily,
      date: day,
      createdAt: clockStamp(),
    );
    _try(() => _saveNote(n));
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
      createdAt: clockStamp(),
    );
    _try(() => _saveNote(n));
    _bump();
    return n;
  }

  void openDailyNote(DayKey day) => openNote(dailyNote(day).id);

  // Empty daily notes

  /// True for a daily note with no text, mood or pin of its own.
  bool isEmptyDailyNote(Note n) =>
      NotesRules.isEmptyDaily(n, template: template(NoteKind.daily));

  /// An editor of note [id] shows it.
  void noteShown(String id) => _shownNotes[id] = (_shownNotes[id] ?? 0) + 1;

  /// An editor of note [id] is gone, and it wrote its text. When no other
  /// editor shows the note, an empty daily note is deleted.
  void noteHidden(String id) {
    final left = (_shownNotes[id] ?? 1) - 1;
    if (left > 0) {
      _shownNotes[id] = left;
      return;
    }
    _shownNotes.remove(id);
    forgetEmptyDailyNote(id);
  }

  /// Deletes daily note [id] when it is empty and no editor shows it. Grove
  /// made the note, not the user, so this is not an undo step.
  void forgetEmptyDailyNote(String id) {
    final n = note(id);
    if (n == null || _shownNotes.containsKey(id) || !isEmptyDailyNote(n)) {
      return;
    }
    _try(() => repos.notes.delete(id));
    if (_selectedNoteId == id) _selectedNoteId = null;
    _bump();
  }

  /// Deletes the empty daily notes that did not change for [after]. A note
  /// that changed in that time can be an empty copy of a note that another
  /// device has text in, and the sync did not bring that text yet.
  void forgetEmptyDailyNotes({Duration after = const Duration(hours: 24)}) {
    final before = Stamp.fromDate(clockNow().subtract(after));
    final empty = [
      for (final n in _try(repos.notes.all) ?? const <Note>[])
        if (n.updatedAt.compareTo(before) < 0 && isEmptyDailyNote(n)) n.id,
    ];
    if (empty.isEmpty) return;
    for (final id in empty) {
      _try(() => repos.notes.delete(id));
      if (_selectedNoteId == id) _selectedNoteId = null;
    }
    _bump();
  }

  void openWeeklyNote(DayKey day) => openNote(weeklyNote(day).id);

  /// Shows a note on the notes screen. When the section or the search would
  /// hide it, the list shows All, or the archive for an archived note.
  void openNote(String id) {
    if (!notes(
      section: _noteSection,
      query: _noteQuery,
    ).any((n) => n.id == id)) {
      _noteSection = note(id)?.archived == true
          ? NoteSection.archive
          : NoteSection.all;
      _noteQuery = '';
    }
    _selectedNoteId = id;
    screen = Screen.notes;
  }

  // Making and changing

  /// A new note. When the list shows a notebook, the note goes at the end of
  /// it, in section [sectionId] when that is a section of the notebook.
  Note newNote({String? title, String body = '', String? sectionId}) {
    final existing = {
      for (final n
          in _try(() => repos.notes.all(includeArchived: true)) ??
              const <Note>[])
        n.title,
    };
    var n = Note(
      title: title ?? NotesRules.untitled(existing: existing),
      body: body,
      createdAt: clockStamp(),
    );
    final book = _noteSection.notebookId;
    if (book != null && notebook(book) != null) {
      final section = sectionId == null
          ? null
          : _try(() => repos.notebooks.section(sectionId));
      final place = _placeNote(
        n,
        notebookId: book,
        sectionId: section?.notebookId == book ? section!.id : null,
      );
      n = place.firstWhere((c) => c.after?.id == n.id).after!;
    }
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
      for (final n
          in _try(() => repos.notes.all(includeArchived: true)) ??
              const <Note>[])
        n.title,
    };
    var copy = Note(
      title: NotesRules.copyTitle(old.title, existing: existing),
      body: NoteParser.withoutMarkers(old.body),
      createdAt: clockStamp(),
    );
    final m = Mutation('Duplicate Note');
    // A copy in a notebook goes right after the first note, in its section.
    final book = old.notebookId;
    if (book != null && !old.archived) {
      final known = {for (final s in notebookSections(book)) s.id};
      final sectionId = known.contains(old.sectionId) ? old.sectionId : null;
      final group = _groupNotes(book, sectionId);
      final at = group.indexWhere((n) => n.id == old.id);
      for (final c in _placeNote(
        copy,
        notebookId: book,
        sectionId: sectionId,
        index: at < 0 ? null : at + 1,
      )) {
        if (c.after?.id == copy.id) {
          copy = c.after!;
        } else {
          m.notes.add(c);
        }
      }
    }
    commit(m..notes.add((before: null, after: copy)));
    openNote(copy.id);
  }

  void deleteNote(String id) {
    final old = note(id);
    if (old == null) return;
    final list = notes(section: _noteSection, query: _noteQuery);
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
