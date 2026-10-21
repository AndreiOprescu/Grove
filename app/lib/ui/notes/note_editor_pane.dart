// Port of Sources/Grove/Notes/NoteEditorPane.swift: one note. Its title,
// its text, its tags and what links to it.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/link.dart';
import 'package:grove/core/model/note.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../editor/rich_text_field.dart';
import '../tasks/task_format.dart';
import '../tasks/task_widgets.dart';
import '../theme/grove_theme.dart';
import '../theme/panel.dart';
import '../theme/symbols.dart';
import 'day_panel.dart';

/// Give it a key with the id of the note: another note needs a new pane.
class NoteEditorPane extends StatefulWidget {
  const NoteEditorPane({
    super.key,
    required this.store,
    required this.noteId,
    this.compact = false,
    this.onBack,
  });

  final AppStore store;
  final String noteId;

  /// A narrow column (the Day Spread): a short header with the mood, no
  /// side card and a shorter text box.
  final bool compact;

  /// Shows a "back" button in front of the title (the phone).
  final VoidCallback? onBack;

  /// The text is saved this long after the last key.
  static const saveDelay = Duration(milliseconds: 500);

  /// The widest column of text, without and with a side card.
  static const textWidth = 780.0;
  static const textWidthWithSide = 720.0;

  @override
  State<NoteEditorPane> createState() => _NoteEditorPaneState();
}

class _NoteEditorPaneState extends State<NoteEditorPane> {
  // What the fields show. The store is only written when the user changes
  // something.
  final _title = TextEditingController();
  final _titleFocus = FocusNode(debugLabel: 'note title');
  String _text = '';

  /// The last title of the store that the title field got.
  String _titleSeen = '';

  /// True from the first key typed in the text until the text loses the
  /// keyboard.
  bool _typing = false;

  /// True from a key typed in the text until that text is saved. Only then
  /// has the pane a text of its own to write.
  bool _unsaved = false;
  Timer? _save;
  late final AppLifecycleListener _life;

  AppStore get _store => widget.store;
  String get _id => widget.noteId;

