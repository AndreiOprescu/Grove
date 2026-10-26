// The left column of the notes screen: "New note", the fixed sections, the
// notebooks and the tags, each with its count. A phone shows it as its own
// page before the list.
import 'package:flutter/material.dart';
import 'package:grove/core/model/note.dart';
import 'package:grove/core/model/notebook.dart';
import 'package:grove/core/model/task_color.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../shell/top_buttons.dart' show KeyNames;
import '../tasks/task_widgets.dart';
import '../theme/grove_theme.dart';
import '../theme/named_colors.dart';
import '../theme/panel.dart';
import '../theme/symbols.dart';
import 'day_panel.dart' show NoteTap;

/// What the notes screen is renaming right now. The sidebar and the list
/// share it: "New section" in the menu of a notebook starts a field in the
/// list.
class NotesEditing extends ChangeNotifier {
  String? _notebook;
  String? _section;

  /// The notebook whose name is a field, or null.
  String? get notebook => _notebook;

  /// The section whose name is a field, or null.
  String? get section => _section;

  void renameNotebook(String? id) {
    _notebook = id;
    _section = null;
    notifyListeners();
  }

  void renameSection(String? id) {
    _section = id;
    _notebook = null;
    notifyListeners();
  }

  void done() {
    if (_notebook == null && _section == null) return;
    _notebook = null;
    _section = null;
    notifyListeners();
  }
}

/// The names, icons and words of the sections of the notes screen.
abstract final class NoteSectionLook {
  static String title(AppStore store, NoteSection s) => switch (s.kind) {
    NoteSectionKind.all => 'All notes',
    NoteSectionKind.inbox => 'Inbox',
    NoteSectionKind.daily => 'Daily',
    NoteSectionKind.weekly => 'Weekly',
    NoteSectionKind.pinned => 'Pinned',
    NoteSectionKind.meetings => 'Meetings',
    NoteSectionKind.withTasks => 'With tasks',
    NoteSectionKind.archive => 'Archive',
    NoteSectionKind.notebook =>
      store.notebook(s.notebookId!)?.name ?? 'Notebook',
    NoteSectionKind.tag => '#${s.tagName}',
  };

  static String icon(NoteSection s) => switch (s.kind) {
    NoteSectionKind.all => 'tray.full',
    NoteSectionKind.inbox => 'tray',
    NoteSectionKind.daily => 'sun.max',
    NoteSectionKind.weekly => 'calendar',
    NoteSectionKind.pinned => 'pin',
    NoteSectionKind.meetings => 'person.2',
    NoteSectionKind.withTasks => 'checklist',
    NoteSectionKind.archive => 'archivebox',
    NoteSectionKind.notebook => 'book.closed',
    NoteSectionKind.tag => 'number',
  };

  /// The small line under the name of the list.
  static String hint(NoteSection s) => switch (s.kind) {
    NoteSectionKind.all => 'Every note that is not archived',
    NoteSectionKind.inbox => 'Notes in no notebook',
    NoteSectionKind.daily => 'One note for each day',
    NoteSectionKind.weekly => 'One note for each week',
    NoteSectionKind.pinned => 'The notes you keep on top',
    NoteSectionKind.meetings => 'Notes linked to an event',
    NoteSectionKind.withTasks => 'Notes with a task still open',
    NoteSectionKind.archive => 'Out of the way, not deleted',
    NoteSectionKind.notebook => 'Drag a note to sort it',
    NoteSectionKind.tag => 'Notes with this tag',
  };

  /// What an empty list says.
  static String empty(NoteSection s) => switch (s.kind) {
    NoteSectionKind.all => 'No notes here yet.',
    NoteSectionKind.inbox =>
      'No loose notes. New notes outside a notebook land here.',
    NoteSectionKind.daily => 'No daily notes yet. "Today" makes one.',
    NoteSectionKind.weekly => 'No weekly notes yet. "This week" makes one.',
    NoteSectionKind.pinned => 'No pinned notes. Pin a note to keep it on top.',
    NoteSectionKind.meetings =>
      'No meeting notes yet. A note made from an event lands here.',
    NoteSectionKind.withTasks => 'No note has a task that is still open.',
    NoteSectionKind.archive => 'The archive is empty.',
    NoteSectionKind.notebook => 'This notebook is empty.',
    NoteSectionKind.tag => 'No notes with this tag.',
  };

