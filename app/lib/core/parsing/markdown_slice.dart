part of 'markdown_edit.dart';

/// A part of a text as Markdown, for copy and paste inside Grove.
abstract final class MarkdownSlice {
  /// The Markdown of the words in `range`. A format that the range cuts
  /// through closes at the edges of the range, so each piece keeps its look.
  /// A mention or an image is taken whole. A line keeps its line mark when
  /// the range takes all its words, or when it is not the first line. The
  /// hidden task mark is left out: a pasted box line makes a task of its own.
  static String of(String text, Utf16Range range) {
    final from = range.location.clamp(0, text.length);
    final to = range.end.clamp(from, text.length);
    if (from == to) return '';
    final lines = MarkdownEdit._readLines(text, Utf16Range(from, to - from));
    final out = StringBuffer();
    for (var n = 0; n < lines.length; n++) {
      final line = lines[n];
      if (n > 0) out.write(text.substring(lines[n - 1].end, line.start));
      final a = from > line.start ? from : line.start;
      final z = to < line.end ? to : line.end;
      final whole = a <= line.bodyStart && z >= line.bodyEnd;
      if (n > 0 || whole) out.write(text.substring(line.start, line.bodyStart));
      final units = [
        for (final u in line.units)
          if (u.start < z && u.end > a) u,
      ];
      final keys = [
        for (final u in units) {...u.keys},
      ];
      MarkdownEdit._trim(units, keys);
      out.write(MarkdownEdit._write(units, keys).body);
    }
    final last = lines.last.end;
    if (to > last) out.write(text.substring(last, to));
    return out.toString();
  }
}
