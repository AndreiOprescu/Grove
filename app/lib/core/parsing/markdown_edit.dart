import 'markdown_spans.dart';
import 'note_parser.dart';
import 'reference_parser.dart';

export 'utf16_range.dart';

/// One change to a text: replace `range` with `replacement`, then select `selection`.
/// `range` is in the old text and `selection` in the new text. Positions are UTF-16 offsets.
class TextEdit {
  const TextEdit({
    required this.range,
    required this.replacement,
    required this.selection,
  });

  final Utf16Range range;
  final String replacement;
  final Utf16Range selection;

  @override
  bool operator ==(Object other) =>
      other is TextEdit &&
      other.range == range &&
      other.replacement == replacement &&
      other.selection == selection;

  @override
  int get hashCode => Object.hash(range, replacement, selection);

  @override
  String toString() => 'TextEdit($range, "$replacement", $selection)';
}

enum _Style { bullet, numbered, checklist, heading, quote }

/// What a line can start with.
final class LineStyle {
  const LineStyle._(this._style, [this.level = 0]);
  const LineStyle.heading(int level) : this._(_Style.heading, level);

  static const bullet = LineStyle._(_Style.bullet);
  static const numbered = LineStyle._(_Style.numbered);
  static const checklist = LineStyle._(_Style.checklist);
  static const quote = LineStyle._(_Style.quote);

  final _Style _style;

  /// Heading level, 1 to 6. Zero for the other styles.
  final int level;

  bool get isList =>
      _style == _Style.bullet ||
      _style == _Style.numbered ||
      _style == _Style.checklist;

  @override
  bool operator ==(Object other) =>
      other is LineStyle && other._style == _style && other.level == level;

  @override
  int get hashCode => Object.hash(_style, level);
}

enum PrefixKind { bullet, numbered, checklist, heading, quote }

/// The marker at the start of a line: `- `, `1. `, `- [ ] `, `## ` or `> `.
class LinePrefix {
  const LinePrefix({
    required this.indent,
    required this.kind,
    required this.length,
    this.bullet = '-',
    this.checked = false,
    this.number = 0,
    this.level = 0,
  });

  final int indent;
  final PrefixKind kind;

  /// Indent, marker and the space after it, in UTF-16 units. All of these are ASCII.
  final int length;

  /// `-`, `*` or `+` for bullets and checklists.
  final String bullet;
  final bool checked;
  final int number;

  /// Heading level, 1 to 6.
  final int level;

  bool get isList =>
      kind == PrefixKind.bullet ||
      kind == PrefixKind.numbered ||
      kind == PrefixKind.checklist;

  bool matches(LineStyle style) => switch ((kind, style._style)) {
    (PrefixKind.bullet, _Style.bullet) ||
    (PrefixKind.numbered, _Style.numbered) ||
    (PrefixKind.checklist, _Style.checklist) ||
    (PrefixKind.quote, _Style.quote) => true,
    (PrefixKind.heading, _Style.heading) => level == style.level,
    _ => false,
  };
}

/// The line a "Make task" command works on, and the words the task is named after.
class TaskTarget {
  const TaskTarget({required this.title, required this.line});

  /// The selected words, or the whole line when nothing is selected. No list marker, no task mark.
  final String title;

  /// The line without its line break.
  final Utf16Range line;

  @override
  bool operator ==(Object other) =>
      other is TaskTarget && other.title == title && other.line == line;

  @override
  int get hashCode => Object.hash(title, line);
}

/// An open `[[` before the caret: the range from the brackets to the caret, and the text typed after them.
class MentionTrigger {
  const MentionTrigger({required this.range, required this.query});

  final Utf16Range range;
  final String query;

  @override
  bool operator ==(Object other) =>
      other is MentionTrigger && other.range == range && other.query == query;

  @override
  int get hashCode => Object.hash(range, query);
}

typedef _LineChange = ({String line, int oldHead, int newHead});

class _LineInfo {
  _LineInfo(this.oldStart, this.newStart, this.oldHead, this.newHead);
  final int oldStart, newStart, oldHead, newHead;
}

/// One letter the reader sees: a character, a surrogate pair, or a whole mention or image.
class _Unit {
  _Unit(this.start, this.end, this.text);
  final int start, end;
  final String text;
  final keys = <String>{};
  bool get isSpace => text.trim().isEmpty;
}

/// One line read for the format rules. Positions are in the whole text.
class _Line {
  _Line({
    required this.start,
    required this.end,
    required this.bodyStart,
    required this.bodyEnd,
    required this.units,
    required this.marks,
    required this.pairs,
    required this.prefix,
  });

  final int start, end;

  /// The words: after the line marker, before a hidden task mark.
  final int bodyStart, bodyEnd;
  final List<_Unit> units;

  /// Positions of format marks in the body.
  final Set<int> marks;
  final List<InlinePair> pairs;
  final LinePrefix? prefix;

  /// The units before `p`.
  int boundary(int p) => units.where((u) => u.end <= p).length;
}

/// A line written again from its units.
class _Written {
  _Written(this.body, this.unitAt, this.gapAt);

  /// The new body.
  final String body;

  /// Where each unit starts in `body`.
  final List<int> unitAt;

  /// For each place between units (0 to n), the spot after the closing marks and before the
  /// opening marks.
  final List<int> gapAt;
}

/// The pure text rules of the editor: what Return, Tab and the format buttons do to a text.
/// No UI. The editor view applies the returned [TextEdit].
abstract final class MarkdownEdit {
  // Line prefixes.

  /// Groups: 1 indent · 2 and 3 checklist bullet and box · 4 bullet · 5 number · 6 hashes · 7 quote.
  static const prefixPattern =
      r'^( *)(?:([-*+]) \[([ xX])\] |([-*+]) |(\d{1,9})\. |(#{1,6}) |(> ))';
  static final _prefixRegex = RegExp(prefixPattern);

  static LinePrefix? prefix(String line) {
    final m = _prefixRegex.firstMatch(line);
    if (m == null) return null;
    final indent = m.group(1)?.length ?? 0;
    final length = m.end;
    final box = m.group(2), bullet = m.group(4), number = m.group(5);
    final hashes = m.group(6);
    if (box != null) {
      return LinePrefix(
        indent: indent,
        kind: PrefixKind.checklist,
        length: length,
        bullet: box,
        checked: m.group(3) != ' ',
      );
    }
    if (bullet != null) {
      return LinePrefix(
        indent: indent,
        kind: PrefixKind.bullet,
        length: length,
        bullet: bullet,
      );
    }
    if (number != null) {
      return LinePrefix(
        indent: indent,
        kind: PrefixKind.numbered,
        length: length,
        number: int.parse(number),
      );
    }
    if (hashes != null) {
      return LinePrefix(
        indent: indent,
        kind: PrefixKind.heading,
        length: length,
        level: hashes.length,
      );
    }
    return LinePrefix(indent: indent, kind: PrefixKind.quote, length: length);
  }

