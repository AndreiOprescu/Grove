// Port of the text rules of Sources/Grove/Editor/RichTextEditor.swift (its
// Coordinator) and of MarkdownStyler.swift. The stored text stays plain
// Markdown. Only its look changes. The rules of the text are in
// `core/parsing/` (`MarkdownSpans`, `MarkdownEdit`).
import 'package:flutter/material.dart';
import 'package:grove/core/parsing/at_date.dart';
import 'package:grove/core/parsing/edit_history.dart';
import 'package:grove/core/parsing/markdown_edit.dart';
import 'package:grove/core/parsing/markdown_spans.dart';
import 'package:grove/core/parsing/note_parser.dart';
import 'package:grove/core/parsing/reference_parser.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../theme/grove_theme.dart';
import '../theme/named_colors.dart';
import '../theme/theme_math.dart';

/// What a key shortcut or a button asks the editor to do to the text.
enum EditorFormat {
  bold,
  italic,
  code,
  bullet,
  numbered,
  checklist,
  heading,
  quote,
}

/// A picture the user gave to the editor, before it is stored. `image` is
/// null when the data is not a picture Grove can read.
typedef PickedImage = ({String name, ImageToStore? image});

/// The formats at the selection, so the buttons of the toolbar can light up.
class ActiveFormats {
  const ActiveFormats({
    this.inline = const {},
    this.heading = 0,
    this.highlight,
    this.line,
    this.link = false,
  });

  /// Bold, italic, underline, strike, highlight and code.
  final Set<InlineFormat> inline;

  /// 1 Big, 2 Medium, 3 Small (a `####` line is Small too); 0 for normal text.
  final int heading;

  /// The colour of the highlight, when [inline] has one.
  final HighlightColor? highlight;

  /// The list or quote of the line. Null for a plain line or a heading.
  final PrefixKind? line;

  /// The selection is in the words of a link.
  final bool link;

  bool has(InlineFormat format) => inline.contains(format);
}

/// The open `[[` list: the rows, and the row that Return takes.
class MentionList {
  const MentionList({
    required this.location,
    required this.query,
    required this.items,
    required this.selected,
  });

  /// Where the `[[` starts in the text.
  final int location;
  final String query;
  final List<MentionSuggestion> items;
  final int selected;

  MentionSuggestion? get current =>
      selected >= 0 && selected < items.length ? items[selected] : null;
}

/// Fonts and colours of the editor text.
class EditorStyle {
  EditorStyle(this.theme, {this.size = 13});

  final GroveTheme theme;
  final double size;

  /// Vintage: every line of text is 28 pt high and sits on a ruled line.
  bool get ruled => theme.ruledLines;

  static const headingScale = [1.55, 1.3, 1.15, 1.05, 1.0, 1.0];

  /// The height of a line with letters of `fontSize` points: 1.28 times
  /// the letters, as on the Mac, on a whole point. A ruled page has one line
  /// every 28 points.
  double line(double fontSize) =>
      ruled ? GridMath.ruledPitch : (fontSize * 1.28).roundToDouble();

  TextStyle get base => theme
      .body(size)
      .copyWith(color: theme.ink, height: line(size) / size, letterSpacing: 0);

  /// A ruled page forces each line to its 28 points. Other pages let a
  /// heading have a taller line.
  StrutStyle get strut => ruled
      ? StrutStyle(
          fontSize: size,
          height: GridMath.ruledPitch / size,
          forceStrutHeight: true,
        )
      : StrutStyle.disabled;

  /// Text that is in the file and that the user does not see. It has no
  /// width that the eye can see, and no colour.
  static const hidden = TextStyle(
    fontSize: 0.01,
    color: Color(0x00000000),
    decoration: TextDecoration.none,
    letterSpacing: 0,
  );
}

/// The text of a Markdown editor. It shows bold, lists, headings, mentions
/// and image names as they should look. It keeps a mention as one unit and
/// goes on with a list at Return.
class MarkdownController extends TextEditingController {
  MarkdownController({
    super.text,
    EditorServices? services,
    EditHistory? history,
  }) : services = services ?? EditorServices(),
       _history = history ?? EditHistory() {
    _spans = MarkdownSpans.scan(text);
    _rememberMarks(text);
  }

  EditorServices services;

  /// Set by the editor widget. The text is plain until then.
  EditorStyle? style;

  /// True while the text has the keyboard. The `[[` list shows only then.
  bool focused = true;

  /// The image shown large, if any.
  final previewImage = ValueNotifier<String?>(null);

  /// The open `[[` list. Null when it is closed.
  final mentions = ValueNotifier<MentionList?>(null);

  List<MarkdownSpan> _spans = const [];
  final Map<String, bool> _live = {};

  /// Where the user pressed Esc on a list, so it stays closed until they
  /// leave that `[[`.
  int? _dismissedAt;
  bool _applying = false;

  /// True: the marks show dim, as they are typed. False: they are hidden
  /// and the caret steps over them. The field sets it from
  /// [EditorServices.showMarks] at each build.
  bool get showMarks => _showMarks;
  set showMarks(bool value) {
    if (value == _showMarks) return;
    _showMarks = value;
    _pending = null;
    _runs = null;
  }

  bool _showMarks = false;

  /// The hidden marks, merged where they touch. Cached until the text
  /// changes.
  List<Utf16Range>? _runs;

  /// The empty pair that a format button put in at the caret, while the
  /// caret is still inside it. `**` and ``` `` ``` do not read as a format,
  /// so the editor keeps it here to hide it.
  ({Utf16Range whole, int middle})? _pending;

  /// The person turned a format off at the caret, so the next letter at the
  /// end of the line must not pull the marks forward again.
  bool _noPull = false;

  /// Spans of the whole text.
  List<MarkdownSpan> get spans => _spans;

  Utf16Range get _selection {
    final s = value.selection;
    if (!s.isValid) return Utf16Range(text.length, 0);
    return Utf16Range(s.start, s.end - s.start);
  }

  @override
  void dispose() {
    previewImage.dispose();
    mentions.dispose();
    undoState.dispose();
    super.dispose();
  }

  // Undo and redo

  final EditHistory _history;

  /// True while a change is being kept as one step, so the changes inside
  /// it are not kept again.
  bool _recording = false;

  /// The text before a word that the keyboard of a phone is still making.
  EditSnapshot? _composeFrom;

  /// Each task mark seen since the last [load], with its line. An undo or a
  /// redo puts a lost mark back (see [MarkdownEdit.keepingTaskMarks]).
  final Map<String, String> _marks = {};