  /// The colour of a notebook, or the accent of the theme.
  static Color tint(GroveTheme theme, Notebook? book) =>
      TaskPalette.color(book?.color ?? '') ?? theme.accent;

  /// Where a note lives, like "Notebooks › Work › Ideas" or "Inbox".
  static String crumb(AppStore store, Note note) {
    final place = store.notePlace(note.id) ?? NoteSection.inbox;
    final id = place.notebookId;
    if (id == null) return title(store, place);
    final book = store.notebook(id);
    final section = store
        .notebookSections(id)
        .where((s) => s.id == note.sectionId)
        .firstOrNull;
    return ['Notebooks', book?.name ?? 'Notebook', ?section?.name].join(' › ');
  }
}

/// The menu that puts a note in a notebook, in one of its sections, or in
/// none.
void showMoveMenu(BuildContext context, Offset at, AppStore store, Note note) {
  final books = store.notebooks();
  showGroveMenu(context, at, [
    MenuLine(
      'No notebook',
      () => store.moveNote(note.id, notebookId: null),
      checked: note.notebookId == null,
    ),
    if (books.isNotEmpty) const MenuLine.divider(),
    for (final b in books) ...[
      MenuLine(
        b.name,
        () => store.moveNote(note.id, notebookId: b.id),
        checked: note.notebookId == b.id && note.sectionId == null,
      ),
      for (final s in store.notebookSections(b.id))
        MenuLine(
          '${b.name} › ${s.name}',
          () => store.moveNote(note.id, notebookId: b.id, sectionId: s.id),
          checked: note.sectionId == s.id,
        ),
    ],
  ]);
}

/// The place under a widget, for a menu.
Offset belowOf(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset(0, box.size.height));
}

/// A name that is being typed. Return or a click elsewhere keeps it, Esc
/// goes back.
class NoteRenameField extends StatefulWidget {
  const NoteRenameField({
    super.key,
    required this.text,
    required this.label,
    required this.onDone,
    required this.onCancel,
    this.style,
  });

  final String text;
  final String label;
  final ValueChanged<String> onDone;
  final VoidCallback onCancel;
  final TextStyle? style;

  @override
  State<NoteRenameField> createState() => _NoteRenameFieldState();
}

class _NoteRenameFieldState extends State<NoteRenameField> {
  late final _controller = TextEditingController(
    text: widget.text,
  )..selection = TextSelection(baseOffset: 0, extentOffset: widget.text.length);
  final _focus = FocusNode();
  var _ended = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _end(keep: true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _end({required bool keep}) {
    if (_ended) return;
    _ended = true;
    if (keep) {
      widget.onDone(_controller.text);
    } else {
      widget.onCancel();
    }
  }

  @override
  Widget build(BuildContext context) => GroveField(
    controller: _controller,
    focusNode: _focus,
    autofocus: true,
    placeholder: 'Name',
    label: widget.label,
    padding: EdgeInsets.zero,
    style: widget.style,
    onSubmitted: (_) => _end(keep: true),
    onEscape: () => _end(keep: false),
  );
}

/// The sidebar of the notes screen.
class NotesSidebar extends StatelessWidget {
  const NotesSidebar({
    super.key,
    required this.store,
    required this.editing,
    this.phone = false,
    this.onPicked,
  });

  final AppStore store;
  final NotesEditing editing;

  /// Rows big enough for a finger.
  final bool phone;

  /// Runs after a section was picked. A phone then shows the list.
  final VoidCallback? onPicked;

  static const width = 220.0;

  double get _rowHeight => phone ? 44 : 30;

