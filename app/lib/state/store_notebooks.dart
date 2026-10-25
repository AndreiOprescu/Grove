part of 'app_store.dart';

/// True when [a] and [b] are the same note in another place: another
/// notebook, section or order, or in or out of the archive. Such a change
/// keeps the edit time.
bool _onlyPlaceChanged(Note a, Note b) =>
    a.id == b.id &&
    a.title == b.title &&
    a.body == b.body &&
    a.kind == b.kind &&
    a.date == b.date &&
    a.pinned == b.pinned &&
    a.mood == b.mood &&
    (a.notebookId != b.notebookId ||
        a.sectionId != b.sectionId ||
        a.sortOrder != b.sortOrder ||
        a.archivedAt != b.archivedAt);

/// "Notebook", then "Notebook 2", …
String _freshName(String base, Iterable<String> taken) {
  final lower = {for (final t in taken) t.toLowerCase()};
  var candidate = base, n = 2;
  while (lower.contains(candidate.toLowerCase())) {
    candidate = '$base $n';
    n += 1;
  }
  return candidate;
}

/// Notebooks and their sections, the place of a note in its notebook, the
/// archive, and the counts and groups of the notes sidebar.
extension AppStoreNotebooks on AppStore {
  // Reading

  /// The notebooks, in sidebar order.
  List<Notebook> notebooks() => _try(repos.notebooks.all) ?? const [];

  Notebook? notebook(String id) => _try(() => repos.notebooks.get(id));

  /// The sections of a notebook, in order.
  List<NotebookSection> notebookSections(String notebookId) =>
      _try(() => repos.notebooks.sections(notebookId)) ?? const [];

  /// How many notes each fixed section and each notebook has. One pass over
  /// the notes and one query each for meeting notes and notes with tasks.
  Map<NoteSection, int> sectionCounts() {
    final list =
        _try(() => repos.notes.all(includeArchived: true)) ?? const <Note>[];
    return NotesRules.counts(
      list,
      facts: _noteFacts(meetings: true, tasks: true),
      notebookIds: [for (final b in notebooks()) b.id],
    );
  }

  /// The list in groups: the sections of a notebook for a notebook, else
  /// date groups by the store's clock. [section] and [query] default to the
  /// ones of the notes screen.
  List<NoteGroup> groupedNotes({NoteSection? section, String? query}) {
    final s = section ?? _noteSection;
    final list = notes(section: s, query: query ?? _noteQuery);
    final book = s.notebookId;
    if (book != null) {
      return NotesRules.notebookGroups(list, notebookSections(book));
    }
    return NotesRules.dateGroups(list, now: clockNow());
  }

  NoteFacts _noteFacts({bool meetings = false, bool tasks = false}) =>
      NoteFacts(
        meetingIds: meetings
            ? _try(repos.notes.linkedToEvents) ?? const {}
            : const {},
        openTaskNoteIds: tasks
            ? _try(repos.notes.withOpenTasks) ?? const {}
            : const {},
      );

  // Notebooks

  /// Makes a notebook at the end of the list and shows it. A blank name
  /// gets "Notebook", "Notebook 2", …
  Notebook newNotebook([String name = '']) {
    final all = notebooks();
    final clean = name.trim();
    final b = Notebook(
      name: clean.isEmpty
          ? _freshName('Notebook', [for (final x in all) x.name])
          : clean,
      sortOrder: all.isEmpty ? 1 : all.last.sortOrder + 1,
      createdAt: clockStamp(),
    );
    if (!commit(
      Mutation('New Notebook')..notebooks.add((before: null, after: b)),
    )) {
      return b;
    }
    _noteSection = NoteSection.notebook(b.id);
    _noteQuery = '';
    _changed();
    return b;
  }

  /// An empty name is refused.
  void renameNotebook(String id, String name) {
    final old = notebook(id);
    final clean = name.trim();
    if (old == null || clean.isEmpty || clean == old.name) return;
    commit(
      Mutation('Rename Notebook')
        ..notebooks.add((
          before: old,
          after: old.copyWith(name: clean, updatedAt: clockStamp()),
        )),
    );
  }

  /// [color] is the name of a colour, or null for the plain look.
  void setNotebookColor(String id, String? color) {
    final old = notebook(id);
    if (old == null || old.color == color) return;
    commit(
      Mutation('Change Notebook Color')
        ..notebooks.add((
          before: old,
          after: old.copyWith(color: color, updatedAt: clockStamp()),
        )),
    );
  }

