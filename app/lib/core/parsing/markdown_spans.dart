import 'at_date.dart';
import 'markdown_edit.dart';
import 'reference_parser.dart';

export 'utf16_range.dart';

/// The shape of a [SpanKind], without its extra data.
enum SpanType {
  /// A whole heading line, marker included.
  heading,

  /// A line that is only `---`.
  divider,

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

  /// `~~x~~`.
  strike,

  /// `<u>x</u>`.
  underline,

  /// `==x==` or `=={green}x==`. The colour is in [SpanKind.color].
  highlight,

  /// The words of `[words](https://…)`. The address is in [SpanKind.url].
  linkWords,

  /// A pair of marks with nothing between them, like `****`. The format is in [SpanKind.format].
  emptyPair,

  /// Marker characters (`**`, `*`, `` ` ``, `~~`, `==`, `<u>`, `[`, `](…)`).
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

/// The colours a highlight can have. Yellow is `==x==`, the others `=={green}x==`.
enum HighlightColor { yellow, green, blue, pink }

/// The formats a format button puts on words.
enum InlineFormat { bold, italic, underline, strike, highlight, code }

/// What a piece of a text is. The editor turns each kind into fonts and colours.
final class SpanKind {
  const SpanKind._(
    this.type, {
    this.level = 0,
    this.checked = false,
    this.id,
    this.title,
    this.url,
    this.color,
    this.format,
  });

  const SpanKind.heading(int level) : this._(SpanType.heading, level: level);
  const SpanKind.checkbox({required bool checked})
    : this._(SpanType.checkbox, checked: checked);

  /// `id` is null until the title is resolved.
  const SpanKind.mention({required String title, String? id})
    : this._(SpanType.mention, id: id, title: title);
  const SpanKind.image(String id) : this._(SpanType.image, id: id);
  const SpanKind.link(String url) : this._(SpanType.link, url: url);
  const SpanKind.linkWords(String url) : this._(SpanType.linkWords, url: url);
  const SpanKind.highlight([HighlightColor color = HighlightColor.yellow])
    : this._(SpanType.highlight, color: color);
  const SpanKind.emptyPair(
    InlineFormat format, [
    HighlightColor color = HighlightColor.yellow,
  ]) : this._(SpanType.emptyPair, format: format, color: color);

  static const headingMark = SpanKind._(SpanType.headingMark);
  static const quote = SpanKind._(SpanType.quote);
  static const quoteMark = SpanKind._(SpanType.quoteMark);
  static const listPrefix = SpanKind._(SpanType.listPrefix);
  static const listMark = SpanKind._(SpanType.listMark);
  static const checkedText = SpanKind._(SpanType.checkedText);
  static const bold = SpanKind._(SpanType.bold);
  static const italic = SpanKind._(SpanType.italic);
  static const code = SpanKind._(SpanType.code);
  static const strike = SpanKind._(SpanType.strike);
  static const underline = SpanKind._(SpanType.underline);
  static const divider = SpanKind._(SpanType.divider);
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

  /// Highlight colour.
  final HighlightColor? color;

  /// The format of an empty pair.
  final InlineFormat? format;

  @override
  bool operator ==(Object other) =>
      other is SpanKind &&
      other.type == type &&
      other.level == level &&
      other.checked == checked &&
      other.id == id &&
      other.title == title &&
      other.url == url &&
      other.color == color &&
      other.format == format;

  @override
  int get hashCode =>
      Object.hash(type, level, checked, id, title, url, color, format);

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

/// A format and where its marks are: `open` and `close` are the marks, `content` is what is
/// between them. Ranges are UTF-16 offsets in the whole text.
class InlinePair {
  const InlinePair(
    this.kind, {
    required this.open,
    required this.content,
    required this.close,
  });

  /// [SpanKind.bold], [SpanKind.italic], [SpanKind.strike], [SpanKind.underline],
  /// [SpanKind.highlight], [SpanKind.code], [SpanKind.linkWords] or [SpanKind.emptyPair].
  final SpanKind kind;
  final Utf16Range open;
  final Utf16Range content;
  final Utf16Range close;

  /// From the first character of `open` to the last of `close`.
  Utf16Range get whole => Utf16Range(open.location, close.end - open.location);