  /// Whether undo and redo can do something now. For the buttons.
  final undoState = ValueNotifier<({bool canUndo, bool canRedo})>((
    canUndo: false,
    canRedo: false,
  ));

  bool get canUndo => _history.canUndo;
  bool get canRedo => _history.canRedo;

  /// Takes back the last change of the text in this box.
  void undo() => _travel(back: true);

  /// Does again the change that undo took back.
  void redo() => _travel(back: false);

  EditSnapshot get _snapshot => EditSnapshot(text, _selection);

  void _historyChanged() =>
      undoState.value = (canUndo: _history.canUndo, canRedo: _history.canRedo);

  /// Runs `change` and keeps it as one step of the history.
  void _recorded(void Function() change, {bool typing = false}) {
    if (_recording) {
      change();
      return;
    }
    final before = _snapshot;
    final pair = _pending;
    _recording = true;
    try {
      change();
    } finally {
      _recording = false;
    }
    _keep(before, pair, typing: typing);
  }

  /// Keeps the change from `before` to now. `pair` is the empty pair that
  /// was there before: when the change only took it away, the step that put
  /// it in is changed instead, so undo does not bring back a pair that does
  /// not show.
  void _keep(
    EditSnapshot before,
    ({Utf16Range whole, int middle})? pair, {
    bool typing = false,
  }) {
    final after = _snapshot;
    if (after.text == before.text) return;
    if (pair != null &&
        pair.whole.end <= before.text.length &&
        after.text ==
            before.text.replaceRange(pair.whole.location, pair.whole.end, '')) {
      _history.amendLast(before, after);
    } else {
      _history.record(before, after, typing: typing);
    }
    _historyChanged();
  }

  /// A letter typed, or one taken away, at a caret. Typing joins into one
  /// step; a Return, a paste or a change of a selection is a step of its
  /// own.
  static bool _isTyping(TextEditingValue old, TextEditingValue next) {
    final s = old.selection;
    if (!s.isValid || !s.isCollapsed) return false;
    final grew = next.text.length - old.text.length;
    if (grew > 0) {
      final put = next.text.substring(s.start, s.start + grew);
      return s.start + grew <= next.text.length &&
          put.runes.length == 1 &&
          put != '\n' &&
          next.text == old.text.replaceRange(s.start, s.start, put);
    }
    return grew < 0 && grew >= -2;
  }

  void _travel({required bool back}) {
    _composeFrom = null;
    while (true) {
      final target = back ? _history.undo() : _history.redo();
      if (target == null) break;
      final text = _withMarks(target.text);
      // A step that changes nothing that shows, such as a task mark that
      // stays, is passed over.
      if (text == this.text) continue;
      _restore(text, text == target.text ? target.selection : null);
      // Redo the steps that the marks already did.
      while (!back) {
        final next = _history.nextRedo;
        if (next == null || _withMarks(next.text) != this.text) break;
        _history.redo();
      }
      break;
    }
    _historyChanged();
  }

  String _withMarks(String target) => MarkdownEdit.keepingTaskMarks(
    [text, ..._marks.values].join('\n'),
    target,
  );

  void _restore(String text, Utf16Range? selection) {
    _pending = null;
    _noPull = false;
    final at = selection ?? Utf16Range(_selection.location, 0);
    final start = at.location.clamp(0, text.length);
    final end = at.end.clamp(0, text.length);
    _applying = true;
    try {
      _set(
        TextEditingValue(
          text: text,
          selection: TextSelection(baseOffset: start, extentOffset: end),
        ),
      );
    } finally {
      _applying = false;
    }
  }

  void _rememberMarks(String text) {
    if (!text.contains('⟦t:')) return;
    final lines = text.split('\n');
    for (final box in NoteParser.checkboxes(text)) {
      final id = box.taskId;
      if (id != null) _marks[id] = lines[box.line];
    }
  }

  // Text changes

  @override
  set value(TextEditingValue next) {
    if (_applying || _recording) {
      _change(next);
      return;
    }
    // A word that the keyboard of a phone is still making is kept as one
    // step when it is done.
    if (next.composing.isValid) {
      _composeFrom ??= _snapshot;
      _change(next);
      return;
    }
    final old = value;
    final from = _composeFrom;
    _composeFrom = null;
    final before = from ?? _snapshot;
    final pair = _pending;
    _recording = true;
    try {
      _change(next);
    } finally {
      _recording = false;
    }
    if (from == null && next.text == old.text) {
      // The caret moved: the next letters are a new step.
      if (next.selection != old.selection) _history.breakGroup();
    }
    _keep(before, pair, typing: from != null || _isTyping(old, next));
  }

  void _change(TextEditingValue next) {
    final old = value;
    // A word that the keyboard of a phone has not done yet is left as it
    // is. The rules run again with the key that ends the word: a Return at
    // the end of a word comes that way.
    if (_applying || next.composing.isValid) {
      _set(next);
      return;
    }
    if (next.text == old.text) {
      if (next.selection != old.selection) _noPull = false;
      final snapped = _snap(old, next);
      if (!_leavePair(snapped)) _set(snapped);
      return;
    }
    final change = _difference(old, next);
    if (!_showMarks) {
      if (_pending != null && _intoPair(old, change)) return;
      _pending = null;
      final rule = _hiddenRule(old, change);
      if (rule != null) {
        apply(rule, from: old.text);
        return;
      }
    }
    // A key that would delete a hidden task mark deletes the visible
    // character next to it.
    final beside = MarkdownSpans.deletionBesideMark(
      change.range,
      replacement: change.replacement,
      spans: _spans,
      text: old.text,
    );
    if (beside is MarkRedirect) {
      final other = beside.range;
      final caret = other.location < change.range.location
          ? other.location
          : change.range.location;
      _edit(old.text, other, '', caret);
      return;
    }
    if (beside != MarkDeletion.unchanged) {
      // The key did nothing. Say so, or the keyboard of a phone and the
      // field do not agree on the text.
      notifyListeners();
      return;
    }
    // A mention or an image is one unit. A change that touches a part of it
    // takes all of it.
    final whole = MarkdownSpans.expanded(change.range, _spans);
    if (whole != change.range) {
      _edit(
        old.text,
        whole,
        change.replacement,
        whole.location + change.replacement.length,
      );
      return;
    }
    // Return takes the chosen row of the `[[` list. With no list it goes on
    // with a list of the text, or ends it.
    final oldSelection = old.selection;
    if (change.replacement == '\n' &&
        change.range.length == 0 &&
        oldSelection.isValid &&
        oldSelection.isCollapsed) {
      if (acceptCurrent()) return;
      final edit = MarkdownEdit.enter(
        old.text,
        Utf16Range(oldSelection.start, 0),
      );
      if (edit != null) {
        apply(edit, from: old.text);
        return;
      }
    }
    _set(next);
  }

