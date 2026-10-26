// Port of Sources/Grove/Notes/NotesView.swift: the notes screen. A wide
// window shows three columns: the sections and notebooks, the list, and the
// chosen note. A narrower one drops the sidebar for a section picker. A phone
// shows one page at a time: the sections, the list, the note.
import 'package:flutter/material.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/note.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../shell/shell_layout.dart';
import '../tasks/task_format.dart';
import '../tasks/task_widgets.dart';
import '../theme/grove_theme.dart';
import '../theme/panel.dart';
import '../theme/symbols.dart';
import 'day_panel.dart';
import 'note_editor_pane.dart';
import 'notes_sidebar.dart';

/// The icon of a note by its kind.
String noteIcon(Note note) => switch (note.kind) {
  NoteKind.daily => 'sun.max',
  NoteKind.weekly => 'calendar',
  NoteKind.note => 'note.text',
};

class NotesView extends StatefulWidget {
  const NotesView({super.key, required this.store});

  final AppStore store;

  /// The width of the list beside the note, with the sidebar.
  static const listWidth = 320.0;

  /// The width of the list without the sidebar.
  static const narrowListWidth = 300.0;

  /// From this width of the screen on, the sidebar shows.
  static const sidebarFrom = 1000.0;

  @override
  State<NotesView> createState() => _NotesViewState();
}

class _NotesViewState extends State<NotesView> {
  final _editing = NotesEditing();

  /// A phone shows the sections instead of the list.
  var _sections = false;

  AppStore get _store => widget.store;

  @override
  void dispose() {
    _editing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StoreBuilder(
    store: _store,
    builder: (context) {
      final phone =
          ShellRules.layoutFor(MediaQuery.sizeOf(context).width) ==
          ShellLayout.phone;
      final pad = phone ? 12.0 : 16.0;
      final id = _store.selectedNoteId;
      final chosen = id != null && _store.note(id) != null ? id : null;
      Widget editor({VoidCallback? onBack}) => NoteEditorPane(
        key: ValueKey('note-$chosen'),
        store: _store,
        noteId: chosen!,
        onBack: onBack,
      );
      return Padding(
        padding: EdgeInsets.fromLTRB(pad, 6, pad, pad),
        child: phone
            ? (chosen != null
                  ? editor(onBack: () => _store.selectedNoteId = null)
                  : _sections
                  ? NotesSidebar(
                      store: _store,
                      editing: _editing,
                      phone: true,
                      onPicked: () => setState(() => _sections = false),
                    )
                  : NotesList(
                      store: _store,
                      editing: _editing,
                      phone: true,
                      onSections: () => setState(() => _sections = true),
                    ))
            : LayoutBuilder(
                builder: (context, box) {
                  final wide = box.maxWidth >= NotesView.sidebarFrom;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 16,
                    children: [
                      if (wide)
                        SizedBox(
                          width: NotesSidebar.width,
                          child: NotesSidebar(store: _store, editing: _editing),
                        ),
                      SizedBox(
                        width: wide
                            ? NotesView.listWidth
                            : NotesView.narrowListWidth,
                        child: NotesList(
                          store: _store,
                          editing: _editing,
                          sidebar: wide,
                        ),
                      ),
                      Expanded(
                        child: chosen == null
                            ? _Empty(store: _store)
                            : editor(),
                      ),
                    ],
                  );
                },
              ),
      );
    },
  );
}