  @override
  bool operator ==(Object other) =>
      other is InlinePair &&
      other.kind == kind &&
      other.open == open &&
      other.content == content &&
      other.close == close;

  @override
  int get hashCode => Object.hash(kind, open, content, close);

  @override
  String toString() => 'InlinePair($kind, $open, $content, $close)';
}

/// A run of the same mark character, or a `<u>` / `</u>` tag, while the formats are matched.
class _Run {
  _Run(
    this.char,
    this.start,
    this.end, {
    required this.canOpen,
    required this.canClose,
    this.color,
    this.tokenEnd,
  }) : lo = start,
       hi = end;

  /// `*`, `~`, `=`, or `u` for the tags.
  final String char;
  final int start, end;
  final bool canOpen, canClose;

  /// The `{green}` after a `==` run, and where it ends.
  final HighlightColor? color;
  final int? tokenEnd;

  /// The characters not used yet: `[lo, hi)`.
  int lo, hi;

  int get left => hi - lo;
  int get length => end - start;
  bool get untouched => lo == start && hi == end;
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
    final out = <MarkdownSpan>[];
    _scan(text, range, out, null);
    return _sorted(out, (s) => s.range.location);
  }

  /// Every format of the lines that touch `range`, or of the whole text, with its marks.
  /// Sorted by where the opening mark starts.
  static List<InlinePair> pairs(String text, {Utf16Range? range}) {
    final out = <InlinePair>[];
    _scan(text, range, <MarkdownSpan>[], out);
    return _sorted(out, (p) => p.open.location);
  }

  /// A stable sort by position: items at the same place keep the order they were found in.
  static List<T> _sorted<T>(List<T> items, int Function(T) at) {
    final order = List<int>.generate(items.length, (i) => i)
      ..sort((a, b) {
        final byLocation = at(items[a]).compareTo(at(items[b]));
        return byLocation != 0 ? byLocation : a.compareTo(b);
      });
    return [for (final i in order) items[i]];
  }