  static String _marker(LineStyle style, int number) => switch (style._style) {
    _Style.bullet => '- ',
    _Style.numbered => '$number. ',
    _Style.checklist => '- [ ] ',
    _Style.heading => '${'#' * style.level.clamp(1, 6)} ',
    _Style.quote => '> ',
  };

  static int _leadingSpaces(String line) {
    var n = 0;
    while (n < line.length && line.codeUnitAt(n) == 0x20) {
      n += 1;
    }
    return n;
  }

  // Whole lines.

  /// The whole lines a selection touches. A selection that ends right after a newline
  /// does not touch the next line.
  static ({Utf16Range range, List<String> lines, bool trailingNewline}) _block(
    String text,
    Utf16Range sel,
  ) {
    var end = sel.end;
    if (sel.length > 0 && end > 0 && text.codeUnitAt(end - 1) == 0x0A) {
      end -= 1;
    }
    final len = end - sel.location;
    final range = lineRange(text, Utf16Range(sel.location, len < 0 ? 0 : len));
    var body = text.substring(range.location, range.end);
    final trailing = body.endsWith('\n');
    if (trailing) body = body.substring(0, body.length - 1);
    return (range: range, lines: body.split('\n'), trailingNewline: trailing);
  }

  /// Changes the start of every touched line. `change` gets the index among the handled lines
  /// and the line, and returns the new line plus how long its changed start was before and after
  /// (so the caret can follow). Returns null when no line changed.
  static TextEdit? _transformLines(
    String text,
    Utf16Range sel,
    _LineChange? Function(int index, String line) change, {
    required bool skipBlank,
  }) {
    final b = _block(text, sel);
    final infos = <_LineInfo>[];
    final out = <String>[];
    var oldPos = 0, newPos = 0, handled = 0;
    var changed = false;
    for (final line in b.lines) {
      final blank = line.trim().isEmpty;
      _LineChange? result;
      if (!(blank && skipBlank)) {
        result = change(handled, line);
        handled += 1;
      }
      final newLine = result?.line ?? line;
      if (newLine != line) changed = true;
      infos.add(
        _LineInfo(oldPos, newPos, result?.oldHead ?? 0, result?.newHead ?? 0),
      );
      out.add(newLine);
      oldPos += line.length + 1;
      newPos += newLine.length + 1;
    }
    if (!changed) return null;

    // Where a position of the old text lands in the new text.
    int map(int pos) {
      final rel = pos - b.range.location;
      final info = infos.lastWhere(
        (i) => i.oldStart <= rel,
        orElse: () => infos.first,
      );
      final col = rel - info.oldStart;
      final newCol = col >= info.oldHead
          ? col + (info.newHead - info.oldHead)
          : (col < info.newHead ? col : info.newHead);
      return b.range.location + info.newStart + newCol;
    }

    final Utf16Range selection;
    if (sel.length == 0) {
      selection = Utf16Range(map(sel.location), 0);
    } else {
      final start = sel.location == b.range.location
          ? b.range.location
          : map(sel.location);
      selection = Utf16Range(start, map(sel.end) - start);
    }
    return TextEdit(
      range: b.range,
      replacement: out.join('\n') + (b.trailingNewline ? '\n' : ''),
      selection: selection,
    );
  }

  // Return.

  /// Return on a list or quote line starts the next item. On an empty item it leaves the list
  /// (an indented item first moves one level out). Null means "do the normal new line".
  static TextEdit? enter(String text, Utf16Range sel) {
    if (sel.length != 0) return null;
    final lr = lineRange(text, Utf16Range(sel.location, 0));
    var line = text.substring(lr.location, lr.end);
    if (line.endsWith('\n')) line = line.substring(0, line.length - 1);
    final p = prefix(line);
    if (p == null || !(p.isList || p.kind == PrefixKind.quote)) return null;
    if (sel.location - lr.location < p.length) return null;

    if (line.substring(p.length).trim().isEmpty) {
      if (p.indent >= 2) {
        final caret = sel.location - 2;
        return TextEdit(
          range: Utf16Range(lr.location, 2),
          replacement: '',
          selection: Utf16Range(caret > lr.location ? caret : lr.location, 0),
        );
      }
      return TextEdit(
        range: Utf16Range(lr.location, line.length),
        replacement: '',
        selection: Utf16Range(lr.location, 0),
      );
    }
    final next = switch (p.kind) {
      PrefixKind.bullet => '${p.bullet} ',
      PrefixKind.numbered => '${p.number + 1}. ',
      PrefixKind.checklist => '${p.bullet} [ ] ',
      PrefixKind.quote => '> ',
      PrefixKind.heading => null,
    };
    if (next == null) return null;
    final insert = '\n${' ' * p.indent}$next';
    return TextEdit(
      range: sel,
      replacement: insert,
      selection: Utf16Range(sel.location + insert.length, 0),
    );
  }

  // Tab.

  /// Tab moves the list items in the selection one level in, Shift-Tab one level out
  /// (two spaces). Other lines stay as they are. Null means "no list line here".
  static TextEdit? indent(
    String text,
    Utf16Range sel, {
    bool outdent = false,
  }) => _transformLines(text, sel, skipBlank: false, (_, line) {
    final p = prefix(line);
    if (p == null || !p.isList) return null;
    if (outdent) {
      final k = p.indent < 2 ? p.indent : 2;
      return k == 0 ? null : (line: line.substring(k), oldHead: k, newHead: 0);
    }
    return (line: '  $line', oldHead: 0, newHead: 2);
  });

  // Bold, italic, code.

  /// Puts `marker` (`**`, `*` or `` ` ``) around the selection, or takes it off when it is
  /// already there. With no selection it adds a pair and puts the caret between them.
  static TextEdit toggleWrap(String marker, String text, Utf16Range sel) {
    final m = marker.length;
    final mark = marker.isEmpty ? 42 : marker.codeUnitAt(0);
    final selEnd = sel.end;

    var left = 0, right = 0;
    while (sel.location - left - 1 >= 0 &&
        text.codeUnitAt(sel.location - left - 1) == mark) {
      left += 1;
    }
    while (selEnd + right < text.length &&
        text.codeUnitAt(selEnd + right) == mark) {
      right += 1;
    }
    final n = left < right ? left : right;
    final chosen = text.substring(sel.location, selEnd);
    // `*` is italic only when an odd number of stars sit around the text: two stars are bold.
    final wrapped = marker == '*' ? n.isOdd : n >= m;
    if (wrapped) {
      return TextEdit(
        range: Utf16Range(sel.location - m, sel.length + 2 * m),
        replacement: chosen,
        selection: Utf16Range(sel.location - m, sel.length),
      );
    }
    if (marker != '*' &&
        sel.length > 2 * m &&
        chosen.startsWith(marker) &&
        chosen.endsWith(marker)) {
      return TextEdit(
        range: sel,
        replacement: chosen.substring(m, sel.length - m),
        selection: Utf16Range(sel.location, sel.length - 2 * m),
      );
    }
    if (sel.length == 0) {
      return TextEdit(
        range: sel,
        replacement: marker + marker,
        selection: Utf16Range(sel.location + m, 0),
      );
    }
    return TextEdit(
      range: sel,
      replacement: '$marker$chosen$marker',
      selection: Utf16Range(sel.location + m, sel.length),
    );
  }