  void _set(TextEditingValue next) {
    final textChanged = next.text != value.text;
    if (textChanged) {
      _spans = MarkdownSpans.scan(next.text);
      _runs = null;
      _rememberMarks(next.text);
    }
    super.value = next;
    _updateMentions();
  }

  void _edit(String from, Utf16Range range, String replacement, int caret) {
    final text = from.replaceRange(range.location, range.end, replacement);
    _set(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: caret),
      ),
    );
  }

  /// Moves a caret out of the middle of a mention.
  TextEditingValue _snap(TextEditingValue old, TextEditingValue next) {
    final s = next.selection;
    if (!s.isValid || s == old.selection) return next;
    final forward = !old.selection.isValid || s.start >= old.selection.start;
    final snapped = MarkdownSpans.snapped(
      Utf16Range(s.start, s.end - s.start),
      _spans,
      movingForward: forward,
    );
    var out = next;
    if (snapped.location != s.start || snapped.end != s.end) {
      final reversed = s.baseOffset > s.extentOffset;
      out = next.copyWith(
        selection: TextSelection(
          baseOffset: reversed ? snapped.end : snapped.location,
          extentOffset: reversed ? snapped.location : snapped.end,
        ),
      );
    }
    // A caret in hidden marks rests at one place, so the next letter always
    // gets the same format.
    final caret = out.selection;
    if (_showMarks || !caret.isCollapsed) return out;
    final at = canonical(caret.baseOffset);
    if (at == caret.baseOffset) return out;
    return out.copyWith(
      selection: TextSelection.collapsed(offset: at, affinity: caret.affinity),
    );
  }

  // Hidden marks

  /// The marks that do not show, as ranges of the text. Empty while "Show
  /// marks" is on. A divider hides two of its three letters; the third is
  /// drawn as the line.
  List<Utf16Range> get hiddenRuns => _runs ??= _hiddenRuns();

  List<Utf16Range> _hiddenRuns() {
    if (_showMarks) return const [];
    final ranges = <Utf16Range>[
      for (final s in _spans)
        if (s.kind.type == SpanType.syntax ||
            s.kind.type == SpanType.headingMark)
          s.range
        else if (s.kind.type == SpanType.divider)
          Utf16Range(s.range.location, 2),
      if (_pending case final p?) p.whole,
    ]..sort((a, b) => a.location.compareTo(b.location));
    final runs = <Utf16Range>[];
    for (final r in ranges) {
      if (runs.isNotEmpty && r.location <= runs.last.end) {
        final last = runs.removeLast();
        final end = r.end > last.end ? r.end : last.end;
        runs.add(Utf16Range(last.location, end - last.location));
      } else {
        runs.add(r);
      }
    }
    return runs;
  }

  /// How many letters that show come before `offset`. A divider counts as
  /// one.
  int visibleIndex(int offset) {
    var hidden = 0;
    for (final r in hiddenRuns) {
      if (r.location >= offset) break;
      hidden += (offset < r.end ? offset : r.end) - r.location;
    }
    return offset - hidden;
  }

  /// The one place where a caret in a run of hidden marks rests: the start
  /// of the run, which is outside the start of a format and inside its end.
  /// Two places differ: at the start of a heading line it rests after the
  /// heading mark, and at the end of a link it rests outside the link. In
  /// an empty pair it rests in the middle. Before or in the mark of a list,
  /// a check box or a quote it rests after the mark.
  int canonical(int offset) {
    if (_lineMarkAt(offset) case final mark?) offset = mark.end;
    for (final r in hiddenRuns) {
      if (offset < r.location) break;
      if (offset > r.end) continue;
      if (_pending case final p? when p.middle == offset) return offset;
      for (final s in _spans) {
        if (s.range.location > r.end) break;
        if (s.kind.type == SpanType.headingMark &&
            s.range.location >= r.location &&
            s.range.end <= r.end) {
          return s.range.end;
        }
        if (s.kind.type == SpanType.linkWords) {
          final close = _linkClose(s);
          if (close != null &&
              close.location >= r.location &&
              close.end <= r.end) {
            return close.end;
          }
        }
      }
      return r.location;
    }
    return offset;
  }

  /// The drawn mark at the start of a line (bullet, number, check box or
  /// quote bar, with its indent and space) when `offset` is in it or just
  /// before it. Null while "Show marks" is on: then each letter is a place.
  Utf16Range? _lineMarkAt(int offset) {
    if (_showMarks) return null;
    for (final s in _spans) {
      final type = s.kind.type;
      if ((type == SpanType.listPrefix || type == SpanType.quoteMark) &&
          s.range.location <= offset &&
          offset < s.range.end) {
        return s.range;
      }
    }
    return null;
  }

  Utf16Range? _linkClose(MarkdownSpan words) {
    for (final m in _spans) {
      if (m.kind.type == SpanType.syntax &&
          m.range.location == words.range.end) {
        return m.range;
      }
    }
    return null;
  }

  /// True when some places of the text are no caret stops: hidden marks,
  /// or the drawn mark at the start of a list, check box or quote line.
  bool get hasSkippedPlaces =>
      !_showMarks &&
      (hiddenRuns.isNotEmpty ||
          _spans.any(
            (s) =>
                s.kind.type == SpanType.listPrefix ||
                s.kind.type == SpanType.quoteMark,
          ));

  /// One arrow key: the selection after a step of one letter that shows.
  /// Hidden marks are stepped over. Without Shift (`collapse`) a selection
  /// goes to its edge; with Shift only its extent moves.
  TextSelection moveByCharacter(
    TextSelection selection, {
    required bool forward,
    required bool collapse,
  }) {
    if (collapse && !selection.isCollapsed) {
      final edge = forward ? selection.end : selection.start;
      return TextSelection.collapsed(offset: canonical(edge));
    }
    final to = canonical(_step(selection.extentOffset, forward));
    if (collapse) return TextSelection.collapsed(offset: to);
    return TextSelection(baseOffset: selection.baseOffset, extentOffset: to);
  }

  /// The nearest place past one more (or one less) letter that shows.
  /// `from` when there is none. A line mark is no place: a step back from
  /// after it goes to the end of the line before.
  int _step(int from, bool forward) {
    final to = _letterStep(from, forward);
    final mark = _lineMarkAt(to);
    if (mark == null) return to;
    if (forward) return mark.end;
    return mark.location > 0 ? mark.location - 1 : from;
  }

  int _letterStep(int from, bool forward) {
    final text = this.text;
    final v = visibleIndex(from);
    bool splitsPair(int q) =>
        q > 0 &&
        q < text.length &&
        (text.codeUnitAt(q - 1) & 0xFC00) == 0xD800 &&
        (text.codeUnitAt(q) & 0xFC00) == 0xDC00;
    if (forward) {
      for (var q = from + 1; q <= text.length; q++) {
        if (visibleIndex(q) > v && !splitsPair(q)) return q;
      }
    } else {
      for (var q = from - 1; q >= 0; q--) {
        if (visibleIndex(q) < v && !splitsPair(q)) return q;
      }
    }
    return from;
  }

  /// Takes away the empty pair when the caret left it. True when it did.
  bool _leavePair(TextEditingValue next) {
    final p = _pending;
    if (p == null) return false;
    final s = next.selection;
    if (s.isValid && s.isCollapsed && s.baseOffset == p.middle) return false;
    _pending = null;
    _runs = null;
    final whole = p.whole;
    int moved(int o) => o <= whole.location
        ? o
        : o >= whole.end
        ? o - whole.length
        : whole.location;
    final text = next.text.replaceRange(whole.location, whole.end, '');
    _set(
      TextEditingValue(
        text: text,
        selection: s.isValid
            ? TextSelection(
                baseOffset: moved(s.baseOffset),
                extentOffset: moved(s.extentOffset),
              )
            : s,
      ),
    );
    final caret = selection;
    if (caret.isValid && caret.isCollapsed) {
      final at = canonical(caret.baseOffset);
      if (at != caret.baseOffset) {
        super.value = value.copyWith(
          selection: TextSelection.collapsed(offset: at),
        );
      }
    }
    return true;
  }

  /// A key in the empty pair. A letter fills it; a space goes before it;
  /// Backspace, Delete and Return take it away first. True when the key was
  /// used here.
  bool _intoPair(
    TextEditingValue old,
    ({Utf16Range range, String replacement}) change,
  ) {
    final p = _pending!;
    final whole = p.whole;
    final caret = old.selection;
    if (!caret.isValid || !caret.isCollapsed || caret.baseOffset != p.middle) {
      return false;
    }
    final r = change.range;
    final typed = change.replacement;
    final withoutPair = old.text.replaceRange(whole.location, whole.end, '');
    if (typed.isEmpty && (r.end == p.middle || r.location == p.middle)) {
      _pending = null;
      _edit(old.text, whole, '', whole.location);
      return true;
    }
    if (r.length != 0 || r.location != p.middle) return false;
    if (typed.contains('\n')) {
      _pending = null;
      _edit(old.text, whole, '', whole.location);
      value = TextEditingValue(
        text: withoutPair.replaceRange(whole.location, whole.location, typed),
        selection: TextSelection.collapsed(
          offset: whole.location + typed.length,
        ),
      );
      return true;
    }
    if (typed.trim().isEmpty) {
      _pending = (
        whole: Utf16Range(whole.location + typed.length, whole.length),
        middle: p.middle + typed.length,
      );
      _edit(
        old.text,
        Utf16Range(whole.location, 0),
        typed,
        p.middle + typed.length,
      );
      return true;
    }
    // A letter fills the pair, which then reads as a format.
    _pending = null;
    _runs = null;
    return false;
  }

  /// What a key does beside hidden marks, or null for the plain change.
  TextEdit? _hiddenRule(
    TextEditingValue old,
    ({Utf16Range range, String replacement}) change,
  ) {
    final s = old.selection;
    if (!s.isValid) return null;
    final selection = Utf16Range(s.start, s.end - s.start);
    final divider = _dividerRule(old.text, change);
    if (divider != null) return divider;
    if (change.replacement.isEmpty && change.range.length > 0) {
      return MarkdownEdit.deletion(
        old.text,
        change.range,
        selection: selection,
      );
    }
    if (change.range.length == 0 &&
        selection.length == 0 &&
        selection.location == change.range.location &&
        !change.replacement.contains('\n')) {
      return MarkdownEdit.typed(
        old.text,
        selection,
        change.replacement,
        pull: !_noPull,
      );
    }
    return null;
  }

  /// A divider is one unit. A key that takes a part of it, or the line
  /// break beside it, takes all of it. Letters typed beside it go on a line
  /// of their own.
  TextEdit? _dividerRule(
    String text,
    ({Utf16Range range, String replacement}) change,
  ) {
    final r = change.range;
    final typed = change.replacement;
    for (final s in _spans) {
      if (s.kind.type != SpanType.divider) continue;
      final d = s.range;
      if (typed.isEmpty && r.length > 0) {
        if (r.location < d.end &&
            d.location < r.end &&
            (r.location > d.location || r.end < d.end)) {
          final from = r.location < d.location ? r.location : d.location;
          final to = r.end > d.end ? r.end : d.end;
          return TextEdit(
            range: Utf16Range(from, to - from),
            replacement: '',
            selection: Utf16Range(from, 0),
          );
        }
        if (r.length == 1 && r.location == d.end && d.end < text.length) {
          return TextEdit(
            range: Utf16Range(d.location, d.length + 1),
            replacement: '',
            selection: Utf16Range(d.location, 0),
          );
        }
        if (r.length == 1 && r.end == d.location && d.location > 0) {
          return TextEdit(
            range: Utf16Range(r.location, d.length + 1),
            replacement: '',
            selection: Utf16Range(r.location, 0),
          );
        }
        continue;
      }
      if (r.length != 0 || typed.isEmpty || typed.contains('\n')) continue;
      if (r.location == d.end) {
        return TextEdit(
          range: r,
          replacement: '\n$typed',
          selection: Utf16Range(r.location + 1 + typed.length, 0),
        );
      }
      if (r.location == d.location) {
        return TextEdit(
          range: r,
          replacement: '$typed\n',
          selection: Utf16Range(r.location + typed.length, 0),
        );
      }
      if (d.location < r.location && r.location < d.end) {
        return TextEdit(
          range: Utf16Range(d.end, 0),
          replacement: '\n$typed',
          selection: Utf16Range(d.end + 1 + typed.length, 0),
        );
      }
    }
    return null;
  }

  /// The one change that turns the text of `from` into the text of `to`:
  /// the range that goes, and the text that comes.
  ///
  /// When the letter that comes or goes is the same as the one next to it,
  /// the two texts alone do not say where the change was: `a|[[x]]` with a
  /// `[` typed at the caret gives the same text as a `[` typed inside the
  /// mention. The caret says where it was.
  static ({Utf16Range range, String replacement}) _difference(
    TextEditingValue from,
    TextEditingValue to,
  ) {
    final a = from.text;
    final b = to.text;
    final most = a.length < b.length ? a.length : b.length;
    var head = 0;
    while (head < most && a.codeUnitAt(head) == b.codeUnitAt(head)) {
      head += 1;
    }
    int tailAfter(int head) {
      var tail = 0;
      while (tail < most - head &&
          a.codeUnitAt(a.length - 1 - tail) ==
              b.codeUnitAt(b.length - 1 - tail)) {
        tail += 1;
      }
      return tail;
    }

    var tail = tailAfter(head);
    final was = from.selection;
    final now = to.selection;
    if (was.isValid && now.isValid) {
      final caret = was.start < now.start ? was.start : now.start;
      if (caret >= 0 && caret < head) {
        // Only when it is the same change, read at another place.
        final other = tailAfter(caret);
        if (other - tail == head - caret) {
          head = caret;
          tail = other;
        }
      }
    }
    return (
      range: Utf16Range(head, a.length - tail - head),
      replacement: b.substring(head, b.length - tail),
    );
  }

  /// Writes an edit of the text rules. Null does nothing.
  void apply(TextEdit? edit, {String? from}) {
    if (edit == null) return;
    final source = from ?? text;
    final next = source.replaceRange(
      edit.range.location,
      edit.range.end,
      edit.replacement,
    );
    final start = edit.selection.location.clamp(0, next.length);
    final end = edit.selection.end.clamp(0, next.length);
    _recorded(() {
      _applying = true;
      try {
        _set(
          TextEditingValue(
            text: next,
            selection: TextSelection(baseOffset: start, extentOffset: end),
          ),
        );
      } finally {
        _applying = false;
      }
    });
  }

  /// The selected words as Markdown, for a copy that keeps the format.
  /// Without the hidden task marks.
  String get selectedMarkdown => MarkdownSlice.of(text, _selection);

  /// Puts `text` in place of the selection, as one step of the history,
  /// with the caret after it. While the marks are hidden the selection goes
  /// by the delete rules first, so the marks stay in pairs. A paste and a
  /// cut (with no text) come here.
  void replaceSelection(String text) {
    final s = _selection;
    var source = this.text;
    var at = s.location;
    if (s.length > 0) {
      final cut =
          (_showMarks
              ? null
              : MarkdownEdit.deletion(source, s, selection: s)) ??
          TextEdit(
            range: s,
            replacement: '',
            selection: Utf16Range(s.location, 0),
          );
      source = source.replaceRange(
        cut.range.location,
        cut.range.end,
        cut.replacement,
      );
      at = cut.selection.location;
    }
    apply(
      TextEdit(
        range: Utf16Range(at, 0),
        replacement: text,
        selection: Utf16Range(at + text.length, 0),
      ),
      from: source,
    );
  }

  /// New text from outside: another note was opened, or an undo of the
  /// app. The history of the box starts again.
  void load(String text) {
    if (text == this.text) return;
    _history.clear();
    _marks.clear();
    _composeFrom = null;
    _historyChanged();
    final caret = _selection.location.clamp(0, text.length);
    _applying = true;
    try {
      _set(
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: caret),
        ),
      );
    } finally {
      _applying = false;
    }
  }

  /// Asks again which mentions point at something that is still there.
  void refresh() {
    _live.clear();
    notifyListeners();
  }

  /// The same, without a word to the listeners. For a build that draws the
  /// text again by itself.
  void forgetLive() => _live.clear();

  /// The ids of the images in the text, in order.
  List<String> get imageIds => ReferenceParser.imageIds(text);

  /// Takes an image out of the text.
  void removeImage(String id) {
    final next = MarkdownEdit.removeImage(id, text);
    if (next == text) return;
    final caret = _selection.location.clamp(0, next.length);
    _recorded(() {
      _applying = true;
      try {
        _set(
          TextEditingValue(
            text: next,
            selection: TextSelection.collapsed(offset: caret),
          ),
        );
      } finally {
        _applying = false;
      }
    });
  }

  // Buttons and keys

  void format(EditorFormat f) {
    final sel = _selection;
    switch (f) {
      case EditorFormat.bold:
        toggleInline(InlineFormat.bold);
      case EditorFormat.italic:
        toggleInline(InlineFormat.italic);
      case EditorFormat.code:
        toggleInline(InlineFormat.code);
      case EditorFormat.bullet:
        apply(MarkdownEdit.toggleLine(LineStyle.bullet, text, sel));
      case EditorFormat.numbered:
        apply(MarkdownEdit.toggleLine(LineStyle.numbered, text, sel));
      case EditorFormat.checklist:
        apply(MarkdownEdit.toggleLine(LineStyle.checklist, text, sel));
      case EditorFormat.heading:
        apply(MarkdownEdit.toggleLine(const LineStyle.heading(2), text, sel));
      case EditorFormat.quote:
        apply(MarkdownEdit.toggleLine(LineStyle.quote, text, sel));
    }
  }

  /// Puts a format on the selection, or takes it off. At a caret it may
  /// put in an empty pair with the caret inside, or step the caret out of
  /// the format (see [MarkdownEdit.toggleInline]).
  void toggleInline(
    InlineFormat format, {
    HighlightColor color = HighlightColor.yellow,
  }) {
    final sel = _selection;
    final before = text;
    final edit = MarkdownEdit.toggleInline(format, text, sel, color: color);
    if (edit == null) return;
    _pending = null;
    // An empty pair at a caret joins the letters typed into it.
    final pair =
        !_showMarks &&
        sel.length == 0 &&
        edit.range.length == 0 &&
        edit.replacement.isNotEmpty;
    if (pair) _history.breakGroup();
    _recorded(() => apply(edit), typing: pair);
    if (_showMarks || sel.length != 0) return;
    final caret = edit.selection;
    if (text == before) {
      // The caret stepped out of (or into) the format.
      _noPull = true;
      return;
    }
    final put = edit.replacement;
    if (edit.range.length == 0 &&
        put.isNotEmpty &&
        caret.length == 0 &&
        caret.location > edit.range.location &&
        caret.location < edit.range.location + put.length) {
      _pending = (
        whole: Utf16Range(edit.range.location, put.length),
        middle: caret.location,
      );
      _runs = null;
      notifyListeners();
    }
  }

  /// The formats at the selection. A caret at either edge of a format is in
  /// it; a selection is in a format when all of it is in one span of it.
  /// The line of the start of the selection gives the size and the list.
  ActiveFormats activeAt() {
    final sel = _selection;
    bool inside(Utf16Range r) => sel.length == 0
        ? r.location <= sel.location && sel.location <= r.end
        : r.location <= sel.location && sel.end <= r.end;
    final inline = <InlineFormat>{};
    HighlightColor? color;
    var link = false;
    for (final s in _spans) {
      final r = s.range;
      final kind = s.kind;
      final format = switch (kind.type) {
        SpanType.bold => InlineFormat.bold,
        SpanType.italic => InlineFormat.italic,
        SpanType.underline => InlineFormat.underline,
        SpanType.strike => InlineFormat.strike,
        SpanType.highlight => InlineFormat.highlight,
        SpanType.code => InlineFormat.code,
        // An empty pair counts only with the caret between its marks.
        SpanType.emptyPair
            when sel.length == 0 &&
                r.location < sel.location &&
                sel.location < r.end =>
          kind.format,
        _ => null,
      };
      if (kind.type == SpanType.linkWords && inside(r)) link = true;
      if (format == null) continue;
      if (kind.type != SpanType.emptyPair && !inside(r)) continue;
      inline.add(format);
      if (format == InlineFormat.highlight) {
        color = kind.color ?? HighlightColor.yellow;
      }
    }
    final start = sel.location.clamp(0, text.length);
    final lineStart = start == 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;
    final lineEnd = text.indexOf('\n', start);
    final prefix = MarkdownEdit.prefix(
      text.substring(lineStart, lineEnd < 0 ? text.length : lineEnd),
    );
    final heading = prefix?.kind == PrefixKind.heading;
    return ActiveFormats(
      inline: inline,
      heading: heading ? prefix!.level.clamp(1, 3) : 0,
      highlight: color,
      line: heading ? null : prefix?.kind,
      link: link,
    );
  }

  /// Makes the lines of the selection a heading of `level` (1 Big, 2
  /// Medium, 3 Small), or normal text for 0.
  void setHeading(int level) =>
      apply(MarkdownEdit.setHeading(level, text, _selection));

  /// Puts a divider line at the selection.
  void insertDivider() => apply(MarkdownEdit.insertDivider(text, _selection));

  /// Takes every format off the selection (a caret: off its line). Lists
  /// keep their marks.
  void clearFormat() => apply(MarkdownEdit.clearInline(text, _selection));

  /// Types `[[` so the list of items opens.
  void startMention() {
    final sel = _selection;
    apply(
      TextEdit(
        range: sel,
        replacement: '[[',
        selection: Utf16Range(sel.location + 2, 0),
      ),
    );
  }

  /// Return. True when the editor used the key: it took a row of the list,
  /// or it went on with a list of the text.
  bool enter() {
    if (acceptCurrent()) return true;
    final sel = _selection;
    final edit = MarkdownEdit.enter(text, sel);
    if (edit == null) return false;
    apply(edit);
    return true;
  }

  /// Tab moves a list item in. False when the caret is not in a list; the
  /// key then moves to the next field.
  bool indent({bool outdent = false}) {
    if (!outdent && acceptCurrent()) return true;
    final edit = MarkdownEdit.indent(text, _selection, outdent: outdent);
    if (edit == null) return false;
    apply(edit);
    return true;
  }

  /// Ticks or clears the check box at `location`.
  void toggleCheckbox(int location) {
    final edit = MarkdownEdit.toggleCheckbox(text, location);
    if (edit == null) return;
    final caret = _selection;
    apply(
      TextEdit(
        range: edit.range,
        replacement: edit.replacement,
        selection: caret,
      ),
    );
  }

  /// The span under a click at `offset`: a check box, a mention, an image or
  /// a link. Null for plain text.
  MarkdownSpan? hit(int offset) {
    for (final span in _spans) {
      final type = span.kind.type;
      if (type != SpanType.checkbox &&
          type != SpanType.mention &&
          type != SpanType.image &&
          type != SpanType.link &&
          type != SpanType.linkWords) {
        continue;
      }
      if (span.range.location <= offset && offset < span.range.end) {
        return span;
      }
    }
    return null;
  }

  // Mentions

  void _updateMentions() {
    final s = value.selection;
    if (!focused || !s.isValid || !s.isCollapsed) {
      _hide(forget: s.isValid && !s.isCollapsed);
      return;
    }
    final trigger = MarkdownEdit.mentionTrigger(text, s.start);
    if (trigger == null) {
      _hide(forget: true);
      return;
    }
    if (_dismissedAt == trigger.range.location) return;
    final open = mentions.value;
    if (open != null &&
        open.location == trigger.range.location &&
        open.query == trigger.query) {
      return;
    }
    final items = services.suggest(trigger.query);
    mentions.value = items.isEmpty
        ? null
        : MentionList(
            location: trigger.range.location,
            query: trigger.query,
            items: items,
            selected: 0,
          );
  }

  void _hide({required bool forget}) {
    if (forget) _dismissedAt = null;
    if (mentions.value != null) mentions.value = null;
  }

  /// The text lost the keyboard, or has it again.
  void setFocused(bool value) {
    if (focused == value) return;
    focused = value;
    if (value) {
      _updateMentions();
    } else {
      _hide(forget: false);
    }
  }

  /// Moves the chosen row of the list down (1) or up (-1).
  void moveList(int delta) {
    final open = mentions.value;
    if (open == null || open.items.isEmpty) return;
    final next = (open.selected + delta).clamp(0, open.items.length - 1);
    mentions.value = MentionList(
      location: open.location,
      query: open.query,
      items: open.items,
      selected: next,
    );
  }

  /// Esc closes the `[[` list and keeps it closed until the caret leaves
  /// that `[[`. False when no list is open.
  bool closeList() {
    final open = mentions.value;
    if (open == null) return false;
    _dismissedAt = open.location;
    mentions.value = null;
    return true;
  }

  /// Takes the chosen row of the list. False when no list is open.
  bool acceptCurrent() {
    final item = mentions.value?.current;
    if (item == null) return false;
    accept(item);
    return true;
  }

  void accept(MentionSuggestion item) {
    final trigger = MarkdownEdit.mentionTrigger(text, _selection.location);
    if (trigger == null) return;
    mentions.value = null;
    apply(
      MarkdownEdit.insertMention(
        title: item.title,
        id: item.ref.id,
        replacing: trigger.range,
      ),
    );
  }

  /// A task or a note that was dragged in from a list becomes a mention.
  void dropItem(String id, int index) {
    final title = services.title(id);
    if (title == null) return;
    apply(
      MarkdownEdit.insertMention(
        title: title,
        id: id,
        replacing: Utf16Range(index.clamp(0, text.length), 0),
      ),
    );
  }

  // Tasks

  bool get canMakeTask => taskTarget() != null;

  /// The words a task would take: the selection, or the line with the
  /// caret. Null when the field cannot make tasks.
  TaskTarget? taskTarget() {
    if (services.makeTask == null) return null;
    return MarkdownEdit.taskTarget(text, _selection);
  }

  /// Makes a task from the words and turns the line into a check box tied
  /// to it.
  void makeTask() {
    final make = services.makeTask;
    if (make == null) return;
    final target = taskTarget();
    if (target == null) {
      final line = lineRange(text, _selection);
      final isTask = text.substring(line.location, line.end).contains('⟦t:');
      services.notify(
        isTask
            ? 'That line is already a task.'
            : 'Put the caret on a line with words, or select some words.',
      );
      return;
    }
    final id = make(target.title);
    if (id == null) return;
    apply(MarkdownEdit.taskLine(target, text, taskId: id));
  }

  // Add to planner

  /// The line with the caret, when the field can use the planner and the
  /// line has an `@date` it can take.
  ({String text, Utf16Range range})? plannerLine() {
    if (services.addToPlanner == null) return null;
    final sel = _selection;
    if (sel.location < 0 || sel.end > text.length) return null;
    final full = lineRange(text, Utf16Range(sel.location, 0));
    var end = full.end;
    while (end > full.location) {
      final c = text.codeUnitAt(end - 1);
      if (c != 0x0A && c != 0x0D) break;
      end -= 1;
    }
    if (sel.end > end) return null;
    final line = text.substring(full.location, end);
    if (!line.contains('@') || AtDatePlanner.plan(line) == null) return null;
    return (text: line, range: Utf16Range(full.location, end - full.location));
  }

  /// Makes the event or the task block, and writes the new text of the line
  /// (a link and when).
  void addToPlanner() {
    final add = services.addToPlanner;
    if (add == null) return;
    final target = plannerLine();
    if (target == null) {
      services.notify(
        'Write @ and a day or time on an open line, like @fri 3pm.',
      );
      return;
    }
    final line = add(target.text);
    if (line == null) return;
    // The caret goes before the hidden task mark, if the line has one.
    final mark = line.indexOf(' ⟦t:');
    final end = mark < 0 ? line.length : mark;
    apply(
      TextEdit(
        range: target.range,
        replacement: line,
        selection: Utf16Range(target.range.location + end, 0),
      ),
    );
  }

  // Images

  void importImages(List<PickedImage> items) {
    for (final item in items) {
      final image = item.image;
      final id = image == null ? null : services.storeImage(image);
      if (id == null) {
        services.notify('${item.name} is not an image Grove can read.');
        continue;
      }
      apply(
        MarkdownEdit.insertImage(
          id: id,
          alt: item.name,
          text: text,
          selection: _selection,
        ),
      );
    }
  }

  // Look

  bool _isLive(String id) => _live[id] ??= services.isLive(id);

  /// The text with its look. Each piece keeps its length, so the caret of
  /// the field is where it is in the stored text.
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final look = this.style;
    final base = look?.base ?? style ?? const TextStyle();
    final text = this.text;
    if (look == null || text.isEmpty || _spans.isEmpty && hiddenRuns.isEmpty) {
      return TextSpan(style: base, text: text);
    }
    final cuts = <int>{0, text.length};
    for (final s in _spans) {
      cuts
        ..add(s.range.location)
        ..add(s.range.end);
      // A check box is three letters. The one in the middle is the box.
      if (s.kind.type == SpanType.checkbox) {
        cuts
          ..add(s.range.location + 1)
          ..add(s.range.location + 2);
      }
    }
    final runs = hiddenRuns;
    for (final r in runs) {
      cuts
        ..add(r.location)
        ..add(r.end);
    }
    final edges = cuts.where((c) => c >= 0 && c <= text.length).toList()
      ..sort();
    final children = <InlineSpan>[];
    var run = 0;
    for (var i = 0; i + 1 < edges.length; i++) {
      final from = edges[i];
      final to = edges[i + 1];
      if (to <= from) continue;
      var piece = text.substring(from, to);
      var pieceStyle = base;
      MarkdownSpan? divider;
      for (final s in _spans) {
        if (s.range.location <= from && to <= s.range.end) {
          if (s.kind.type == SpanType.divider) divider = s;
          final styled = _styled(look, s, from, piece, pieceStyle);
          piece = styled.text;
          pieceStyle = styled.style;
        }
      }
      while (run < runs.length && runs[run].end <= from) {
        run += 1;
      }
      if (run < runs.length && runs[run].location <= from) {
        // Each piece is in a run or out of it: the runs are cuts too.
        pieceStyle = _hiddenBeside(look, pieceStyle);
      } else if (divider != null && !_showMarks) {
        // The last letter of a hidden divider is the line.
        children.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: EditorDivider(color: look.theme.line, height: look.size),
          ),
        );
        continue;
      }
      children.add(TextSpan(text: piece, style: pieceStyle));
    }
    return TextSpan(style: base, children: children);
  }

  /// Hidden marks with the height of the line they are on, so the caret
  /// beside them is as high as beside a letter.
  static TextStyle _hiddenBeside(EditorStyle look, TextStyle style) {
    final size = style.fontSize ?? look.size;
    final line = size * (style.height ?? look.line(size) / size);
    return EditorStyle.hidden.copyWith(
      height: line / EditorStyle.hidden.fontSize!,
    );
  }

  /// The check box is a little bigger than the letters.
  static double _boxSize(EditorStyle look) =>
      (look.size * 1.25).roundToDouble();

  ({String text, TextStyle style}) _styled(
    EditorStyle look,
    MarkdownSpan span,
    int from,
    String piece,
    TextStyle style,
  ) {
    final t = look.theme;
    final kind = span.kind;
    switch (kind.type) {
      case SpanType.heading:
        final level = kind.level.clamp(1, 6);
        final size = (look.size * EditorStyle.headingScale[level - 1])
            .roundToDouble();
        return (
          text: piece,
          style: style.copyWith(
            fontSize: size,
            fontWeight: FontWeight.w700,
            height: look.line(size) / size,
          ),
        );
      case SpanType.headingMark:
        return (
          text: piece,
          style: style.copyWith(color: t.muted.withValues(alpha: 0.6)),
        );
      case SpanType.quote:
        return (text: piece, style: style.copyWith(color: t.muted));
      case SpanType.quoteMark:
        // With hidden marks a quote shows a bar, as a bullet shows a dot.
        if (!_showMarks &&
            from == span.range.location &&
            piece.startsWith('>')) {
          return (
            text: '▎${piece.substring(1)}',
            style: style.copyWith(color: t.accent),
          );
        }
        return (text: piece, style: style.copyWith(color: t.accent));
      case SpanType.listPrefix:
        return (text: piece, style: style);
      case SpanType.listMark:
        // A bullet shows as a dot. A number stays text.
        final first = piece.isEmpty ? '' : piece[0];
        if (from == span.range.location && '-*+'.contains(first)) {
          return (
            text: '•${piece.substring(1)}',
            style: style.copyWith(color: t.accent),
          );
        }
        return (text: piece, style: style.copyWith(color: t.accent));
      case SpanType.checkbox:
        if (from != span.range.location + 1) {
          return (text: piece, style: EditorStyle.hidden);
        }
        final icon = kind.checked
            ? Icons.check_box
            : Icons.check_box_outline_blank;
        return (
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            fontSize: _boxSize(look),
            height: look.line(look.size) / _boxSize(look),
            color: kind.checked ? t.accent : t.muted,
            letterSpacing: 0,
          ),
        );
      case SpanType.checkedText:
        return (
          text: piece,
          style: style.copyWith(
            color: t.muted,
            decoration: TextDecoration.lineThrough,
          ),
        );
      case SpanType.bold:
        return (
          text: piece,
          style: style.copyWith(fontWeight: FontWeight.w700),
        );
      case SpanType.italic:
        return (
          text: piece,
          style: style.copyWith(fontStyle: FontStyle.italic),
        );
      case SpanType.code:
        final outer = style.fontSize ?? look.size;
        final size = (outer * 0.92).roundToDouble();
        return (
          text: piece,
          style: t
              .number(size)
              .copyWith(
                color: style.color,
                height: look.line(outer) / size,
                backgroundColor: t.surface2,
                letterSpacing: 0,
              ),
        );
      case SpanType.strike:
        return (
          text: piece,
          style: style.copyWith(
            decoration: _decorated(style, TextDecoration.lineThrough),
          ),
        );
      case SpanType.underline:
        return (
          text: piece,
          style: style.copyWith(
            decoration: _decorated(style, TextDecoration.underline),
          ),
        );
      case SpanType.highlight:
        final paint =
            TaskPalette.color(kind.color?.name ?? 'yellow') ?? t.accent;
        return (
          text: piece,
          style: style.copyWith(backgroundColor: paint.withValues(alpha: 0.3)),
        );
      case SpanType.emptyPair:
        return (text: piece, style: style);
      case SpanType.divider:
      case SpanType.syntax:
        return (
          text: piece,
          style: style.copyWith(color: t.muted.withValues(alpha: 0.55)),
        );
      case SpanType.hidden:
      case SpanType.taskMark:
        return (text: piece, style: EditorStyle.hidden);
      case SpanType.mention:
        final id = kind.id;
        if (style.fontSize == EditorStyle.hidden.fontSize) {
          return (text: piece, style: style);
        }
        if (id != null && !_isLive(id)) {
          return (
            text: piece,
            style: style.copyWith(
              fontWeight: FontWeight.w500,
              color: t.muted,
              decoration: TextDecoration.lineThrough,
              backgroundColor: t.muted.withValues(alpha: 0.12),
            ),
          );
        }
        final tint = id == null ? t.muted : t.accent;
        return (
          text: piece,
          style: style.copyWith(
            fontWeight: FontWeight.w500,
            color: tint,
            backgroundColor: tint.withValues(alpha: 0.12),
          ),
        );
      case SpanType.image:
        if (style.fontSize == EditorStyle.hidden.fontSize) {
          return (text: piece, style: style);
        }
        return (
          text: piece,
          style: style.copyWith(
            fontWeight: FontWeight.w500,
            color: t.accent2,
            backgroundColor: t.accent2.withValues(alpha: 0.12),
          ),
        );
      case SpanType.tag:
        return (text: piece, style: style.copyWith(color: t.accent2));
      case SpanType.atDate:
        return (
          text: piece,
          style: style.copyWith(
            color: t.accent,
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.dotted,
            decorationColor: t.accent,
          ),
        );
      case SpanType.link:
      case SpanType.linkWords:
        return (
          text: piece,
          style: style.copyWith(
            color: t.accent,
            decoration: TextDecoration.underline,
            decorationColor: t.accent,
          ),
        );
    }
  }

  /// Adds a line to the lines a piece already has, so strike and underline can show together.
  static TextDecoration _decorated(TextStyle style, TextDecoration line) {
    final had = style.decoration;
    if (had == null || had == TextDecoration.none) return line;
    return TextDecoration.combine([had, line]);
  }
}

