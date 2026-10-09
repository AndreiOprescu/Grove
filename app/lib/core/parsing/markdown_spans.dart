import 'at_date.dart';
import 'markdown_edit.dart';
import 'reference_parser.dart';

export 'utf16_range.dart';

/// The shape of a [SpanKind], without its extra data.
enum SpanType {
  /// A whole heading line, marker included.
  heading,

  /// The `## ` at the start of a heading.
  headingMark,

  /// A whole quote line, marker included.
  quote,
  quoteMark,

  /// Everything before the text of a list line: indent, marker, box and the space after it.
  listPrefix,

  /// The `- ` or `1. ` itself, without the indent.
  listMark,
  checkbox,

  /// The text after a ticked box.
  checkedText,

  /// The text between the markers. The markers are [syntax].
  bold,
  italic,
  code,

  /// Marker characters (`**`, `*`, `` ` ``).
  syntax,

  /// Characters the editor does not show.
  hidden,

  /// A whole `[[Title|ID]]`.
  mention,

  /// A whole `![alt](grove-image:ID)`.
  image,
  tag,

  /// An `@fri 3pm` that can go to the planner.
  atDate,
  link,

  /// The hidden ` ⟦t:ID⟧` that ties a check box line to its task. One unit, never shown.
  taskMark,
}

/// What a piece of a text is. The editor turns each kind into fonts and colours.
final class SpanKind {
  const SpanKind._(
    this.type, {
    this.level = 0,
    this.checked = false,
    this.id,
    this.title,
    this.url,
  });

  const SpanKind.heading(int level) : this._(SpanType.heading, level: level);
  const SpanKind.checkbox({required bool checked})
    : this._(SpanType.checkbox, checked: checked);

  /// `id` is null until the title is resolved.
  const SpanKind.mention({required String title, String? id})
    : this._(SpanType.mention, id: id, title: title);
  const SpanKind.image(String id) : this._(SpanType.image, id: id);
  const SpanKind.link(String url) : this._(SpanType.link, url: url);

  static const headingMark = SpanKind._(SpanType.headingMark);
  static const quote = SpanKind._(SpanType.quote);
  static const quoteMark = SpanKind._(SpanType.quoteMark);
  static const listPrefix = SpanKind._(SpanType.listPrefix);
  static const listMark = SpanKind._(SpanType.listMark);
  static const checkedText = SpanKind._(SpanType.checkedText);
  static const bold = SpanKind._(SpanType.bold);
  static const italic = SpanKind._(SpanType.italic);
  static const code = SpanKind._(SpanType.code);
  static const syntax = SpanKind._(SpanType.syntax);
  static const hidden = SpanKind._(SpanType.hidden);
  static const tag = SpanKind._(SpanType.tag);
  static const atDate = SpanKind._(SpanType.atDate);
  static const taskMark = SpanKind._(SpanType.taskMark);

  final SpanType type;

  /// Heading level, 1 to 6.
  final int level;

  /// The box is ticked.
  final bool checked;

  /// Mention target or image attachment.
  final String? id;

  /// Mention title.
  final String? title;

  /// Link address.
  final String? url;

  @override
  bool operator ==(Object other) =>
      other is SpanKind &&
      other.type == type &&
      other.level == level &&
      other.checked == checked &&
      other.id == id &&
      other.title == title &&
      other.url == url;

  @override
  int get hashCode => Object.hash(type, level, checked, id, title, url);

  @override
  String toString() => 'SpanKind.${type.name}';
}

/// One piece of a text and what it is. The range is UTF-16 offsets in the whole text.
class MarkdownSpan {
  const MarkdownSpan(this.kind, this.range);

  final SpanKind kind;
  final Utf16Range range;

  @override
  bool operator ==(Object other) =>
      other is MarkdownSpan && other.kind == kind && other.range == range;

  @override
  int get hashCode => Object.hash(kind, range);

  @override
  String toString() => '$kind$range';
}

/// What to do with a one-character delete that touches a hidden task mark.
sealed class MarkDeletion {
  const MarkDeletion();