  // Line styles.

  /// Gives every touched line the style, or takes it off when all of them already have it.
  /// A line with another style gets this one instead. Empty lines are skipped when several
  /// lines are touched.
  static TextEdit? toggleLine(LineStyle style, String text, Utf16Range sel) {
    final lines = _block(text, sel).lines;
    final filled = lines.where((l) => l.trim().isNotEmpty);
    final allHaveIt =
        filled.isNotEmpty &&
        filled.every((l) => prefix(l)?.matches(style) ?? false);
    return _transformLines(text, sel, skipBlank: lines.length > 1, (i, line) {
      final p = prefix(line);
      final oldHead = p?.length ?? _leadingSpaces(line);
      final keep = style.isList ? (p?.indent ?? oldHead) : 0;
      final head = ' ' * keep + (allHaveIt ? '' : _marker(style, i + 1));
      return (
        line: head + line.substring(oldHead),
        oldHead: oldHead,
        newHead: head.length,
      );
    });
  }

  // Checklist.

  /// Flips `[ ]` and `[x]` on the checklist line that contains `location`.
  /// Null when it is not a checklist line.
  static TextEdit? toggleCheckbox(String text, int location) {
    if (location < 0 || location > text.length) return null;
    final lr = lineRange(text, Utf16Range(location, 0));
    final p = prefix(text.substring(lr.location, lr.end));
    if (p == null || p.kind != PrefixKind.checklist) return null;
    return TextEdit(
      range: Utf16Range(lr.location + p.indent + 3, 1),
      replacement: p.checked ? ' ' : 'x',
      selection: Utf16Range(location, 0),
    );
  }

  // Make a task.

  /// The line to turn into a task. Null when the selection runs over several lines,
  /// the line has no words, or the line already has a task.
  static TaskTarget? taskTarget(String text, Utf16Range sel) {
    if (sel.location < 0 || sel.end > text.length) return null;
    final full = lineRange(text, Utf16Range(sel.location, 0));
    var lineEnd = full.end;
    while (lineEnd > full.location) {
      final c = text.codeUnitAt(lineEnd - 1);
      if (c != 0x0A && c != 0x0D) break;
      lineEnd -= 1;
    }
    final line = Utf16Range(full.location, lineEnd - full.location);
    if (sel.end > line.end) return null;
    final lineText = text.substring(line.location, line.end);
    if (lineText.contains('⟦t:')) return null;

    final words = sel.length > 0
        ? text.substring(sel.location, sel.end)
        : lineText.substring(prefix(lineText)?.length ?? 0);
    final title = words.trim();
    if (title.isEmpty) return null;
    return TaskTarget(title: title, line: line);
  }

  /// Turns the line into `- [ ] words ⟦t:ID⟧`. A line that is already a check box keeps
  /// its box and indent. The caret ends at the end of the words, before the hidden mark.
  static TextEdit taskLine(
    TaskTarget target,
    String text, {
    required String taskId,
  }) {
    final lineText = text.substring(target.line.location, target.line.end);
    final p = prefix(lineText);
    var head = '- [ ] ';
    var indent = 0;
    if (p != null) {
      if (p.isList) indent = p.indent;
      if (p.kind == PrefixKind.checklist) {
        head = '${p.bullet} [${p.checked ? 'x' : ' '}] ';
      }
    } else {
      indent = _leadingSpaces(lineText);
    }
    final words = lineText.substring(p?.length ?? indent).trim();
    final body = ' ' * indent + head + words;
    return TextEdit(
      range: target.line,
      replacement: '$body ${NoteParser.marker(taskId)}',
      selection: Utf16Range(target.line.location + body.length, 0),
    );
  }

  // Mentions.

  static MentionTrigger? mentionTrigger(String text, int caret) {
    if (caret < 0 || caret > text.length) return null;
    final lineStart = lineRange(text, Utf16Range(caret, 0)).location;
    final before = text.substring(lineStart, caret);
    final open = before.lastIndexOf('[[');
    if (open < 0) return null;
    final query = before.substring(open + 2);
    if (query.contains(RegExp(r'[\[\]|]'))) return null;
    return MentionTrigger(
      range: Utf16Range(lineStart + open, caret - lineStart - open),
      query: query,
    );
  }

  /// Writes `[[Title|ID]]` over what the user typed after `[[`. The caret ends after it.
  static TextEdit insertMention({
    required String title,
    required String id,
    required Utf16Range replacing,
  }) {
    final text = ReferenceParser.mention(title: title, id: id);
    return TextEdit(
      range: replacing,
      replacement: text,
      selection: Utf16Range(replacing.location + text.length, 0),
    );
  }

  /// Puts an image on a line of its own at the selection. The caret ends on the line after it.
  static TextEdit insertImage({
    required String id,
    required String alt,
    required String text,
    required Utf16Range selection,
  }) {
    final lead =
        selection.location > 0 &&
            text.codeUnitAt(selection.location - 1) != 0x0A
        ? '\n'
        : '';
    final end = selection.end;
    final nextIsBreak = end < text.length && text.codeUnitAt(end) == 0x0A;
    final replacement =
        lead +
        ReferenceParser.imageMarkup(id: id, alt: alt) +
        (nextIsBreak ? '' : '\n');
    // When a line break follows, the caret steps over it. It is part of the text that stays.
    final caret =
        selection.location + replacement.length + (nextIsBreak ? 1 : 0);
    return TextEdit(
      range: selection,
      replacement: replacement,
      selection: Utf16Range(caret, 0),
    );
  }

  /// The text without the image `id`. A line that held only that image goes away
  /// with its line break.
  static String removeImage(String id, String text) {
    final regex = RegExp(
      '!\\[[^\\]\\n]*\\]\\(grove-image:${RegExp.escape(id)}\\)',
      caseSensitive: false,
    );
    var out = text;
    for (final m in regex.allMatches(text).toList().reversed) {
      var cut = Utf16Range(m.start, m.end - m.start);
      final line = lineRange(text, cut);
      final alone =
          line.location == cut.location &&
          (line.end == cut.end ||
              (line.end - 1 == cut.end && text.codeUnitAt(cut.end) == 0x0A));
      if (alone) {
        cut = line;
        // The last line has no break of its own: take the one before it.
        if (line.end == text.length &&
            line.location > 0 &&
            text.codeUnitAt(line.location - 1) == 0x0A) {
          cut = Utf16Range(line.location - 1, line.length + 1);
        }
      }
      out = out.replaceRange(cut.location, cut.end, '');
    }
    return out;
  }
  // Formats.

