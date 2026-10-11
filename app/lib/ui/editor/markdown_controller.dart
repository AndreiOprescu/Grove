// Port of the text rules of Sources/Grove/Editor/RichTextEditor.swift (its
// Coordinator) and of MarkdownStyler.swift. The stored text stays plain
// Markdown. Only its look changes. The rules of the text are in
// `core/parsing/` (`MarkdownSpans`, `MarkdownEdit`).
import 'package:flutter/material.dart';
import 'package:grove/core/parsing/at_date.dart';
import 'package:grove/core/parsing/markdown_edit.dart';
import 'package:grove/core/parsing/markdown_spans.dart';
import 'package:grove/core/parsing/reference_parser.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../theme/grove_theme.dart';
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
  MarkdownController({super.text, EditorServices? services})
    : services = services ?? EditorServices() {
    _spans = MarkdownSpans.scan(text);
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
    super.dispose();
  }

  // Text changes

  @override
  set value(TextEditingValue next) {
    final old = value;
    if (_applying || next.composing.isValid || old.composing.isValid) {
      _set(next);
      return;
    }
    if (next.text == old.text) {
      _set(_snap(old, next));
      return;
    }
    final change = _difference(old.text, next.text);
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
    if (textChanged) _spans = MarkdownSpans.scan(next.text);
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
    if (snapped.location == s.start && snapped.end == s.end) return next;
    final reversed = s.baseOffset > s.extentOffset;
    return next.copyWith(
      selection: TextSelection(
        baseOffset: reversed ? snapped.end : snapped.location,
        extentOffset: reversed ? snapped.location : snapped.end,
      ),
    );
  }

  /// The one change that turns `a` into `b`: the range of `a` that goes, and
  /// the text that comes.
  static ({Utf16Range range, String replacement}) _difference(
    String a,
    String b,
  ) {
    var head = 0;
    final most = a.length < b.length ? a.length : b.length;
    while (head < most && a.codeUnitAt(head) == b.codeUnitAt(head)) {
      head += 1;
    }
    var tail = 0;
    while (tail < most - head &&
        a.codeUnitAt(a.length - 1 - tail) ==
            b.codeUnitAt(b.length - 1 - tail)) {
      tail += 1;
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
  }

  /// New text from outside: another note was opened, or an undo.
  void load(String text) {
    if (text == this.text) return;
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
  }

  // Buttons and keys

  void format(EditorFormat f) {
    final sel = _selection;
    switch (f) {
      case EditorFormat.bold:
        apply(MarkdownEdit.toggleWrap('**', text, sel));
      case EditorFormat.italic:
        apply(MarkdownEdit.toggleWrap('*', text, sel));
      case EditorFormat.code:
        apply(MarkdownEdit.toggleWrap('`', text, sel));
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
          type != SpanType.link) {
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
    if (look == null || text.isEmpty || _spans.isEmpty) {
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
    final edges = cuts.where((c) => c >= 0 && c <= text.length).toList()
      ..sort();
    final children = <InlineSpan>[];
    for (var i = 0; i + 1 < edges.length; i++) {
      final from = edges[i];
      final to = edges[i + 1];
      if (to <= from) continue;
      var piece = text.substring(from, to);
      var pieceStyle = base;
      for (final s in _spans) {
        if (s.range.location <= from && to <= s.range.end) {
          final styled = _styled(look, s, from, piece, pieceStyle);
          piece = styled.text;
          pieceStyle = styled.style;
        }
      }
      children.add(TextSpan(text: piece, style: pieceStyle));
    }
    return TextSpan(style: base, children: children);
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
}
