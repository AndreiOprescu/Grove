/// One `[[Title]]` or `[[Title|ID]]` found in a text.
class Mention {
  const Mention({
    required this.title,
    required this.start,
    required this.end,
    this.id,
  });

  final String title;

  /// The target's id, when the text carries one (`[[Title|ID]]`).
  final String? id;

  /// UTF-16 offsets that cover the whole `[[…]]` in the text it was parsed from.
  final int start;
  final int end;
}

/// Reads and writes the text forms Grove uses inside task bodies, notes and event notes:
/// mentions (`[[Title|ID]]`), images (`![alt](grove-image:ID)`) and hidden task markers (`⟦t:ID⟧`).
abstract final class ReferenceParser {
  static const _uuid =
      '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}';
  static final _mentionRegex = RegExp(r'\[\[([^\[\]\n]+)\]\]');
  static final _idRegex = RegExp('^$_uuid\$');
  static final _imageRegex = RegExp(
    '!\\[([^\\]\\n]*)\\]\\(grove-image:($_uuid)\\)',
  );
  static final _markerRegex = RegExp(r'\s?⟦t:[^⟧]*⟧');

  // Mentions.

  static List<Mention> mentions(String text) => [
    for (final m in _mentionRegex.allMatches(text))
      if (_split(m.group(1)!) case final parts?)
        Mention(title: parts.title, id: parts.id, start: m.start, end: m.end),
  ];

  /// The text for a mention. Characters that would break the syntax become spaces.
  static String mention({required String title, String? id}) {
    final clean = _collapse(title, '[]|');
    final shown = clean.isEmpty ? 'Untitled' : clean;
    return id == null ? '[[$shown]]' : '[[$shown|$id]]';
  }

  /// Changes the title of every mention that points at `id`. Other text is untouched.
  static String rewriting(
    String text, {
    required String id,
    required String title,
  }) {
    var out = text;
    for (final m in mentions(text).reversed) {
      if (m.id != id) continue;
      out = out.replaceRange(m.start, m.end, mention(title: title, id: id));
    }
    return out;
  }

  static ({String title, String? id})? _split(String inner) {
    var title = inner;
    String? id;
    final bar = inner.lastIndexOf('|');
    if (bar >= 0) {
      final tail = inner.substring(bar + 1).trim();
      if (_idRegex.hasMatch(tail)) {
        id = tail;
        title = inner.substring(0, bar);
      }
    }
    final trimmed = title.trim();
    return trimmed.isEmpty ? null : (title: trimmed, id: id);
  }

  // Images.

  /// Attachment ids used by a text, in order, without repeats.
  static List<String> imageIds(String text) {
    final seen = <String>{};
    return [
      for (final m in _imageRegex.allMatches(text))
        if (seen.add(m.group(2)!)) m.group(2)!,
    ];
  }

  static String imageMarkup({required String id, required String alt}) =>
      '![${_collapse(alt, '[]')}](grove-image:$id)';

  // Search.

  /// The words of a text without ids and markup, so a search cannot hit a UUID.
  static String searchText(String text) {
    var out = text.replaceAllMapped(_imageRegex, (m) => m.group(1) ?? '');
    for (final m in mentions(out).reversed) {
      out = out.replaceRange(m.start, m.end, m.title);
    }
    return out.replaceAll(_markerRegex, '');
  }

  static final _space = RegExp(r'\s');

  /// Newlines and the given characters become spaces; runs of spaces become one; ends are trimmed.
  static String _collapse(String s, String bad) {
    final spaced = s.split('').map((c) {
      return _space.hasMatch(c) || bad.contains(c) ? ' ' : c;
    }).join();
    return spaced.split(' ').where((w) => w.isNotEmpty).join(' ');
  }
}
