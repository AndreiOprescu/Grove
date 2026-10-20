/// A run of text by UTF-16 offsets, like Foundation's `NSRange`.
/// Dart strings are UTF-16, so these offsets index a Dart `String` directly.
class Utf16Range {
  const Utf16Range(this.location, this.length);

  final int location;
  final int length;

  int get end => location + length;

  bool contains(int position) => position >= location && position < end;

  @override
  bool operator ==(Object other) =>
      other is Utf16Range &&
      other.location == location &&
      other.length == length;

  @override
  int get hashCode => Object.hash(location, length);

  @override
  String toString() => '{$location, $length}';
}

bool _isBreak(int c) =>
    c == 0x0A || c == 0x0D || c == 0x85 || c == 0x2028 || c == 0x2029;

/// The whole lines that `range` touches, with their line breaks,
/// like `NSString.lineRange(for:)`. `\r\n` counts as one break.
Utf16Range lineRange(String text, Utf16Range range) {
  var start = range.location;
  while (start > 0) {
    final c = text.codeUnitAt(start - 1);
    // The gap inside `\r\n` is not a line start.
    final insideCrlf =
        c == 0x0D && start < text.length && text.codeUnitAt(start) == 0x0A;
    if (_isBreak(c) && !insideCrlf) break;
    start -= 1;
  }
  var end = range.length > 0 ? range.end - 1 : range.location;
  while (end < text.length && !_isBreak(text.codeUnitAt(end))) {
    end += 1;
  }
  if (end < text.length) {
    final crlf =
        text.codeUnitAt(end) == 0x0D &&
        end + 1 < text.length &&
        text.codeUnitAt(end + 1) == 0x0A;
    end += crlf ? 2 : 1;
  }
  return Utf16Range(start, end - start);
}