  @override
  void initState() {
    super.initState();
    _store.noteShown(_id);
    final n = _store.note(_id);
    _titleSeen = n?.title ?? '';
    _title.text = _titleSeen;
    _text = n?.body ?? '';
    _titleFocus.addListener(_titleFocusChanged);
    _life = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.resumed) return;
        // The app goes to the back, or it ends.
        _flush(creating: state == AppLifecycleState.detached && _typing);
      },
    );
  }

  @override
  void dispose() {
    _save?.cancel();
    _life.dispose();
    // The store must not change in the middle of a frame.
    final store = _store;
    final id = _id;
    final text = _unsaved ? _text : null;
    final title = _title.text;
    final typing = _typing;
    // After the text is written: an empty daily note goes.
    writeLater(store, () {
      _write(store, id, text: text, title: title, creating: typing);
      store.noteHidden(id);
    });
    _titleFocus
      ..removeListener(_titleFocusChanged)
      ..dispose();
    _title.dispose();
    super.dispose();
  }

  // Loading and saving

  /// Shows what the store has. Undo, a sync and a ticked task come this
  /// way. Only what the user typed and the pane did not save yet stays: the
  /// caret in a field is not a change. Without this, the pane would later
  /// write its old text over the new one.
  void _follow() {
    final n = _store.note(_id);
    if (n == null) return;
    if (!_unsaved && n.body != _text) _text = n.body;
    final renaming =
        _titleFocus.hasFocus &&
        _title.text != _titleSeen &&
        _title.text != n.title;
    if (!renaming) {
      if (n.title != _title.text) _title.text = n.title;
      _titleSeen = n.title;
    }
  }

  /// Writes any unsaved title and text of note `id` now. Then the tasks
  /// follow the boxes. `text` is null when the user typed nothing since the
  /// last save. `creating` lets open boxes make tasks. It is for the
  /// time the user is done with the text, never for text they only looked
  /// at. It adds hidden marks to the saved text.
  static void _write(
    AppStore store,
    String id, {
    required String? text,
    required String title,
    required bool creating,
  }) {
    final n = store.note(id);
    if (n == null) return;
    if (text != null && text != n.body) store.setNoteBody(id, text);
    final name = title.trim();
    if (n.kind == NoteKind.note && name.isNotEmpty && name != n.title) {
      store.renameNote(id, to: name);
    }
    store.syncNoteTasks(id, creating: creating);
  }

  void _flush({required bool creating}) {
    _save?.cancel();
    _save = null;
    final text = _unsaved ? _text : null;
    _unsaved = false;
    _write(_store, _id, text: text, title: _title.text, creating: creating);
  }

  void _textChanged(String text) {
    setState(() {
      _text = text;
      _typing = true;
      _unsaved = true;
    });
    _save?.cancel();
    _save = Timer(NoteEditorPane.saveDelay, () {
      _save = null;
      if (!mounted) return;
      _unsaved = false;
      _store.setNoteBody(_id, _text);
      // A ticked box finishes its task now. New tasks wait until the user
      // stops typing.
      _store.syncNoteTasks(_id, creating: false);
    });
  }

  void _bodyFocusChanged(bool focused) {
    if (focused || !_typing || !mounted) return;
    _flush(creating: true);
    setState(() {
      _typing = false;
      // the saved text has the ids added
      final n = _store.note(_id);
      if (n != null) _text = n.body;
    });
  }

  void _commitTitle() {
    final name = _title.text.trim();
    final n = _store.note(_id);
    if (n == null) return;
    if (name.isEmpty) {
      _title.text = n.title;
      return;
    }
    _store.renameNote(_id, to: name);
  }

  void _titleFocusChanged() {
    if (!_titleFocus.hasFocus && mounted) _commitTitle();
  }

  void _insertSummary() {
    _flush(creating: false);
    _store.insertWeekSummary(_id);
    setState(() {
      _typing = false;
      final n = _store.note(_id);
      if (n != null) _text = n.body;
    });
  }

  // Content

  @override
  Widget build(BuildContext context) => StoreBuilder(
    store: _store,
    onChange: _follow,
    builder: (context) {
      final theme = GroveTheme.of(context);
      final note = _store.note(_id);
      return Panel(
        child: note == null
            ? Center(
                child: Text(
                  'This note is gone.',
                  style: theme.body(13).copyWith(color: theme.muted),
                ),
              )
            : LayoutBuilder(
                builder: (context, box) => _content(theme, note, box.maxWidth),
              ),
      );
    },
  );

  Widget _content(GroveTheme theme, Note note, double width) {
    if (widget.compact) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: _editorColumn(theme, note, narrow: true),
      );
    }
    final side = _sidePanel(note);
    final narrow = width < 560;
    final pad = narrow ? 14.0 : 28.0;
    final free = width - 2 * pad;
    // The side card stands beside the text when both have room.
    final beside = side != null && free >= 320 + 20 + SideCard.width;
    final most = beside
        ? NoteEditorPane.textWidthWithSide + 20 + SideCard.width
        : NoteEditorPane.textWidth;
    final used = (free < most ? free : most).floorToDouble();
    final left = pad + ((free - used) / 2).floorToDouble();
    final column = _editorColumn(theme, note, narrow: narrow);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(left, narrow ? 14 : 22, 0, narrow ? 14 : 22),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: used,
          child: side == null
              ? column
              : beside
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 20,
                  children: [
                    Expanded(child: column),
                    SizedBox(width: SideCard.width, child: side),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 14,
                  children: [column, side],
                ),
        ),
      ),
    );
  }

  Widget _editorColumn(GroveTheme theme, Note note, {required bool narrow}) {
    final day = note.date;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 14,
      children: [
        if (widget.compact)
          _compactHeader(theme, note)
        else
          _header(theme, note, narrow: narrow),
        ..._tagRow(theme, note),
        RichTextField(
          key: const ValueKey('note-text'),
          text: _text,
          services: _services,
          placeholder:
              'Write something. Type [[ to link a task, note or event.',
          minHeight: widget.compact ? 200 : 320,
          onChanged: _textChanged,
          onFocusChange: _bodyFocusChanged,
        ),
        if (note.kind == NoteKind.daily && day != null)
          DoneLog(store: _store, day: day),
        ..._linked(theme),
      ],
    );
  }

  late final EditorServices _services = _store.editorServices(
    excluding: ItemRef(ItemType.note, _id),
    noteId: _id,
  );

  /// The card beside a daily note (its day) or a weekly note (its week).
  Widget? _sidePanel(Note note) {
    final date = note.date;
    if (date == null) return null;
    return switch (note.kind) {
      NoteKind.daily => DayPanel(store: _store, day: date),
      NoteKind.weekly => WeekReviewPanel(
        store: _store,
        monday: date,
        hasSummary: DayRules.hasSummary(_text),
        onInsert: _insertSummary,
      ),
      NoteKind.note => null,
    };
  }

  // Header

  Widget _pin(GroveTheme theme, Note note) => IconTap(
    key: const ValueKey('note-pin'),
    icon: symbolIcon(note.pinned ? 'pin.fill' : 'pin'),
    label: note.pinned ? 'Unpin note' : 'Pin note',
    tip: note.pinned ? 'Unpin' : 'Pin to the top of the list',
    color: note.pinned ? theme.accent2 : theme.muted,
    onTap: () => _store.togglePin(note.id),
  );

  static bool get _apple =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Widget _menu(GroveTheme theme, Note note) => Builder(
    builder: (context) => IconTap(
      key: const ValueKey('note-menu'),
      icon: symbolIcon('ellipsis.circle'),
      label: 'More for this note',
      color: theme.muted,
      onTap: () {
        final box = context.findRenderObject()! as RenderBox;
        showGroveMenu(context, box.localToGlobal(Offset(0, box.size.height)), [
          MenuLine('Duplicate', () => _store.duplicateNote(note.id)),
          MenuLine('Delete note', () {
            _store
              ..deleteNote(note.id)
              ..showToast(
                'Note deleted. ${_apple ? '⌘Z' : 'Ctrl+Z'} brings it back.',
              );
          }),
        ]);
      },
    ),
  );

  String _kindLine(Note note) {
    final at = note.updatedAt;
    final day = at.length >= 10 ? DayKey(at.substring(0, 10)) : null;
    final clock = at.length >= 16 ? at.substring(11, 16) : '';
    final edited = day == null
        ? 'Edited'
        : 'Edited ${TaskFormat.dayLabel(day, today: _store.clockToday)}'
              '${clock.isEmpty ? '' : ', $clock'}';
    return switch (note.kind) {
      NoteKind.daily => 'Daily note · $edited',
      NoteKind.weekly => 'Weekly note · $edited',
      NoteKind.note => edited,
    };
  }

  Widget _header(GroveTheme theme, Note note, {required bool narrow}) {
    final back = widget.onBack;
    final size = narrow ? 22.0 : 28.0;
    final mood = note.kind == NoteKind.daily
        ? MoodPicker(store: _store, note: note)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: [
        Row(
          spacing: 6,
          children: [
            if (back != null)
              IconTap(
                key: const ValueKey('note-back'),
                icon: symbolIcon('chevron.left'),
                label: 'Back to the notes',
                size: 20,
                color: theme.accent,
                onTap: back,
              ),
            Expanded(
              child: note.kind == NoteKind.note
                  ? GroveField(
                      key: const ValueKey('note-title'),
                      controller: _title,
                      focusNode: _titleFocus,
                      placeholder: 'Title',
                      padding: EdgeInsets.zero,
                      style: theme.heading(size).copyWith(color: theme.ink),
                      onSubmitted: (_) => _commitTitle(),
                    )
                  : ThemedHeading(note.title, size),
            ),
            if (mood != null && !narrow) mood,
            _pin(theme, note),
            _menu(theme, note),
          ],
        ),
        if (mood != null && narrow)
          Align(alignment: Alignment.centerLeft, child: mood),
        Text(
          _kindLine(note),
          key: const ValueKey('note-kind-line'),
          style: theme.body(12).copyWith(color: theme.muted),
        ),
      ],
    );
  }

  /// "Today's note", the pin and the button to the Notes screen, then the
  /// mood.
  Widget _compactHeader(GroveTheme theme, Note note) {
    final today = _store.clockToday;
    final day = note.date ?? today;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Row(
          spacing: 6,
          children: [
            Expanded(
              child: ThemedHeading(
                day == today
                    ? "Today's note"
                    : 'Note · ${TaskFormat.dayLabel(day, today: today)}',
                20,
              ),
            ),
            _pin(theme, note),
            IconTap(
              key: const ValueKey('note-open'),
              icon: symbolIcon('arrow.up.left.and.arrow.down.right'),
              label: 'Open in the Notes screen',
              color: theme.muted,
              onTap: () => _store.openNote(note.id),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: MoodPicker(store: _store, note: note),
        ),
      ],
    );
  }

  List<Widget> _tagRow(GroveTheme theme, Note note) {
    final tags = _store.noteTags(note.id);
    if (tags.isEmpty) return const [];
    return [
      Wrap(
        spacing: 5,
        runSpacing: 5,
        children: [
          for (final tag in tags)
            NoteTap(
              key: ValueKey('note-tag-$tag'),
              label: '#$tag',
              tip: 'Show notes with this tag',
              onTap: () => _store.noteFilter = NoteFilter.tag(tag),
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: theme.surface2,
                  shape: const StadiumBorder(),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  child: Text(
                    '#$tag',
                    maxLines: 1,
                    style: theme.body(11).copyWith(color: theme.muted),
                  ),
                ),
              ),
            ),
        ],
      ),
    ];
  }

  static String _icon(ItemType type) => switch (type) {
    ItemType.task => 'checkmark.circle',
    ItemType.note => 'note.text',
    ItemType.event => 'calendar',
  };

  List<Widget> _linked(GroveTheme theme) {
    final items = _store.linkedItems(ItemRef(ItemType.note, _id));
    if (items.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            const ThemedHeading('Linked here', 12, weight: FontWeight.w700),
            for (final item in items)
              NoteTap(
                key: ValueKey('note-linked-${item.id}'),
                label: item.title,
                onTap: () => _store.open(item.ref),
                child: Row(
                  spacing: 8,
                  children: [
                    Icon(
                      symbolIcon(_icon(item.ref.type)),
                      size: 14,
                      color: theme.accent,
                    ),
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.body(12).copyWith(color: theme.ink),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }
}