  /// Not next to a mark. Let the editor do its normal work.
  static const unchanged = _Unchanged();

  /// Do nothing.
  static const swallow = _Swallow();

  /// Delete this range instead.
  const factory MarkDeletion.redirect(Utf16Range range) = MarkRedirect;
}

final class _Unchanged extends MarkDeletion {
  const _Unchanged();

  @override
  String toString() => 'MarkDeletion.unchanged';
}

final class _Swallow extends MarkDeletion {
  const _Swallow();

  @override
  String toString() => 'MarkDeletion.swallow';
}

final class MarkRedirect extends MarkDeletion {
  const MarkRedirect(this.range);

  final Utf16Range range;

  @override
  bool operator ==(Object other) =>
      other is MarkRedirect && other.range == range;

  @override
  int get hashCode => range.hashCode;

  @override
  String toString() => 'MarkDeletion.redirect($range)';
}

bool _isBreak(int c) =>
    c == 0x0A || c == 0x0D || c == 0x85 || c == 0x2028 || c == 0x2029;

/// Reads the Markdown that Grove uses and says what each part is. No UI, no state.
/// Nothing crosses a line, so a changed line can be read again alone.
abstract final class MarkdownSpans {
  /// Spans of the lines that touch `range`, or of the whole text. Sorted by position.
  static List<MarkdownSpan> scan(String text, {Utf16Range? range}) {
    if (text.isEmpty) return const [];
    var target = Utf16Range(0, text.length);
    if (range != null) {
      final loc = range.location.clamp(0, text.length);
      final len = range.length.clamp(0, text.length - loc);
      target = lineRange(text, Utf16Range(loc, len));
    }

    final out = <MarkdownSpan>[];
    // Each line without its break, like `enumerateSubstrings(.byLines)`.
    var start = target.location;
    while (start < target.end) {
      var end = start;
      while (end < target.end && !_isBreak(text.codeUnitAt(end))) {
        end += 1;
      }
      _scanLine(text.substring(start, end), start, out);
      if (end >= target.end) break;
      final crlf =
          text.codeUnitAt(end) == 0x0D &&
          end + 1 < text.length &&
          text.codeUnitAt(end + 1) == 0x0A;
      start = end + (crlf ? 2 : 1);
    }

    // A stable sort by position: spans at the same place keep the order they were found in.
    final order = List<int>.generate(out.length, (i) => i)
      ..sort((a, b) {
        final byLocation = out[a].range.location.compareTo(
          out[b].range.location,
        );
        return byLocation != 0 ? byLocation : a.compareTo(b);
      });
    return [for (final i in order) out[i]];
  }

  // Chips.

  /// Mentions, images and task marks. The editor treats each as one character.
  static List<Utf16Range> atoms(List<MarkdownSpan> spans) => [
    for (final s in spans)
      if (s.kind.type == SpanType.mention ||
          s.kind.type == SpanType.image ||
          s.kind.type == SpanType.taskMark)
        s.range,
  ];

  /// Moves a selection out of the middle of a chip. A caret goes to the edge it moves towards;
  /// a range grows to take whole chips.
  static Utf16Range snapped(
    Utf16Range selection,
    List<MarkdownSpan> spans, {
    bool movingForward = true,
  }) {
    final all = atoms(spans);
    Utf16Range? inside(int p) {
      for (final a in all) {
        if (a.location < p && p < a.end) return a;
      }
      return null;
    }

    if (selection.length == 0) {
      final a = inside(selection.location);
      if (a == null) return selection;
      return Utf16Range(movingForward ? a.end : a.location, 0);
    }
    final start = inside(selection.location)?.location ?? selection.location;
    final end = inside(selection.end)?.end ?? selection.end;
    return Utf16Range(start, end - start);
  }

  /// The range an edit must really replace: a change that touches part of a chip takes all of it.
  /// Typing inside a chip lands after it.
  static Utf16Range expanded(Utf16Range change, List<MarkdownSpan> spans) {
    final all = atoms(spans);
    if (change.length == 0) {
      for (final a in all) {
        if (a.location < change.location && change.location < a.end) {
          return Utf16Range(a.end, 0);
        }
      }
      return change;
    }
    var start = change.location, end = change.end;
    for (final a in all) {
      if (a.location < end && start < a.end) {
        if (a.location < start) start = a.location;
        if (a.end > end) end = a.end;
      }
    }
    return Utf16Range(start, end - start);
  }