  static String _keyOf(InlineFormat f, HighlightColor color) => switch (f) {
    InlineFormat.bold => 'b',
    InlineFormat.italic => 'i',
    InlineFormat.underline => 'u',
    InlineFormat.strike => 's',
    InlineFormat.highlight => 'h:${color.name}',
    InlineFormat.code => 'c',
  };

  static String? _keyOfKind(SpanKind k) => switch (k.type) {
    SpanType.bold => 'b',
    SpanType.italic => 'i',
    SpanType.underline => 'u',
    SpanType.strike => 's',
    SpanType.highlight => 'h:${(k.color ?? HighlightColor.yellow).name}',
    SpanType.code => 'c',
    SpanType.linkWords => 'l:${k.url}',
    _ => null,
  };

  /// `h:green` and `h:yellow` are one family, so are links.
  static String _family(String key) => key[0];

  static String _openMark(String key) => switch (key[0]) {
    'b' => '**',
    'i' => '*',
    'u' => '<u>',
    's' => '~~',
    'c' => '`',
    'l' => '[',
    _ => key == 'h:yellow' ? '==' : '=={${key.substring(2)}}',
  };

  static String _closeMark(String key) => switch (key[0]) {
    'b' => '**',
    'i' => '*',
    'u' => '</u>',
    's' => '~~',
    'c' => '`',
    'l' => '](${key.substring(2)})',
    _ => '==',
  };

  /// Links are outside every other format, code inside every other format.
  static int _rank(String key) => switch (key[0]) {
    'l' => 0,
    'c' => 2,
    _ => 1,
  };

  /// Among formats that start together, the one written first. Outer first.
  static const _order = 'hsubi';

  static int _lineEndAt(String text, int p) {
    var e = p;
    while (e < text.length) {
      final c = text.codeUnitAt(e);
      if (c == 0x0A || c == 0x0D) break;
      e += 1;
    }
    return e;
  }

  static int _lineStartAt(String text, int p) {
    var s = p;
    while (s > 0) {
      final c = text.codeUnitAt(s - 1);
      if (c == 0x0A || c == 0x0D) break;
      s -= 1;
    }
    return s;
  }

  /// Reads the line that holds `p`: where its words are, the letters and their formats.
  static _Line _readLine(String text, int p) {
    final start = _lineStartAt(text, p);
    final end = _lineEndAt(text, p);
    final range = Utf16Range(start, 0);
    final spans = MarkdownSpans.scan(text, range: range);
    final pairs = start == end
        ? const <InlinePair>[]
        : MarkdownSpans.pairs(text, range: range);
    final lineText = text.substring(start, end);
    final pre = prefix(lineText);
    var bodyStart = start + (pre?.length ?? 0);
    var bodyEnd = end;
    final atoms = <int, int>{};
    for (final sp in spans) {
      switch (sp.kind.type) {
        case SpanType.taskMark:
          if (sp.range.location < bodyEnd) bodyEnd = sp.range.location;
        case SpanType.divider:
          bodyStart = end;
        case SpanType.mention || SpanType.image:
          atoms[sp.range.location] = sp.range.end;
        default:
          break;
      }
    }
    if (bodyStart > bodyEnd) bodyStart = bodyEnd;
    final marks = <int>{};
    for (final pr in pairs) {
      for (final r in [pr.open, pr.close]) {
        for (var i = r.location; i < r.end; i++) {
          marks.add(i);
        }
      }
    }
    final units = <_Unit>[];
    var i = bodyStart;
    while (i < bodyEnd) {
      if (marks.contains(i)) {
        i += 1;
        continue;
      }
      var e = atoms[i] ?? i + 1;
      if (e == i + 1 &&
          e < bodyEnd &&
          (text.codeUnitAt(i) & 0xFC00) == 0xD800 &&
          (text.codeUnitAt(e) & 0xFC00) == 0xDC00) {
        e += 1;
      }
      units.add(_Unit(i, e, text.substring(i, e)));
      i = e;
    }
    for (final pr in pairs) {
      final key = _keyOfKind(pr.kind);
      if (key == null) continue;
      for (final u in units) {
        if (u.start >= pr.content.location && u.end <= pr.content.end) {
          u.keys.add(key);
        }
      }
    }
    return _Line(
      start: start,
      end: end,
      bodyStart: bodyStart,
      bodyEnd: bodyEnd,
      units: units,
      marks: marks,
      pairs: pairs,
      prefix: pre,
    );
  }

  /// The lines a selection touches. A selection that ends right after a line break does not
  /// touch the next line.
  static List<_Line> _readLines(String text, Utf16Range sel) {
    var last = sel.end;
    if (sel.length > 0 && last > 0 && text.codeUnitAt(last - 1) == 0x0A) {
      last -= 1;
    }
    final lines = <_Line>[];
    var p = sel.location;
    while (true) {
      final line = _readLine(text, p);
      lines.add(line);
      if (line.end >= last || line.end >= text.length) break;
      p = line.end + 1;
    }
    return lines;
  }

  /// Takes a format off the spaces at the edges of each of its runs. Code keeps its spaces.
  static void _trim(List<_Unit> units, List<Set<String>> keys) {
    final all = {for (final k in keys) ...k}..removeWhere((k) => k == 'c');
    for (final key in all) {
      var i = 0;
      while (i < units.length) {
        if (!keys[i].contains(key)) {
          i += 1;
          continue;
        }
        var e = i;
        while (e < units.length && keys[e].contains(key)) {
          e += 1;
        }
        var a = i, z = e;
        while (a < z && units[a].isSpace) {
          keys[a].remove(key);
          a += 1;
        }
        while (z > a && units[z - 1].isSpace) {
          keys[z - 1].remove(key);
          z -= 1;
        }
        i = e;
      }
    }
  }

