// Port of Sources/Grove/Notes/NotesView.swift: the notes screen. The list
// on the left, the chosen note on the right. A phone shows one of the two.
import 'package:flutter/material.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/note.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../shell/shell_layout.dart';
import '../shell/top_buttons.dart' show KeyNames;
import '../tasks/task_format.dart';
import '../tasks/task_widgets.dart';
import '../theme/grove_theme.dart';
import '../theme/panel.dart';
import '../theme/symbols.dart';
import 'day_panel.dart';
import 'note_editor_pane.dart';

/// The icon of a note by its kind.
String noteIcon(Note note) => switch (note.kind) {
  NoteKind.daily => 'sun.max',
  NoteKind.weekly => 'calendar',
  NoteKind.note => 'note.text',
};

class NotesView extends StatelessWidget {
  const NotesView({super.key, required this.store});

  final AppStore store;

  /// The width of the list beside the note.
  static const listWidth = 300.0;

  @override
  Widget build(BuildContext context) => StoreBuilder(
    store: store,
    builder: (context) {
      final phone =
          ShellRules.layoutFor(MediaQuery.sizeOf(context).width) ==
          ShellLayout.phone;
      final pad = phone ? 12.0 : 16.0;
      final id = store.selectedNoteId;
      final chosen = id != null && store.note(id) != null ? id : null;
      final list = NotesList(store: store);
      return Padding(
        padding: EdgeInsets.fromLTRB(pad, 6, pad, pad),
        child: phone
            ? (chosen == null
                  ? list
                  : NoteEditorPane(
                      key: ValueKey('note-$chosen'),
                      store: store,
                      noteId: chosen,
                      onBack: () => store.selectedNoteId = null,
                    ))
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 16,
                children: [
                  SizedBox(width: listWidth, child: list),
                  Expanded(
                    child: chosen == null
                        ? _Empty(store: store)
                        : NoteEditorPane(
                            key: ValueKey('note-$chosen'),
                            store: store,
                            noteId: chosen,
                          ),
                  ),
                ],
              ),
      );
    },
  );
}

/// What the right side shows when no note is chosen.
class _Empty extends StatelessWidget {
  const _Empty({required this.store});

  final AppStore store;

  /// The key of "New Note" in the menus, the Mac way.
  static const newNoteKey = '⌥⌘N';

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final none = store.notes().isEmpty;
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
              child: none
                  // One sentence, as in the Mac app. The hint goes under
                  // the first words when the window is narrow.
                  ? Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 2,
                      children: [
                        const ThemedHeading('Your thoughts grow here.', 20),
                        ThemedHeading(
                          '${KeyNames.of(_Empty.newNoteKey)} for a new note.',
                          20,
                        ),
                      ],
                    )
                  : const ThemedHeading('Pick a note, or start a new one.', 20),
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

/// Search, filters and the notes themselves.
class NotesList extends StatefulWidget {
  const NotesList({super.key, required this.store});

  final AppStore store;

  @override
  State<NotesList> createState() => _NotesListState();
}

class _NotesListState extends State<NotesList> {
  late final _query = TextEditingController(text: widget.store.noteQuery);

