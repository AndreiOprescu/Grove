import 'markdown_spans.dart';

/// The words of a text as a reader sees them, without the marks of the formats.
abstract final class MarkdownPlain {
  /// Takes out the marks of bold, italic, code, strike, underline, highlight and links, the
  /// marks of headings and quotes, empty pairs and hidden task marks. A link keeps its words,
  /// a mention its title, an image its alt text. A divider line becomes empty. List marks,
  /// `#tags` and `/list` words stay.
  static String text(String text) {
    if (text.isEmpty) return text;
    // What to put in place of each range. Ranges never overlap once sorted.
    final cuts = <(Utf16Range, String)>[];
    for (final s in MarkdownSpans.scan(text)) {
      final r = s.range;
      switch (s.kind.type) {
        case SpanType.syntax ||
            SpanType.headingMark ||
            SpanType.quoteMark ||
            SpanType.emptyPair ||
            SpanType.taskMark ||
            SpanType.divider:
          cuts.add((r, ''));
        case SpanType.mention:
          cuts.add((r, s.kind.title ?? ''));
        case SpanType.image:
          final close = text.indexOf(']', r.location + 2);
          cuts.add((r, text.substring(r.location + 2, close)));
        default:
          break;
      }
    }
    cuts.sort((a, b) => a.$1.location.compareTo(b.$1.location));
    final out = StringBuffer();
    var at = 0;
    for (final (r, put) in cuts) {
      if (r.location < at) continue;
      out
        ..write(text.substring(at, r.location))
        ..write(put);
      at = r.end;
    }
    out.write(text.substring(at));
    return out.toString();
  }
}