  /// Deletes a notebook and its sections. Its notes stay, in no notebook.
  /// Undo brings the notebook, its sections and the places of its notes
  /// back. A list that showed the notebook shows All.
  void deleteNotebook(String id) {
    final old = notebook(id);
    if (old == null) return;
    final m = Mutation('Delete Notebook')
      ..notebooks.add((before: old, after: null));
    for (final s in notebookSections(id)) {
      m.notebookSections.add((before: s, after: null));
    }
    for (final n
        in _try(() => repos.notes.all(includeArchived: true)) ??
            const <Note>[]) {
      if (n.notebookId != id) continue;
      m.notes.add((
        before: n,
        after: n.copyWith(notebookId: null, sectionId: null),
      ));
    }
    if (!commit(m)) return;
    if (_noteSection.notebookId == id) {
      _noteSection = NoteSection.all;
      _changed();
    }
  }

  /// Puts notebook [id] at [index] of the list.
  void reorderNotebook(String id, int index) {
    final all = notebooks();
    final old = all.where((b) => b.id == id).firstOrNull;
    if (old == null) return;
    final others = [
      for (final b in all)
        if (b.id != id) (id: b.id, order: b.sortOrder),
    ];
    final m = Mutation('Move Notebook');
    final byId = {for (final b in all) b.id: b};
    NotesRules.placeAt(id, others, index).forEach((bid, order) {
      final b = byId[bid]!;
      if (b.sortOrder != order) {
        m.notebooks.add((
          before: b,
          after: b.copyWith(sortOrder: order, updatedAt: clockStamp()),
        ));
      }
    });
    if (!m.isEmpty) commit(m);
  }

  // Sections

  /// Makes a section at the end of the notebook. A blank name gets
  /// "Section", "Section 2", … Null when the notebook is gone.
  NotebookSection? newSection(String notebookId, String name) {
    if (notebook(notebookId) == null) return null;
    final all = notebookSections(notebookId);
    final clean = name.trim();
    final s = NotebookSection(
      notebookId: notebookId,
      name: clean.isEmpty
          ? _freshName('Section', [for (final x in all) x.name])
          : clean,
      sortOrder: all.isEmpty ? 1 : all.last.sortOrder + 1,
      createdAt: clockStamp(),
    );
    final m = Mutation('New Section')
      ..notebookSections.add((before: null, after: s));
    return commit(m) ? s : null;
  }

  /// An empty name is refused.
  void renameSection(String id, String name) {
    final old = _try(() => repos.notebooks.section(id));
    final clean = name.trim();
    if (old == null || clean.isEmpty || clean == old.name) return;
    commit(
      Mutation('Rename Section')
        ..notebookSections.add((
          before: old,
          after: old.copyWith(name: clean, updatedAt: clockStamp()),
        )),
    );
  }

  /// Deletes a section. Its notes stay in the notebook, in no section. Undo
  /// puts them back in it.
  void deleteSection(String id) {
    final old = _try(() => repos.notebooks.section(id));
    if (old == null) return;
    final m = Mutation('Delete Section')
      ..notebookSections.add((before: old, after: null));
    for (final n
        in _try(() => repos.notes.all(includeArchived: true)) ??
            const <Note>[]) {
      if (n.sectionId != id) continue;
      m.notes.add((before: n, after: n.copyWith(sectionId: null)));
    }
    commit(m);
  }

  /// Puts section [id] at [index] of its notebook.
  void reorderSection(String id, int index) {
    final old = _try(() => repos.notebooks.section(id));
    if (old == null) return;
    final all = notebookSections(old.notebookId);
    final others = [
      for (final s in all)
        if (s.id != id) (id: s.id, order: s.sortOrder),
    ];
    final m = Mutation('Move Section');
    final byId = {for (final s in all) s.id: s};
    NotesRules.placeAt(id, others, index).forEach((sid, order) {
      final s = byId[sid]!;
      if (s.sortOrder != order) {
        m.notebookSections.add((
          before: s,
          after: s.copyWith(sortOrder: order, updatedAt: clockStamp()),
        ));
      }
    });
    if (!m.isEmpty) commit(m);
  }

  // The place of a note