  AppStore get _store => widget.store;

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
  Widget build(BuildContext context) => StoreBuilder(
    store: _store,
    onChange: _follow,
    builder: (context) {
      final theme = GroveTheme.of(context);
      final notes = _store.notes(
        filter: _store.noteFilter,
        query: _store.noteQuery,
      );
      final today = _store.clockToday;
      return Panel(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: ThemedHeading('Notes', 20, weight: FontWeight.w600),
                  ),
                  IconTap(
                    key: const ValueKey('notes-new'),
                    icon: symbolIcon('square.and.pencil'),
                    label: 'New note',
                    color: theme.accent,
                    onTap: _store.newNote,
                  ),
                ],
              ),
              Row(
                spacing: 6,
                children: [
                  _pill(
                    theme,
                    'notes-today',
                    'Today',
                    'sun.max',
                    () => _store.openDailyNote(today),
                  ),
                  _pill(
                    theme,
                    'notes-week',
                    'This week',
                    'calendar',
                    () => _store.openWeeklyNote(today),
                  ),
                ],
              ),
              _search(theme),
              _filters(theme),
              Expanded(
                child: notes.isEmpty
                    ? Align(
                        alignment: Alignment.topLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Text(
                            _store.noteQuery.isEmpty &&
                                    _store.noteFilter == NoteFilter.all
                                ? 'No notes here yet.'
                                : 'Nothing matches.',
                            style: theme.body(12).copyWith(color: theme.muted),
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: notes.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, i) =>
                            _row(context, theme, notes[i], today),
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _pill(
    GroveTheme theme,
    String key,
    String title,
    String icon,
    VoidCallback action,
  ) => NoteTap(
    key: ValueKey(key),
    label: title,
    onTap: action,
    child: DecoratedBox(
      decoration: ShapeDecoration(
        color: theme.accent.withValues(alpha: 0.14),
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            Icon(symbolIcon(icon), size: 12, color: theme.accent),
            Text(
              title,
              maxLines: 1,
              style: theme
                  .body(12, weight: FontWeight.w600)
                  .copyWith(color: theme.accent),
            ),
          ],
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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

  Widget _filters(GroveTheme theme) {
    final filters = <(String, String, NoteFilter)>[
      ('all', 'All', NoteFilter.all),
      ('daily', 'Daily', NoteFilter.daily),
      ('weekly', 'Weekly', NoteFilter.weekly),
      ('pinned', 'Pinned', NoteFilter.pinned),
      for (final tag in _store.allNoteTags())
        ('tag-$tag', '#$tag', NoteFilter.tag(tag)),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        spacing: 6,
        children: [
          for (final (key, name, filter) in filters)
            _filter(theme, key, name, filter),
        ],
      ),
    );
  }

  Widget _filter(GroveTheme theme, String key, String name, NoteFilter filter) {
    final on = _store.noteFilter == filter;
    return NoteTap(
      key: ValueKey('notes-filter-$key'),
      label: name,
      selected: on,
      onTap: () => _store.noteFilter = filter,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: on ? theme.accent : theme.surface2,
          shape: const StadiumBorder(),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          child: Text(
            name,
            maxLines: 1,
            style: theme
                .body(11, weight: on ? FontWeight.w600 : FontWeight.w400)
                .copyWith(color: on ? theme.surface : theme.muted),
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, GroveTheme theme, Note note, DayKey today) {
    final selected = _store.selectedNoteId == note.id;
    final preview = NotesRules.preview(note.body);
    final at = note.updatedAt;
    final day = at.length >= 10 ? DayKey(at.substring(0, 10)) : null;
    final title = note.title.isEmpty ? 'Untitled' : note.title;
    return NoteTap(
      key: ValueKey('note-row-${note.id}'),
      label: title,
      selected: selected,
      onTap: () => _store.openNote(note.id),
      onMenu: (place) => showGroveMenu(context, place, [
        MenuLine(
          note.pinned ? 'Unpin' : 'Pin',
          () => _store.togglePin(note.id),
        ),
        MenuLine('Duplicate', () => _store.duplicateNote(note.id)),
        const MenuLine.divider(),
        MenuLine('Delete', () => _store.deleteNote(note.id)),
      ]),
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
                    Icon(symbolIcon('pin.fill'), size: 9, color: theme.accent2),
                ],
              ),
              if (preview.isNotEmpty)
                Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.body(12).copyWith(color: theme.muted),
                ),
              if (day != null)
                Text(
                  TaskFormat.dayLabel(day, today: today),
                  maxLines: 1,
                  style: theme
                      .body(10)
                      .copyWith(color: theme.muted.withValues(alpha: 0.8)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
