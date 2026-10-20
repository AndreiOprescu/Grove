/// One `- [ ] text` line of a note.
class NoteCheckbox {
  const NoteCheckbox({
    required this.line,
    required this.checked,
    required this.text,
    this.taskId,
  });

  /// Index of the line in the text, from 0.
  final int line;
  final bool checked;

  /// The words after the box, without the hidden task marker.
  final String text;

  /// The task this line made, read from the hidden marker. Null until a task exists.
  final String? taskId;

  @override
  bool operator ==(Object other) =>
      other is NoteCheckbox &&
      other.line == line &&
      other.checked == checked &&
      other.text == text &&
      other.taskId == taskId;

  @override
  int get hashCode => Object.hash(line, checked, text, taskId);
}

/// A Unicode word letter, like `\w` in the Swift (ICU) regexes.
/// Dart's own `\w` is ASCII only. Use with `unicode: true`.
const wordChar = '[$wordLetters]';

/// The inside of [wordChar], for building bigger character classes.
const wordLetters = r'\p{L}\p{M}\p{Nd}\p{Pc}';

/// What the app reads out of a note's text: `#tags` and check box lines.
abstract final class NoteParser {
  // Tags.

  static final _tagRegex = RegExp(
    '(?<![$wordLetters#&/\\[\\]])#([A-Za-z]$wordChar*(?:-$wordChar+)*)',
    unicode: true,
  );

  /// Spans that never hold a tag: code, `[[mentions]]` and links or images.
  static final _skipRegexes = [
    RegExp(r'`[^`\n]*`'),
    RegExp(r'\[\[[^\]\n]*\]\]'),
    RegExp(r'!?\[[^\]\n]*\]\([^)\n]*\)'),
  ];

  /// The `#tags` in a text, each once (letter case ignored), in the order they first appear.
  static List<String> tags(String text) {
    var clean = text;
    for (final r in _skipRegexes) {
      clean = clean.replaceAll(r, ' ');
    }
    final seen = <String>{};
    final out = <String>[];
    for (final m in _tagRegex.allMatches(clean)) {
      final tag = m.group(1)!;
      if (seen.add(tag.toLowerCase())) out.add(tag);
    }
    return out;
  }

  // Check boxes.

  static final _boxRegex = RegExp(r'^(\s*- \[)([ xX])(\]\s+)(.*)$');
  static final _markerRegex = RegExp(r'\s?⟦t:([^⟧\s]+)⟧');

  /// The hidden text that ties a line to its task.
  static String marker(String taskId) => '⟦t:$taskId⟧';

  static List<String> _lines(String body) => body.split('\n');

  /// Every check box line that has some text. An empty box (a template line) is ignored.
  static List<NoteCheckbox> checkboxes(String body) {
    final out = <NoteCheckbox>[];
    final all = _lines(body);
    for (var i = 0; i < all.length; i++) {
      final m = _boxRegex.firstMatch(all[i]);
      if (m == null) continue;
      final tail = m.group(4)!;
      final id = _markerRegex.firstMatch(tail)?.group(1);
      final text = withoutMarkers(tail).trim();
      if (text.isEmpty) continue;
      out.add(
        NoteCheckbox(
          line: i,
          checked: m.group(2) != ' ',
          text: text,
          taskId: id,
        ),
      );
    }
    return out;
  }

  /// The text with every hidden task marker taken out.
  static String withoutMarkers(String text) =>
      text.replaceAll(_markerRegex, '');

  /// Puts the marker for `taskId` at the end of line `line`.
  /// A line that already has a marker is left alone.
  static String addingMarker(
    String body, {
    required int line,
    required String taskId,
  }) {
    final all = _lines(body);
    if (line < 0 || line >= all.length || all[line].contains('⟦t:')) {
      return body;
    }
    all[line] = '${all[line].trimRight()} ${marker(taskId)}';
    return all.join('\n');
  }

  /// Ticks or clears the box on line `line`. A line that is not a check box is left alone.
  static String settingChecked(
    String body, {
    required int line,
    required bool checked,
  }) {
    final all = _lines(body);
    if (line < 0 || line >= all.length) return body;
    final l = all[line];
    final m = _boxRegex.firstMatch(l);
    if (m == null) return body;
    // Group 1 starts at the line start, so the flag sits right after it.
    final at = m.group(1)!.length;
    all[line] = l.replaceRange(at, at + 1, checked ? 'x' : ' ');
    return all.join('\n');
  }
}