  /// Backspace after a mark and forward delete before it would remove the mark, which the user
  /// cannot see. The mark stays. The key deletes the visible character on the other side.
  static MarkDeletion deletionBesideMark(
    Utf16Range change, {
    required String replacement,
    required List<MarkdownSpan> spans,
    required String text,
  }) {
    if (replacement.isNotEmpty || change.length != 1) {
      return MarkDeletion.unchanged;
    }
    for (final span in spans) {
      if (span.kind != SpanKind.taskMark) continue;
      final mark = span.range;
      if (change.end == mark.end) {
        // Backspace at the end of the mark. The first character the user can reach is before it.
        final line = lineRange(text, Utf16Range(mark.location, 0));
        var floor = line.location;
        for (final p in spans) {
          if (p.kind == SpanKind.listPrefix &&
              p.range.location == line.location) {
            floor = p.range.end;
            break;
          }
        }
        return mark.location > floor
            ? MarkDeletion.redirect(Utf16Range(mark.location - 1, 1))
            : MarkDeletion.swallow;
      }
      if (change.location == mark.location) {
        // Forward delete at the start of the mark. The next character is after it.
        return mark.end < text.length
            ? MarkDeletion.redirect(Utf16Range(mark.end, 1))
            : MarkDeletion.swallow;
      }
    }
    return MarkDeletion.unchanged;
  }

  // One line.

  static final _prefixRegex = RegExp(MarkdownEdit.prefixPattern);
  static final _codeRegex = RegExp(r'`([^`\n]+)`');
  static const _uuid =
      '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}';
  static final _imageRegex = RegExp(
    '!\\[([^\\]\\n]*)\\]\\(grove-image:($_uuid)\\)',
  );
  static final _markRegex = RegExp(r'\s?⟦t:[^⟧\s]+⟧');
  static final _linkRegex = RegExp(r'https?://[^\s<>\[\]]+');
  static final _tagRegex = RegExp(
    r'(?<![\p{L}\p{N}_#&/])#[\p{L}\p{N}_][\p{L}\p{N}_-]*',
    unicode: true,
  );
  static final _tripleRegex = RegExp(
    r'(?<!\*)\*\*\*(?![\s*])(.+?)(?<![\s*])\*\*\*(?!\*)',
  );
  static final _boldRegex = RegExp(
    r'(?<!\*)\*\*(?![\s*])(.+?)(?<![\s*])\*\*(?!\*)',
  );
  static final _italicRegex = RegExp(
    r'(?<!\*)\*(?![\s*])(.+?)(?<![\s*])\*(?!\*)',
  );

  static const _placeholder = '';
  static const _linkTail = '.,;:!?)\'"';