/// The line a hidden `---` is drawn as: a rule of one point across the text.
/// It is as high as the letters, so its line is as high as any other.
class EditorDivider extends LeafRenderObjectWidget {
  const EditorDivider({super.key, required this.color, required this.height});

  final Color color;
  final double height;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderDivider(color, height);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderDivider)
      ..color = color
      ..lineHeight = height;
  }
}

class _RenderDivider extends RenderBox {
  _RenderDivider(this._color, this._height);

  /// The field lays out its text a little narrower than the room it gives
  /// to a picture in the text, to leave room for the caret.
  static const _inset = 4.0;

  Color _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  double _height;
  set lineHeight(double value) {
    if (value == _height) return;
    _height = value;
    markNeedsLayout();
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final width = constraints.hasBoundedWidth
        ? (constraints.maxWidth - _inset).clamp(0.0, double.infinity)
        : 0.0;
    return constraints.constrain(Size(width, _height));
  }

  @override
  void performLayout() => size = computeDryLayout(constraints);

  @override
  void paint(PaintingContext context, Offset offset) {
    final y = (offset.dy + size.height / 2).floorToDouble();
    context.canvas.drawRect(
      Rect.fromLTWH(offset.dx, y, size.width, 1),
      Paint()..color = _color,
    );
  }
}