/// What the right side shows when no note is chosen.
class _Empty extends StatelessWidget {
  const _Empty({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final none = !store.hasNotes();
    return Panel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 10,
          children: [
            WholeCenter(
              child: Icon(symbolIcon('leaf'), size: 30, color: theme.accent),
            ),
            WholeCenter(
              child: ThemedHeading(
                none
                    ? 'Your thoughts grow here.'
                    : 'Pick a note, or start a new one.',
                20,
              ),
            ),
            WholeCenter(
              child: CardButton(
                key: const ValueKey('notes-empty-new'),
                label: 'New note',
                primary: true,
                onTap: store.newNote,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of the list: a group label, a note, a button.
class _Item {
  const _Item(this.id, this.build, {this.noteId, this.sectionHead});

  /// The key of the line in a list that can be sorted.
  final String id;
  final WidgetBuilder build;

  /// Set on the line of a note.
  final String? noteId;

  /// Set on the head of a section of a notebook.
  final String? sectionHead;
}

/// The name of the section, the search and the notes in their groups.
class NotesList extends StatefulWidget {
  const NotesList({
    super.key,
    required this.store,
    required this.editing,
    this.sidebar = false,
    this.phone = false,
    this.onSections,
  });

  final AppStore store;
  final NotesEditing editing;

  /// The sidebar is beside the list, with "New note", "Today" and the
  /// sections. Without it, the list has them itself.
  final bool sidebar;

  /// Lines big enough for a finger, and a button back to the sections.
  final bool phone;

  /// A phone goes back to the sections.
  final VoidCallback? onSections;

  @override
  State<NotesList> createState() => _NotesListState();
}

class _NotesListState extends State<NotesList> {
  late final _query = TextEditingController(text: widget.store.noteQuery);

  AppStore get _store => widget.store;
  NotesEditing get _editing => widget.editing;
  bool get _phone => widget.phone;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// The store clears the search when it opens a note that the list hides.
  void _follow() {
    if (_query.text != _store.noteQuery) _query.text = _store.noteQuery;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _editing,
    builder: (context, _) => StoreBuilder(
      store: _store,
      onChange: _follow,
      builder: (context) {
        final theme = GroveTheme.of(context);
        final section = _store.noteSection;
        final today = _store.clockToday;
        final book = section.notebookId;
        return Panel(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                _head(context, theme, section),
                if (!widget.sidebar && !_phone) _picker(theme, section),
                if (!widget.sidebar)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      NotePill(
                        keyName: 'notes-today',
                        title: 'Today',
                        icon: 'sun.max',
                        tall: _phone,
                        onTap: () => _store.openDailyNote(today),
                      ),
                      NotePill(
                        keyName: 'notes-week',
                        title: 'This week',
                        icon: 'calendar',
                        tall: _phone,
                        onTap: () => _store.openWeeklyNote(today),
                      ),
                    ],
                  ),
                _search(theme),
                Expanded(
                  child: book != null && _store.notebook(book) != null
                      ? _notebookList(context, theme, book, today)
                      : _plainList(context, theme, section, today),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  // The head

  Widget _head(BuildContext context, GroveTheme theme, NoteSection section) {
    final book = section.notebookId == null
        ? null
        : _store.notebook(section.notebookId!);
    final renaming =
        book != null && !widget.sidebar && _editing.notebook == book.id;
    return Row(
      spacing: 6,
      children: [
        if (_phone)
          IconTap(
            key: const ValueKey('notes-sections-back'),
            icon: symbolIcon('chevron.left'),
            label: 'Back to the sections',
            size: 20,
            color: theme.accent,
            minSide: 44,
            onTap: widget.onSections,
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              if (renaming)
                NoteRenameField(
                  key: ValueKey('notebook-title-rename-${book.id}'),
                  text: book.name,
                  label: 'Name of the notebook',
                  style: theme.heading(20).copyWith(color: theme.ink),
                  onDone: (name) {
                    _store.renameNotebook(book.id, name);
                    _editing.done();
                  },
                  onCancel: _editing.done,
                )
              else
                ThemedHeading(
                  NoteSectionLook.title(_store, section),
                  20,
                  key: const ValueKey('notes-list-title'),
                  color: book == null
                      ? null
                      : NoteSectionLook.tint(theme, book),
                ),
              Text(
                NoteSectionLook.hint(section),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.body(11).copyWith(color: theme.muted),
              ),
            ],
          ),
        ),
        // Without the sidebar, the menu of a notebook is here.
        if (book != null && !widget.sidebar)
          Builder(
            builder: (context) => IconTap(
              key: const ValueKey('notes-notebook-menu'),
              icon: symbolIcon('ellipsis.circle'),
              label: 'More for this notebook',
              minSide: _phone ? 44 : 0,
              onTap: () => showNotebookMenu(
                context,
                belowOf(context),
                _store,
                _editing,
                book,
              ),
            ),
          ),
        if (!widget.sidebar)
          IconTap(
            key: const ValueKey('notes-new'),
            icon: symbolIcon('square.and.pencil'),
            label: 'New note',
            color: theme.accent,
            minSide: _phone ? 44 : 0,
            onTap: _store.newNote,
          ),
      ],
    );
  }

  /// Without the sidebar: the section in a button that opens the list of
  /// sections.
  Widget _picker(GroveTheme theme, NoteSection section) => Builder(
    builder: (context) => NoteTap(
      key: const ValueKey('notes-picker'),
      label: 'Section: ${NoteSectionLook.title(_store, section)}',
      onTap: () {
        final books = _store.notebooks();
        final tags = _store.allNoteTags();
        void pick(NoteSection s) => _store.noteSection = s;
        showGroveMenu(context, belowOf(context), [
          for (final s in NoteSection.fixed)
            MenuLine(
              NoteSectionLook.title(_store, s),
              () => pick(s),
              checked: s == section,
            ),
          const MenuLine.divider(),
          const MenuLine.title('Notebooks'),
          for (final b in books)
            MenuLine(
              b.name,
              () => pick(NoteSection.notebook(b.id)),
              checked: section.notebookId == b.id,
            ),
          MenuLine('New notebook', () {
            final b = _store.newNotebook();
            _editing.renameNotebook(b.id);
          }),
          if (tags.isNotEmpty) ...[
            const MenuLine.divider(),
            const MenuLine.title('Tags'),
            for (final t in tags)
              MenuLine(
                '#$t',
                () => pick(NoteSection.tag(t)),
                checked: section.tagName == t,
              ),
          ],
        ]);
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.line),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            spacing: 6,
            children: [
              Icon(
                symbolIcon(NoteSectionLook.icon(section)),
                size: 13,
                color: theme.accent,
              ),
              Expanded(
                child: Text(
                  NoteSectionLook.title(_store, section),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.body(13).copyWith(color: theme.ink),
                ),
              ),
              Icon(symbolIcon('chevron.down'), size: 14, color: theme.muted),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _search(GroveTheme theme) => DecoratedBox(
    decoration: BoxDecoration(
      color: theme.surface2,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: _phone ? 11 : 7),
      child: Row(
        spacing: 6,
        children: [
          Icon(symbolIcon('magnifyingglass'), size: 14, color: theme.muted),
          Expanded(
            child: GroveField(
              key: const ValueKey('notes-search'),
              controller: _query,
              placeholder: 'Search notes',
              label: 'Search notes',
              padding: EdgeInsets.zero,
              style: theme.body(13).copyWith(color: theme.ink),
              onChanged: (text) => _store.noteQuery = text,
              onEscape: () => _store.noteQuery = '',
            ),
          ),
          if (_store.noteQuery.isNotEmpty)
            IconTap(
              key: const ValueKey('notes-search-clear'),
              icon: symbolIcon('xmark.circle.fill'),
              label: 'Clear the search',
              size: 14,
              color: theme.muted,
              onTap: () => _store.noteQuery = '',
            ),
        ],
      ),
    ),
  );

  // The lists

  Widget _emptyText(GroveTheme theme, String text) => Align(
    alignment: Alignment.topLeft,
    child: Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Text(text, style: theme.body(12).copyWith(color: theme.muted)),
    ),
  );

  Widget _groupLabel(GroveTheme theme, String text, {Color? color}) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
    child: Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme
          .body(10, weight: FontWeight.w700)
          .copyWith(color: color ?? theme.muted),
    ),
  );

  /// Every section but a notebook: the notes in date groups, the pinned
  /// ones first.
  Widget _plainList(
    BuildContext context,
    GroveTheme theme,
    NoteSection section,
    DayKey today,
  ) {
    final groups = _store.groupedNotes();
    if (groups.every((g) => g.notes.isEmpty)) {
      return _emptyText(
        theme,
        _store.noteQuery.isEmpty
            ? NoteSectionLook.empty(section)
            : 'Nothing matches.',
      );
    }
    // The pinned notes stay on top, above the date groups.
    final split = section != NoteSection.pinned;
    final pinned = [
      if (split)
        for (final g in groups)
          for (final n in g.notes)
            if (n.pinned) n,
    ];
    final places = section == NoteSection.all
        ? _store.notePlaces([for (final g in groups) ...g.notes])
        : const <String, NoteSection>{};
    final items = <WidgetBuilder>[];
    void addGroup(String label, List<Note> notes) {
      if (notes.isEmpty) return;
      items.add((_) => _groupLabel(theme, label));
      for (final n in notes) {
        items.add((c) => _row(c, theme, n, today, place: places[n.id]));
      }
    }

    addGroup('Pinned', pinned);
    for (final g in groups) {
      addGroup(g.label, [
        for (final n in g.notes)
          if (!split || !n.pinned) n,
      ]);
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, i) => items[i](context),
    );
  }

  /// A notebook: its notes in no section, then each section with its
  /// notes, "Add note to …" and at the end "New section". A note can be
  /// dragged to another place, except on a phone and while searching.
  Widget _notebookList(
    BuildContext context,
    GroveTheme theme,
    String bookId,
    DayKey today,
  ) {
    final book = _store.notebook(bookId)!;
    final tint = NoteSectionLook.tint(theme, book);
    final searching = _store.noteQuery.isNotEmpty;
    final groups = _store.groupedNotes();
    if (searching && groups.every((g) => g.notes.isEmpty)) {
      return _emptyText(theme, 'Nothing matches.');
    }
    final hasSections = groups.any((g) => g.sectionId != null);
    final drag = !_phone && !searching;
    final items = <_Item>[];
    for (final g in groups) {
      final sid = g.sectionId;
      if (searching && g.notes.isEmpty) continue;
      if (sid != null) {
        items.add(
          _Item(
            'head-$sid',
            (c) => _sectionHead(c, theme, sid, g.label, tint),
            sectionHead: sid,
          ),
        );
      }
      for (final n in g.notes) {
        items.add(
          _Item('note-${n.id}', (c) {
            final row = Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _row(c, theme, n, today),
            );
            if (!drag) return row;
            return ReorderableDragStartListener(
              index: items.indexWhere((it) => it.noteId == n.id),
              child: row,
            );
          }, noteId: n.id),
        );
      }
      if (searching) continue;
      if (sid != null) {
        items.add(
          _Item(
            'add-$sid',
            (_) => _addButton(theme, 'section-add-$sid', g.label, sid),
          ),
        );
      } else if (!hasSections) {
        items.add(
          _Item(
            'add-loose',
            (_) => _addButton(theme, 'section-add-loose', book.name, null),
          ),
        );
      }
    }
    if (!searching) {
      items.add(_Item('new-section', (_) => _newSectionButton(theme, bookId)));
    }
    if (!drag) {
      return ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, i) => items[i].build(context),
      );
    }
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      itemCount: items.length,
      proxyDecorator: (child, _, _) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: child,
      ),
      onReorderItem: (from, to) => _drop(items, bookId, from, to),
      itemBuilder: (context, i) => KeyedSubtree(
        key: ValueKey('notes-item-${items[i].id}'),
        child: items[i].build(context),
      ),
    );
  }