  /// Writes units with the given formats as Markdown. A format that has to close for another
  /// one closes before spaces and opens again after them, so it still reads back.
  static _Written _write(List<_Unit> units, List<Set<String>> keys) {
    // Tokens: a unit (index >= 0), a gap (-1 - k), or a mark (text).
    final tokens = <Object>[];
    final stack = <String>[];
    final waiting = <String>{};
    int runLength(String key, int from) {
      var e = from;
      while (e < units.length && keys[e].contains(key)) {
        e += 1;
      }
      return e - from;
    }

    for (var k = 0; k <= units.length; k++) {
      final want = k < units.length ? keys[k] : const <String>{};
      waiting.removeWhere((key) => !want.contains(key));
      final fresh = [
        for (final key in want)
          if (!stack.contains(key) && !waiting.contains(key)) key,
      ];
      // Close from the lowest format that ends here, or that must sit inside a new one.
      var cut = stack.length;
      for (var j = 0; j < stack.length; j++) {
        final ends = !want.contains(stack[j]);
        final inside = fresh.any((key) => _rank(key) < _rank(stack[j]));
        if (ends || inside) {
          cut = j;
          break;
        }
      }
      final again = <String>[];
      if (cut < stack.length) {
        final closing = stack.sublist(cut).reversed.toList();
        stack.length = cut;
        final marks = [for (final key in closing) _closeMark(key)];
        // Close before trailing spaces, so the closing mark touches a letter.
        var at = tokens.length;
        if (!closing.any((key) => key[0] == 'c' || key[0] == 'l')) {
          while (at > 0) {
            final t = tokens[at - 1];
            if (t is int && t < 0) {
              at -= 1;
            } else if (t is int && units[t].isSpace) {
              at -= 1;
            } else {
              break;
            }
          }
        }
        tokens.insertAll(at, marks);
        for (final key in closing.reversed) {
          if (want.contains(key)) again.add(key);
        }
      }
      tokens.add(-1 - k);
      if (k == units.length) break;
      final opening = [...again, ...fresh, ...waiting];
      waiting.clear();
      if (units[k].isSpace) {
        // Open again at the next letter. Code and links keep their spaces.
        for (final key in opening.toList()) {
          if (key[0] != 'c' && key[0] != 'l') {
            waiting.add(key);
            opening.remove(key);
          }
        }
      }
      opening.sort((a, b) {
        final r = _rank(a).compareTo(_rank(b));
        if (r != 0) return r;
        final l = runLength(b, k).compareTo(runLength(a, k));
        if (l != 0) return l;
        return _order.indexOf(a[0]).compareTo(_order.indexOf(b[0]));
      });
      // A new outer format closes the inner ones first; they open again inside it.
      for (final key in opening) {
        tokens.add(_openMark(key));
        stack.add(key);
      }
      tokens.add(k);
    }

    final out = StringBuffer();
    final unitAt = List<int>.filled(units.length, 0);
    final gapAt = List<int>.filled(units.length + 1, 0);
    for (final t in tokens) {
      if (t is String) {
        out.write(t);
      } else if (t is int && t >= 0) {
        unitAt[t] = out.length;
        out.write(units[t].text);
      } else if (t is int) {
        gapAt[-1 - t] = out.length;
      }
    }
    return _Written(out.toString(), unitAt, gapAt);
  }

  /// The formats of a line as a list of sets, one per unit, without the formats on spaces
  /// that a reader cannot tell apart (all but code and links).
  static List<(String, Set<String>)> _shape(
    List<_Unit> units,
    List<Set<String>> keys,
  ) => [
    for (var i = 0; i < units.length; i++)
      (
        units[i].text,
        units[i].isSpace
            ? keys[i].where((k) => k[0] == 'c' || k[0] == 'l').toSet()
            : keys[i],
      ),
  ];