  void _pick(NoteSection s) {
    store.noteSection = s;
    onPicked?.call();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: editing,
    builder: (context, _) => StoreBuilder(
      store: store,
      builder: (context) {
        final theme = GroveTheme.of(context);
        final counts = store.sectionCounts();
        final tags = store.allNoteTags();
        final today = store.clockToday;
        return Panel(
          key: const ValueKey('notes-sidebar'),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                _newNote(theme),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    NotePill(
                      keyName: 'notes-today',
                      title: 'Today',
                      icon: 'sun.max',
                      tall: phone,
                      onTap: () => store.openDailyNote(today),
                    ),
                    NotePill(
                      keyName: 'notes-week',
                      title: 'This week',
                      icon: 'calendar',
                      tall: phone,
                      onTap: () => store.openWeeklyNote(today),
                    ),
                  ],
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final s in NoteSection.fixed)
                        _sectionRow(theme, s, counts[s] ?? 0),
                      _label(
                        theme,
                        'NOTEBOOKS',
                        trailing: IconTap(
                          key: const ValueKey('notes-new-notebook'),
                          icon: symbolIcon('plus'),
                          label: 'New notebook',
                          color: theme.accent,
                          minSide: phone ? 44 : 0,
                          onTap: () {
                            final book = store.newNotebook();
                            editing.renameNotebook(book.id);
                          },
                        ),
                      ),
                      for (final b in store.notebooks())
                        _notebookRow(
                          context,
                          theme,
                          b,
                          counts[NoteSection.notebook(b.id)] ?? 0,
                        ),
                      if (tags.isNotEmpty) ...[
                        _label(theme, 'TAGS'),
                        for (final t in tags) _tagRow(theme, t),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget _newNote(GroveTheme theme) => NoteTap(
    key: const ValueKey('notes-new'),
    label: 'New note',
    tip: phone ? null : 'New note (${KeyNames.of('⌥⌘N')})',
    onTap: store.newNote,
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: phone ? 44 : 32),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.accent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            spacing: 6,
            children: [
              Icon(symbolIcon('square.and.pencil'), size: 14, color: theme.bg),
              Expanded(
                child: Text(
                  'New note',
                  maxLines: 1,
                  style: theme
                      .body(13, weight: FontWeight.w600)
                      .copyWith(color: theme.bg),
                ),
              ),
              if (!phone)
                Text(
                  KeyNames.of('⌥⌘N'),
                  maxLines: 1,
                  style: theme
                      .body(11)
                      .copyWith(color: theme.bg.withValues(alpha: 0.75)),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _label(GroveTheme theme, String text, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 14, 2, 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: theme
                .body(10, weight: FontWeight.w700)
                .copyWith(color: theme.muted),
          ),
        ),
        ?trailing,
      ],
    ),
  );

  /// The look of one row: an icon, a name and a count.
  Widget _rowBox(
    GroveTheme theme, {
    required bool on,
    required Widget icon,
    required Widget name,
    int? count,
  }) => ConstrainedBox(
    constraints: BoxConstraints(minHeight: _rowHeight),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: on ? theme.accent.withValues(alpha: 0.14) : null,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          spacing: 8,
          children: [
            icon,
            Expanded(child: name),
            if (count != null)
              Text(
                '$count',
                key: const ValueKey('notes-count'),
                style: theme.body(11).copyWith(color: theme.muted),
              ),
          ],
        ),
      ),
    ),
  );

  Text _name(GroveTheme theme, String text, {required bool on}) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: theme
        .body(13, weight: on ? FontWeight.w600 : FontWeight.w400)
        .copyWith(color: theme.ink),
  );

  Widget _sectionRow(GroveTheme theme, NoteSection s, int count) {
    final on = store.noteSection == s;
    final title = NoteSectionLook.title(store, s);
    return NoteTap(
      key: ValueKey('notes-section-${s.kind.name}'),
      label: '$title, $count',
      selected: on,
      onTap: () => _pick(s),
      child: _rowBox(
        theme,
        on: on,
        icon: Icon(
          symbolIcon(NoteSectionLook.icon(s)),
          size: 14,
          color: on ? theme.accent : theme.muted,
        ),
        name: _name(theme, title, on: on),
        count: count,
      ),
    );
  }

  Widget _tagRow(GroveTheme theme, String tag) {
    final s = NoteSection.tag(tag);
    final on = store.noteSection == s;
    return NoteTap(
      key: ValueKey('notes-tag-$tag'),
      label: '#$tag',
      selected: on,
      onTap: () => _pick(s),
      child: _rowBox(
        theme,
        on: on,
        icon: Icon(symbolIcon('number'), size: 13, color: theme.muted),
        name: _name(theme, tag, on: on),
      ),
    );
  }

  Widget _notebookRow(
    BuildContext context,
    GroveTheme theme,
    Notebook book,
    int count,
  ) {
    final s = NoteSection.notebook(book.id);
    final on = store.noteSection == s;
    final icon = Icon(
      symbolIcon('book.closed'),
      size: 14,
      color: NoteSectionLook.tint(theme, book),
    );
    if (editing.notebook == book.id) {
      return KeyedSubtree(
        key: ValueKey('notebook-row-${book.id}'),
        child: _rowBox(
          theme,
          on: on,
          icon: icon,
          name: NoteRenameField(
            key: ValueKey('notebook-rename-${book.id}'),
            text: book.name,
            label: 'Name of the notebook',
            style: theme.body(13).copyWith(color: theme.ink),
            onDone: (name) {
              store.renameNotebook(book.id, name);
              editing.done();
            },
            onCancel: editing.done,
          ),
          count: count,
        ),
      );
    }
    return NoteTap(
      key: ValueKey('notebook-row-${book.id}'),
      label: '${book.name}, $count',
      selected: on,
      onTap: () => _pick(s),
      onMenu: (at) => showNotebookMenu(
        context,
        at,
        store,
        editing,
        book,
        onPicked: onPicked,
      ),
      child: _rowBox(
        theme,
        on: on,
        icon: icon,
        name: _name(theme, book.name, on: on),
        count: count,
      ),
    );
  }
}