  static void _scanLine(String line, int base, List<MarkdownSpan> out) {
    if (line.isEmpty) return;
    final found = <MarkdownSpan>[];
    void add(SpanKind kind, int loc, int len) {
      if (len <= 0) return;
      found.add(MarkdownSpan(kind, Utf16Range(base + loc, len)));
    }

    var bodyStart = 0;
    final p = _prefixRegex.firstMatch(line);
    if (p != null) {
      bodyStart = p.end;
      final indent = p.group(1)!.length;
      if (p.group(2) != null) {
        final checked = p.group(3) != ' ';
        add(SpanKind.listPrefix, 0, bodyStart);
        add(SpanKind.listMark, indent, 2);
        add(SpanKind.checkbox(checked: checked), indent + 2, 3);
        if (checked) {
          add(SpanKind.checkedText, bodyStart, line.length - bodyStart);
        }
      } else if (p.group(4) != null || p.group(5) != null) {
        add(SpanKind.listPrefix, 0, bodyStart);
        add(SpanKind.listMark, indent, bodyStart - indent);
      } else if (p.group(6) != null) {
        add(SpanKind.heading(p.group(6)!.length), 0, line.length);
        add(SpanKind.headingMark, 0, bodyStart);
      } else {
        add(SpanKind.quote, 0, line.length);
        add(SpanKind.quoteMark, 0, bodyStart);
      }
    }

    // Markers are read on a copy where finished pieces are blanked, so they cannot be read twice.
    var masked = line;
    void mask(int start, int end) {
      masked = masked.replaceRange(start, end, _placeholder * (end - start));
    }

    // Matches in the body only, offset to the line. Like NSRegularExpression with a range,
    // a look-behind cannot see the list marker before the body.
    List<({int start, int end, List<String?> groups})> inBody(RegExp r) => [
      for (final m in r.allMatches(masked.substring(bodyStart)))
        (
          start: m.start + bodyStart,
          end: m.end + bodyStart,
          groups: [for (var g = 1; g <= m.groupCount; g++) m.group(g)],
        ),
    ];

    for (final m in inBody(_codeRegex)) {
      add(SpanKind.code, m.start + 1, m.groups[0]!.length);
      add(SpanKind.syntax, m.start, 1);
      add(SpanKind.syntax, m.end - 1, 1);
      mask(m.start, m.end);
    }

    for (final m in inBody(_imageRegex)) {
      final altEnd = m.start + 2 + m.groups[0]!.length;
      add(SpanKind.image(m.groups[1]!), m.start, m.end - m.start);
      if (m.groups[0]!.isNotEmpty) {
        add(SpanKind.hidden, m.start, 2);
        add(SpanKind.hidden, altEnd, m.end - altEnd);
      } else {
        add(SpanKind.hidden, altEnd + 1, m.end - altEnd - 1);
      }
      mask(m.start, m.end);
    }

    if (line.contains('⟦t:')) {
      for (final m in inBody(_markRegex)) {
        add(SpanKind.taskMark, m.start, m.end - m.start);
        mask(m.start, m.end);
      }
    }

    if (masked.contains('[[')) {
      final text = masked;
      for (final m in ReferenceParser.mentions(text)) {
        if (m.start < bodyStart) continue;
        add(
          SpanKind.mention(title: m.title, id: m.id),
          m.start,
          m.end - m.start,
        );
        add(SpanKind.hidden, m.start, 2);
        if (m.id != null) {
          final bar = text.lastIndexOf('|', m.end - 1);
          add(SpanKind.hidden, bar, m.end - bar);
        } else {
          add(SpanKind.hidden, m.end - 2, 2);
        }
        mask(m.start, m.end);
      }
    }

    for (final m in inBody(_linkRegex)) {
      var end = m.end;
      while (end - m.start > 1 && _linkTail.contains(masked[end - 1])) {
        end -= 1;
      }
      add(
        SpanKind.link(masked.substring(m.start, end)),
        m.start,
        end - m.start,
      );
      mask(m.start, end);
    }

    for (final m in inBody(_tagRegex)) {
      add(SpanKind.tag, m.start, m.end - m.start);
    }

    if (line.contains('@')) {
      final hit = AtDateParser.find(masked);
      if (hit != null && hit.range.location >= bodyStart) {
        add(SpanKind.atDate, hit.range.location, hit.range.length);
      }
    }

    for (final m in inBody(_tripleRegex)) {
      final len = m.groups[0]!.length;
      add(SpanKind.bold, m.start + 3, len);
      add(SpanKind.italic, m.start + 3, len);
      add(SpanKind.syntax, m.start, 3);
      add(SpanKind.syntax, m.end - 3, 3);
    }
    for (final m in inBody(_boldRegex)) {
      add(SpanKind.bold, m.start + 2, m.groups[0]!.length);
      add(SpanKind.syntax, m.start, 2);
      add(SpanKind.syntax, m.end - 2, 2);
    }
    for (final m in inBody(_italicRegex)) {
      add(SpanKind.italic, m.start + 1, m.groups[0]!.length);
      add(SpanKind.syntax, m.start, 1);
      add(SpanKind.syntax, m.end - 1, 1);
    }

    out.addAll(found);
  }
}