  static void _scan(
    String text,
    Utf16Range? range,
    List<MarkdownSpan> out,
    List<InlinePair>? pairs,
  ) {
    if (text.isEmpty) return;
    var target = Utf16Range(0, text.length);
    if (range != null) {
      final loc = range.location.clamp(0, text.length);
      final len = range.length.clamp(0, text.length - loc);
      target = lineRange(text, Utf16Range(loc, len));
    }

    // Each line without its break, like `enumerateSubstrings(.byLines)`.
    var start = target.location;
    while (start < target.end) {
      var end = start;
      while (end < target.end && !_isBreak(text.codeUnitAt(end))) {
        end += 1;
      }
      _scanLine(text.substring(start, end), start, out, pairs);
      if (end >= target.end) break;
      final crlf =
          text.codeUnitAt(end) == 0x0D &&
          end + 1 < text.length &&
          text.codeUnitAt(end + 1) == 0x0A;
      start = end + (crlf ? 2 : 1);
    }
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
  static final _linkWordsRegex = RegExp(
    r'(?<![!\[])\[([^\[\]\n]+)\]\((https?://[^\s()<>\[\]]+)\)',
  );
  static final _spaceRegex = RegExp(r'\s');
  static const _colors = {
    '{green}': HighlightColor.green,
    '{blue}': HighlightColor.blue,
    '{pink}': HighlightColor.pink,
  };

  static const _placeholder = '';
  static const _linkTail = '.,;:!?)\'"';

  static void _scanLine(
    String line,
    int base,
    List<MarkdownSpan> out,
    List<InlinePair>? pairs,
  ) {
    if (line.isEmpty) return;
    final found = <MarkdownSpan>[];
    void add(SpanKind kind, int loc, int len) {
      if (len <= 0) return;
      found.add(MarkdownSpan(kind, Utf16Range(base + loc, len)));
    }

    void pair(SpanKind kind, int open, int from, int to, int closeEnd) {
      pairs?.add(
        InlinePair(
          kind,
          open: Utf16Range(base + open, from - open),
          content: Utf16Range(base + from, to - from),
          close: Utf16Range(base + to, closeEnd - to),
        ),
      );
    }

    if (line == '---') {
      add(SpanKind.divider, 0, 3);
      out.addAll(found);
      return;
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
      pair(SpanKind.code, m.start, m.start + 1, m.end - 1, m.end);
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

    // Links with words. Only the marks are masked: the words can have formats.
    final linkWords = <(int, int)>[];
    final linkMarks = <int>{};
    for (final m in inBody(_linkWordsRegex)) {
      final from = m.start + 1, to = from + m.groups[0]!.length;
      final kind = SpanKind.linkWords(m.groups[1]!);
      add(kind, from, to - from);
      add(SpanKind.syntax, m.start, 1);
      add(SpanKind.syntax, to, m.end - to);
      pair(kind, m.start, from, to, m.end);
      linkWords.add((from, to));
      linkMarks
        ..add(m.start)
        ..addAll([for (var i = to; i < m.end; i++) i]);
      mask(m.start, from);
      mask(to, m.end);
    }

    for (final m in inBody(_linkRegex)) {
      if (linkWords.any((w) => w.$1 <= m.start && m.start < w.$2)) continue;
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

    _scanFormats(masked, bodyStart, linkWords, add, pair);

    out.addAll(found);
  }

  static bool _isSpace(String s, int i) =>
      i < 0 || i >= s.length || _spaceRegex.hasMatch(s[i]);

  /// Bold, italic, strike, underline and highlight, by matching runs of marks the way
  /// CommonMark matches `*`: a run can open when a letter follows it and close when a letter
  /// comes before it. `~~` and `==` always use two marks. Formats inside the words of a link
  /// are matched on their own, so no format crosses the edge of a link.
  static void _scanFormats(
    String line,
    int bodyStart,
    List<(int, int)> linkWords,
    void Function(SpanKind kind, int loc, int len) add,
    void Function(SpanKind kind, int open, int from, int to, int closeEnd) pair,
  ) {
    final runs = <_Run>[];
    var i = bodyStart;
    while (i < line.length) {
      final c = line[i];
      if (c == '<' && line.startsWith('<u>', i)) {
        runs.add(_Run('u', i, i + 3, canOpen: true, canClose: false));
        i += 3;
        continue;
      }
      if (c == '<' && line.startsWith('</u>', i)) {
        runs.add(_Run('u', i, i + 4, canOpen: false, canClose: true));
        i += 4;
        continue;
      }
      if (c != '*' && c != '~' && c != '=') {
        i += 1;
        continue;
      }
      var end = i;
      while (end < line.length && line[end] == c) {
        end += 1;
      }
      HighlightColor? color;
      int? tokenEnd;
      if (c == '=') {
        for (final e in _colors.entries) {
          if (line.startsWith(e.key, end)) {
            color = e.value;
            tokenEnd = end + e.key.length;
          }
        }
      }
      runs.add(
        _Run(
          c,
          i,
          end,
          canOpen: !_isSpace(line, tokenEnd ?? end),
          canClose: i > bodyStart && !_isSpace(line, i - 1),
          color: color,
          tokenEnd: tokenEnd,
        ),
      );
      i = end;
    }
    if (runs.isEmpty) return;

    // Matched pairs as (kind, opener run, open start, open end, close start, closer run, close end).
    final matched =
        <
          ({
            String char,
            int use,
            _Run opener,
            int open,
            int from,
            int to,
            _Run closer,
            int closeEnd,
          })
        >[];
    void match(List<_Run> scope) {
      final stack = <_Run>[];
      for (final r in scope) {
        if (r.canClose) {
          while (r.left > 0) {
            var at = stack.length - 1;
            for (; at >= 0; at--) {
              final o = stack[at];
              if (o.char != r.char) continue;
              if (r.char == '*') {
                final both = o.canClose || r.canOpen;
                if (both &&
                    (o.length + r.length) % 3 == 0 &&
                    !(o.length % 3 == 0 && r.length % 3 == 0)) {
                  continue;
                }
                break;
              }
              if (r.char == 'u') break;
              if (o.left >= 2 && r.left >= 2) break;
            }
            if (at < 0) break;
            final o = stack[at];
            final use = switch (r.char) {
              '*' => o.left >= 2 && r.left >= 2 ? 2 : 1,
              'u' => 0,
              _ => 2,
            };
            final int open, from, to, closeEnd;
            if (r.char == 'u') {
              open = o.start;
              from = o.end;
              to = r.start;
              closeEnd = r.end;
              o.lo = o.hi;
              r.lo = r.hi;
            } else {
              final atRunEnd = o.hi == o.end;
              open = o.hi - use;
              from = atRunEnd && o.tokenEnd != null ? o.tokenEnd! : o.hi;
              o.hi -= use;
              to = r.lo;
              closeEnd = r.lo + use;
              r.lo += use;
            }
            matched.add((
              char: r.char,
              use: use,
              opener: o,
              open: open,
              from: from,
              to: to,
              closer: r,
              closeEnd: closeEnd,
            ));
            stack.removeRange(at + 1, stack.length);
            if (o.left == 0) stack.removeAt(at);
          }
        }
        if (r.canOpen && r.left > 0) stack.add(r);
      }
    }

    int scopeOf(_Run r) {
      for (var k = 0; k < linkWords.length; k++) {
        if (linkWords[k].$1 <= r.start && r.end <= linkWords[k].$2) return k;
      }
      return -1;
    }

    for (var k = 0; k < linkWords.length; k++) {
      match([
        for (final r in runs)
          if (scopeOf(r) == k) r,
      ]);
    }
    match([
      for (final r in runs)
        if (scopeOf(r) == -1) r,
    ]);

    // The marks that were used, run by run, so marks that touch read as one piece.
    final used = <int>{};
    for (final m in matched) {
      for (var k = m.open; k < m.from; k++) {
        used.add(k);
      }
      for (var k = m.to; k < m.closeEnd; k++) {
        used.add(k);
      }
    }

    InlineFormat formatOf(String char, int use) => switch (char) {
      '*' => use == 2 ? InlineFormat.bold : InlineFormat.italic,
      '~' => InlineFormat.strike,
      '=' => InlineFormat.highlight,
      _ => InlineFormat.underline,
    };
    SpanKind kindOf(InlineFormat f, HighlightColor color) => switch (f) {
      InlineFormat.bold => SpanKind.bold,
      InlineFormat.italic => SpanKind.italic,
      InlineFormat.strike => SpanKind.strike,
      InlineFormat.underline => SpanKind.underline,
      _ => SpanKind.highlight(color),
    };

    for (final m in matched) {
      final format = formatOf(m.char, m.use);
      final color = m.from > m.open + m.use && m.char == '='
          ? m.opener.color!
          : HighlightColor.yellow;
      if (m.from == m.to) {
        final kind = SpanKind.emptyPair(format, color);
        add(kind, m.open, m.closeEnd - m.open);
        pair(kind, m.open, m.from, m.to, m.closeEnd);
        continue;
      }
      final kind = kindOf(format, color);
      // The words start after the whole opening run and end before the whole closing run,
      // so `***a*b**` reads as bold `a*b` and italic `a`.
      final runEnd = m.char == 'u'
          ? m.opener.end
          : (m.opener.tokenEnd ?? m.opener.end);
      final from = m.from > runEnd ? m.from : runEnd;
      final to = m.to < m.closer.start ? m.to : m.closer.start;
      add(kind, from, to - from);
      pair(kind, m.open, m.from, m.to, m.closeEnd);
    }

    // Runs of four that were never used are empty pairs: `****`, `~~~~`, `====`.
    for (final r in runs) {
      if (r.char == 'u' || !r.untouched || r.length != 4) continue;
      final format = formatOf(r.char, 2);
      final kind = SpanKind.emptyPair(format);
      add(kind, r.start, 4);
      pair(kind, r.start, r.start + 2, r.start + 2, r.end);
      for (var k = r.start; k < r.end; k++) {
        used.add(k);
      }
    }

    final marks = used.toList()..sort();
    var k = 0;
    while (k < marks.length) {
      var e = k + 1;
      while (e < marks.length && marks[e] == marks[e - 1] + 1) {
        e += 1;
      }
      add(SpanKind.syntax, marks[k], marks[e - 1] + 1 - marks[k]);
      k = e;
    }
  }
}