/// The menu of a notebook: Rename, Colour, New section, Delete.
void showNotebookMenu(
  BuildContext context,
  Offset at,
  AppStore store,
  NotesEditing editing,
  Notebook book, {
  VoidCallback? onPicked,
}) {
  showGroveMenu(context, at, [
    MenuLine('Rename', () => editing.renameNotebook(book.id)),
    MenuLine('Colour…', () {
      if (!context.mounted) return;
      showGroveMenu(context, at, [
        MenuLine(
          'None',
          () => store.setNotebookColor(book.id, null),
          checked: book.color == null,
        ),
        for (final name in TaskColor.names)
          MenuLine(
            '${name[0].toUpperCase()}${name.substring(1)}',
            () => store.setNotebookColor(book.id, name),
            checked: book.color == name,
          ),
      ]);
    }),
    MenuLine('New section', () {
      store.noteSection = NoteSection.notebook(book.id);
      final section = store.newSection(book.id, '');
      if (section != null) editing.renameSection(section.id);
      onPicked?.call();
    }),
    const MenuLine.divider(),
    MenuLine('Delete notebook', () {
      store
        ..deleteNotebook(book.id)
        ..showToast(
          'Notebook deleted. Its notes stay. '
          '${KeyNames.of('⌘Z')} brings it back.',
        );
    }),
  ]);
}

/// "Today" and "This week": a small round button.
class NotePill extends StatelessWidget {
  const NotePill({
    super.key,
    required this.keyName,
    required this.title,
    required this.icon,
    required this.onTap,
    this.tall = false,
  });

  final String keyName;
  final String title;
  final String icon;
  final VoidCallback onTap;

  /// 44 high, for a finger.
  final bool tall;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return NoteTap(
      key: ValueKey(keyName),
      label: title,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: tall ? 44 : 0),
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
      ),
    );
  }
}