  /// The notes of a group of a notebook: the notes of section [sectionId],
  /// or the notes in no section for null. In order. Archived notes are not
  /// in it.
  List<Note> _groupNotes(String notebookId, String? sectionId) {
    final groups = NotesRules.notebookGroups(
      _try(() => repos.notes.inNotebook(notebookId)) ?? const [],
      notebookSections(notebookId),
    );
    return groups.where((g) => g.sectionId == sectionId).firstOrNull?.notes ??
        const [];
  }

  /// The changes that put [note] at [index] of its group (the end for
  /// null), in [notebookId] and [sectionId]. Other notes of the group get a
  /// new order only when there is no room.
  List<Change<Note>> _placeNote(
    Note note, {
    required String notebookId,
    required String? sectionId,
    int? index,
  }) {
    final group = [
      for (final n in _groupNotes(notebookId, sectionId))
        if (n.id != note.id) n,
    ];
    final orders = NotesRules.placeAt(note.id, [
      for (final n in group) (id: n.id, order: n.sortOrder),
    ], index ?? group.length);
    final byId = {for (final n in group) n.id: n};
    final out = <Change<Note>>[];
    orders.forEach((id, order) {
      if (id == note.id) {
        final after = note.copyWith(
          notebookId: notebookId,
          sectionId: sectionId,
          sortOrder: order,
        );
        if (after != note) out.add((before: note, after: after));
        return;
      }
      final n = byId[id]!;
      if (n.sortOrder != order) {
        out.add((before: n, after: n.copyWith(sortOrder: order)));
      }
    });
    return out;
  }

  /// Puts a note in notebook [notebookId] (null for none) and in its
  /// section [sectionId] (null for none; a section of another notebook
  /// counts as none), at [index] of that group, or at the end. The edit time
  /// of the note stays.
  void moveNote(
    String noteId, {
    required String? notebookId,
    String? sectionId,
    int? index,
  }) {
    final old = note(noteId);
    if (old == null) return;
    final m = Mutation('Move Note');
    if (notebookId == null || notebook(notebookId) == null) {
      final after = old.copyWith(
        notebookId: null,
        sectionId: null,
        sortOrder: 0,
      );
      if (after != old) m.notes.add((before: old, after: after));
    } else {
      final section = sectionId == null
          ? null
          : _try(() => repos.notebooks.section(sectionId));
      m.notes.addAll(
        _placeNote(
          old,
          notebookId: notebookId,
          sectionId: section?.notebookId == notebookId ? section!.id : null,
          index: index,
        ),
      );
    }
    if (!m.isEmpty) commit(m);
  }

  /// Puts a note at [index] of its group in its notebook.
  void reorderInNotebook(String noteId, int index) {
    final old = note(noteId);
    final book = old?.notebookId;
    if (old == null || book == null) return;
    final m = Mutation('Move Note');
    final known = {for (final s in notebookSections(book)) s.id};
    m.notes.addAll(
      _placeNote(
        old,
        notebookId: book,
        sectionId: known.contains(old.sectionId) ? old.sectionId : null,
        index: index,
      ),
    );
    if (!m.isEmpty) commit(m);
  }

  // The archive

  /// Archives a note. It then shows only in the archive. When it is the
  /// note on screen, it stays on screen and the list shows the archive.
  void archiveNote(String id) {
    final old = note(id);
    if (old == null || old.archived) return;
    final m = Mutation('Archive Note')
      ..notes.add((before: old, after: old.copyWith(archivedAt: clockStamp())));
    if (!commit(m)) return;
    if (_selectedNoteId == id && _noteSection != NoteSection.archive) {
      _noteSection = NoteSection.archive;
      _noteQuery = '';
      _changed();
    }
  }

  /// Takes a note out of the archive. When it is the note on screen and the
  /// list would hide it, the list shows All.
  void unarchiveNote(String id) {
    final old = note(id);
    if (old == null || !old.archived) return;
    final m = Mutation('Unarchive Note')
      ..notes.add((before: old, after: old.copyWith(archivedAt: null)));
    if (!commit(m)) return;
    if (_selectedNoteId == id &&
        !notes(
          section: _noteSection,
          query: _noteQuery,
        ).any((n) => n.id == id)) {
      _noteSection = NoteSection.all;
      _noteQuery = '';
      _changed();
    }
  }
}
