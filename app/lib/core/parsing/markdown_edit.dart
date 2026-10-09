import 'note_parser.dart';
import 'reference_parser.dart';
import 'utf16_range.dart';

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
}