  static bool _sameShape(
    List<(String, Set<String>)> a,
    List<(String, Set<String>)> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].$1 != b[i].$1) return false;
      if (a[i].$2.length != b[i].$2.length) return false;
      if (!a[i].$2.containsAll(b[i].$2)) return false;
    }
    return true;
  }

  /// Writes the lines again with new formats (and new line marks), checks that the result
  /// reads back the same, and returns one edit over all of them. `place` turns a position of
  /// a line's new text into the new selection. Null when nothing changed or it would not read
  /// back.
  static TextEdit? _rewrite(
    String text,
    List<_Line> lines,
    List<List<Set<String>>> keys, {
    List<String>? heads,
    required Utf16Range Function(List<_Written> written, List<int> bodyAt)
    place,
  }) {
    final written = <_Written>[];
    final bodyAt = <int>[];
    final out = StringBuffer();
    final first = lines.first.start;
    for (var n = 0; n < lines.length; n++) {
      final line = lines[n];
      if (n > 0) out.write(text.substring(lines[n - 1].end, line.start));
      _trim(line.units, keys[n]);
      final w = _write(line.units, keys[n]);
      written.add(w);
      out.write(heads?[n] ?? text.substring(line.start, line.bodyStart));
      bodyAt.add(first + out.length);
      out
        ..write(w.body)
        ..write(text.substring(line.bodyEnd, line.end));
    }
    final last = lines.last.end;
    final replacement = out.toString();
    if (replacement == text.substring(first, last)) return null;

    // Read the new lines back.
    final next = text.replaceRange(first, last, replacement);
    for (var n = 0; n < lines.length; n++) {
      final back = _readLine(next, bodyAt[n]);
      final want = _shape(lines[n].units, keys[n]);
      final got = _shape(back.units, [for (final u in back.units) u.keys]);
      if (!_sameShape(want, got)) return null;
    }
    return TextEdit(
      range: Utf16Range(first, last - first),
      replacement: replacement,
      selection: place(written, bodyAt),
    );
  }

  /// The selection over the picked units in the written lines.
  static Utf16Range _over(
    List<List<int>> picked,
    List<_Line> lines,
    List<_Written> written,
    List<int> bodyAt,
  ) {
    int? from, to;
    for (var n = 0; n < lines.length; n++) {
      for (final i in picked[n]) {
        final a = bodyAt[n] + written[n].unitAt[i];
        final z = a + lines[n].units[i].text.length;
        from ??= a;
        to = z;
      }
    }
    return Utf16Range(from ?? 0, (to ?? 0) - (from ?? 0));
  }

  static String _emptyPair(InlineFormat f, HighlightColor color) =>
      _openMark(_keyOf(f, color)) + _closeMark(_keyOf(f, color));

  /// Puts a format on the selected words, or takes it off when all of them already have it.
  /// Works line by line and keeps spaces at the edges outside the marks. A highlight of
  /// another colour changes colour.
  ///
  /// At a caret: in a word it works on the whole word; at the edge of the format the caret
  /// steps out; just outside it steps in; in the middle beside a space the format splits;
  /// anywhere else an empty pair goes in with the caret inside. Null when nothing can change.
  static TextEdit? toggleInline(
    InlineFormat format,
    String text,
    Utf16Range sel, {
    HighlightColor color = HighlightColor.yellow,
  }) {
    final key = _keyOf(format, color);
    if (sel.length == 0) return _toggleAtCaret(format, key, color, text, sel);
    final lines = _readLines(text, sel);
    final picked = [
      for (final line in lines)
        [
          for (var i = 0; i < line.units.length; i++)
            if (line.units[i].start < sel.end &&
                line.units[i].end > sel.location)
              i,
        ],
    ];
    return _apply(key, text, lines, picked, (w, at) {
      return _over(picked, lines, w, at);
    });
  }

  /// Turns `key` on for the picked units, or off when all their letters have it.
  static TextEdit? _apply(
    String key,
    String text,
    List<_Line> lines,
    List<List<int>> picked,
    Utf16Range Function(List<_Written>, List<int>) place,
  ) {
    var letters = 0, have = 0;
    for (var n = 0; n < lines.length; n++) {
      for (final i in picked[n]) {
        final u = lines[n].units[i];
        if (u.isSpace) continue;
        letters += 1;
        if (u.keys.contains(key)) have += 1;
      }
    }
    if (letters == 0) return null;
    final on = have < letters;
    final family = _family(key);
    final keys = [
      for (var n = 0; n < lines.length; n++)
        [
          for (final u in lines[n].units) {...u.keys},
        ],
    ];
    for (var n = 0; n < lines.length; n++) {
      for (final i in picked[n]) {
        keys[n][i].removeWhere((k) => _family(k) == family);
        if (on) keys[n][i].add(key);
      }
    }
    return _rewrite(text, lines, keys, place: place);
  }

  static TextEdit _caretAt(int p) => TextEdit(
    range: Utf16Range(p, 0),
    replacement: '',
    selection: Utf16Range(p, 0),
  );

  static TextEdit? _toggleAtCaret(
    InlineFormat format,
    String key,
    HighlightColor color,
    String text,
    Utf16Range sel,
  ) {
    final p = sel.location;
    final line = _readLine(text, p);
    final family = _family(key);
    TextEdit insert(int at) {
      final pair = _emptyPair(format, color);
      return TextEdit(
        range: Utf16Range(at, 0),
        replacement: pair,
        selection: Utf16Range(at + _openMark(key).length, 0),
      );
    }

    // An empty pair at the caret goes away, or changes colour.
    for (final pr in line.pairs) {
      if (pr.kind.type != SpanType.emptyPair || pr.kind.format != format) {
        continue;
      }
      if (pr.content.location != p) continue;
      final same = format != InlineFormat.highlight || pr.kind.color == color;
      final whole = pr.whole;
      return TextEdit(
        range: whole,
        replacement: same ? '' : _emptyPair(format, color),
        selection: Utf16Range(
          whole.location + (same ? 0 : _openMark(key).length),
          0,
        ),
      );
    }
    // `**` and ``` `` ``` do not read as empty pairs. Take them away too.
    if ((format == InlineFormat.italic || format == InlineFormat.code) &&
        p > 0 &&
        p < text.length) {
      final m = _openMark(key);
      if (text[p - 1] == m &&
          text[p] == m &&
          !line.marks.contains(p - 1) &&
          !line.marks.contains(p)) {
        return TextEdit(
          range: Utf16Range(p - 1, 2),
          replacement: '',
          selection: Utf16Range(p - 1, 0),
        );
      }
    }

    final k = line.boundary(p);
    final units = line.units;
    final before = k > 0 ? units[k - 1] : null;
    final after = k < units.length ? units[k] : null;
    final inWord =
        before != null &&
        after != null &&
        !before.isSpace &&
        !after.isSpace &&
        p >= line.bodyStart &&
        p <= line.bodyEnd;
    if (inWord) {
      var a = k - 1, z = k;
      while (a > 0 && !units[a - 1].isSpace) {
        a -= 1;
      }
      while (z < units.length && !units[z].isSpace) {
        z += 1;
      }
      final picked = [
        [for (var i = a; i < z; i++) i],
      ];
      return _apply(key, text, [line], picked, (w, at) {
        return Utf16Range(at[0] + w[0].unitAt[k], 0);
      });
    }

    bool sameFamily(InlinePair pr) {
      final kk = _keyOfKind(pr.kind);
      return kk != null && _family(kk) == family;
    }

    bool hasUnits(int from, int to) =>
        units.any((u) => u.start >= from && u.end <= to);

    InlinePair? around;
    for (final pr in line.pairs) {
      if (!sameFamily(pr)) continue;
      if (pr.content.location <= p && p <= pr.content.end) {
        if (around == null || pr.content.length < around.content.length) {
          around = pr;
        }
      }
    }
    if (around != null) {
      final same = _keyOfKind(around.kind) == key;
      final atEnd = !hasUnits(p, around.content.end);
      final atStart = !hasUnits(around.content.location, p);
      if (atEnd) {
        return same ? _caretAt(around.close.end) : insert(around.close.end);
      }
      if (atStart) {
        return same
            ? _caretAt(around.open.location)
            : insert(around.open.location);
      }
      if (!same) return insert(p);
      final besideSpace =
          (before != null && before.isSpace) ||
          (after != null && after.isSpace);
      if (!besideSpace) return null;
      var a = k, z = k;
      while (a > 0 && units[a - 1].isSpace) {
        a -= 1;
      }
      while (z < units.length && units[z].isSpace) {
        z += 1;
      }
      final keys = [
        [
          for (final u in units) {...u.keys},
        ],
      ];
      for (var i = a; i < z; i++) {
        keys[0][i].removeWhere((kk) => _family(kk) == family);
      }
      return _rewrite(
        text,
        [line],
        keys,
        place: (w, at) {
          return Utf16Range(at[0] + w[0].gapAt[k], 0);
        },
      );
    }

    for (final pr in line.pairs) {
      if (!sameFamily(pr)) continue;
      final same = _keyOfKind(pr.kind) == key;
      if (pr.close.end == p) return same ? _caretAt(pr.content.end) : insert(p);
      if (pr.open.location == p) {
        return same ? _caretAt(pr.content.location) : insert(p);
      }
    }
    return insert(p);
  }

  /// Takes every format off the selected words, and the heading or quote mark off the lines.
  /// A caret clears its whole line. Lists and check boxes keep their marks. Null when there
  /// is nothing to clear.
  static TextEdit? clearInline(String text, Utf16Range sel) {
    final lines = _readLines(text, sel);
    final collapsed = sel.length == 0;
    final picked = [
      for (final line in lines)
        [
          for (var i = 0; i < line.units.length; i++)
            if (collapsed ||
                (line.units[i].start < sel.end &&
                    line.units[i].end > sel.location))
              i,
        ],
    ];
    final heads = [
      for (final line in lines)
        switch (line.prefix?.kind) {
          PrefixKind.heading || PrefixKind.quote => '',
          _ => text.substring(line.start, line.bodyStart),
        },
    ];
    final keys = [
      for (var n = 0; n < lines.length; n++)
        [
          for (var i = 0; i < lines[n].units.length; i++)
            picked[n].contains(i) ? <String>{} : {...lines[n].units[i].keys},
        ],
    ];
    return _rewrite(
      text,
      lines,
      keys,
      heads: heads,
      place: (w, at) {
        if (!collapsed) return _over(picked, lines, w, at);
        final line = lines.first;
        return Utf16Range(at[0] + w[0].gapAt[line.boundary(sel.location)], 0);
      },
    );
  }

  /// Makes every touched line a heading of `level` (1 to 6), or a plain line for 0. A quote
  /// becomes a heading. List lines are left alone. Null when nothing changes.
  static TextEdit? setHeading(int level, String text, Utf16Range sel) {
    final lines = _block(text, sel).lines;
    return _transformLines(text, sel, skipBlank: lines.length > 1, (_, line) {
      final p = prefix(line);
      if (p != null && p.isList) return null;
      final isHeading = p?.kind == PrefixKind.heading;
      if (level <= 0) {
        if (!isHeading) return null;
        return (line: line.substring(p!.length), oldHead: p.length, newHead: 0);
      }
      final head = '${'#' * level.clamp(1, 6)} ';
      if (isHeading && p!.level == level.clamp(1, 6)) return null;
      final oldHead = p?.length ?? _leadingSpaces(line);
      return (
        line: head + line.substring(oldHead),
        oldHead: oldHead,
        newHead: head.length,
      );
    });
  }

  // Links.

  static final _scheme = RegExp(r'^https?://', caseSensitive: false);
  static final _goodAddress = RegExp(r'^https?://[^\s()<>\[\]]+$');

  /// The address as it is stored: with `https://` when it has no scheme. Null when it cannot
  /// be a link.
  static String? linkAddress(String url) {
    final t = url.trim();
    if (t.isEmpty) return null;
    final full = _scheme.hasMatch(t) ? t : 'https://$t';
    return _goodAddress.hasMatch(full) ? full : null;
  }

  /// The link whose words hold `pos`, or null.
  static InlinePair? linkAt(String text, int pos) {
    if (pos < 0 || pos > text.length) return null;
    for (final pr in MarkdownSpans.pairs(text, range: Utf16Range(pos, 0))) {
      if (pr.kind.type != SpanType.linkWords) continue;
      if (pr.content.location <= pos && pos <= pr.content.end) return pr;
    }
    return null;
  }

  /// Makes the selected words a link to `url`. At a caret in a link it changes the address;
  /// elsewhere it puts in `[words](url)`, or the address as its own words. The caret ends
  /// after the link. Null when the address cannot be a link.
  static TextEdit? setLink(
    String url,
    String text,
    Utf16Range sel, {
    String? words,
  }) {
    final address = linkAddress(url);
    if (address == null) return null;
    if (sel.length == 0) {
      final p = sel.location;
      final old = linkAt(text, p);
      if (old != null) {
        final close = '](${address.replaceAll(')', '')})';
        return TextEdit(
          range: old.close,
          replacement: close,
          selection: Utf16Range(old.close.location + close.length, 0),
        );
      }
      var shown = _collapse(words ?? '');
      if (shown.isEmpty) shown = address;
      final link = '[$shown]($address)';
      return TextEdit(
        range: sel,
        replacement: link,
        selection: Utf16Range(p + link.length, 0),
      );
    }
    final key = 'l:$address';
    final lines = _readLines(text, sel);
    final keys = <List<Set<String>>>[];
    final picked = <List<int>>[];
    var letters = 0;
    for (final line in lines) {
      final ks = <Set<String>>[];
      final pk = <int>[];
      for (var i = 0; i < line.units.length; i++) {
        final u = line.units[i];
        final k = {...u.keys};
        if (u.start < sel.end && u.end > sel.location) {
          k.removeWhere((x) => x[0] == 'l');
          k.add(key);
          pk.add(i);
          if (!u.isSpace) letters += 1;
        }
        ks.add(k);
      }
      keys.add(ks);
      picked.add(pk);
    }
    if (letters == 0) return null;
    return _rewrite(
      text,
      lines,
      keys,
      place: (w, at) {
        // After the close of the last link.
        for (var n = lines.length - 1; n >= 0; n--) {
          final ks = keys[n];
          for (var i = ks.length - 1; i >= 0; i--) {
            if (ks[i].contains(key) && picked[n].contains(i)) {
              return Utf16Range(at[n] + w[n].gapAt[i + 1], 0);
            }
          }
        }
        return Utf16Range(sel.end, 0);
      },
    );
  }

  /// Newlines and brackets become spaces, runs of spaces one, ends trimmed.
  static String _collapse(String s) =>
      s.replaceAll(RegExp(r'[\s\[\]]+'), ' ').trim();

  /// Takes the link marks off the links the selection touches, or the link at the caret.
  /// The words stay. Null when there is no link.
  static TextEdit? removeLink(String text, Utf16Range sel) {
    final links = <InlinePair>[];
    if (sel.length == 0) {
      final one = linkAt(text, sel.location);
      if (one != null) links.add(one);
    } else {
      for (final pr in MarkdownSpans.pairs(text, range: sel)) {
        if (pr.kind.type != SpanType.linkWords) continue;
        if (pr.whole.location < sel.end && pr.whole.end > sel.location) {
          links.add(pr);
        }
      }
    }
    if (links.isEmpty) return null;
    final from = links.first.whole.location, to = links.last.whole.end;
    final cuts = [
      for (final l in links) ...[l.open, l.close],
    ];
    final out = StringBuffer();
    var at = from;
    for (final c in cuts) {
      out.write(text.substring(at, c.location));
      at = c.end;
    }
    out.write(text.substring(at, to));
    int map(int p) {
      var shift = 0;
      for (final c in cuts) {
        if (c.end <= p) {
          shift += c.length;
        } else if (c.location < p) {
          shift += p - c.location;
        }
      }
      return p - shift;
    }

    final a = map(sel.location), z = map(sel.end);
    return TextEdit(
      range: Utf16Range(from, to - from),
      replacement: out.toString(),
      selection: Utf16Range(a, z - a),
    );
  }

  /// Puts a divider (`---`) on a line of its own at the selection. The caret ends on the
  /// line after it.
  static TextEdit insertDivider(String text, Utf16Range sel) {
    final lead = sel.location > 0 && text.codeUnitAt(sel.location - 1) != 0x0A
        ? '\n'
        : '';
    final nextIsBreak =
        sel.end < text.length && text.codeUnitAt(sel.end) == 0x0A;
    final replacement = '$lead---${nextIsBreak ? '' : '\n'}';
    return TextEdit(
      range: sel,
      replacement: replacement,
      selection: Utf16Range(
        sel.location + replacement.length + (nextIsBreak ? 1 : 0),
        0,
      ),
    );
  }

  // Deleting and typing beside marks.

  static TextEdit _noChange(int p) => _caretAt(p);

  /// What a delete of `change` must really do so marks the reader cannot see stay right.
  /// `selection` is the selection before the key: a caret for Backspace or Delete, or the
  /// range being deleted.
  ///
  /// A key on a mark deletes the nearest letter instead. Deleting every letter of a format
  /// takes its marks too; otherwise its marks stay. Backspace at the start of a line's words
  /// takes the heading or quote mark, moves a list item out, or takes its list mark. A hidden
  /// task mark stays. Null when the plain delete is right.
  static TextEdit? deletion(
    String text,
    Utf16Range change, {
    required Utf16Range selection,
  }) {
    final caret = selection.length == 0;
    final p = selection.location;
    final oneKey =
        caret && change.length > 0 && (change.end == p || change.location == p);
    final backward = oneKey && change.end == p;

    if (oneKey && p >= 0 && p <= text.length) {
      final line = _readLine(text, p);
      // Backspace at the start of the words.
      if (backward &&
          p >= line.bodyStart &&
          p <= line.bodyEnd &&
          !line.units.any((u) => u.start < p)) {
        final pre = line.prefix;
        if (pre != null &&
            (pre.kind == PrefixKind.heading ||
                pre.kind == PrefixKind.quote ||
                pre.indent < 2)) {
          return TextEdit(
            range: Utf16Range(line.start, pre.length),
            replacement: '',
            selection: Utf16Range(line.start + (p - line.bodyStart), 0),
          );
        }
        if (pre != null) {
          return TextEdit(
            range: Utf16Range(line.start, 2),
            replacement: '',
            selection: Utf16Range(p - 2, 0),
          );
        }
        if (line.start == 0) return _noChange(p);
        return _join(text, line, p);
      }
    }
    if (change.location < 0 || change.end > text.length) return null;

    final spans = MarkdownSpans.scan(text, range: change);
    var redirected = false;
    if (oneKey) {
      final d = MarkdownSpans.deletionBesideMark(
        change,
        replacement: '',
        spans: spans,
        text: text,
      );
      if (d == MarkDeletion.swallow) return _noChange(p);
      if (d is MarkRedirect) {
        change = d.range;
        redirected = true;
      }
    }

    final lines = _readLines(text, change);
    final pairs = [for (final l in lines) ...l.pairs];
    final units = [for (final l in lines) ...l.units];
    bool inChange(int i) => change.location <= i && i < change.end;

    // A key on marks only: the nearest letter goes instead.
    if (oneKey && !redirected) {
      final empty = pairs.where(
        (pr) =>
            pr.kind.type == SpanType.emptyPair &&
            pr.whole.location < change.end &&
            change.location < pr.whole.end,
      );
      final onMarks =
          empty.isEmpty &&
          List.generate(
            change.length,
            (i) => change.location + i,
          ).every((i) => lines.any((l) => l.marks.contains(i)));
      if (onMarks) {
        final line = lines.first;
        _Unit? target;
        if (backward) {
          for (final u in line.units) {
            if (u.end <= change.end) target = u;
          }
        } else {
          for (final u in line.units.reversed) {
            if (u.start >= change.location) target = u;
          }
        }
        if (target == null) {
          if (backward) return _noChange(p);
          if (line.bodyEnd < line.end || line.end >= text.length) {
            return _noChange(p);
          }
          return TextEdit(
            range: Utf16Range(line.end, 1),
            replacement: '',
            selection: Utf16Range(p, 0),
          );
        }
        change = Utf16Range(target.start, target.end - target.start);
        redirected = true;
      }
    }

    // What goes: the letters in the change, whole chips, and the marks of formats that lose
    // every letter. Other marks stay. Text outside the words goes as asked.
    final gone = <int>{};
    final allMarks = {for (final l in lines) ...l.marks};
    for (var i = change.location; i < change.end; i++) {
      if (!allMarks.contains(i)) gone.add(i);
    }
    for (final u in units) {
      if (u.start < change.end && change.location < u.end) {
        for (var i = u.start; i < u.end; i++) {
          gone.add(i);
        }
      }
    }
    for (final pr in pairs) {
      final whole = pr.whole;
      if (pr.kind.type == SpanType.emptyPair) {
        if (whole.location < change.end && change.location < whole.end) {
          for (var i = whole.location; i < whole.end; i++) {
            gone.add(i);
          }
        }
        continue;
      }
      final inside = units.where(
        (u) => u.start >= pr.content.location && u.end <= pr.content.end,
      );
      if (inside.isEmpty || !inside.every((u) => gone.contains(u.start))) {
        continue;
      }
      for (final r in [pr.open, pr.close]) {
        for (var i = r.location; i < r.end; i++) {
          gone.add(i);
        }
      }
    }
    if (gone.isEmpty) return _noChange(p);
    final plain =
        !redirected && gone.length == change.length && gone.every(inChange);
    if (plain) return null;

    final sorted = gone.toList()..sort();
    final from = sorted.first, to = sorted.last + 1;
    final kept = StringBuffer();
    var caretAt = from;
    final anchor = change.location;
    for (var i = from; i < to; i++) {
      if (gone.contains(i)) continue;
      kept.writeCharCode(text.codeUnitAt(i));
      if (i < anchor) caretAt += 1;
    }
    return TextEdit(
      range: Utf16Range(from, to - from),
      replacement: kept.toString(),
      selection: Utf16Range(caretAt, 0),
    );
  }

  /// Backspace at the start of a plain line joins it to the line before. When that line
  /// ends with a hidden task mark, the words go before the mark. Null for the plain join.
  static TextEdit? _join(String text, _Line line, int p) {
    final before = _readLine(text, line.start - 1);
    if (before.bodyEnd == before.end) {
      if (p == line.start) return null;
      return TextEdit(
        range: Utf16Range(line.start - 1, 1),
        replacement: '',
        selection: Utf16Range(line.start - 1, 0),
      );
    }
    final mark = text.substring(before.bodyEnd, before.end);
    final words = text.substring(line.start, line.end);
    return TextEdit(
      range: Utf16Range(before.bodyEnd, line.end - before.bodyEnd),
      replacement: words + mark,
      selection: Utf16Range(before.bodyEnd + (p - line.start), 0),
    );
  }

  static const _chainable = {
    SpanType.bold,
    SpanType.italic,
    SpanType.underline,
    SpanType.strike,
    SpanType.highlight,
  };

  /// What typing `typed` at the caret must really do beside marks. A space at the end of a
  /// format goes after its closing marks. A letter after `closing marks + spaces` at the end
  /// of a line pulls the marks forward, so the format goes on; `pull: false` stops that (for
  /// example after the format was turned off). Null when plain typing is right.
  static TextEdit? typed(
    String text,
    Utf16Range sel,
    String typed, {
    bool pull = true,
  }) {
    if (sel.length != 0 || typed.isEmpty) return null;
    final p = sel.location;
    final line = _readLine(text, p);
    if (p < line.bodyStart || p > line.bodyEnd) return null;
    final closers = [
      for (final pr in line.pairs)
        if (_chainable.contains(pr.kind.type)) pr,
    ];

    if (typed == ' ') {
      var q = p;
      var moved = true;
      while (moved) {
        moved = false;
        for (final pr in closers) {
          if (pr.close.location == q) {
            q = pr.close.end;
            moved = true;
          }
        }
      }
      if (q == p) return null;
      return TextEdit(
        range: Utf16Range(q, 0),
        replacement: ' ',
        selection: Utf16Range(q + 1, 0),
      );
    }

    if (!pull || typed.trim().isEmpty) return null;
    if (text.substring(p, line.bodyEnd).trim().isNotEmpty) return null;
    var s = p;
    while (s > line.bodyStart && text[s - 1] == ' ') {
      s -= 1;
    }
    if (s == p) return null;
    var c = s;
    var moved = true;
    while (moved) {
      moved = false;
      for (final pr in closers) {
        if (pr.close.end == c && pr.close.location < c) {
          c = pr.close.location;
          moved = true;
        }
      }
    }
    if (c == s) return null;
    final marks = text.substring(c, s);
    final spaces = text.substring(s, p);
    return TextEdit(
      range: Utf16Range(c, p - c),
      replacement: '$spaces$typed$marks',
      selection: Utf16Range(c + spaces.length + typed.length, 0),
    );
  }
}