  /// A note let go at [to] of [items] without it: the section is the last
  /// head above it, the place is the number of notes between that head and
  /// it.
  void _drop(List<_Item> items, String bookId, int from, int to) {
    final noteId = items[from].noteId;
    if (noteId == null) return;
    final rest = [...items]..removeAt(from);
    final at = to.clamp(0, rest.length);
    String? sectionId;
    var index = 0;
    for (final it in rest.take(at)) {
      if (it.sectionHead != null) {
        sectionId = it.sectionHead;
        index = 0;
      } else if (it.noteId != null) {
        index += 1;
      }
    }
    _store.moveNote(
      noteId,
      notebookId: bookId,
      sectionId: sectionId,
      index: index,
    );
  }

  Widget _sectionHead(
    BuildContext context,
    GroveTheme theme,
    String sectionId,
    String name,
    Color tint,
  ) {
    final renaming = _editing.section == sectionId;
    return Padding(
      key: ValueKey('section-head-$sectionId'),
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Row(
        spacing: 6,
        children: [
          Expanded(
            child: renaming
                ? NoteRenameField(
                    key: ValueKey('section-rename-$sectionId'),
                    text: name,
                    label: 'Name of the section',
                    style: theme
                        .body(12, weight: FontWeight.w700)
                        .copyWith(color: tint),
                    onDone: (text) {
                      _store.renameSection(sectionId, text);
                      _editing.done();
                    },
                    onCancel: _editing.done,
                  )
                : _groupLabel(theme, name, color: tint),
          ),
          if (!renaming)
            Builder(
              builder: (context) => IconTap(
                key: ValueKey('section-menu-$sectionId'),
                icon: symbolIcon('ellipsis.circle'),
                label: 'More for the section $name',
                size: 13,
                minSide: _phone ? 44 : 0,
                onTap: () => showGroveMenu(context, belowOf(context), [
                  MenuLine(
                    'Rename section',
                    () => _editing.renameSection(sectionId),
                  ),
                  MenuLine(
                    'Delete section',
                    () => _store.deleteSection(sectionId),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _addButton(
    GroveTheme theme,
    String key,
    String name,
    String? sectionId,
  ) => Padding(
    padding: EdgeInsets.zero,
    child: NoteTap(
      key: ValueKey(key),
      label: 'Add note to $name',
      onTap: () => _store.newNote(sectionId: sectionId),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: _phone ? 44 : 26),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            spacing: 5,
            children: [
              Icon(symbolIcon('plus'), size: 12, color: theme.muted),
              Expanded(
                child: Text(
                  'Add note to $name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.body(12).copyWith(color: theme.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _newSectionButton(GroveTheme theme, String bookId) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 4),
    child: NoteTap(
      key: const ValueKey('notes-new-section'),
      label: 'New section',
      onTap: () {
        final s = _store.newSection(bookId, '');
        if (s != null) _editing.renameSection(s.id);
      },
      child: DashedBorder(
        color: theme.line,
        radius: 8,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: _phone ? 44 : 32),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 5,
            children: [
              Icon(symbolIcon('plus'), size: 12, color: theme.muted),
              Text(
                'New section',
                style: theme.body(12).copyWith(color: theme.muted),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  // A note

  Widget _row(
    BuildContext context,
    GroveTheme theme,
    Note note,
    DayKey today, {
    NoteSection? place,
  }) {
    final selected = _store.selectedNoteId == note.id;
    final preview = NotesRules.preview(note.body);
    final at = note.updatedAt;
    final day = at.length >= 10 ? DayKey(at.substring(0, 10)) : null;
    final title = note.title.isEmpty ? 'Untitled' : note.title;
    final placeBook = place?.notebookId == null
        ? null
        : _store.notebook(place!.notebookId!);
    return NoteTap(
      key: ValueKey('note-row-${note.id}'),
      label: title,
      selected: selected,
      onTap: () => _store.openNote(note.id),
      onMenu: (spot) => showGroveMenu(context, spot, [
        MenuLine(
          note.pinned ? 'Unpin' : 'Pin',
          () => _store.togglePin(note.id),
        ),
        MenuLine('Duplicate', () => _store.duplicateNote(note.id)),
        MenuLine('Move to notebook…', () {
          if (context.mounted) showMoveMenu(context, spot, _store, note);
        }),
        MenuLine(
          note.archived ? 'Unarchive' : 'Archive',
          () => note.archived
              ? _store.unarchiveNote(note.id)
              : _store.archiveNote(note.id),
        ),
        const MenuLine.divider(),
        MenuLine('Delete', () => _store.deleteNote(note.id)),
      ]),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: _phone ? 44 : 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? theme.accent.withValues(alpha: 0.16)
                : theme.surface2.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 3,
              children: [
                Row(
                  spacing: 5,
                  children: [
                    Icon(
                      symbolIcon(noteIcon(note)),
                      size: 10,
                      color: theme.accent,
                    ),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme
                            .body(13, weight: FontWeight.w600)
                            .copyWith(color: theme.ink),
                      ),
                    ),
                    if (note.pinned)
                      Icon(
                        symbolIcon('pin.fill'),
                        size: 9,
                        color: theme.accent2,
                      ),
                  ],
                ),
                if (preview.isNotEmpty)
                  Text(
                    preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.body(12).copyWith(color: theme.muted),
                  ),
                if (day != null || place != null)
                  Row(
                    spacing: 6,
                    children: [
                      if (day != null)
                        Flexible(
                          child: Text(
                            TaskFormat.dayLabel(day, today: today),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme
                                .body(10)
                                .copyWith(
                                  color: theme.muted.withValues(alpha: 0.8),
                                ),
                          ),
                        ),
                      if (place != null)
                        Flexible(
                          child: TaskChip(
                            placeBook?.name ??
                                NoteSectionLook.title(_store, place),
                            key: ValueKey('note-place-${note.id}'),
                            icon: symbolIcon(NoteSectionLook.icon(place)),
                            tint: placeBook == null
                                ? null
                                : NoteSectionLook.tint(theme, placeBook),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
